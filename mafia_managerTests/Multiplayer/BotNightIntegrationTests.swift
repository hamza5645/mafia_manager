import Foundation
import Testing

@testable import mafia_manager

@MainActor
struct BotNightIntegrationTests {
    enum Scenario: CaseIterable {
        case noActions, doctorSubmitted, humanMafiaSubmitted, mafiaBotSubmitted
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CONVEX_INTEGRATION"] == "1"),
          .timeLimit(.minutes(2)), arguments: Scenario.allCases)
    func assignedBotRolesLoadBeforeNightAndExistingActionsSurviveRetries(scenario: Scenario) async throws {
        let service = SessionService()
        let hash = "qa-bot-night-\(UUID().uuidString)"
        let host = try await AuthService().signInAsGuest(displayName: "QA Bot Night", guestSecretHash: hash)
        let room = try await service.createSession(hostUserId: host.id, guestSecretHash: hash)
        do {
            var lobby: [SessionPlayer] = []
            let hostIsMafia = scenario == .humanMafiaSubmitted
            let partialMafia = scenario == .mafiaBotSubmitted
            for index in 0..<((hostIsMafia || partialMafia) ? 5 : 4) {
                lobby.append(try await service.addPlayer(
                    sessionId: room.id, userId: index == 0 ? host.id : nil,
                    playerName: "QA Bot Night \(index)", isBot: index != 0,
                    callerUserId: host.id, guestSecretHash: hash
                ))
            }
            var assignments: [(UUID, Role, Int)] = [
                (lobby[0].playerId, hostIsMafia ? .mafia : .citizen, 1), (lobby[1].playerId, .mafia, 2),
                (lobby[2].playerId, .doctor, 3), (lobby[3].playerId, .inspector, 4)
            ]
            if hostIsMafia { assignments.append((lobby[4].playerId, .citizen, 5)) }
            if partialMafia { assignments.append((lobby[4].playerId, .mafia, 5)) }
            try await service.assignRolesAndNumbers(
                sessionId: room.id, assignments: assignments,
                callerUserId: host.id, guestSecretHash: hash
            )
            try await service.updateSessionStatus(sessionId: room.id, status: .inProgress,
                                                  callerUserId: host.id, guestSecretHash: hash)
            let phase = PhaseData.night(nightIndex: 0, activeRole: nil)
            try await service.updateSessionPhase(sessionId: room.id, currentPhase: "night", phaseData: phase,
                                                 callerUserId: host.id, guestSecretHash: hash)
            let active = try #require(try await service.getSession(sessionId: room.id, viewerUserId: host.id,
                                                                  guestSecretHash: hash))
            let round = try #require(active.currentRoundId)
            if scenario == .doctorSubmitted {
                _ = try await service.submitAction(.doctorAction(
                    sessionId: room.id, roundId: round, nightIndex: 0,
                    actorPlayerId: lobby[2].playerId, targetPlayerId: lobby[0].playerId
                ), callerUserId: host.id, guestSecretHash: hash)
            }
            if hostIsMafia {
                _ = try await service.submitAction(.mafiaAction(
                    sessionId: room.id, roundId: round, nightIndex: 0,
                    actorPlayerId: lobby[0].playerId, targetPlayerId: lobby[4].playerId
                ), callerUserId: host.id, guestSecretHash: hash)
            }
            if partialMafia {
                _ = try await service.submitAction(.mafiaAction(
                    sessionId: room.id, roundId: round, nightIndex: 0,
                    actorPlayerId: lobby[1].playerId, targetPlayerId: lobby[0].playerId
                ), callerUserId: host.id, guestSecretHash: hash)
            }
            let store = MultiplayerGameStore()
            store.testCurrentUserIdProvider = { host.id }
            store.testGuestSecretHashProvider = { hash }
            store.currentSession = active
            store.allPlayers = lobby // Role-less snapshot captured before assignment.
            store.myPlayer = lobby[0]
            store.isHost = true

            await store.testEnterPhase(phase)
            let types: [ActionType] = [.mafiaTarget, .doctorProtect, .inspectorCheck]
            let actions = try await service.getActionsForPhase(
                sessionId: room.id, actionTypes: types, phaseIndex: 0, roundId: round,
                viewerUserId: host.id, guestSecretHash: hash
            )
            let expectedActions = (hostIsMafia || partialMafia) ? 4 : 3
            #expect(actions.count == expectedActions, "Every living active bot must submit even when the phase arrives before roles")
            #expect(store.isPhaseReadyToAdvance)
            if scenario == .doctorSubmitted {
                #expect(actions.first(where: { $0.actionType == .doctorProtect })?.targetPlayerId == lobby[0].playerId,
                        "Recovery must preserve the doctor's already submitted target")
            }
            if hostIsMafia {
                #expect(actions.first(where: { $0.actorPlayerId == lobby[1].playerId })?.targetPlayerId == lobby[4].playerId,
                        "Missing bot actions must follow an existing human action even without its realtime event")
            }
            if partialMafia {
                #expect(actions.first(where: { $0.actorPlayerId == lobby[4].playerId })?.targetPlayerId == lobby[0].playerId,
                        "A Mafia bot retry must follow the target already submitted by its teammate")
            }
            await store.testEvaluatePhaseReadiness()
            let retried = try await service.getActionsForPhase(
                sessionId: room.id, actionTypes: types, phaseIndex: 0, roundId: round,
                viewerUserId: host.id, guestSecretHash: hash
            )
            #expect(retried.count == expectedActions)
            #expect(Set(retried.map(\.id)) == Set(actions.map(\.id)))
            #expect(Dictionary(uniqueKeysWithValues: retried.map { ($0.id, $0.createdAt) })
                    == Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0.createdAt) }),
                    "Readiness retries must not rewrite completed bot actions")
        } catch {
            try? await service.cancelSession(sessionId: room.id, callerUserId: host.id, guestSecretHash: hash)
            throw error
        }
        try await service.cancelSession(sessionId: room.id, callerUserId: host.id, guestSecretHash: hash)
    }
}
