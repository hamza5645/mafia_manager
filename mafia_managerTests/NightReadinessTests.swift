import Foundation
import Testing

@testable import mafia_manager

@MainActor
struct NightReadinessTests {
    @Test func absentRosterCannotCompleteNight() {
        #expect(MultiplayerGameStore.nightActionsReady(players: [], actions: [], roundId: UUID(), nightIndex: 0) == false)
    }

    private func player(role: Role?, bot: Bool = false) -> SessionPlayer {
        SessionPlayer(id: UUID(), sessionId: UUID(), userId: bot ? nil : UUID(), playerId: UUID(),
                      playerName: "QA", playerNumber: 1, role: role, isBot: bot, isAlive: true,
                      isOnline: true, isReady: true, lastHeartbeat: Date(), joinedAt: Date())
    }

    private func action(_ player: SessionPlayer, type: ActionType, round: UUID, night: Int = 0) -> GameAction {
        GameAction(id: UUID(), sessionId: player.sessionId, roundId: round, actionType: type,
                   phaseIndex: night, actorPlayerId: player.playerId, targetPlayerId: nil, createdAt: Date())
    }

    @Test func readyFlagsDoNotReplaceHumanOrBotActions() {
        let round = UUID()
        let police = player(role: .inspector)
        let mafia = player(role: .mafia, bot: true)
        let citizen = player(role: .citizen)
        let players = [police, mafia, citizen]
        let botAction = action(mafia, type: .mafiaTarget, round: round)
        #expect(MultiplayerGameStore.nightActionsReady(players: players, actions: [botAction], roundId: round, nightIndex: 0) == false)
        let humanAction = action(police, type: .inspectorCheck, round: round)
        #expect(MultiplayerGameStore.nightActionsReady(players: players, actions: [humanAction], roundId: round, nightIndex: 0) == false)
        #expect(MultiplayerGameStore.nightActionsReady(players: players, actions: [botAction, humanAction], roundId: round, nightIndex: 0))
    }

    @Test func staleOrWrongRoleActionsCannotCompleteNight() {
        let round = UUID()
        let police = player(role: .inspector)
        for invalid in [action(police, type: .inspectorCheck, round: UUID()),
                        action(police, type: .inspectorCheck, round: round, night: 1),
                        action(police, type: .mafiaTarget, round: round)] {
            #expect(MultiplayerGameStore.nightActionsReady(players: [police], actions: [invalid], roundId: round, nightIndex: 0) == false)
        }
    }

    @Test func deadRolesNeedNoActionAndUnknownLiveRolesFailClosed() {
        let round = UUID()
        var dead = player(role: .doctor)
        dead.isAlive = false
        #expect(MultiplayerGameStore.nightActionsReady(players: [dead, player(role: .citizen)], actions: [], roundId: round, nightIndex: 0))
        #expect(MultiplayerGameStore.nightActionsReady(players: [player(role: nil)], actions: [], roundId: round, nightIndex: 0) == false)
    }
}
