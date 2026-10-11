import XCTest
@testable import mafia_manager

// nonisolated, with main-actor members: under default MainActor isolation a main-actor
// XCTestCase subclass inherits its initializers as main-actor ones (an error in Swift 6).
nonisolated final class GameStoreTests: XCTestCase {

    @MainActor var gameStore: GameStore!
    @MainActor private var environment: SoloTestEnvironment!

    @MainActor override func setUp() async throws {
        environment = SoloTestEnvironment()
        gameStore = environment.makeStore()
    }

    @MainActor override func tearDown() async throws {
        gameStore = nil
        environment.removeFiles()
        environment = nil
    }

    // MARK: - Setup Tests

    @MainActor func testInitialState() {
        XCTAssertTrue(gameStore.state.players.isEmpty)
        XCTAssertTrue(gameStore.isFreshSetup)
        XCTAssertEqual(gameStore.state.nightHistory.count, 0)
        XCTAssertEqual(gameStore.state.dayHistory.count, 0)
        XCTAssertFalse(gameStore.state.isGameOver)
        XCTAssertNil(gameStore.state.winner)
    }

    @MainActor func testAssignNumbersAndRoles_MinimumPlayers() {
        let names = ["Alice", "Bob", "Charlie", "David"]
        gameStore.assignNumbersAndRoles(names: names)

        XCTAssertEqual(gameStore.state.players.count, 4)
        XCTAssertFalse(gameStore.isFreshSetup)

        // Verify all players have unique numbers
        let numbers = Set(gameStore.state.players.map { $0.number })
        XCTAssertEqual(numbers.count, 4)

        // Verify all numbers are in valid range (1...8 for 4 players)
        for number in numbers {
            XCTAssertTrue(number >= 1 && number <= 8)
        }

        // Verify role distribution for 4 players: 1 mafia, 1 inspector, 0 doctor, 2 citizens
        let mafiaCount = gameStore.state.players.filter { $0.role == .mafia }.count
        let inspectorCount = gameStore.state.players.filter { $0.role == .inspector }.count
        let doctorCount = gameStore.state.players.filter { $0.role == .doctor }.count
        let citizenCount = gameStore.state.players.filter { $0.role == .citizen }.count

        XCTAssertEqual(mafiaCount, 1)
        XCTAssertEqual(inspectorCount, 1)
        XCTAssertEqual(doctorCount, 0)
        XCTAssertEqual(citizenCount, 2)
    }

    @MainActor func testAssignNumbersAndRoles_MediumGame() {
        let names = ["P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8"]
        gameStore.assignNumbersAndRoles(names: names)

        XCTAssertEqual(gameStore.state.players.count, 8)

        // Verify role distribution for 8 players: 2 mafia, 1 doctor, 1 inspector
        let mafiaCount = gameStore.state.players.filter { $0.role == .mafia }.count
        let inspectorCount = gameStore.state.players.filter { $0.role == .inspector }.count
        let doctorCount = gameStore.state.players.filter { $0.role == .doctor }.count

        XCTAssertEqual(mafiaCount, 2)
        XCTAssertEqual(inspectorCount, 1)
        XCTAssertEqual(doctorCount, 1)
    }

    @MainActor func testAssignNumbersAndRoles_TooFewPlayers() {
        let names = ["Alice", "Bob"]
        gameStore.assignNumbersAndRoles(names: names)

        // Should not assign roles with fewer than 4 players
        XCTAssertTrue(gameStore.state.players.isEmpty)
        XCTAssertTrue(gameStore.isFreshSetup)
    }

    @MainActor func testAssignNumbersAndRoles_TooManyPlayers() {
        let names = Array(repeating: "Player", count: 20).enumerated().map { "Player\($0)" }
        gameStore.assignNumbersAndRoles(names: names)

        // Should not assign roles with more than 19 players
        XCTAssertTrue(gameStore.state.players.isEmpty)
        XCTAssertTrue(gameStore.isFreshSetup)
    }

    @MainActor func testAssignNumbersAndRoles_DuplicateNames() {
        let names = ["Alice", "Bob", "Alice", "Charlie"]
        gameStore.assignNumbersAndRoles(names: names)

        // Should reject duplicate names
        XCTAssertTrue(gameStore.state.players.isEmpty)
        XCTAssertTrue(gameStore.isFreshSetup)
    }

    @MainActor func testAssignNumbersAndRoles_AllPlayersAlive() {
        let names = ["Alice", "Bob", "Charlie", "David"]
        gameStore.assignNumbersAndRoles(names: names)

        for player in gameStore.state.players {
            XCTAssertTrue(player.alive)
            XCTAssertNil(player.removalNote)
        }
    }

    // MARK: - Night Phase Tests

    @MainActor func testEndNight_RecordsActions() {
        setupGame(playerCount: 6)

        let alivePlayers = gameStore.alivePlayers
        let mafiaTarget = alivePlayers.first { $0.role != .mafia }
        let inspectorTarget = alivePlayers.first { $0.role == .mafia }
        let doctorTarget = alivePlayers.first { $0.role == .citizen }

        gameStore.endNight(
            mafiaTargetID: mafiaTarget?.id,
            inspectorCheckedID: inspectorTarget?.id,
            doctorProtectedID: doctorTarget?.id
        )

        XCTAssertEqual(gameStore.state.nightHistory.count, 1)

        let action = gameStore.state.nightHistory[0]
        XCTAssertEqual(action.nightIndex, 1)
        XCTAssertEqual(action.mafiaTargetPlayerID, mafiaTarget?.id)
        XCTAssertEqual(action.inspectorCheckedPlayerID, inspectorTarget?.id)
        XCTAssertEqual(action.doctorProtectedPlayerID, doctorTarget?.id)
        XCTAssertEqual(action.inspectorResultIsMafia, true)
    }

    @MainActor func testResolveNightOutcome_TargetKilled() {
        setupGame(playerCount: 6)

        let alivePlayers = gameStore.alivePlayers
        let mafiaTarget = alivePlayers.first { $0.role != .mafia }!

        gameStore.endNight(mafiaTargetID: mafiaTarget.id, inspectorCheckedID: nil, doctorProtectedID: nil)

        let aliveCountBefore = gameStore.alivePlayers.count
        gameStore.resolveNightOutcome(targetWasSaved: false)

        let aliveCountAfter = gameStore.alivePlayers.count
        XCTAssertEqual(aliveCountAfter, aliveCountBefore - 1)

        let killedPlayer = gameStore.player(by: mafiaTarget.id)
        XCTAssertNotNil(killedPlayer)
        XCTAssertFalse(killedPlayer!.alive)
    }

    @MainActor func testResolveNightOutcome_TargetSaved() {
        setupGame(playerCount: 6)

        let alivePlayers = gameStore.alivePlayers
        let mafiaTarget = alivePlayers.first { $0.role != .mafia }!

        gameStore.endNight(mafiaTargetID: mafiaTarget.id, inspectorCheckedID: nil, doctorProtectedID: mafiaTarget.id)

        let aliveCountBefore = gameStore.alivePlayers.count
        gameStore.resolveNightOutcome(targetWasSaved: true)

        let aliveCountAfter = gameStore.alivePlayers.count
        XCTAssertEqual(aliveCountAfter, aliveCountBefore) // No deaths

        let targetPlayer = gameStore.player(by: mafiaTarget.id)
        XCTAssertNotNil(targetPlayer)
        XCTAssertTrue(targetPlayer!.alive)
    }

    @MainActor func testInspectorCheck_DetectsMafia() {
        setupGame(playerCount: 6)

        let mafiaPlayer = gameStore.state.players.first { $0.role == .mafia }!

        gameStore.endNight(mafiaTargetID: nil, inspectorCheckedID: mafiaPlayer.id, doctorProtectedID: nil)

        let action = gameStore.state.nightHistory[0]
        XCTAssertEqual(action.inspectorResultIsMafia, true)
        XCTAssertEqual(action.inspectorResultRole, .mafia)
    }

    @MainActor func testInspectorCheck_DetectsInnocent() {
        setupGame(playerCount: 6)

        let citizenPlayer = gameStore.state.players.first { $0.role == .citizen }!

        gameStore.endNight(mafiaTargetID: nil, inspectorCheckedID: citizenPlayer.id, doctorProtectedID: nil)

        let action = gameStore.state.nightHistory[0]
        XCTAssertEqual(action.inspectorResultIsMafia, false)
        XCTAssertEqual(action.inspectorResultRole, .citizen)
    }

    @MainActor func testInspectorCheck_CannotIdentifyOtherInspectors() throws {
        setupGame(playerCount: 9) // 9 or more players have 2 inspectors

        let inspectors = gameStore.state.players.filter { $0.role == .inspector }
        XCTAssertEqual(inspectors.count, 2)
        guard inspectors.count >= 2 else { return }

        gameStore.endNight(mafiaTargetID: nil, inspectorCheckedID: inspectors[1].id, doctorProtectedID: nil)

        let action = try XCTUnwrap(gameStore.state.nightHistory.first)
        XCTAssertEqual(action.inspectorCheckedPlayerID, inspectors[1].id)
        XCTAssertNil(action.inspectorResultIsMafia)
        XCTAssertNil(action.inspectorResultRole)
    }

    @MainActor func testBotInspector_NeverTargetsAnotherInspector() throws {
        setupGame(playerCount: 9)

        let inspectors = gameStore.state.players.filter { $0.role == .inspector }
        XCTAssertEqual(inspectors.count, 2)
        let bot = try XCTUnwrap(inspectors.first)
        let service = BotDecisionService()

        for _ in 0..<200 {
            let targetID = try XCTUnwrap(service.chooseInspectorTarget(
                botPlayer: bot,
                alivePlayers: gameStore.alivePlayers,
                nightHistory: gameStore.state.nightHistory
            ))
            XCTAssertNotEqual(gameStore.player(by: targetID)?.role, .inspector)
        }
    }

    @MainActor func testEndNight_StoresOnlyAliveMafiaNumbers() throws {
        setupGame(playerCount: 8)

        let mafiaPlayers = gameStore.state.players.filter { $0.role == .mafia }
        XCTAssertEqual(mafiaPlayers.count, 2)

        let eliminatedMafia = try XCTUnwrap(mafiaPlayers.first)
        let survivingNonMafia = try XCTUnwrap(gameStore.state.players.first { $0.role != .mafia })

        gameStore.applyDayRemovals(
            removed: [eliminatedMafia.id: true],
            notes: [eliminatedMafia.id: "Eliminated"]
        )

        XCTAssertFalse(gameStore.player(by: eliminatedMafia.id)?.alive ?? true)

        gameStore.endNight(
            mafiaTargetID: survivingNonMafia.id,
            inspectorCheckedID: nil,
            doctorProtectedID: nil
        )

        let action = try XCTUnwrap(gameStore.state.nightHistory.last)
        XCTAssertEqual(action.mafiaNumbers.count, 1)
        XCTAssertEqual(action.mafiaNumbers, gameStore.aliveMafia.map(\.number).sorted())
        XCTAssertFalse(action.mafiaNumbers.contains(eliminatedMafia.number))
    }

    @MainActor func testEndNight_StoresOnlyAlivePoliceAndDoctorNumbers() throws {
        setupGame(playerCount: 8)

        let doctor = try XCTUnwrap(gameStore.state.players.first { $0.role == .doctor })
        let inspector = try XCTUnwrap(gameStore.state.players.first { $0.role == .inspector })
        let survivingNonMafia = try XCTUnwrap(
            gameStore.state.players.first { player in
                player.role == .citizen && player.id != doctor.id && player.id != inspector.id
            }
        )

        gameStore.applyDayRemovals(
            removed: [doctor.id: true, inspector.id: true],
            notes: [doctor.id: "Eliminated", inspector.id: "Eliminated"]
        )

        gameStore.endNight(
            mafiaTargetID: survivingNonMafia.id,
            inspectorCheckedID: nil,
            doctorProtectedID: nil
        )

        let action = try XCTUnwrap(gameStore.state.nightHistory.last)
        XCTAssertEqual(action.inspectorNumbers ?? [], [])
        XCTAssertEqual(action.doctorNumbers ?? [], [])
        XCTAssertFalse((action.inspectorNumbers ?? []).contains(inspector.number))
        XCTAssertFalse((action.doctorNumbers ?? []).contains(doctor.number))
    }

    @MainActor func testApplyVotingResult_TieStillAdvancesDay() {
        setupGame(playerCount: 6)

        let alivePlayers = gameStore.state.players.filter(\.alive)
        var votingSession = VotingSession(dayIndex: gameStore.currentDayIndex)
        votingSession.recordVote(from: alivePlayers[0].id, for: alivePlayers[2].id)
        votingSession.recordVote(from: alivePlayers[1].id, for: alivePlayers[2].id)
        votingSession.recordVote(from: alivePlayers[2].id, for: alivePlayers[3].id)
        votingSession.recordVote(from: alivePlayers[3].id, for: alivePlayers[3].id)
        _ = votingSession.tallyVotes()

        gameStore.setVotingSessionForPreview(votingSession)
        gameStore.applyVotingResult()

        XCTAssertEqual(gameStore.state.dayIndex, 1)
        XCTAssertEqual(gameStore.state.dayHistory.count, 1)
        XCTAssertTrue(gameStore.state.dayHistory[0].removedPlayerIDs.isEmpty)
    }

    @MainActor func testApplyVotingResult_EliminationTransitionsToVoteDeathReveal() throws {
        setupGame(playerCount: 6)

        let eliminatedPlayer = try XCTUnwrap(gameStore.state.players.first { $0.role != .mafia })
        let voters = gameStore.state.players.filter { $0.id != eliminatedPlayer.id }
        var votingSession = VotingSession(dayIndex: gameStore.currentDayIndex)

        for voter in voters.prefix(3) {
            votingSession.recordVote(from: voter.id, for: eliminatedPlayer.id)
        }
        _ = votingSession.tallyVotes()

        gameStore.setVotingSessionForPreview(votingSession)
        gameStore.applyVotingResult()

        XCTAssertFalse(gameStore.player(by: eliminatedPlayer.id)?.alive ?? true)
        XCTAssertEqual(gameStore.state.dayHistory.last?.removedPlayerIDs, [eliminatedPlayer.id])
        XCTAssertEqual(gameStore.state.currentPhase, .voteDeathReveal)
        XCTAssertNil(gameStore.state.currentVotingSession)
        XCTAssertFalse(gameStore.state.isGameOver)
    }

    @MainActor func testCompleteVoteDeathReveal_StartsNextNightAfterVoteElimination() throws {
        setupGame(playerCount: 6)

        let eliminatedPlayer = try XCTUnwrap(gameStore.state.players.first { $0.role != .mafia })
        let voters = gameStore.state.players.filter { $0.id != eliminatedPlayer.id }
        var votingSession = VotingSession(dayIndex: gameStore.currentDayIndex)

        for voter in voters.prefix(3) {
            votingSession.recordVote(from: voter.id, for: eliminatedPlayer.id)
        }
        _ = votingSession.tallyVotes()

        gameStore.setVotingSessionForPreview(votingSession)
        gameStore.applyVotingResult()
        gameStore.completeVoteDeathReveal()

        XCTAssertEqual(gameStore.state.currentPhase, .nightWakeUp(activeRole: .mafia))
    }

    @MainActor func testCompleteVoteDeathReveal_ShowsGameOverWhenVoteEndsGame() throws {
        setupGame(playerCount: 4)

        let mafiaPlayer = try XCTUnwrap(gameStore.state.players.first { $0.role == .mafia })
        let voters = gameStore.state.players.filter { $0.id != mafiaPlayer.id }
        var votingSession = VotingSession(dayIndex: gameStore.currentDayIndex)

        for voter in voters {
            votingSession.recordVote(from: voter.id, for: mafiaPlayer.id)
        }
        _ = votingSession.tallyVotes()

        gameStore.setVotingSessionForPreview(votingSession)
        gameStore.applyVotingResult()

        XCTAssertTrue(gameStore.state.isGameOver)
        XCTAssertEqual(gameStore.state.currentPhase, .voteDeathReveal)

        gameStore.completeVoteDeathReveal()

        XCTAssertEqual(gameStore.state.currentPhase, .gameOver)
    }

    // MARK: - Day Phase Tests

    @MainActor func testApplyDayRemovals() {
        setupGame(playerCount: 6)

        let aliveCountBefore = gameStore.alivePlayers.count
        let targetPlayer = gameStore.alivePlayers.first!

        let removed: [UUID: Bool] = [targetPlayer.id: true]
        let notes: [UUID: String] = [targetPlayer.id: "Voted out"]

        gameStore.applyDayRemovals(removed: removed, notes: notes)

        let aliveCountAfter = gameStore.alivePlayers.count
        XCTAssertEqual(aliveCountAfter, aliveCountBefore - 1)

        let removedPlayer = gameStore.player(by: targetPlayer.id)
        XCTAssertNotNil(removedPlayer)
        XCTAssertFalse(removedPlayer!.alive)
        XCTAssertEqual(removedPlayer!.removalNote, "Voted out")
    }

    // MARK: - Win Condition Tests

    @MainActor func testMafiaWins_WhenEqualOrMoreThanNonMafia() {
        setupGame(playerCount: 6)

        // Kill non-mafia players through night actions until mafia >= non-mafia
        let nonMafiaPlayers = gameStore.state.players.filter { $0.role != .mafia }

        // Kill enough non-mafia to trigger mafia win (need 2 mafia vs 2 non-mafia)
        for i in 0..<(nonMafiaPlayers.count - 2) {
            gameStore.endNight(mafiaTargetID: nonMafiaPlayers[i].id, inspectorCheckedID: nil, doctorProtectedID: nil)
            gameStore.resolveNightOutcome(targetWasSaved: false)

            // Check if game ended
            if gameStore.state.isGameOver {
                break
            }
        }

        XCTAssertTrue(gameStore.state.isGameOver)
        XCTAssertEqual(gameStore.state.winner, .mafia)
        XCTAssertEqual(gameStore.state.currentPhase, .gameOver)
    }

    @MainActor func testMafiaWins_AtParityAfterAVote() throws {
        // 2 mafia and 3 others; voting one citizen out leaves 2 vs 2.
        let players = [
            SoloStateBuilder.player(.mafia, number: 1),
            SoloStateBuilder.player(.mafia, number: 2),
            SoloStateBuilder.player(.doctor, number: 3),
            SoloStateBuilder.player(.inspector, number: 4),
            SoloStateBuilder.player(.citizen, number: 5),
        ]
        gameStore = try environment.makeStore(loading: SoloStateBuilder.state(players, phase: .votingResults))

        vote(out: players[4])

        XCTAssertTrue(gameStore.state.isGameOver)
        XCTAssertEqual(gameStore.state.winner, .mafia)
    }

    @MainActor func testNoWinner_WhileMafiaIsOutnumbered() throws {
        let players = [
            SoloStateBuilder.player(.mafia, number: 1),
            SoloStateBuilder.player(.doctor, number: 2),
            SoloStateBuilder.player(.inspector, number: 3),
            SoloStateBuilder.player(.citizen, number: 4),
        ]
        gameStore = try environment.makeStore(loading: SoloStateBuilder.state(players))

        gameStore.endNight(mafiaTargetID: players[3].id, inspectorCheckedID: nil, doctorProtectedID: nil)
        gameStore.resolveNightOutcome(targetWasSaved: false)

        // 1 mafia against 2 others plays on.
        XCTAssertFalse(gameStore.state.isGameOver)
        XCTAssertNil(gameStore.state.winner)
    }

    @MainActor func testGameEnds_WhenOnlyBotsAreAlive() throws {
        // The last human dies at night; one bot mafia and two bot citizens remain.
        let human = SoloStateBuilder.player(.citizen, number: 1)
        let players = [
            human,
            SoloStateBuilder.player(.mafia, bot: true, number: 2),
            SoloStateBuilder.player(.citizen, bot: true, number: 3),
            SoloStateBuilder.player(.doctor, bot: true, number: 4),
        ]
        gameStore = try environment.makeStore(loading: SoloStateBuilder.state(players))

        gameStore.endNight(mafiaTargetID: human.id, inspectorCheckedID: nil, doctorProtectedID: nil)
        gameStore.resolveNightOutcome(targetWasSaved: false)

        XCTAssertTrue(gameStore.state.isGameOver)
        XCTAssertEqual(gameStore.state.winner, .mafia)
    }

    @MainActor func testAGameOfOnlyBots_PlaysToARealFinish() throws {
        // Setup allows a game with no human at all; the "only bots left" rule is for a
        // game whose humans are gone, so this one goes on until parity.
        let players = [
            SoloStateBuilder.player(.mafia, bot: true, number: 1),
            SoloStateBuilder.player(.inspector, bot: true, number: 2),
            SoloStateBuilder.player(.citizen, bot: true, number: 3),
            SoloStateBuilder.player(.citizen, bot: true, number: 4),
            SoloStateBuilder.player(.citizen, bot: true, number: 5),
        ]
        gameStore = try environment.makeStore(loading: SoloStateBuilder.state(players))

        gameStore.endNight(mafiaTargetID: players[4].id, inspectorCheckedID: nil, doctorProtectedID: nil)
        gameStore.resolveNightOutcome(targetWasSaved: false)

        XCTAssertFalse(gameStore.state.isGameOver, "1 mafia against 3 others plays on")
        XCTAssertNil(gameStore.state.winner)
    }

    @MainActor func testCitizensWin_WhenOnlyBotsWithoutMafiaRemain() throws {
        // Voting out the human mafia leaves only bot citizens.
        let mafia = SoloStateBuilder.player(.mafia, number: 1)
        let players = [
            mafia,
            SoloStateBuilder.player(.citizen, bot: true, number: 2),
            SoloStateBuilder.player(.citizen, bot: true, number: 3),
            SoloStateBuilder.player(.inspector, bot: true, number: 4),
        ]
        gameStore = try environment.makeStore(loading: SoloStateBuilder.state(players, phase: .votingResults))

        vote(out: mafia)

        XCTAssertTrue(gameStore.state.isGameOver)
        XCTAssertEqual(gameStore.state.winner, .citizen)
    }

    @MainActor func testNonMafiaWins_WhenAllMafiaDead() {
        setupGame(playerCount: 6)

        // Kill all mafia through day removals
        let mafiaPlayers = gameStore.state.players.filter { $0.role == .mafia }
        var removed: [UUID: Bool] = [:]
        var notes: [UUID: String] = [:]

        for mafia in mafiaPlayers {
            removed[mafia.id] = true
            notes[mafia.id] = "Voted out"
        }

        gameStore.applyDayRemovals(removed: removed, notes: notes)

        XCTAssertTrue(gameStore.state.isGameOver)
        XCTAssertEqual(gameStore.state.winner, .citizen)
    }

    // MARK: - Ended Game Tests

    @MainActor func testEndNight_DoesNothingAfterEndGame() {
        setupGame(playerCount: 6)
        let target = gameStore.alivePlayers.first { $0.role != .mafia }!

        gameStore.endGameEarly()
        gameStore.endNight(mafiaTargetID: target.id, inspectorCheckedID: nil, doctorProtectedID: nil)

        XCTAssertTrue(gameStore.state.nightHistory.isEmpty)
        XCTAssertNil(gameStore.state.winner)
    }

    @MainActor func testResolveNightOutcome_DoesNotKillAfterEndGame() {
        setupGame(playerCount: 6)
        let target = gameStore.alivePlayers.first { $0.role != .mafia }!
        gameStore.endNight(mafiaTargetID: target.id, inspectorCheckedID: nil, doctorProtectedID: nil)

        // A bot turn or the doctor's delayed transition lands after End Game.
        gameStore.endGameEarly()
        gameStore.resolveNightOutcome(targetWasSaved: false)

        XCTAssertTrue(gameStore.player(by: target.id)?.alive ?? false)
        XCTAssertFalse(gameStore.state.nightHistory[0].isResolved)
        XCTAssertNil(gameStore.state.winner)
    }

    // MARK: - Stats Tests

    @MainActor func testGameEnd_QueuesStatsForHumansOnly() throws {
        let mafia = SoloStateBuilder.player(.mafia, number: 1)
        let botMafia = SoloStateBuilder.player(.mafia, bot: true, number: 2)
        let doctor = SoloStateBuilder.player(.doctor, number: 3)
        let victim = SoloStateBuilder.player(.citizen, number: 4)
        let botCitizen = SoloStateBuilder.player(.citizen, bot: true, number: 5)
        let state = SoloStateBuilder.state([mafia, botMafia, doctor, victim, botCitizen])
        gameStore = try environment.makeStore(loading: state)

        // 2 mafia against 3; the night kill makes it 2 against 2.
        gameStore.endNight(mafiaTargetID: victim.id, inspectorCheckedID: nil, doctorProtectedID: nil)
        gameStore.resolveNightOutcome(targetWasSaved: false)
        XCTAssertEqual(gameStore.state.winner, .mafia)

        let entry = try XCTUnwrap(environment.outbox.pending.first)
        XCTAssertEqual(environment.outbox.pending.count, 1)
        XCTAssertEqual(entry.gameID, state.gameID?.uuidString.lowercased())
        XCTAssertEqual(entry.results.map(\.playerName), [mafia.name, doctor.name, victim.name])
        XCTAssertEqual(entry.results.map(\.won), [true, false, false])
        XCTAssertEqual(entry.results.map(\.kills), [1, 0, 0])
        XCTAssertEqual(entry.results.map(\.role), [.mafia, .doctor, .citizen])
    }

    @MainActor func testEarlyEnd_QueuesNoStats() {
        setupGame(playerCount: 6)

        gameStore.endGameEarly()

        XCTAssertTrue(environment.outbox.pending.isEmpty)
    }

    @MainActor func testGameEnd_StatsSurvivePlayAgain() throws {
        setupGame(playerCount: 4)
        let mafia = try XCTUnwrap(gameStore.state.players.first { $0.role == .mafia })
        vote(out: mafia)
        XCTAssertEqual(gameStore.state.winner, .citizen)

        gameStore.resetAll()

        XCTAssertEqual(environment.outbox.pending.count, 1)
        let reopened = StatsOutbox(fileURL: environment.directory.appendingPathComponent("StatsOutbox.json")) { _ in }
        XCTAssertEqual(reopened.pending, environment.outbox.pending)
    }

    // MARK: - Helper Methods

    @MainActor private func setupGame(playerCount: Int) {
        let names = (1...playerCount).map { "Player\($0)" }
        gameStore.assignNumbersAndRoles(names: names)
    }

    /// Applies a vote that eliminates `player`.
    @MainActor private func vote(out player: Player) {
        var votingSession = VotingSession(dayIndex: gameStore.currentDayIndex)
        votingSession.recordVote(from: UUID(), for: player.id)
        _ = votingSession.tallyVotes()
        gameStore.setVotingSessionForPreview(votingSession)
        gameStore.applyVotingResult()
    }
}
