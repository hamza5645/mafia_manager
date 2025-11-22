import Foundation
import Supabase

@MainActor
final class SessionService {
    private let supabase = SupabaseService.shared.client

    // MARK: - Session Management

    /// Create a new game session with a unique room code
    func createSession(
        hostUserId: UUID,
        maxPlayers: Int = 19,
        botCount: Int = 0
    ) async throws -> GameSession {
        // CRITICAL: Verify auth session is valid before creating a session
        // The RLS policy checks auth.uid() = host_user_id
        guard let currentSession = try? await supabase.auth.session else {
            throw SessionError.notAuthenticated
        }

        // Verify the session's user ID matches the requested hostUserId
        guard currentSession.user.id == hostUserId else {
            throw SessionError.sessionMismatch
        }

        // Generate room code via RPC function
        let roomCode: String = try await supabase
            .rpc("generate_room_code")
            .execute()
            .value

        struct CreateSessionData: Encodable {
            let roomCode: String
            let hostUserId: String
            let status: String
            let maxPlayers: Int
            let botCount: Int
            let currentPhase: String
            let dayIndex: Int
            let isGameOver: Bool
            let assignedNumbers: [Int] // Empty JSON array
            let nightHistory: [String] // Empty JSON array
            let dayHistory: [String] // Empty JSON array

            enum CodingKeys: String, CodingKey {
                case roomCode = "room_code"
                case hostUserId = "host_user_id"
                case status
                case maxPlayers = "max_players"
                case botCount = "bot_count"
                case currentPhase = "current_phase"
                case dayIndex = "day_index"
                case isGameOver = "is_game_over"
                case assignedNumbers = "assigned_numbers"
                case nightHistory = "night_history"
                case dayHistory = "day_history"
            }
        }

        let createData = CreateSessionData(
            roomCode: roomCode,
            hostUserId: hostUserId.uuidString,
            status: "waiting",
            maxPlayers: maxPlayers,
            botCount: botCount,
            currentPhase: "lobby",
            dayIndex: 0,
            isGameOver: false,
            assignedNumbers: [],
            nightHistory: [],
            dayHistory: []
        )

        let sessions: [GameSession] = try await supabase
            .from("game_sessions")
            .insert(createData)
            .select()
            .execute()
            .value

        guard let session = sessions.first else {
            throw SessionError.sessionNotCreated
        }

        return session
    }

    /// Join an existing session by room code
    func joinSession(roomCode: String, userId: UUID, playerName: String) async throws -> (GameSession, SessionPlayer) {
        // CRITICAL: Verify auth session is valid before attempting to join
        // The RLS policy checks auth.uid() = user_id, so we need a valid JWT session
        guard let currentSession = try? await supabase.auth.session else {
            print("❌ [SessionService] No Supabase auth session found")
            throw SessionError.notAuthenticated
        }

        print("✅ [SessionService] Auth session found - User ID: \(currentSession.user.id)")
        print("📝 [SessionService] Requested user ID: \(userId)")
        print("🔑 [SessionService] Access token present: \(!currentSession.accessToken.isEmpty)")

        // Verify the session's user ID matches the requested userId
        guard currentSession.user.id == userId else {
            print("❌ [SessionService] User ID mismatch! Session: \(currentSession.user.id), Requested: \(userId)")
            throw SessionError.sessionMismatch
        }

        print("✅ [SessionService] User ID verified, proceeding to join session")

        // Find session by room code
        let sessions: [GameSession] = try await supabase
            .from("game_sessions")
            .select()
            .eq("room_code", value: roomCode.uppercased())
            .eq("status", value: "waiting")
            .execute()
            .value

        guard let session = sessions.first else {
            throw SessionError.sessionNotFound
        }

        // Check if session is full
        let existingPlayers: [SessionPlayer] = try await getSessionPlayers(sessionId: session.id)
        if existingPlayers.count >= session.maxPlayers {
            throw SessionError.sessionFull
        }

        // Check if user already in session
        if existingPlayers.contains(where: { $0.userId == userId }) {
            throw SessionError.alreadyInSession
        }

        // Create player entry
        let player = try await addPlayer(
            sessionId: session.id,
            userId: userId,
            playerName: playerName,
            isBot: false
        )

        return (session, player)
    }

    /// Leave a session
    func leaveSession(sessionId: UUID, userId: UUID) async throws {
        // Get player record
        let players: [SessionPlayer] = try await supabase
            .from("session_players")
            .select()
            .eq("session_id", value: sessionId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value

        guard let player = players.first else {
            return // Already not in session
        }

        // Delete player
        try await removePlayer(playerId: player.id)
    }
    
    /// Remove a player by ID
    func removePlayer(playerId: UUID) async throws {
        try await supabase
            .from("session_players")
            .delete()
            .eq("id", value: playerId.uuidString)
            .execute()
    }

    /// Get session by ID
    func getSession(sessionId: UUID) async throws -> GameSession? {
        let sessions: [GameSession] = try await supabase
            .from("game_sessions")
            .select()
            .eq("id", value: sessionId.uuidString)
            .execute()
            .value

        return sessions.first
    }

    /// Get session by room code
    func getSessionByRoomCode(roomCode: String) async throws -> GameSession? {
        let sessions: [GameSession] = try await supabase
            .from("game_sessions")
            .select()
            .eq("room_code", value: roomCode.uppercased())
            .execute()
            .value

        return sessions.first
    }

    /// Update session status
    func updateSessionStatus(sessionId: UUID, status: SessionStatus) async throws {
        struct UpdateData: Encodable {
            let status: String
        }

        try await supabase
            .from("game_sessions")
            .update(UpdateData(status: status.rawValue))
            .eq("id", value: sessionId.uuidString)
            .execute()
    }

    /// Transfer host privileges to another authenticated user (host only)
    func updateSessionHost(sessionId: UUID, newHostUserId: UUID) async throws {
        let params: [String: AnyJSON] = [
            "p_session_id": .string(sessionId.uuidString),
            "p_new_host_user_id": .string(newHostUserId.uuidString)
        ]

        struct TransferResponse: Decodable { let success: Bool? }

        let _: TransferResponse = try await supabase
            .rpc("transfer_session_host", params: params)
            .execute()
            .value
    }

    /// Update session phase
    func updateSessionPhase(
        sessionId: UUID,
        currentPhase: String,
        phaseData: PhaseData?
    ) async throws {
        struct UpdateData: Encodable {
            let currentPhase: String
            let currentPhaseData: PhaseData?

            enum CodingKeys: String, CodingKey {
                case currentPhase = "current_phase"
                case currentPhaseData = "current_phase_data"
            }
        }

        try await supabase
            .from("game_sessions")
            .update(UpdateData(currentPhase: currentPhase, currentPhaseData: phaseData))
            .eq("id", value: sessionId.uuidString)
            .execute()
    }

    /// Update multiple session fields atomically (phase, history, status, etc.)
    func updateSessionState(
        sessionId: UUID,
        currentPhase: String? = nil,
        phaseData: PhaseData? = nil,
        dayIndex: Int? = nil,
        nightHistory: [NightActionRecord]? = nil,
        dayHistory: [DayActionRecord]? = nil,
        isGameOver: Bool? = nil,
        winner: Role? = nil
    ) async throws {
        struct UpdateData: Encodable {
            let currentPhase: String?
            let currentPhaseData: PhaseData?
            let dayIndex: Int?
            let nightHistory: [NightActionRecord]?
            let dayHistory: [DayActionRecord]?
            let isGameOver: Bool?
            let winner: String?

            enum CodingKeys: String, CodingKey {
                case currentPhase = "current_phase"
                case currentPhaseData = "current_phase_data"
                case dayIndex = "day_index"
                case nightHistory = "night_history"
                case dayHistory = "day_history"
                case isGameOver = "is_game_over"
                case winner
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encodeIfPresent(currentPhase, forKey: .currentPhase)
                try container.encodeIfPresent(currentPhaseData, forKey: .currentPhaseData)
                try container.encodeIfPresent(dayIndex, forKey: .dayIndex)
                try container.encodeIfPresent(nightHistory, forKey: .nightHistory)
                try container.encodeIfPresent(dayHistory, forKey: .dayHistory)
                try container.encodeIfPresent(isGameOver, forKey: .isGameOver)
                try container.encodeIfPresent(winner, forKey: .winner)
            }
        }

        let hasUpdates = currentPhase != nil ||
                         phaseData != nil ||
                         dayIndex != nil ||
                         nightHistory != nil ||
                         dayHistory != nil ||
                         isGameOver != nil ||
                         winner != nil

        guard hasUpdates else { return }

        let updateData = UpdateData(
            currentPhase: currentPhase,
            currentPhaseData: phaseData,
            dayIndex: dayIndex,
            nightHistory: nightHistory,
            dayHistory: dayHistory,
            isGameOver: isGameOver,
            winner: winner?.rawValue
        )

        try await supabase
            .from("game_sessions")
            .update(updateData)
            .eq("id", value: sessionId.uuidString)
            .execute()
    }

    // MARK: - Player Management

    /// Get all players in a session
    func getSessionPlayers(sessionId: UUID) async throws -> [SessionPlayer] {
        // Use the secure view that masks roles
        let players: [SessionPlayer] = try await supabase
            .from("game_session_players")
            .select()
            .eq("session_id", value: sessionId.uuidString)
            .order("joined_at")
            .execute()
            .value

        return players
    }

    /// Add a player to a session
    func addPlayer(
        sessionId: UUID,
        userId: UUID?,
        playerName: String,
        isBot: Bool
    ) async throws -> SessionPlayer {
        struct CreatePlayerData: Encodable {
            let sessionId: String
            let userId: String?
            let playerId: String
            let playerName: String
            let isBot: Bool
            let isAlive: Bool
            let isOnline: Bool
            let isReady: Bool

            enum CodingKeys: String, CodingKey {
                case sessionId = "session_id"
                case userId = "user_id"
                case playerId = "player_id"
                case playerName = "player_name"
                case isBot = "is_bot"
                case isAlive = "is_alive"
                case isOnline = "is_online"
                case isReady = "is_ready"
            }
        }

        // Debug: Check current auth session before insert
        if let authSession = try? await supabase.auth.session {
            print("🔐 [addPlayer] Auth session exists - User: \(authSession.user.id)")
            print("🔐 [addPlayer] Inserting player with userId: \(userId?.uuidString ?? "nil (bot)")")
        } else {
            print("❌ [addPlayer] WARNING: No auth session found!")
        }

        let playerId = UUID()

        let createData = CreatePlayerData(
            sessionId: sessionId.uuidString,
            userId: userId?.uuidString,
            playerId: playerId.uuidString,
            playerName: playerName,
            isBot: isBot,
            isAlive: true,
            isOnline: !isBot, // Bots start offline
            isReady: isBot // Bots are always ready
        )

        print("📤 [addPlayer] Attempting insert with data: session=\(sessionId), user=\(userId?.uuidString ?? "nil"), name=\(playerName)")

        do {
            // CRITICAL: Verify session is still valid right before insert
            // This ensures the JWT token is fresh and included in the request
            guard let authSession = try? await supabase.auth.session else {
                print("❌ [addPlayer] Auth session lost right before insert!")
                throw SessionError.notAuthenticated
            }
            
            print("🔐 [addPlayer] Auth token verified before insert")
            let expiryDate = Date(timeIntervalSince1970: authSession.expiresAt)
            print("🔐 [addPlayer] Token expires at: \(expiryDate)")
            
            let players: [SessionPlayer] = try await supabase
                .from("session_players")
                .insert(createData)
                .select()
                .execute()
                .value

            guard let player = players.first else {
                throw SessionError.playerNotCreated
            }

            print("✅ [addPlayer] Player created successfully: \(player.id)")
            return player
        } catch {
            print("❌ [addPlayer] Insert failed with error: \(error)")
            print("❌ [addPlayer] Error details: \(error.localizedDescription)")
            throw error
        }
    }

    /// Update player ready status
    func updatePlayerReady(playerId: UUID, isReady: Bool) async throws {
        struct UpdateData: Encodable {
            let isReady: Bool

            enum CodingKeys: String, CodingKey {
                case isReady = "is_ready"
            }
        }

        try await supabase
            .from("session_players")
            .update(UpdateData(isReady: isReady))
            .eq("id", value: playerId.uuidString)
            .execute()
    }

    /// Update a player's alive status and optional removal note
    func updatePlayerLifeStatus(
        recordId: UUID,
        isAlive: Bool,
        removalNote: String?
    ) async throws {
        struct UpdateData: Encodable {
            let isAlive: Bool
            let removalNote: String?

            enum CodingKeys: String, CodingKey {
                case isAlive = "is_alive"
                case removalNote = "removal_note"
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(isAlive, forKey: .isAlive)
                try container.encodeIfPresent(removalNote, forKey: .removalNote)
            }
        }

        let updateData = UpdateData(isAlive: isAlive, removalNote: removalNote)

        try await supabase
            .from("session_players")
            .update(updateData)
            .eq("id", value: recordId.uuidString)
            .execute()
    }

    /// Update player heartbeat
    func updatePlayerHeartbeat(playerId: UUID) async throws {
        struct UpdateData: Encodable {
            let lastHeartbeat: String
            let isOnline: Bool

            enum CodingKeys: String, CodingKey {
                case lastHeartbeat = "last_heartbeat"
                case isOnline = "is_online"
            }
        }

        let updateData = UpdateData(
            lastHeartbeat: ISO8601DateFormatter().string(from: Date()),
            isOnline: true
        )

        try await supabase
            .from("session_players")
            .update(updateData)
            .eq("id", value: playerId.uuidString)
            .execute()
    }

    /// Assign roles and numbers to all players
    func assignRolesAndNumbers(
        sessionId: UUID,
        assignments: [(playerId: UUID, role: Role, number: Int)]
    ) async throws {
        // Update each player with their role and number
        for assignment in assignments {
            struct UpdateData: Encodable {
                let playerNumber: Int
                let role: String

                enum CodingKeys: String, CodingKey {
                    case playerNumber = "player_number"
                    case role
                }
            }

            let updateData = UpdateData(
                playerNumber: assignment.number,
                role: assignment.role.rawValue
            )

            try await supabase
                .from("session_players")
                .update(updateData)
                .eq("session_id", value: sessionId.uuidString)
                .eq("player_id", value: assignment.playerId.uuidString)
                .execute()
        }

        // Update session with assigned numbers
        let numberAssignments = assignments.map {
            PlayerNumberAssignment(playerId: $0.playerId, number: $0.number)
        }

        struct UpdateSessionData: Encodable {
            let assignedNumbers: [PlayerNumberAssignment]

            enum CodingKeys: String, CodingKey {
                case assignedNumbers = "assigned_numbers"
            }
        }

        try await supabase
            .from("game_sessions")
            .update(UpdateSessionData(assignedNumbers: numberAssignments))
            .eq("id", value: sessionId.uuidString)
            .execute()
    }

    // MARK: - Game Actions

    /// Submit a game action
    @discardableResult
    func submitAction(_ action: GameAction) async throws -> ActionResponse {
        let params: [String: AnyJSON] = [
            "p_session_id": .string(action.sessionId.uuidString),
            "p_action_type": .string(action.actionType.rawValue),
            "p_phase_index": .integer(action.phaseIndex),
            "p_actor_player_id": .string(action.actorPlayerId.uuidString),
            "p_target_player_id": action.targetPlayerId.map { .string($0.uuidString) } ?? .null
        ]

        // Use RPC to handle action submission securely (especially for Inspector logic)
        let response: ActionResponse = try await supabase
            .rpc("submit_game_action", params: params)
            .execute()
            .value
            
        return response
    }

    /// Get actions for a specific phase
    func getActionsForPhase(
        sessionId: UUID,
        actionType: ActionType,
        phaseIndex: Int
    ) async throws -> [GameAction] {
        let actions: [GameAction] = try await supabase
            .from("game_actions")
            .select()
            .eq("session_id", value: sessionId.uuidString)
            .eq("action_type", value: actionType.rawValue)
            .eq("phase_index", value: phaseIndex)
            .order("created_at")
            .execute()
            .value

        return actions
    }

    /// Get all actions for a session
    func getAllActions(sessionId: UUID) async throws -> [GameAction] {
        let actions: [GameAction] = try await supabase
            .from("game_actions")
            .select()
            .eq("session_id", value: sessionId.uuidString)
            .order("created_at")
            .execute()
            .value

        return actions
    }

}

// MARK: - Helper Structs

struct ActionResponse: Decodable, Sendable {
    let success: Bool
    let action_id: UUID
    let result: String?
}

// MARK: - Errors

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
        }
    }
}
