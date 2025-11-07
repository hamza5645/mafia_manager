import XCTest
@testable import mafia_manager

@MainActor
final class GameStoreTests: XCTestCase {

    var gameStore: GameStore!

    override func setUp() async throws {
        gameStore = GameStore()
        gameStore.resetAll()
    }

    override func tearDown() async throws {
        gameStore = nil
    }

    // MARK: - Setup Tests

    func testInitialState() {
        XCTAssertTrue(gameStore.state.players.isEmpty)
        XCTAssertTrue(gameStore.isFreshSetup)
        XCTAssertEqual(gameStore.state.nightHistory.count, 0)
        XCTAssertEqual(gameStore.state.dayHistory.count, 0)
        XCTAssertFalse(gameStore.state.isGameOver)
        XCTAssertNil(gameStore.state.winner)
    }

    func testAssignNumbersAndRoles_MinimumPlayers() {
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

    func testAssignNumbersAndRoles_MediumGame() {
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

    func testAssignNumbersAndRoles_TooFewPlayers() {
        let names = ["Alice", "Bob"]
        gameStore.assignNumbersAndRoles(names: names)

        // Should not assign roles with fewer than 4 players
        XCTAssertTrue(gameStore.state.players.isEmpty)
        XCTAssertTrue(gameStore.isFreshSetup)
    }

    func testAssignNumbersAndRoles_TooManyPlayers() {
        let names = Array(repeating: "Player", count: 20).enumerated().map { "Player\($0)" }
        gameStore.assignNumbersAndRoles(names: names)

        // Should not assign roles with more than 19 players
        XCTAssertTrue(gameStore.state.players.isEmpty)
        XCTAssertTrue(gameStore.isFreshSetup)
    }

    func testAssignNumbersAndRoles_DuplicateNames() {
        let names = ["Alice", "Bob", "Alice", "Charlie"]
        gameStore.assignNumbersAndRoles(names: names)

        // Should reject duplicate names
        XCTAssertTrue(gameStore.state.players.isEmpty)
        XCTAssertTrue(gameStore.isFreshSetup)
    }

    func testAssignNumbersAndRoles_AllPlayersAlive() {
        let names = ["Alice", "Bob", "Charlie", "David"]
        gameStore.assignNumbersAndRoles(names: names)

        for player in gameStore.state.players {
            XCTAssertTrue(player.alive)
            XCTAssertNil(player.removalNote)
        }
    }

    // MARK: - Night Phase Tests

    func testEndNight_RecordsActions() {
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

    func testResolveNightOutcome_TargetKilled() {
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

    func testResolveNightOutcome_TargetSaved() {
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

    func testInspectorCheck_DetectsMafia() {
        setupGame(playerCount: 6)

        let mafiaPlayer = gameStore.state.players.first { $0.role == .mafia }!

        gameStore.endNight(mafiaTargetID: nil, inspectorCheckedID: mafiaPlayer.id, doctorProtectedID: nil)

        let action = gameStore.state.nightHistory[0]
        XCTAssertEqual(action.inspectorResultIsMafia, true)
        XCTAssertEqual(action.inspectorResultRole, .mafia)
    }

    func testInspectorCheck_DetectsInnocent() {
        setupGame(playerCount: 6)

        let citizenPlayer = gameStore.state.players.first { $0.role == .citizen }!

        gameStore.endNight(mafiaTargetID: nil, inspectorCheckedID: citizenPlayer.id, doctorProtectedID: nil)

        let action = gameStore.state.nightHistory[0]
        XCTAssertEqual(action.inspectorResultIsMafia, false)
        XCTAssertEqual(action.inspectorResultRole, .citizen)
    }

    func testInspectorCheck_CannotIdentifyOtherInspectors() {
        setupGame(playerCount: 8) // Has 2 inspectors

        let inspectors = gameStore.state.players.filter { $0.role == .inspector }
        if inspectors.count >= 2 {
            gameStore.endNight(mafiaTargetID: nil, inspectorCheckedID: inspectors[1].id, doctorProtectedID: nil)

            let action = gameStore.state.nightHistory[0]
            XCTAssertNil(action.inspectorResultIsMafia)
            XCTAssertNil(action.inspectorResultRole)
        }
    }

    // MARK: - Day Phase Tests

    func testApplyDayRemovals() {
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

    func testMafiaWins_WhenEqualOrMoreThanNonMafia() {
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
    }

    func testNonMafiaWins_WhenAllMafiaDead() {
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

    // MARK: - Helper Methods

    private func setupGame(playerCount: Int) {
        let names = (1...playerCount).map { "Player\($0)" }
        gameStore.assignNumbersAndRoles(names: names)
    }
}
