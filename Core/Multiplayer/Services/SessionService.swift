import Foundation
import ConvexMobile

@MainActor
final class SessionService {
    private let convex = ConvexService.shared

    // MARK: - Session Management

    func createSession(
        hostUserId: UUID,
        maxPlayers: Int = 19,
        botCount: Int = 0,
        guestSecretHash: String? = nil
    ) async throws -> GameSession {
        try await convex.mutation(
            "sessions:createSession",
            with: [
                "host_user_id": hostUserId.uuidString.lowercased(),
                "max_players": Double(maxPlayers),
                "bot_count": Double(botCount),
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    func joinSession(
        roomCode: String,
        userId: UUID,
        playerName: String,
        guestSecretHash: String? = nil
    ) async throws -> (GameSession, SessionPlayer) {
        let response: JoinSessionResponse = try await convex.mutation(
            "sessions:joinSession",
            with: [
                "room_code": roomCode.uppercased(),
                "user_id": userId.uuidString.lowercased(),
                "player_name": playerName,
                "guest_secret_hash": guestSecretHash,
            ]
        )
        return (response.session, response.player)
    }

    func leaveSession(sessionId: UUID, userId: UUID, guestSecretHash: String? = nil) async throws {
        try await convex.mutation(
            "sessions:leaveSession",
            with: [
                "session_id": sessionId.uuidString.lowercased(),
                "user_id": userId.uuidString.lowercased(),
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    func removePlayer(playerId: UUID, callerUserId: UUID, guestSecretHash: String? = nil) async throws {
        try await convex.mutation(
            "sessions:removePlayer",
            with: [
                "player_id": playerId.uuidString.lowercased(),
                "caller_user_id": callerUserId.uuidString.lowercased(),
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    func getSession(sessionId: UUID) async throws -> GameSession? {
        try await convex.query(
            "sessions:getSessionById",
            with: ["session_id": sessionId.uuidString.lowercased()],
            as: GameSession?.self
        )
    }

    func getSessionByRoomCode(roomCode: String) async throws -> GameSession? {
        try await convex.query(
            "sessions:getSessionByRoomCode",
            with: ["room_code": roomCode.uppercased()],
            as: GameSession?.self
        )
    }

    func updateSessionStatus(
        sessionId: UUID,
        status: SessionStatus,
        callerUserId: UUID,
        guestSecretHash: String? = nil
    ) async throws {
        try await convex.mutation(
            "sessions:updateSessionStatus",
            with: [
                "session_id": sessionId.uuidString.lowercased(),
                "status": status.rawValue,
                "caller_user_id": callerUserId.uuidString.lowercased(),
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    func updateSessionHost(
        sessionId: UUID,
        newHostUserId: UUID,
        callerUserId: UUID,
        guestSecretHash: String? = nil
    ) async throws {
        try await convex.mutation(
            "sessions:updateSessionHost",
            with: [
                "session_id": sessionId.uuidString.lowercased(),
                "new_host_user_id": newHostUserId.uuidString.lowercased(),
                "caller_user_id": callerUserId.uuidString.lowercased(),
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    func updateSessionPhase(
        sessionId: UUID,
        currentPhase: String,
        phaseData: PhaseData?,
        callerUserId: UUID,
        guestSecretHash: String? = nil
    ) async throws {
        try await convex.mutation(
            "sessions:updateSessionPhase",
            with: [
                "session_id": sessionId.uuidString.lowercased(),
                "current_phase": currentPhase,
                "current_phase_data": try phaseData.map { try raw($0) },
                "caller_user_id": callerUserId.uuidString.lowercased(),
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    func updateSessionState(
        sessionId: UUID,
        callerUserId: UUID,
        currentPhase: String? = nil,
        phaseData: PhaseData? = nil,
        dayIndex: Int? = nil,
        nightHistory: [NightActionRecord]? = nil,
        dayHistory: [DayActionRecord]? = nil,
        isGameOver: Bool? = nil,
        winner: Role? = nil,
        guestSecretHash: String? = nil
    ) async throws {
        var args: [String: ConvexEncodable?] = [
            "session_id": sessionId.uuidString.lowercased(),
            "caller_user_id": callerUserId.uuidString.lowercased(),
            "current_phase": currentPhase,
            "day_index": dayIndex.map(Double.init),
            "is_game_over": isGameOver,
            "winner": winner?.rawValue,
            "guest_secret_hash": guestSecretHash,
        ]
        if let phaseData {
            args["current_phase_data"] = try raw(phaseData)
        }
        if let nightHistory {
            args["night_history"] = try raw(nightHistory)
        }
        if let dayHistory {
            args["day_history"] = try raw(dayHistory)
        }
        try await convex.mutation("sessions:updateSessionState", with: args)
    }

    func resolveNightAtomic(
        sessionId: UUID,
        nightRecord: NightActionRecord,
        eliminatedPlayerIds: [UUID],
        nextPhase: String,
        nextPhaseData: PhaseData,
        callerUserId: UUID,
        isGameOver: Bool? = nil,
        winner: Role? = nil,
        guestSecretHash: String? = nil
    ) async throws -> Bool {
        try await convex.mutation(
            "sessions:resolveNightAtomic",
            with: [
                "session_id": sessionId.uuidString.lowercased(),
                "night_record": try raw(nightRecord),
                "eliminated_player_ids": eliminatedPlayerIds.map { $0.uuidString.lowercased() as ConvexEncodable? },
                "next_phase": nextPhase,
                "next_phase_data": try raw(nextPhaseData),
                "is_game_over": isGameOver,
                "winner": winner?.rawValue,
                "caller_user_id": callerUserId.uuidString.lowercased(),
                "guest_secret_hash": guestSecretHash,
            ],
            as: Bool.self
        )
    }

    // MARK: - Player Management

    func getSessionPlayers(
        sessionId: UUID,
        viewerUserId: UUID? = nil,
        guestSecretHash: String? = nil
    ) async throws -> [SessionPlayer] {
        try await convex.query(
            "sessions:getSessionPlayers",
            with: [
                "session_id": sessionId.uuidString.lowercased(),
                "viewer_user_id": viewerUserId?.uuidString.lowercased(),
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    func addPlayer(
        sessionId: UUID,
        userId: UUID?,
        playerName: String,
        isBot: Bool,
        callerUserId: UUID? = nil,
        guestSecretHash: String? = nil
    ) async throws -> SessionPlayer {
        try await convex.mutation(
            "sessions:addPlayer",
            with: [
                "session_id": sessionId.uuidString.lowercased(),
                "user_id": userId?.uuidString.lowercased(),
                "player_name": playerName,
                "is_bot": isBot,
                "caller_user_id": callerUserId?.uuidString.lowercased(),
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    func updatePlayerReady(
        playerId: UUID,
        isReady: Bool,
        guestSecretHash: String? = nil
    ) async throws {
        try await convex.mutation(
            "sessions:updatePlayerReady",
            with: [
                "player_id": playerId.uuidString.lowercased(),
                "is_ready": isReady,
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    func resetAllPlayersReady(
        sessionId: UUID,
        callerUserId: UUID,
        guestSecretHash: String? = nil
    ) async throws {
        try await convex.mutation(
            "sessions:resetAllPlayersReady",
            with: [
                "session_id": sessionId.uuidString.lowercased(),
                "caller_user_id": callerUserId.uuidString.lowercased(),
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    func updatePlayerLifeStatus(
        recordId: UUID,
        isAlive: Bool,
        removalNote: String?,
        callerUserId: UUID,
        guestSecretHash: String? = nil
    ) async throws {
        try await convex.mutation(
            "sessions:updatePlayerLifeStatus",
            with: [
                "record_id": recordId.uuidString.lowercased(),
                "is_alive": isAlive,
                "removal_note": removalNote,
                "caller_user_id": callerUserId.uuidString.lowercased(),
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    func updatePlayerHeartbeat(playerId: UUID, guestSecretHash: String? = nil) async throws {
        try await convex.mutation(
            "sessions:updatePlayerHeartbeat",
            with: [
                "player_id": playerId.uuidString.lowercased(),
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    func assignRolesAndNumbers(
        sessionId: UUID,
        assignments: [(playerId: UUID, role: Role, number: Int)],
        callerUserId: UUID,
        guestSecretHash: String? = nil
    ) async throws {
        let payload: [[String: ConvexEncodable?]] = assignments.map {
            [
                "player_id": $0.playerId.uuidString.lowercased(),
                "role": $0.role.rawValue,
                "number": Double($0.number),
            ]
        }

        try await convex.mutation(
            "sessions:assignRolesAndNumbers",
            with: [
                "session_id": sessionId.uuidString.lowercased(),
                "assignments": payload.map { $0 as ConvexEncodable? },
                "caller_user_id": callerUserId.uuidString.lowercased(),
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    // MARK: - Game Actions

    @discardableResult
    func submitAction(
        _ action: GameAction,
        callerUserId: UUID? = nil,
        guestSecretHash: String? = nil
    ) async throws -> ActionResponse {
        try await convex.mutation(
            "sessions:submitAction",
            with: [
                "session_id": action.sessionId.uuidString.lowercased(),
                "round_id": action.roundId.uuidString.lowercased(),
                "action_type": action.actionType.rawValue,
                "phase_index": Double(action.phaseIndex),
                "actor_player_id": action.actorPlayerId.uuidString.lowercased(),
                "target_player_id": action.targetPlayerId?.uuidString.lowercased(),
                "caller_user_id": callerUserId?.uuidString.lowercased(),
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    func getActionsForPhase(
        sessionId: UUID,
        actionType: ActionType,
        phaseIndex: Int,
        roundId: UUID? = nil,
        viewerUserId: UUID? = nil,
        guestSecretHash: String? = nil
    ) async throws -> [GameAction] {
        try await getActionsForPhase(
            sessionId: sessionId,
            actionTypes: [actionType],
            phaseIndex: phaseIndex,
            roundId: roundId,
            viewerUserId: viewerUserId,
            guestSecretHash: guestSecretHash
        )
    }

    func getActionsForPhase(
        sessionId: UUID,
        actionTypes: [ActionType],
        phaseIndex: Int,
        roundId: UUID? = nil,
        viewerUserId: UUID? = nil,
        guestSecretHash: String? = nil
    ) async throws -> [GameAction] {
        try await convex.query(
            "sessions:getActionsForPhase",
            with: [
                "session_id": sessionId.uuidString.lowercased(),
                "action_types": actionTypes.map(\.rawValue),
                "phase_index": Double(phaseIndex),
                "round_id": roundId?.uuidString.lowercased(),
                "viewer_user_id": viewerUserId?.uuidString.lowercased(),
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    func getAllActions(
        sessionId: UUID,
        viewerUserId: UUID? = nil,
        guestSecretHash: String? = nil
    ) async throws -> [GameAction] {
        try await convex.query(
            "sessions:getAllActions",
            with: [
                "session_id": sessionId.uuidString.lowercased(),
                "viewer_user_id": viewerUserId?.uuidString.lowercased(),
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    // MARK: - Instant Return to Lobby

    func returnToLobby(
        sessionId: UUID,
        playerId: UUID,
        playerUserId: UUID,
        originalHostUserId: UUID,
        guestSecretHash: String? = nil
    ) async throws {
        try await convex.mutation(
            "sessions:returnToLobby",
            with: [
                "session_id": sessionId.uuidString.lowercased(),
                "player_id": playerId.uuidString.lowercased(),
                "player_user_id": playerUserId.uuidString.lowercased(),
                "original_host_user_id": originalHostUserId.uuidString.lowercased(),
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    private func raw<T: Encodable>(_ value: T) throws -> RawConvexValue {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw SessionError.operationFailed("Could not encode Convex JSON argument")
        }
        return RawConvexValue(json: string)
    }
}

private struct RawConvexValue: ConvexEncodable {
    let json: String

    func convexEncode() throws -> String {
        json
    }
}

private struct JoinSessionResponse: Decodable {
    let session: GameSession
    let player: SessionPlayer
}

struct ActionResponse: Decodable, Sendable {
    let success: Bool
    let result: String?
}

enum SessionError: LocalizedError {
    case sessionNotCreated
    case sessionNotFound
    case sessionFull
    case alreadyInSession
    case playerNotCreated
    case notHost
    case invalidPhase
    case notAuthenticated
    case sessionMismatch
    case noActiveSession
    case playerNotFound
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .sessionNotCreated:
            return "Failed to create game session"
        case .sessionNotFound:
            return "Game session not found"
        case .sessionFull:
            return "Game session is full"
        case .alreadyInSession:
            return "You are already in this session"
        case .playerNotCreated:
            return "Failed to add player to session"
        case .notHost:
            return "Only the host can perform this action"
        case .invalidPhase:
            return "Cannot perform this action in the current phase"
        case .notAuthenticated:
            return "Please sign in to join a multiplayer game"
        case .sessionMismatch:
            return "Authentication error. Please sign out and sign in again"
        case .noActiveSession:
            return "No active game session"
        case .playerNotFound:
            return "Player not found in session"
        case .operationFailed(let message):
            return message
        }
    }
}
