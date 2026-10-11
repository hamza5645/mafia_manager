import Foundation

/// One bot submission for the current round.
struct BotPlan: Equatable {
    let botPlayerId: UUID
    let actionType: ActionType
    let target: UUID?
}

/// Host-only: submits bot night actions and votes from the latest snapshots (api_contract 5, §8.2).
@MainActor
final class BotDirector {
    /// Server messages after which retrying this round can never succeed.
    nonisolated static let roundClosedMessages: Set<String> = [
        "Night actions are closed.",
        "The game has moved on.",
        "This action is not available right now.",
        "This game is no longer active.",
    ]

    /// Sends one pass of bot actions (`play:submitBotActions`) and returns the per-bot results.
    typealias Submit = (_ plans: [BotPlan], _ sessionId: UUID, _ roundId: UUID, _ phaseIndex: Int) async throws -> [BotActionResult]

    private let submitActions: Submit
    private let decisions = BotDecisionService()
    private var roundId: UUID?
    /// `"\(roundId):\(botPlayerId)"` for submissions in flight or already accepted this round.
    private var handled: Set<String> = []
    private var isRoundClosed = false

    init(submit: @escaping Submit) {
        submitActions = submit
    }

    func reset() {
        roundId = nil
        handled = []
        isRoundClosed = false
    }

    /// Runs on every changed snapshot and every tick while I am host. Safe to call repeatedly:
    /// a failed submission is planned again on a later pass.
    func run(session: GameSession, players: [SessionPlayer], round: RoundState) {
        guard let roundId = round.roundId, roundId == session.currentRoundId,
              let phaseIndex = round.phaseIndex else { return }
        if roundId != self.roundId {
            reset()
            self.roundId = roundId
        }
        guard !isRoundClosed else { return }

        let plans: [BotPlan]
        switch round.phase {
        case "night":
            plans = Self.nightPlans(players: players, actions: round.actions,
                                    nightHistory: session.nightHistory, decisions: decisions)
        case "voting":
            plans = Self.votePlans(players: players, actions: round.actions, nightHistory: session.nightHistory,
                                   dayHistory: session.dayHistory, decisions: decisions)
        default:
            return
        }

        let batch = plans.filter { !handled.contains(Self.key(roundId, $0)) }
        guard !batch.isEmpty else { return }
        batch.forEach { handled.insert(Self.key(roundId, $0)) }
        Task {
            let retries = await submit(batch, sessionId: session.id, roundId: roundId, phaseIndex: phaseIndex)
            retries.forEach { handled.remove(Self.key(roundId, $0)) }
        }
    }

    /// Returns the plans to send again on a later pass.
    private func submit(_ batch: [BotPlan], sessionId: UUID, roundId: UUID, phaseIndex: Int) async -> [BotPlan] {
        let results: [BotActionResult]
        do {
            results = try await submitActions(batch, sessionId, roundId, phaseIndex)
        } catch {
            print("❌ [BotDirector] Submitting \(batch.count) bot action(s) failed: \(error.localizedDescription)")
            guard Self.closesRound(error) else { return batch }
            closeRound(roundId)
            return []
        }
        let byBot = Dictionary(results.map { ($0.actorPlayerId, $0) }, uniquingKeysWith: { first, _ in first })
        return batch.filter { plan in
            guard let result = byBot[plan.botPlayerId] else { return true }
            guard !result.ok else { return false }
            let message = result.error ?? ""
            print("❌ [BotDirector] \(plan.actionType.rawValue) for bot \(plan.botPlayerId) failed: \(message)")
            guard Self.roundClosedMessages.contains(message) else { return true }
            closeRound(roundId)
            return false
        }
    }

    private func closeRound(_ roundId: UUID) {
        if self.roundId == roundId { isRoundClosed = true }
    }

    private static func key(_ roundId: UUID, _ plan: BotPlan) -> String {
        "\(roundId):\(plan.botPlayerId)"
    }

    /// A server rejection after which no submission can succeed this round.
    static func closesRound(_ error: Error) -> Bool {
        guard let error = error as? BackendError, error.isServerMessage else { return false }
        return roundClosedMessages.contains(error.message)
    }

    // MARK: - Planning

    /// Night actions for living bots that have none this round. Mafia bots wait for every
    /// living human Mafia and then back the humans' plurality; doctor and inspector bots follow
    /// the latest human of their role. A bot follows only a target the server would accept.
    static func nightPlans(
        players: [SessionPlayer],
        actions: [GameAction],
        nightHistory: [NightActionRecord],
        decisions: BotDecisionService
    ) -> [BotPlan] {
        let alive = players.filter(\.isAlive)
        let localAlive = alive.map(localPlayer)
        let history = nightHistory.map(localNight)
        var plans: [BotPlan] = []

        for (role, type) in [(Role.mafia, ActionType.mafiaTarget), (.doctor, .doctorProtect), (.inspector, .inspectorCheck)] {
            let rows = actions.filter { $0.actionType == type }
            let acted = Set(rows.map(\.actorPlayerId))
            let pending = alive.filter { $0.isBot && $0.role == role && !acted.contains($0.playerId) }
            guard !pending.isEmpty else { continue }

            func ownTarget(_ bot: SessionPlayer) -> UUID? {
                let me = localPlayer(bot)
                switch role {
                case .mafia: return decisions.chooseMafiaTarget(botPlayer: me, alivePlayers: localAlive, nightHistory: history)
                case .doctor: return decisions.chooseDoctorProtection(botPlayer: me, alivePlayers: localAlive, nightHistory: history)
                case .inspector: return decisions.chooseInspectorTarget(botPlayer: me, alivePlayers: localAlive, nightHistory: history)
                case .citizen: return nil
                }
            }

            let humans = Set(alive.filter { !$0.isBot && $0.role == role }.map(\.playerId))
            if role == .mafia {
                var target: UUID?
                if !humans.isEmpty {
                    // The server counts human Mafia rows first; bots only break ties among their leaders.
                    guard humans.isSubset(of: acted) else { continue }
                    target = humanLead(rows.filter { humans.contains($0.actorPlayerId) }, actor: pending[0], alive: alive)
                }
                if target == nil {
                    // No human named a usable target: the bots decide together. A submitted bot
                    // target is reused only while the server still accepts it.
                    let botIds = Set(alive.filter { $0.isBot && $0.role == .mafia }.map(\.playerId))
                    target = rows.filter { botIds.contains($0.actorPlayerId) }
                        .max(by: { $0.createdAt < $1.createdAt })?.targetPlayerId
                        .flatMap { canTarget($0, actor: pending[0], actionType: type, alive: alive) ? $0 : nil }
                        ?? decisions.chooseCoordinatedMafiaTarget(
                            mafiaBots: pending.map(localPlayer), alivePlayers: localAlive, nightHistory: history
                        )
                }
                for bot in pending {
                    plans.append(BotPlan(botPlayerId: bot.playerId, actionType: type, target: target ?? ownTarget(bot)))
                }
            } else if !humans.isEmpty {
                // Bots wait until a human of their role has acted.
                guard let latest = rows.filter({ humans.contains($0.actorPlayerId) })
                    .max(by: { $0.createdAt < $1.createdAt }) else { continue }
                for bot in pending {
                    let follow = canTarget(latest.targetPlayerId, actor: bot, actionType: type, alive: alive)
                    plans.append(BotPlan(botPlayerId: bot.playerId, actionType: type,
                                         target: follow ? latest.targetPlayerId : ownTarget(bot)))
                }
            } else {
                for bot in pending {
                    plans.append(BotPlan(botPlayerId: bot.playerId, actionType: type, target: ownTarget(bot)))
                }
            }
        }
        return plans
    }

    /// The target most human Mafia rows name, among targets the server accepts. A tie goes
    /// to the leader named first, so every bot backs the same leader.
    private static func humanLead(_ rows: [GameAction], actor: SessionPlayer, alive: [SessionPlayer]) -> UUID? {
        let named = rows.sorted { $0.createdAt < $1.createdAt }
            .compactMap(\.targetPlayerId)
            .filter { canTarget($0, actor: actor, actionType: .mafiaTarget, alive: alive) }
        var counts: [UUID: Int] = [:]
        named.forEach { counts[$0, default: 0] += 1 }
        guard let top = counts.values.max() else { return nil }
        return named.first { counts[$0] == top }
    }

    /// Votes for living bots without a targeted vote this round (bots never abstain).
    static func votePlans(
        players: [SessionPlayer],
        actions: [GameAction],
        nightHistory: [NightActionRecord],
        dayHistory: [DayActionRecord],
        decisions: BotDecisionService
    ) -> [BotPlan] {
        let alive = players.filter(\.isAlive)
        let localAlive = alive.map(localPlayer)
        let voted = Set(actions.filter { $0.actionType == .vote && $0.targetPlayerId != nil }.map(\.actorPlayerId))
        return alive.filter { $0.isBot && !voted.contains($0.playerId) }.map { bot in
            BotPlan(botPlayerId: bot.playerId, actionType: .vote, target: decisions.chooseVotingTarget(
                botPlayer: localPlayer(bot), alivePlayers: localAlive,
                nightHistory: nightHistory.map(localNight),
                dayHistory: dayHistory.map { DayAction(dayIndex: $0.dayIndex, removedPlayerIDs: $0.removedPlayerIds) }
            ))
        }
    }

    /// Mirrors the target checks of `validateGameAction` (§4.5) for an alive actor with the right role.
    static func canTarget(_ target: UUID?, actor: SessionPlayer, actionType: ActionType, alive: [SessionPlayer]) -> Bool {
        guard let target else { return true } // Abstaining is always accepted.
        guard let seat = alive.first(where: { $0.playerId == target }) else { return false }
        if actionType == .mafiaTarget && seat.role == .mafia { return false }
        if actionType == .inspectorCheck && target == actor.playerId { return false }
        return true
    }

    private static func localPlayer(_ player: SessionPlayer) -> Player {
        Player(
            id: player.playerId,
            number: player.playerNumber ?? 0,
            name: player.playerName,
            role: player.role ?? .citizen,
            alive: player.isAlive,
            isBot: player.isBot,
            removalNote: player.removalNote
        )
    }

    private static func localNight(_ record: NightActionRecord) -> NightAction {
        NightAction(
            nightIndex: record.nightIndex,
            mafiaTargetPlayerID: record.mafiaTargetId,
            inspectorCheckedPlayerID: record.inspectorCheckedId,
            doctorProtectedPlayerID: record.doctorProtectedId,
            resultingDeaths: record.resultingDeaths,
            mafiaNumbers: record.mafiaPlayerNumbers,
            isResolved: record.isResolved
        )
    }
}
