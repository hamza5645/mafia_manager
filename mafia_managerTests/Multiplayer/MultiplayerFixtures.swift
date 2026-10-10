import Foundation

@testable import mafia_manager

/// Small builders for multiplayer unit tests.
enum Fixture {
    static func seat(
        _ role: Role?,
        bot: Bool = true,
        alive: Bool = true,
        ready: Bool = true,
        isMe: Bool = false,
        joinedAt: Date = Date(),
        lastHeartbeat: Date = Date()
    ) -> SessionPlayer {
        SessionPlayer(
            id: UUID(), sessionId: UUID(), userId: bot ? nil : UUID(), playerId: UUID(),
            playerName: "\(bot ? "Bot" : "Human") \(role?.rawValue ?? "unassigned")", playerNumber: nil,
            role: role, isBot: bot, isAlive: alive, isOnline: true, isReady: ready,
            lastHeartbeat: lastHeartbeat, joinedAt: joinedAt, isMe: isMe
        )
    }

    static func action(
        _ actor: SessionPlayer,
        _ type: ActionType,
        target: SessionPlayer?,
        round: UUID = UUID(),
        at seconds: TimeInterval = 0
    ) -> GameAction {
        GameAction(
            id: UUID(), sessionId: actor.sessionId, roundId: round, actionType: type, phaseIndex: 0,
            actorPlayerId: actor.playerId, targetPlayerId: target?.playerId,
            createdAt: Date(timeIntervalSinceReferenceDate: seconds)
        )
    }

    static func session(status: SessionStatus = .inProgress, phase: String = "night", roundId: UUID? = UUID()) -> GameSession {
        GameSession(
            id: UUID(), roomCode: "123456", hostUserId: UUID(), status: status, createdAt: Date(),
            maxPlayers: 19, botCount: 0, currentPhase: phase, currentPhaseData: nil, dayIndex: 0,
            isGameOver: false, assignedNumbers: [], nightHistory: [], dayHistory: [],
            currentRoundId: roundId, updatedAt: Date()
        )
    }

    static func view(_ session: GameSession, isMember: Bool = true, isHost: Bool = false) -> SessionView {
        SessionView(session: session, viewer: .init(
            userId: UUID(), playerRecordId: nil, playerId: nil, isMember: isMember, isHost: isHost
        ))
    }

    static func round(
        phase: String = "night",
        ready: Bool = false,
        actions: [GameAction] = [],
        tentative: [TentativeSelection] = []
    ) -> RoundState {
        RoundState(roundId: UUID(), phase: phase, phaseIndex: 0, readyToAdvance: ready, actions: actions, tentative: tentative)
    }
}
