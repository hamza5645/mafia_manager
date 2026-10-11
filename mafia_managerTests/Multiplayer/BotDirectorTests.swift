import ConvexMobile
import Foundation
import Testing

@testable import mafia_manager

@MainActor
struct BotDirectorTests {
    private let decisions = BotDecisionService()

    private func nightPlans(_ players: [SessionPlayer], _ actions: [GameAction]) -> [BotPlan] {
        BotDirector.nightPlans(players: players, actions: actions, nightHistory: [], decisions: decisions)
    }

    private func role(of id: UUID?, in players: [SessionPlayer]) -> Role? {
        players.first { $0.playerId == id }?.role
    }

    // MARK: - Inspector (9+ players have two inspectors)

    @Test func botInspectorPicksItsOwnTargetWhenTheHumanInspectsIt() throws {
        let human = Fixture.seat(.inspector, bot: false)
        let botInspector = Fixture.seat(.inspector)
        let others = (0..<4).map { _ in Fixture.seat(.mafia) } + [Fixture.seat(.doctor), Fixture.seat(.citizen), Fixture.seat(.citizen)]
        let players = [human, botInspector] + others
        let actions = [Fixture.action(human, .inspectorCheck, target: botInspector)]

        for _ in 0..<50 { // Bot choices are random.
            let plan = try #require(nightPlans(players, actions).first { $0.botPlayerId == botInspector.playerId })
            #expect(plan.actionType == .inspectorCheck)
            let target = try #require(plan.target)
            #expect(target != botInspector.playerId, "The server rejects self-inspection forever")
            #expect(role(of: target, in: players) != .inspector)
        }
    }

    @Test func botInspectorFollowsAnAcceptableHumanTarget() {
        let human = Fixture.seat(.inspector, bot: false)
        let botInspector = Fixture.seat(.inspector)
        let suspect = Fixture.seat(.citizen)
        let players = [human, botInspector, suspect, Fixture.seat(.mafia)]
        let plans = nightPlans(players, [Fixture.action(human, .inspectorCheck, target: suspect)])
        #expect(plans.first { $0.botPlayerId == botInspector.playerId }?.target == suspect.playerId)
    }

    @Test func inspectorBotWithAnActionIsNeverResubmitted() {
        let botInspector = Fixture.seat(.inspector)
        let suspect = Fixture.seat(.citizen)
        let players = [botInspector, suspect, Fixture.seat(.mafia)]
        let plans = nightPlans(players, [Fixture.action(botInspector, .inspectorCheck, target: suspect)])
        #expect(!plans.contains { $0.botPlayerId == botInspector.playerId })
    }


    // MARK: - Mafia

    @Test func mafiaBotsBackTheHumanPlurality() {
        let first = Fixture.seat(.mafia, bot: false)
        let second = Fixture.seat(.mafia, bot: false)
        let third = Fixture.seat(.mafia, bot: false)
        let bot = Fixture.seat(.mafia)
        let x = Fixture.seat(.citizen)
        let y = Fixture.seat(.citizen)
        let players = [first, second, third, bot, x, y]
        let actions = [
            Fixture.action(first, .mafiaTarget, target: x, at: 10),
            Fixture.action(second, .mafiaTarget, target: y, at: 20),
            Fixture.action(third, .mafiaTarget, target: y, at: 30),
        ]
        #expect(nightPlans(players, actions) == [BotPlan(botPlayerId: bot.playerId, actionType: .mafiaTarget, target: y.playerId)])
    }

    @Test func mafiaBotsBreakAHumanTieTowardTheLeaderNamedFirst() {
        let older = Fixture.seat(.mafia, bot: false)
        let newer = Fixture.seat(.mafia, bot: false)
        let bots = [Fixture.seat(.mafia), Fixture.seat(.mafia)]
        let first = Fixture.seat(.citizen)
        let second = Fixture.seat(.citizen)
        let players = [older, newer] + bots + [first, second]
        let actions = [
            Fixture.action(newer, .mafiaTarget, target: second, at: 20),
            Fixture.action(older, .mafiaTarget, target: first, at: 10),
        ]
        let plans = nightPlans(players, actions)
        #expect(plans.count == 2)
        #expect(plans.allSatisfy { $0.target == first.playerId }, "Every bot backs the same human leader")
    }

    @Test func mafiaBotsWaitForEveryLivingHumanMafia() {
        let acted = Fixture.seat(.mafia, bot: false)
        let waiting = Fixture.seat(.mafia, bot: false)
        let dead = Fixture.seat(.mafia, bot: false, alive: false)
        let bot = Fixture.seat(.mafia)
        let victim = Fixture.seat(.citizen)
        let players = [acted, waiting, dead, bot, victim, Fixture.seat(.citizen)]
        let first = [Fixture.action(acted, .mafiaTarget, target: victim)]
        #expect(nightPlans(players, first).isEmpty, "A bot must not lock onto the first human's pick")
        let both = first + [Fixture.action(waiting, .mafiaTarget, target: nil, at: 5)]
        #expect(nightPlans(players, both).first?.target == victim.playerId, "Abstaining counts as acting; dead seats never")
    }

    @Test func mafiaBotNeverFollowsOntoATeammate() throws {
        let human = Fixture.seat(.mafia, bot: false)
        let bot = Fixture.seat(.mafia)
        let teammate = Fixture.seat(.mafia)
        let players = [human, bot, teammate, Fixture.seat(.citizen), Fixture.seat(.doctor)]
        let actions = [Fixture.action(human, .mafiaTarget, target: teammate)]
        for _ in 0..<50 {
            let plan = try #require(nightPlans(players, actions).first { $0.botPlayerId == bot.playerId })
            let target = try #require(plan.target)
            #expect(role(of: target, in: players) != .mafia)
        }
    }

    @Test func botsWaitForTheirHumanTeammate() {
        let players = [Fixture.seat(.doctor, bot: false), Fixture.seat(.doctor), Fixture.seat(.citizen)]
        #expect(nightPlans(players, []).isEmpty)
    }

    @Test func mafiaBotsWithoutHumansShareOneTarget() throws {
        let bots = (0..<3).map { _ in Fixture.seat(.mafia) }
        let players = bots + (0..<4).map { _ in Fixture.seat(.citizen) }
        let plans = nightPlans(players, [])
        #expect(plans.count == 3)
        let target = try #require(plans.first?.target)
        #expect(plans.allSatisfy { $0.target == target })
        #expect(role(of: target, in: players) == .citizen)
    }

    @Test func remainingMafiaBotsReuseTheSubmittedBotTarget() {
        let submitted = Fixture.seat(.mafia)
        let pending = Fixture.seat(.mafia)
        let victim = Fixture.seat(.citizen)
        let players = [submitted, pending, victim, Fixture.seat(.citizen), Fixture.seat(.citizen)]
        let plans = nightPlans(players, [Fixture.action(submitted, .mafiaTarget, target: victim)])
        #expect(plans == [BotPlan(botPlayerId: pending.playerId, actionType: .mafiaTarget, target: victim.playerId)])
    }

    @Test func aReusedBotTargetThatLeftIsNotSentAgain() throws {
        let submitted = Fixture.seat(.mafia)
        let pending = Fixture.seat(.mafia)
        let gone = Fixture.seat(.citizen) // Left mid-night: no longer a seat.
        let players = [submitted, pending, Fixture.seat(.citizen), Fixture.seat(.citizen)]
        for _ in 0..<20 {
            let plan = try #require(nightPlans(players, [Fixture.action(submitted, .mafiaTarget, target: gone)]).first)
            let target = try #require(plan.target)
            #expect(target != gone.playerId, "The server rejects a missing seat forever")
            #expect(role(of: target, in: players) == .citizen)
        }
    }

    @Test func deadBotsAndCitizensDoNotAct() {
        let players = [Fixture.seat(.doctor, alive: false), Fixture.seat(.citizen), Fixture.seat(.citizen, bot: false)]
        #expect(nightPlans(players, []).isEmpty)
    }

    // MARK: - Voting

    @Test func everyLivingBotWithoutATargetedVoteVotes() {
        let abstained = Fixture.seat(.citizen)
        let voted = Fixture.seat(.mafia)
        let silent = Fixture.seat(.doctor)
        let dead = Fixture.seat(.citizen, alive: false)
        let human = Fixture.seat(.citizen, bot: false)
        let players = [abstained, voted, silent, dead, human]
        let actions = [
            Fixture.action(abstained, .vote, target: nil),
            Fixture.action(voted, .vote, target: human),
        ]
        let plans = BotDirector.votePlans(players: players, actions: actions, nightHistory: [], dayHistory: [], decisions: decisions)
        #expect(Set(plans.map(\.botPlayerId)) == [abstained.playerId, silent.playerId])
        #expect(plans.allSatisfy { $0.actionType == .vote && $0.target != nil })
    }

    @Test func canTargetMatchesServerValidation() {
        let inspector = Fixture.seat(.inspector)
        let mafia = Fixture.seat(.mafia)
        let citizen = Fixture.seat(.citizen)
        let dead = Fixture.seat(.citizen, alive: false)
        let alive = [inspector, mafia, citizen]
        #expect(BotDirector.canTarget(nil, actor: inspector, actionType: .inspectorCheck, alive: alive))
        #expect(BotDirector.canTarget(citizen.playerId, actor: inspector, actionType: .inspectorCheck, alive: alive))
        #expect(!BotDirector.canTarget(inspector.playerId, actor: inspector, actionType: .inspectorCheck, alive: alive))
        #expect(!BotDirector.canTarget(mafia.playerId, actor: mafia, actionType: .mafiaTarget, alive: alive))
        #expect(!BotDirector.canTarget(dead.playerId, actor: mafia, actionType: .mafiaTarget, alive: alive))
        #expect(BotDirector.canTarget(mafia.playerId, actor: mafia, actionType: .vote, alive: alive), "Votes may name anyone alive")
        let doctor = Fixture.seat(.doctor)
        #expect(BotDirector.canTarget(doctor.playerId, actor: doctor, actionType: .doctorProtect, alive: alive + [doctor]))
    }

    // MARK: - Submission pass (`run`)

    private func serverError(_ message: String) -> BackendError {
        BackendError(ClientError.ConvexError(data: "\"\(message)\""))
    }

    private func accepted(_ plans: [BotPlan]) -> [BotActionResult] {
        plans.map { BotActionResult(actorPlayerId: $0.botPlayerId, ok: true, error: nil, result: nil) }
    }

    /// A night where one doctor bot acts alone and an inspector bot waits for its human.
    private func nightTable(round: UUID) -> (GameSession, [SessionPlayer], RoundState) {
        let players = [Fixture.seat(.doctor), Fixture.seat(.inspector), Fixture.seat(.inspector, bot: false),
                       Fixture.seat(.mafia, bot: false), Fixture.seat(.citizen)]
        return (Fixture.session(roundId: round), players, Fixture.round(round))
    }

    @Test func aBotIsSubmittedOncePerRoundWhileInFlightAndAfterSuccess() async {
        var batches: [[BotPlan]] = []
        var inFlight: [UnsafeContinuation<Void, Never>] = []
        let director = BotDirector { plans, _, _, _ in
            batches.append(plans)
            await withUnsafeContinuation { inFlight.append($0) }
            return accepted(plans)
        }
        let round = UUID()
        let (session, players, state) = nightTable(round: round)

        director.run(session: session, players: players, round: state)
        await settle()
        #expect(batches.map { $0.map(\.actionType) } == [[.doctorProtect]])
        director.run(session: session, players: players, round: state) // Same snapshot, still in flight.
        await settle()
        #expect(batches.count == 1)

        inFlight.forEach { $0.resume() }
        await settle()
        director.run(session: session, players: players, round: state) // Accepted; the row is not in the snapshot yet.
        await settle()
        #expect(batches.count == 1)
    }

    @Test func onePassSendsEveryPendingBotInOneCall() async throws {
        var batches: [[BotPlan]] = []
        let director = BotDirector { plans, _, _, _ in
            batches.append(plans)
            return accepted(plans)
        }
        let bots = (0..<3).map { _ in Fixture.seat(.mafia) } + [Fixture.seat(.doctor), Fixture.seat(.inspector)]
        let players = bots + (0..<5).map { _ in Fixture.seat(.citizen, bot: false) }
        let round = UUID()
        director.run(session: Fixture.session(roundId: round), players: players, round: Fixture.round(round))
        await settle()
        #expect(batches.count == 1)
        #expect(Set(try #require(batches.first).map(\.botPlayerId)) == Set(bots.map(\.playerId)))
    }

    @Test(arguments: BotDirector.roundClosedMessages.sorted())
    func aClosedRoundStopsEveryRetry(message: String) async {
        var batches: [[BotPlan]] = []
        let director = BotDirector { plans, _, _, _ in
            batches.append(plans)
            throw serverError(message)
        }
        let round = UUID()
        let (session, players, state) = nightTable(round: round)
        director.run(session: session, players: players, round: state)
        await settle()
        #expect(batches.count == 1)

        // The human inspector acts, so the inspector bot would now be planned.
        let human = players[2]
        let acted = Fixture.round(round, actions: [Fixture.action(human, .inspectorCheck, target: players[4], round: round)])
        director.run(session: session, players: players, round: acted)
        await settle()
        #expect(batches.count == 1, "No submission can succeed after \(message)")

        let nextRound = UUID()
        director.run(session: Fixture.session(roundId: nextRound), players: players, round: Fixture.round(nextRound))
        await settle()
        #expect(batches.count == 2, "A new round starts fresh")
    }

    @Test func aRoundClosingItemIsHandledAndOtherItemErrorsRetry() async {
        var batches: [[BotPlan]] = []
        let mafia = Fixture.seat(.mafia)
        let doctor = Fixture.seat(.doctor)
        let director = BotDirector { plans, _, _, _ in
            batches.append(plans)
            return plans.map { plan in
                switch (batches.count, plan.botPlayerId) {
                case (1, doctor.playerId): BotActionResult(actorPlayerId: plan.botPlayerId, ok: false,
                                                           error: "Choose a player who is still alive.", result: nil)
                case (2, doctor.playerId): BotActionResult(actorPlayerId: plan.botPlayerId, ok: false,
                                                           error: "Night actions are closed.", result: nil)
                default: BotActionResult(actorPlayerId: plan.botPlayerId, ok: true, error: nil, result: nil)
                }
            }
        }
        let players = [mafia, doctor] + (0..<3).map { _ in Fixture.seat(.citizen, bot: false) }
        let round = UUID()
        let session = Fixture.session(roundId: round)
        director.run(session: session, players: players, round: Fixture.round(round))
        await settle()
        #expect(batches.map(\.count) == [2])

        director.run(session: session, players: players, round: Fixture.round(round)) // A later tick.
        await settle()
        #expect(batches.last?.map(\.botPlayerId) == [doctor.playerId], "Only the rejected item is sent again")

        director.run(session: session, players: players, round: Fixture.round(round))
        await settle()
        #expect(batches.count == 2, "A round-closed item is handled for good")
    }

    @Test func otherErrorsAreRetriedOnALaterPass() async {
        var batches: [[BotPlan]] = []
        var failures: [Error] = [
            serverError("Choose a player who is still alive."),
            URLError(.notConnectedToInternet),
        ]
        let director = BotDirector { plans, _, _, _ in
            batches.append(plans)
            if !failures.isEmpty { throw failures.removeFirst() }
            return accepted(plans)
        }
        let round = UUID()
        let (session, players, state) = nightTable(round: round)
        for expected in 1...3 {
            director.run(session: session, players: players, round: state)
            await settle()
            #expect(batches.count == expected)
        }
        director.run(session: session, players: players, round: state)
        await settle()
        #expect(batches.count == 3, "Accepted on the third try")
    }

    @Test func onlyServerMessagesCloseARound() {
        #expect(BotDirector.closesRound(serverError("Night actions are closed.")))
        #expect(!BotDirector.closesRound(serverError("Choose a player who is still alive.")))
        #expect(!BotDirector.closesRound(NSError(domain: "Test", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "The game has moved on.",
        ])))
    }

    /// Feeds the host's snapshots in the order the server writes the rows.
    @Test func orderedSnapshotsLetBotsFollowTheHumanMajorityNotTheFirstPick() async throws {
        var batches: [[BotPlan]] = []
        let director = BotDirector { plans, _, _, _ in
            batches.append(plans)
            return accepted(plans)
        }
        let humans = (0..<3).map { _ in Fixture.seat(.mafia, bot: false) }
        let bot = Fixture.seat(.mafia)
        let x = Fixture.seat(.citizen)
        let y = Fixture.seat(.citizen)
        let players = humans + [bot, x, y] + (0..<3).map { _ in Fixture.seat(.citizen, bot: false) }
        let round = UUID()
        let session = Fixture.session(roundId: round)
        var rows: [GameAction] = []
        for (index, (human, target)) in zip(humans, [x, y, y]).enumerated() {
            rows.append(Fixture.action(human, .mafiaTarget, target: target, round: round, at: Double(index)))
            director.run(session: session, players: players, round: Fixture.round(round, actions: rows))
            await settle()
            if index < 2 { #expect(batches.isEmpty, "Bots wait while a human Mafia has not acted") }
        }
        #expect(try #require(batches.first) == [BotPlan(botPlayerId: bot.playerId, actionType: .mafiaTarget, target: y.playerId)])
    }

    @Test func aRejectedBotVoteIsReplannedOnALaterPassWithoutAFallback() async throws {
        var batches: [[BotPlan]] = []
        let director = BotDirector { plans, _, _, _ in
            batches.append(plans)
            if batches.count == 1 { throw serverError("Choose a player who is still alive.") }
            return accepted(plans)
        }
        let bot = Fixture.seat(.citizen)
        let players = [bot, Fixture.seat(.citizen, bot: false), Fixture.seat(.mafia, bot: false)]
        let round = UUID()
        let session = Fixture.session(phase: "voting", roundId: round)
        director.run(session: session, players: players, round: Fixture.round(round, phase: "voting"))
        await settle()
        #expect(batches.count == 1, "No immediate role-blind fallback vote")

        director.run(session: session, players: players, round: Fixture.round(round, phase: "voting"))
        await settle()
        #expect(batches.count == 2)
        let target = try #require(batches.last?.first?.target)
        #expect(target != bot.playerId)
        #expect(players.contains { $0.playerId == target })
    }

    @Test func aReplannedMafiaBotVoteNeverNamesATeammate() async throws {
        var batches: [[BotPlan]] = []
        let director = BotDirector { plans, _, _, _ in
            batches.append(plans)
            throw serverError("Choose a player who is still alive.")
        }
        let bot = Fixture.seat(.mafia)
        let teammate = Fixture.seat(.mafia)
        let players = [bot, teammate, Fixture.seat(.citizen, bot: false), Fixture.seat(.citizen, bot: false)]
        let round = UUID()
        let session = Fixture.session(phase: "voting", roundId: round)
        for _ in 0..<30 {
            director.run(session: session, players: players, round: Fixture.round(round, phase: "voting"))
            await settle()
        }
        let votes = batches.flatMap { $0 }.filter { $0.botPlayerId == bot.playerId }
        #expect(votes.count == 30)
        #expect(votes.allSatisfy { $0.target != teammate.playerId && $0.target != bot.playerId })
    }
}
