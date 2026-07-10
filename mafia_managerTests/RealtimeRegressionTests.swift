import XCTest

@testable import mafia_manager

@MainActor
final class RealtimeRegressionTests: XCTestCase {
    func testPlayerSnapshotsEmitInsertUpdateAndDeletionOnce() {
        let service = RealtimeService()
        let first = makePlayer(name: "First")
        let second = makePlayer(name: "Second")
        var updates: [UUID] = []
        var removals: [UUID] = []

        service.handlePlayersSnapshot(
            [first, second],
            onPlayerUpdate: { updates.append($0.id) },
            onPlayerRemoved: { removals.append($0) }
        )
        XCTAssertEqual(Set(updates), Set([first.id, second.id]))
        XCTAssertTrue(removals.isEmpty)

        updates.removeAll()
        var renamed = first
        renamed.playerName = "Renamed"
        let inserted = makePlayer(name: "Inserted")
        service.handlePlayersSnapshot(
            [renamed, second, inserted],
            onPlayerUpdate: { updates.append($0.id) },
            onPlayerRemoved: { removals.append($0) }
        )
        XCTAssertEqual(Set(updates), Set([first.id, inserted.id]))

        service.handlePlayersSnapshot(
            [renamed, inserted],
            onPlayerUpdate: { _ in },
            onPlayerRemoved: { removals.append($0) }
        )
        service.handlePlayersSnapshot(
            [renamed, inserted],
            onPlayerUpdate: { _ in },
            onPlayerRemoved: { removals.append($0) }
        )
        XCTAssertEqual(removals, [second.id])
    }

    func testOtherPlayerRemovalKeepsLocalMembership() {
        let store = MultiplayerGameStore()
        let local = makePlayer(name: "Local", role: .citizen, number: 1)
        let other = makePlayer(name: "Other")
        store.myPlayer = local
        store.allPlayers = [local, other]
        store.isInSession = true

        store.testHandlePlayerRemoval(other.id)

        XCTAssertEqual(store.myPlayer?.id, local.id)
        XCTAssertTrue(store.isInSession)
        XCTAssertFalse(store.wasKicked)
        XCTAssertFalse(store.allPlayers.contains(where: { $0.id == other.id }))
    }

    func testLocalPlayerRemovalClearsIdentityAndMarksKick() {
        let store = MultiplayerGameStore()
        let local = makePlayer(name: "Local", role: .mafia, number: 7)
        store.myPlayer = local
        store.myRole = .mafia
        store.myNumber = 7
        store.allPlayers = [local]
        store.isInSession = true
        store.isHost = true

        store.testHandlePlayerRemoval(local.id)

        XCTAssertNil(store.myPlayer)
        XCTAssertNil(store.myRole)
        XCTAssertNil(store.myNumber)
        XCTAssertFalse(store.isInSession)
        XCTAssertFalse(store.isHost)
        XCTAssertTrue(store.wasKicked)
    }

    private func makePlayer(
        name: String,
        role: Role? = nil,
        number: Int? = nil
    ) -> SessionPlayer {
        SessionPlayer(
            id: UUID(),
            sessionId: UUID(),
            userId: UUID(),
            playerId: UUID(),
            playerName: name,
            playerNumber: number,
            role: role,
            isBot: false,
            isAlive: true,
            isOnline: true,
            isReady: true,
            lastHeartbeat: Date(),
            joinedAt: Date(),
            removalNote: nil
        )
    }
}
