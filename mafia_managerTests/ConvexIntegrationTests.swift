import ConvexMobile
import CryptoKit
import Foundation
import Testing

@testable import mafia_manager

/// Live multiplayer tests against a Convex deployment running api_contract 5: the one in
/// `ConvexConfig.swift`, or in Debug builds the `MAFIA_CONVEX_URL` override (a local or
/// preview backend). Opt in with `CONVEX_INTEGRATION=1`; xcodebuild hands `TEST_RUNNER_`
/// variables to the test process, e.g.:
///
///     xcodebuild test -workspace mafia_manager.xcworkspace -scheme mafia_manager \
///       -destination 'platform=iOS Simulator,name=iPhone 17' \
///       TEST_RUNNER_CONVEX_INTEGRATION=1 TEST_RUNNER_MAFIA_CONVEX_URL=http://127.0.0.1:3210 \
///       -only-testing:mafia_managerTests/ConvexIntegrationTests
///
/// `ConvexService` sends one process-wide guest proof and reads it again on every request
/// and every resubscription. So only one live store, for the identity `act(as:)` installed,
/// runs at a time; it is stopped before the proof changes. Other players act through
/// one-shot calls that pass `guest_secret_hash` explicitly, which `ConvexService` keeps.
/// Every guest is named "QA …" so a dev-only purge can find what a run leaves behind.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CONVEX_INTEGRATION"] == "1"),
       .serialized, .timeLimit(.minutes(4)))
struct ConvexIntegrationTests {
    private struct Timeout: Error, CustomStringConvertible {
        let description: String
    }

    private struct Guest: Decodable {
        let id: UUID
    }

    /// A first snapshot can be dropped by ConvexMobile; recovery takes the supervisor's
    /// 15 s first-value timeout plus backoff, so these waits allow two drops.
    private static let firstSnapshot: Duration = .seconds(40)

    private let service = SessionService()
    private let originalProof = ConvexService.shared.guestProofProvider

    // MARK: - Tests

    @Test func smokeCreateJoinStartAndResolveABotNight() async throws {
        let hostHash = try await createGuest("QA Smoke Host")
        let memberHash = try await createGuest("QA Smoke Member")
        act(as: hostHash)
        let host = MultiplayerGameStore()
        try await host.createSession(playerName: "QA Smoke Host", botCount: 2)
        let room = try #require(host.sessionId)

        try await withCleanup(room: room, guests: [hostHash, memberHash], stores: [host]) {
            try await waitUntil("lobby snapshot", within: Self.firstSnapshot, watching: [host]) {
                host.currentSession != nil && host.players.count == 3
            }
            let roomCode = try #require(host.roomCode)
            #expect(roomCode == host.currentSession?.roomCode)
            let _: EnterResult = try await mutate("sessions:joinSession", as: memberHash, [
                "room_code": roomCode, "player_name": "QA Smoke Member",
            ])
            try await waitUntil("member seat", watching: [host]) { host.players.count == 4 }

            // Humans are citizens, so the night is decided by the bots alone.
            let bots = host.players.filter(\.isBot)
            try await startNight(host, room: room, roles: [bots[0].playerId: .mafia, bots[1].playerId: .inspector])

            // The member watches the host's presence, measured on the server clock.
            let presence: HostPresence? = try await query("views:getHostPresence", as: memberHash, room: room)
            #expect(presence?.hostUserId == host.currentSession?.hostUserId)
            #expect(presence?.hostLastHeartbeat != nil)
            #expect(presence?.staleAfterSeconds == 15)
            let outsider: HostPresence? = try await query("views:getHostPresence", as: try await createGuest("QA Outsider"), room: room)
            #expect(outsider == nil)

            try await waitUntil("bot night actions", watching: [host]) { host.isPhaseReadyToAdvance }
            #expect(host.roundState?.actions.count == 2)
            try await host.completeNightPhase() // night:finishNight
            try await waitUntil("resolved night", watching: [host]) { host.currentSession?.currentPhase == "morning" }
            let record = try #require(host.currentSession?.nightHistory.first)
            #expect(record.isResolved)
            #expect(record.resultingDeaths.count == 1)
        }
    }

    @Test func botInspectorPicksItsOwnTargetWhenTheHumanInspectsIt() async throws {
        let hostHash = try await createGuest("QA Inspector Host")
        act(as: hostHash)
        let host = MultiplayerGameStore()
        try await host.createSession(playerName: "QA Inspector Host", botCount: 8)
        let room = try #require(host.sessionId)

        try await withCleanup(room: room, guests: [hostHash], stores: [host]) {
            try await waitUntil("nine seats", within: Self.firstSnapshot, watching: [host]) {
                host.players.count == 9 && host.myPlayer != nil
            }
            let me = try #require(host.myPlayer)
            let bots = host.players.filter(\.isBot)
            var roles: [UUID: Role] = [me.playerId: .inspector, bots[0].playerId: .inspector, bots[5].playerId: .doctor]
            for bot in bots[1...4] { roles[bot.playerId] = .mafia }
            try await startNight(host, room: room, roles: roles)

            let botInspector = bots[0]
            let result = try await host.submitNightAction(
                actionType: .inspectorCheck, nightIndex: 0, targetPlayerId: botInspector.playerId
            )
            #expect(result == "blocked")
            try await waitUntil("every night action, including the bot inspector's", watching: [host]) {
                host.isPhaseReadyToAdvance
            }
            let botCheck = host.roundState?.actions.first { $0.actorPlayerId == botInspector.playerId }
            #expect(botCheck?.targetPlayerId != nil)
            #expect(botCheck?.targetPlayerId != botInspector.playerId)

            try await host.completeNightPhase()
            try await waitUntil("resolved night", watching: [host]) { host.currentSession?.nightHistory.first?.isResolved == true }
        }
    }

    @Test func memberReentersTheSameSeatMidGame() async throws {
        let hostHash = try await createGuest("QA Reentry Host")
        let memberHash = try await createGuest("QA Reentry Member")
        act(as: hostHash)
        let host = MultiplayerGameStore()
        try await host.createSession(playerName: "QA Reentry Host", botCount: 2)
        let room = try #require(host.sessionId)
        let relaunched = MultiplayerGameStore()

        try await withCleanup(room: room, guests: [hostHash, memberHash], stores: [host, relaunched]) {
            try await waitUntil("lobby snapshot", within: Self.firstSnapshot, watching: [host]) { host.currentSession != nil }
            let roomCode = try #require(host.roomCode)
            let joined: EnterResult = try await mutate("sessions:joinSession", as: memberHash, [
                "room_code": roomCode, "player_name": "QA Reentry Member",
            ])
            #expect(!joined.rejoined)
            try await waitUntil("member seat", watching: [host]) { host.players.count == 4 }
            let seat = try #require(host.players.first { $0.id == joined.playerRecordId })
            let bots = host.players.filter(\.isBot)
            try await startNight(host, room: room, roles: [seat.playerId: .inspector, bots[0].playerId: .mafia])

            let memberView: [SessionPlayer] = try await query("views:getPlayers", as: memberHash, room: room)
            #expect(memberView.first(where: \.isMe)?.role == .inspector)
            let roundId = host.currentSession?.currentRoundId

            // A relaunch starts from nothing. The host's store stops before the proof changes.
            host.clearLocalSession()
            act(as: memberHash)
            let again = try await service.joinSession(roomCode: roomCode, playerName: "Ignored rename")
            #expect(again.playerRecordId == seat.id)
            #expect(again.playerId == seat.playerId)
            #expect(again.rejoined)
            try await relaunched.joinSession(roomCode: roomCode, playerName: "Ignored rename")

            try await waitUntil("relaunched snapshot", within: Self.firstSnapshot, watching: [relaunched]) {
                relaunched.myPlayer != nil && relaunched.currentSession != nil
            }
            let restored = try #require(relaunched.myPlayer)
            #expect(restored.id == seat.id)
            #expect(restored.playerName == seat.playerName)
            #expect(restored.role == .inspector)
            #expect(restored.isAlive)
            #expect(relaunched.currentSession?.currentRoundId == roundId)
            #expect(!relaunched.isHostOffline, "The host heartbeated moments ago")
        }
    }

    // MARK: - Helpers

    /// A fresh 64-hex guest secret hash per run.
    private func createGuest(_ name: String) async throws -> String {
        let hash = SHA256.hash(data: Data(UUID().uuidString.utf8)).map { String(format: "%02x", $0) }.joined()
        let _: Guest = try await ConvexService.shared.mutation(
            "users:createOrRestoreGuest", with: ["display_name": name, "guest_secret_hash": hash]
        )
        return hash
    }

    /// The identity every request without an explicit proof uses, live stores included.
    private func act(as hash: String) {
        ConvexService.shared.guestProofProvider = { hash }
    }

    /// One mutation as `guest`, whatever proof is installed.
    private func mutate<T: Decodable>(_ name: String, as guest: String, _ args: [String: ConvexEncodable?]) async throws -> T {
        var args = args
        args["guest_secret_hash"] = guest
        return try await ConvexService.shared.mutation(name, with: args)
    }

    /// One `views:*` value for `room` as `guest`, whatever proof is installed.
    private func query<T: Decodable>(_ name: String, as guest: String, room: UUID) async throws -> T {
        try await ConvexService.shared.query(name, with: [
            "session_id": room.uuidString.lowercased(), "guest_secret_hash": guest,
        ])
    }

    /// Starts with fixed roles (unlisted seats are citizens), then moves from role reveal to night 0.
    private func startNight(_ host: MultiplayerGameStore, room: UUID, roles: [UUID: Role]) async throws {
        let assignments = host.players.enumerated().map { index, seat in
            RoleAssignment(playerId: seat.playerId, role: roles[seat.playerId] ?? .citizen, number: index + 1)
        }
        try await service.startGame(sessionId: room, assignments: assignments)
        try await waitUntil("role reveal", watching: [host]) { host.currentSession?.currentPhase == "role_reveal" }
        try await host.forceStartNight()
        try await waitUntil("night round", watching: [host]) {
            host.currentSession?.currentPhase == "night"
                && host.roundState?.roundId != nil
                && host.roundState?.roundId == host.currentSession?.currentRoundId
        }
    }

    /// Polls `condition`; a timeout names each watched store's subscription states.
    private func waitUntil(
        _ what: String,
        within limit: Duration = .seconds(20),
        watching stores: [MultiplayerGameStore] = [],
        _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + limit
        while !condition() {
            guard ContinuousClock.now < deadline else {
                let states = stores.map { store in
                    store.subscriptions.map { "\($0.label): \($0.status)" }.joined(separator: ", ")
                }
                throw Timeout(description: "Timed out after \(limit) waiting for \(what). Subscriptions: \(states)")
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Runs `body`, then always stops the stores, cancels the room and restores the proof.
    /// The room is cancelled by whichever guest is host now (a night death can move host).
    private func withCleanup(
        room: UUID,
        guests: [String],
        stores: [MultiplayerGameStore],
        _ body: () async throws -> Void
    ) async throws {
        var failure: Error?
        do {
            try await body()
        } catch {
            failure = error
        }
        stores.forEach { $0.clearLocalSession() }
        var cancelled = false
        for guest in guests where !cancelled {
            cancelled = (try? await ConvexService.shared.mutation(
                "sessions:cancelSession", with: ["session_id": room.uuidString.lowercased(), "guest_secret_hash": guest]
            )) != nil
        }
        if !cancelled { Issue.record("Could not cancel test room \(room)") }
        ConvexService.shared.guestProofProvider = originalProof
        if let failure { throw failure }
    }
}
