import Foundation
import Supabase

@MainActor
final class SessionService {
    private let supabase = SupabaseService.shared.client

    private func anyJSON<T: Encodable>(from value: T) throws -> AnyJSON {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        let jsonObject = try JSONSerialization.jsonObject(with: data)

        func convert(_ value: Any) -> AnyJSON? {
            switch value {
            case let dict as [String: Any]:
                return .object(dict.compactMapValues { convert($0) })
            case let array as [Any]:
                return .array(array.compactMap { convert($0) })
            case let string as String:
                return .string(string)
            case let number as NSNumber:
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    return .bool(number.boolValue)
                }

                let doubleValue = number.doubleValue
                if doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
                    return .integer(number.intValue)
                } else {
                    return .double(doubleValue)
                }
            case _ as NSNull:
                return .null
            default:
                return nil
            }
        }

        return convert(jsonObject) ?? .null
    }

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
            hostUserId: hostUserId.uuidString.lowercased(),
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
            throw SessionError.notAuthenticated
        }

        // Verify the session's user ID matches the requested userId
        guard currentSession.user.id == userId else {
            throw SessionError.sessionMismatch
        }

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
            .eq("session_id", value: sessionId.uuidString.lowercased())
            .eq("user_id", value: userId.uuidString.lowercased())
            .execute()
            .value

        guard let player = players.first else {
            return // Already not in session
        }

        // Delete player
        try await removePlayer(playerId: player.id)
    }
    
    /// Remove a player by ID (uses RPC to bypass RLS for unauthenticated users)
    func removePlayer(playerId: UUID) async throws {
        var lastError: Error?

        // Preferred path: delete via table (works for host/players under RLS)
        do {
            let deleted: [SessionPlayer] = try await supabase
                .from("session_players")
                .delete()
                .eq("id", value: playerId.uuidString.lowercased())
                .select()
                .execute()
                .value

            guard !deleted.isEmpty else {
                throw SessionError.playerNotFound
            }

            return
        } catch {
            lastError = error
            print("⚠️ removePlayer direct delete failed, falling back to RPC: \(error)")
        }

        // Fallback: legacy RPC for environments missing updated policies
        do {
            struct RemoveResponse: Decodable {
                let success: Bool
                let error: String?
            }

            let response: RemoveResponse = try await supabase
                .rpc("remove_player_by_id", params: ["p_player_id": AnyJSON.string(playerId.uuidString.lowercased())])
                .execute()
                .value

            if !response.success {
                throw SessionError.playerNotFound
            }
        } catch {
            throw lastError ?? error
        }
    }

    /// Get session by ID
    func getSession(sessionId: UUID) async throws -> GameSession? {
        let sessions: [GameSession] = try await supabase
            .from("game_sessions")
            .select()
            .eq("id", value: sessionId.uuidString.lowercased())
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
            .eq("id", value: sessionId.uuidString.lowercased())
            .execute()
    }

    /// Transfer host privileges to another authenticated user (host only)
    func updateSessionHost(sessionId: UUID, newHostUserId: UUID) async throws {
        let params: [String: AnyJSON] = [
            "p_session_id": .string(sessionId.uuidString.lowercased()),
            "p_new_host_user_id": .string(newHostUserId.uuidString.lowercased())
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
            let currentRoundId: String?

            enum CodingKeys: String, CodingKey {
                case currentPhase = "current_phase"
                case currentPhaseData = "current_phase_data"
                case currentRoundId = "current_round_id"
            }
        }

        // Initialize round_id when starting night phase (prevents action replay)
        let newRoundId: UUID? = (currentPhase == "night") ? UUID() : nil

        try await supabase
            .from("game_sessions")
            .update(UpdateData(
                currentPhase: currentPhase,
                currentPhaseData: phaseData,
                currentRoundId: newRoundId?.uuidString.lowercased()
            ))
            .eq("id", value: sessionId.uuidString.lowercased())
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
            let currentRoundId: String?
            let dayIndex: Int?
            let nightHistory: [NightActionRecord]?
            let dayHistory: [DayActionRecord]?
            let isGameOver: Bool?
            let winner: String?

            enum CodingKeys: String, CodingKey {
                case currentPhase = "current_phase"
                case currentPhaseData = "current_phase_data"
                case currentRoundId = "current_round_id"
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
                try container.encodeIfPresent(currentRoundId, forKey: .currentRoundId)
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

        // Initialize round_id when starting night phase (prevents action replay)
        let newRoundId: UUID? = (currentPhase == "night") ? UUID() : nil

        let updateData = UpdateData(
            currentPhase: currentPhase,
            currentPhaseData: phaseData,
            currentRoundId: newRoundId?.uuidString.lowercased(),
            dayIndex: dayIndex,
            nightHistory: nightHistory,
            dayHistory: dayHistory,
            isGameOver: isGameOver,
            winner: winner?.rawValue
        )

        try await supabase
            .from("game_sessions")
            .update(updateData)
            .eq("id", value: sessionId.uuidString.lowercased())
            .execute()
    }

    /// Atomically resolve night phase (prevents race conditions)
    /// Applies player eliminations AND updates night_history + phase transition in a single transaction
    func resolveNightAtomic(
        sessionId: UUID,
        nightRecord: NightActionRecord,
        eliminatedPlayerIds: [UUID],
        nextPhase: String,
        nextPhaseData: PhaseData,
        isGameOver: Bool? = nil,
        winner: Role? = nil
    ) async throws -> Bool {
        let params: [String: AnyJSON] = [
            "p_session_id": .string(sessionId.uuidString.lowercased()),
            "p_night_record": try anyJSON(from: nightRecord),
            "p_eliminated_player_ids": .array(eliminatedPlayerIds.map { .string($0.uuidString.lowercased()) }),
            "p_next_phase": .string(nextPhase),
            "p_next_phase_data": try anyJSON(from: nextPhaseData),
            "p_is_game_over": isGameOver.map(AnyJSON.bool) ?? .null,
            "p_winner": winner.map { .string($0.rawValue) } ?? .null
        ]

        do {
            let result: Bool = try await supabase
                .rpc("resolve_night_atomic", params: params)
                .single()
                .execute()
                .value

            return result
        } catch {
            print("❌ resolveNightAtomic RPC failed: \(error)")
            return false
        }
    }

    // MARK: - Player Management

    /// Get all players in a session
    func getSessionPlayers(sessionId: UUID) async throws -> [SessionPlayer] {
        // Use the secure view that properly handles role visibility:
        // - Host sees all roles (via get_visible_role function)
        // - Players see their own role
        // - Mafia see other mafia roles
        let players: [SessionPlayer] = try await supabase
            .from("game_session_players")
            .select()
            .eq("session_id", value: sessionId.uuidString.lowercased())
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

        let playerId = UUID()

        let createData = CreatePlayerData(
            sessionId: sessionId.uuidString.lowercased(),
            userId: userId?.uuidString.lowercased(),
            playerId: playerId.uuidString.lowercased(),
            playerName: playerName,
            isBot: isBot,
            isAlive: true,
            isOnline: !isBot, // Bots start offline
            isReady: true // Everyone is ready by default
        )

        do {
            // CRITICAL: Get session for auth header
            guard let authSession = try? await supabase.auth.session else {
                throw SessionError.notAuthenticated
            }

            // Use RPC function to bypass RLS issues with anonymous auth
            // The function validates auth.uid() internally and returns SETOF session_players
            let players: [SessionPlayer] = try await supabase.rpc(
                "add_session_player",
                params: [
                    "p_session_id": AnyJSON.string(sessionId.uuidString.lowercased()),
                    "p_user_id": userId != nil ? AnyJSON.string(userId!.uuidString.lowercased()) : AnyJSON.null,
                    "p_player_id": AnyJSON.string(playerId.uuidString.lowercased()),
                    "p_player_name": AnyJSON.string(playerName),
                    "p_is_bot": AnyJSON.bool(isBot)
                ]
            )
            .setHeader(name: "Authorization", value: "Bearer \(authSession.accessToken)")
            .execute()
            .value

            guard let player = players.first else {
                throw SessionError.playerNotCreated
            }

            return player
        } catch {
            print("⚠️ add_session_player RPC failed, falling back to direct insert: \(error)")

            let players: [SessionPlayer] = try await supabase
                .from("session_players")
                .insert(createData)
                .select()
                .execute()
                .value

            guard let player = players.first else {
                throw SessionError.playerNotCreated
            }

            return player
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
            .eq("id", value: playerId.uuidString.lowercased())
            .execute()
    }

    /// Reset ready status for all human players in a session (single batch update)
    func resetAllPlayersReady(sessionId: UUID) async throws {
        do {
            try await supabase.rpc(
                "reset_players_ready",
                params: ["p_session_id": AnyJSON.string(sessionId.uuidString.lowercased())]
            ).execute()
        } catch {
            print("⚠️ reset_players_ready RPC failed, falling back to direct update: \(error)")

            struct ReadyReset: Encodable {
                let isReady: Bool

                enum CodingKeys: String, CodingKey {
                    case isReady = "is_ready"
                }
            }

            try await supabase
                .from("session_players")
                .update(ReadyReset(isReady: false))
                .eq("session_id", value: sessionId.uuidString.lowercased())
                .eq("is_bot", value: false)
                .execute()
        }
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
            .eq("id", value: recordId.uuidString.lowercased())
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
            .eq("id", value: playerId.uuidString.lowercased())
            .execute()
    }

    /// Assign roles and numbers to all players
    /// PERF: Uses batch RPC to reduce N sequential requests to 1
    func assignRolesAndNumbers(
        sessionId: UUID,
        assignments: [(playerId: UUID, role: Role, number: Int)]
    ) async throws {
        struct RoleAssignmentPayload: Encodable {
            let playerId: String
            let role: String
            let number: Int

            enum CodingKeys: String, CodingKey {
                case playerId = "player_id"
                case role
                case number
            }
        }

        // Build assignment array for batch RPC
        let assignmentData: [RoleAssignmentPayload] = assignments.map { assignment in
            RoleAssignmentPayload(
                playerId: assignment.playerId.uuidString.lowercased(),
                role: assignment.role.rawValue,
                number: assignment.number
            )
        }

        // Try batch RPC first (single database transaction)
        do {
            let params: [String: AnyJSON] = [
                "p_session_id": .string(sessionId.uuidString.lowercased()),
                "p_assignments": try anyJSON(from: assignmentData)
            ]

            try await supabase.rpc("batch_assign_roles", params: params).execute()
            print("✅ [SessionService] Batch role assignment completed via RPC")
        } catch {
            // Fallback to sequential updates if RPC fails
            print("⚠️ [SessionService] Batch RPC failed, falling back to sequential updates: \(error)")
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
                    .eq("session_id", value: sessionId.uuidString.lowercased())
                    .eq("player_id", value: assignment.playerId.uuidString.lowercased())
                    .execute()
            }
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
            .eq("id", value: sessionId.uuidString.lowercased())
            .execute()
    }

    // MARK: - Game Actions

    /// Submit a game action
    @discardableResult
    func submitAction(_ action: GameAction) async throws -> ActionResponse {
        let params: [String: AnyJSON] = [
            "p_session_id": .string(action.sessionId.uuidString.lowercased()),
            "p_round_id": .string(action.roundId.uuidString.lowercased()),  // Include round_id for action isolation
            "p_action_type": .string(action.actionType.rawValue),
            "p_phase_index": .integer(action.phaseIndex),
            "p_actor_player_id": .string(action.actorPlayerId.uuidString.lowercased()),
            "p_target_player_id": action.targetPlayerId.map { .string($0.uuidString.lowercased()) } ?? .null
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
        phaseIndex: Int,
        roundId: UUID? = nil  // Optional: filter by round_id to prevent action replay
    ) async throws -> [GameAction] {
        var query = supabase
            .from("game_actions")
            .select()
            .eq("session_id", value: sessionId.uuidString.lowercased())
            .eq("action_type", value: actionType.rawValue)
            .eq("phase_index", value: phaseIndex)

        // If round_id provided, filter by it (prevents old actions from being re-applied)
        if let roundId = roundId {
            query = query.eq("round_id", value: roundId.uuidString.lowercased())
        }

        let actions: [GameAction] = try await query
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
            .eq("session_id", value: sessionId.uuidString.lowercased())
            .order("created_at")
            .execute()
            .value

        return actions
    }

    // MARK: - Instant Return to Lobby (Play Again)

    /// Instantly return a player to lobby - resets session if needed, handles host transfer
    /// - Parameters:
    ///   - sessionId: The session to return to
    ///   - playerId: The session_player ID clicking "Play Again"
    ///   - playerUserId: The user ID of the clicking player
    ///   - originalHostUserId: The original host's user ID (for host reclaim logic)
    func returnToLobby(
        sessionId: UUID,
        playerId: UUID,
        playerUserId: UUID,
        originalHostUserId: UUID
    ) async throws {
        // 1. Check current session state
        guard let session = try await getSession(sessionId: sessionId) else {
            throw SessionError.sessionNotFound
        }

        // 2. If session is not in lobby, reset it (first clicker triggers this)
        if session.currentPhase != "lobby" {
            try await resetSessionToLobby(
                sessionId: sessionId,
                firstClickerUserId: playerUserId,
                originalHostUserId: originalHostUserId
            )
        } else {
            // Session already in lobby - check if original host is joining and should reclaim
            if playerUserId == originalHostUserId && session.hostUserId != originalHostUserId {
                try await transferHost(sessionId: sessionId, toUserId: originalHostUserId)
            }
        }

        // 3. Mark this player as ready (in lobby)
        try await updatePlayerReady(playerId: playerId, isReady: true)
    }

    /// Reset session to lobby state - called by first player to click "Play Again"
    /// Uses RPC with SECURITY DEFINER to bypass RLS (non-host can trigger reset)
    /// Includes row locking to handle race conditions (first caller wins)
    private func resetSessionToLobby(
        sessionId: UUID,
        firstClickerUserId: UUID,
        originalHostUserId: UUID
    ) async throws {
        // First clicker becomes host (original host can reclaim via transferHost later)
        let newHostUserId = firstClickerUserId

        struct ResetResponse: Decodable {
            let success: Bool
            let error: String?
            let alreadyInLobby: Bool?
            let newHostId: String?

            enum CodingKeys: String, CodingKey {
                case success
                case error
                case alreadyInLobby = "already_in_lobby"
                case newHostId = "new_host_id"
            }
        }

        let params: [String: AnyJSON] = [
            "p_session_id": .string(sessionId.uuidString.lowercased()),
            "p_caller_user_id": .string(firstClickerUserId.uuidString.lowercased()),
            "p_new_host_user_id": .string(newHostUserId.uuidString.lowercased())
        ]

        let response: ResetResponse = try await supabase
            .rpc("reset_session_to_lobby", params: params)
            .single()
            .execute()
            .value

        if !response.success {
            throw SessionError.operationFailed(response.error ?? "Failed to reset session to lobby")
        }

        // If already in lobby (concurrent click), that's fine - idempotent success
        if response.alreadyInLobby == true {
            print("ℹ️ [SessionService] Session already in lobby (concurrent Play Again click)")
        }
    }

    /// Transfer host to a specific user (used when original host joins lobby)
    private func transferHost(sessionId: UUID, toUserId: UUID) async throws {
        // Verify the target user is still in the session before transfer
        let playerCheck: [SessionPlayer] = try await supabase
            .from("session_players")
            .select()
            .eq("session_id", value: sessionId.uuidString.lowercased())
            .eq("user_id", value: toUserId.uuidString.lowercased())
            .execute()
            .value

        // Only transfer if the user exists in the session
        guard !playerCheck.isEmpty else {
            print("⚠️ [SessionService] Cannot transfer host - user \(toUserId) not in session")
            return
        }

        struct HostUpdate: Encodable {
            let hostUserId: String
            let updatedAt: Date

            enum CodingKeys: String, CodingKey {
                case hostUserId = "host_user_id"
                case updatedAt = "updated_at"
            }
        }

        try await supabase
            .from("game_sessions")
            .update(HostUpdate(
                hostUserId: toUserId.uuidString.lowercased(),
                updatedAt: Date()
            ))
            .eq("id", value: sessionId.uuidString.lowercased())
            .execute()
    }

}

// MARK: - Helper Structs

struct ActionResponse: Decodable, Sendable {
    let success: Bool
    let result: String?  // Inspector result: "mafia", "not_mafia", or "blocked"
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
