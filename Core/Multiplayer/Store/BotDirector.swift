import Foundation

/// One bot submission for the current round.
struct BotPlan: Equatable {
    let botPlayerId: UUID
    let actionType: ActionType
    let target: UUID?
}

/// Host-only: submits bot night actions and votes from the latest snapshots (api_contract 4, §8.2).
@MainActor
final class BotDirector {
    /// Server messages after which retrying this round can never succeed.
    nonisolated static let roundClosedMessages: Set<String> = [
        "Night actions are closed.",
        "The game has moved on.",
        "This action is not available right now.",
        "This game is no longer active.",
    ]

    /// Sends one bot action (`play:submitAction`) for the given session, round and phase index.
    typealias Submit = (_ plan: BotPlan, _ sessionId: UUID, _ roundId: UUID, _ phaseIndex: Int) async throws -> Void

    private let submitAction: Submit
    private let decisions = BotDecisionService()
    private var roundId: UUID?
    /// `"\(roundId):\(botPlayerId)"` for submissions in flight or already accepted this round.
    private var handled: Set<String> = []
    private var isRoundClosed = false

    init(submit: @escaping Submit) {
        submitAction = submit
    }

    func reset() {
        roundId = nil
        handled = []
        isRoundClosed = false
    }

    /// Runs on every snapshot while I am host. Safe to call repeatedly.
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

        let alive = players.filter(\.isAlive).map(\.playerId)
        for plan in plans {
            let key = "\(roundId):\(plan.botPlayerId)"
            guard !handled.contains(key) else { continue }
            handled.insert(key)
            Task {
                if await submit(plan, sessionId: session.id, roundId: roundId, phaseIndex: phaseIndex, alive: alive) == false {
                    handled.remove(key) // Retry on the next snapshot.
                }
            }
        }
    }

    /// Returns false when the submission should be retried.
    private func submit(_ plan: BotPlan, sessionId: UUID, roundId: UUID, phaseIndex: Int, alive: [UUID]) async -> Bool {
        do {
            try await submitAction(plan, sessionId, roundId, phaseIndex)
            return true
        } catch {
            print("❌ [BotDirector] \(plan.actionType.rawValue) for bot \(plan.botPlayerId) failed: \(error.localizedDescription)")
            if Self.closesRound(error) {
                if self.roundId == roundId { isRoundClosed = true }
                return true
            }
            guard plan.actionType == .vote else { return false }
        }
        // A rejected vote falls back to another living seat, and to self as the last resort.
        let fallback = alive.filter { $0 != plan.botPlayerId && $0 != plan.target }.randomElement() ?? plan.botPlayerId
        do {
            try await submitAction(BotPlan(botPlayerId: plan.botPlayerId, actionType: .vote, target: fallback),
                                   sessionId, roundId, phaseIndex)
            return true
        } catch {
            print("❌ [BotDirector] Fallback vote for bot \(plan.botPlayerId) failed: \(error.localizedDescription)")
            if Self.closesRound(error), self.roundId == roundId { isRoundClosed = true }
            return Self.closesRound(error)
        }
    }

    /// A server rejection after which no submission can succeed this round.
    static func closesRound(_ error: Error) -> Bool {
        guard let error = error as? BackendError, error.isServerMessage else { return false }
        return roundClosedMessages.contains(error.message)
    }

    // MARK: - Planning

    /// Night actions for living bots that have none this round. A bot follows the latest
    /// human of its role only when the server would accept that target.
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
            if !humans.isEmpty {
                // Bots wait until a human of their role has acted.
                guard let latest = rows.filter({ humans.contains($0.actorPlayerId) })
                    .max(by: { $0.createdAt < $1.createdAt }) else { continue }
                for bot in pending {
                    let follow = canTarget(latest.targetPlayerId, actor: bot, role: role, alive: alive)
                    plans.append(BotPlan(botPlayerId: bot.playerId, actionType: type,
                                         target: follow ? latest.targetPlayerId : ownTarget(bot)))
                }
            } else if role == .mafia {
                let mafiaIds = Set(alive.filter { $0.role == .mafia }.map(\.playerId))
                let shared = rows.filter { mafiaIds.contains($0.actorPlayerId) }
                    .max(by: { $0.createdAt < $1.createdAt })?.targetPlayerId
                    ?? decisions.chooseCoordinatedMafiaTarget(
                        mafiaBots: pending.map(localPlayer), alivePlayers: localAlive, nightHistory: history
                    )
                for bot in pending {
                    plans.append(BotPlan(botPlayerId: bot.playerId, actionType: type, target: shared ?? ownTarget(bot)))
                }
            } else {
                for bot in pending {
                    plans.append(BotPlan(botPlayerId: bot.playerId, actionType: type, target: ownTarget(bot)))
                }
            }
        }
        return plans
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

    /// Mirrors `validateGameAction` (§4.5) for a target another player chose.
    static func canTarget(_ target: UUID?, actor: SessionPlayer, role: Role, alive: [SessionPlayer]) -> Bool {
        guard let target else { return true } // Abstaining is always accepted.
        guard let seat = alive.first(where: { $0.playerId == target }) else { return false }
        if role == .mafia && seat.role == .mafia { return false }
        if role == .inspector && target == actor.playerId { return false }
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
