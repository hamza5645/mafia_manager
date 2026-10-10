import Foundation
import Testing

@testable import mafia_manager

@MainActor
struct SessionReentryIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CONVEX_INTEGRATION"] == "1"),
          .timeLimit(.minutes(2)))
    func activeGuestReentryDecodesTheSameSeatAndRound() async throws {
        let service = SessionService()
        let hostHash = "qa-reentry-host-\(UUID().uuidString)"
        let guestHash = "qa-reentry-member-\(UUID().uuidString)"
        let host = try await AuthService().signInAsGuest(displayName: "QA Reentry Host", guestSecretHash: hostHash)
        let guest = try await AuthService().signInAsGuest(displayName: "QA Reentry Member", guestSecretHash: guestHash)
        let room = try await service.createSession(hostUserId: host.id, guestSecretHash: hostHash)
        do {
            let hostPlayer = try await service.addPlayer(sessionId: room.id, userId: host.id,
                playerName: host.displayName, isBot: false, callerUserId: host.id, guestSecretHash: hostHash)
            let (_, original) = try await service.joinSession(roomCode: room.roomCode, userId: guest.id,
                playerName: guest.displayName, guestSecretHash: guestHash)
            let mafia = try await service.addPlayer(sessionId: room.id, userId: nil,
                playerName: "QA Reentry Mafia", isBot: true, callerUserId: host.id, guestSecretHash: hostHash)
            let doctor = try await service.addPlayer(sessionId: room.id, userId: nil,
                playerName: "QA Reentry Doctor", isBot: true, callerUserId: host.id, guestSecretHash: hostHash)
            try await service.assignRolesAndNumbers(sessionId: room.id,
                assignments: [(hostPlayer.playerId, .citizen, 1), (original.playerId, .inspector, 2),
                              (mafia.playerId, .mafia, 3), (doctor.playerId, .doctor, 4)],
                callerUserId: host.id, guestSecretHash: hostHash)
            try await service.updateSessionStatus(sessionId: room.id, status: .inProgress,
                                                  callerUserId: host.id, guestSecretHash: hostHash)
            try await service.updateSessionPhase(sessionId: room.id, currentPhase: "night",
                phaseData: .night(nightIndex: 0, activeRole: nil), callerUserId: host.id, guestSecretHash: hostHash)
            let before = try #require(try await service.getSession(sessionId: room.id,
                viewerUserId: guest.id, guestSecretHash: guestHash))
            let (restored, player) = try await service.joinSession(roomCode: room.roomCode, userId: guest.id,
                playerName: "Ignored rename", guestSecretHash: guestHash)
            #expect(restored.id == room.id)
            #expect(restored.currentPhase == "night")
            #expect(restored.currentRoundId == before.currentRoundId)
            #expect(player.id == original.id)
            #expect(player.playerId == original.playerId)
            #expect(player.playerName == original.playerName)
            #expect(player.role == .inspector)
            #expect(player.playerNumber == 2)
            #expect(player.isAlive && player.isOnline)
            let roster = try await service.getSessionPlayers(sessionId: room.id,
                viewerUserId: host.id, guestSecretHash: hostHash)
            #expect(roster.count == 4)
        } catch {
            try? await service.cancelSession(sessionId: room.id, callerUserId: host.id, guestSecretHash: hostHash)
            throw error
        }
        try await service.cancelSession(sessionId: room.id, callerUserId: host.id, guestSecretHash: hostHash)
    }
}
