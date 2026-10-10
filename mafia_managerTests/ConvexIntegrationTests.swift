import CryptoKit
import Foundation
import Testing

@testable import mafia_manager

/// Live multiplayer tests against the Convex dev deployment in `ConvexConfig.swift`.
/// Opt in with `CONVEX_INTEGRATION=1`, e.g.:
///
///     xcodebuild test -workspace mafia_manager.xcworkspace -scheme mafia_manager \
///       -destination 'platform=iOS Simulator,name=iPhone 17' \
///       TEST_RUNNER_CONVEX_INTEGRATION=1 -only-testing:mafia_managerTests/ConvexIntegrationTests
///
/// Every request carries the guest proof that `act(as:)` installed, so each step
/// runs as exactly one guest. Subscriptions keep the proof they started with.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CONVEX_INTEGRATION"] == "1"),
       .serialized, .timeLimit(.minutes(2)))
struct ConvexIntegrationTests {
    private struct Timeout: Error, CustomStringConvertible {
        let description: String
    }

    private struct Guest: Decodable {
        let id: UUID
    }

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
            try await waitUntil("lobby snapshot") { host.currentSession != nil && host.players.count == 3 }
            act(as: memberHash)
            _ = try await service.joinSession(roomCode: try #require(host.currentSession?.roomCode), playerName: "QA Smoke Member")
            act(as: hostHash)
            try await waitUntil("member seat") { host.players.count == 4 }

            // Humans are citizens, so the night is decided by the bots alone.
            let bots = host.players.filter(\.isBot)
            try await startNight(host, room: room, roles: [bots[0].playerId: .mafia, bots[1].playerId: .inspector])

            try await waitUntil("bot night actions") { host.isPhaseReadyToAdvance }
            #expect(host.roundState?.actions.count == 2)
            try await host.completeNightPhase()
            try await waitUntil("resolved night") { host.currentSession?.currentPhase == "morning" }
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
            try await waitUntil("nine seats") { host.players.count == 9 && host.myPlayer != nil }
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
            try await waitUntil("every night action, including the bot inspector's") { host.isPhaseReadyToAdvance }
            let botCheck = host.roundState?.actions.first { $0.actorPlayerId == botInspector.playerId }
            #expect(botCheck?.targetPlayerId != nil)
            #expect(botCheck?.targetPlayerId != botInspector.playerId)

            try await host.completeNightPhase()
            try await waitUntil("resolved night") { host.currentSession?.nightHistory.first?.isResolved == true }
        }
    }

    @Test func memberReentersTheSameSeatMidGame() async throws {
        let hostHash = try await createGuest("QA Reentry Host")
        let memberHash = try await createGuest("QA Reentry Member")
        act(as: hostHash)
        let host = MultiplayerGameStore()
        try await host.createSession(playerName: "QA Reentry Host", botCount: 2)
        let room = try #require(host.sessionId)
        let member = MultiplayerGameStore()
        let relaunched = MultiplayerGameStore()

        try await withCleanup(room: room, guests: [hostHash, memberHash], stores: [host, member, relaunched]) {
            try await waitUntil("lobby snapshot") { host.currentSession != nil }
            let roomCode = try #require(host.currentSession?.roomCode)
            act(as: memberHash)
            try await member.joinSession(roomCode: roomCode, playerName: "QA Reentry Member")
            act(as: hostHash)
            try await waitUntil("member seat") { host.players.count == 4 && member.myPlayer != nil }
            let seat = try #require(member.myPlayer)
            let bots = host.players.filter(\.isBot)
            try await startNight(host, room: room, roles: [seat.playerId: .inspector, bots[0].playerId: .mafia])
            try await waitUntil("member night") { member.currentSession?.currentPhase == "night" && member.myRole == .inspector }

            // A relaunch starts from nothing: drop the first device's subscriptions, then re-enter.
            member.clearLocalSession()
            act(as: memberHash)
            let again = try await service.joinSession(roomCode: roomCode, playerName: "Ignored rename")
            try await relaunched.joinSession(roomCode: roomCode, playerName: "Ignored rename")
            act(as: hostHash)
            #expect(again.playerRecordId == seat.id)
            #expect(again.playerId == seat.playerId)

            try await waitUntil("relaunched snapshot") { relaunched.myPlayer != nil && relaunched.currentSession != nil }
            let restored = try #require(relaunched.myPlayer)
            #expect(restored.id == seat.id)
            #expect(restored.playerName == seat.playerName)
            #expect(restored.role == .inspector)
            #expect(restored.isAlive)
            #expect(relaunched.currentSession?.currentRoundId == host.currentSession?.currentRoundId)
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

    private func act(as hash: String) {
        ConvexService.shared.guestProofProvider = { hash }
    }

    /// Starts with fixed roles (unlisted seats are citizens), then moves from role reveal to night 0.
    private func startNight(_ host: MultiplayerGameStore, room: UUID, roles: [UUID: Role]) async throws {
        let assignments = host.players.enumerated().map { index, seat in
            RoleAssignment(playerId: seat.playerId, role: roles[seat.playerId] ?? .citizen, number: index + 1)
        }
        try await service.startGame(sessionId: room, assignments: assignments)
        try await waitUntil("role reveal") { host.currentSession?.currentPhase == "role_reveal" }
        try await host.forceStartNight()
        try await waitUntil("night round") {
            host.currentSession?.currentPhase == "night"
                && host.roundState?.roundId != nil
                && host.roundState?.roundId == host.currentSession?.currentRoundId
        }
    }

    private func waitUntil(_ what: String, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(20)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw Timeout(description: "Timed out waiting for \(what)") }
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
            act(as: guest)
            cancelled = (try? await service.cancelSession(sessionId: room)) != nil
        }
        if !cancelled { Issue.record("Could not cancel test room \(room)") }
        ConvexService.shared.guestProofProvider = originalProof
        if let failure { throw failure }
    }
}
