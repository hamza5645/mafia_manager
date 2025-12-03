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
        // Encode night record and phase data to JSON using helper
        func toAnyJSON<T: Encodable>(_ value: T) throws -> AnyJSON {
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
                        return number.boolValue ? .integer(1) : .integer(0)
                    }

                    let doubleValue = number.doubleValue
                    if doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
                        return .integer(number.intValue)
                    } else {
                        return .double(doubleValue)
                    }
                default:
                    return nil
                }
            }

            return convert(jsonObject) ?? .null
        }

        let params: [String: AnyJSON] = [
            "p_session_id": .string(sessionId.uuidString.lowercased()),
            "p_night_record": try toAnyJSON(nightRecord),
            "p_eliminated_player_ids": .array(eliminatedPlayerIds.map { .string($0.uuidString.lowercased()) }),
            "p_next_phase": .string(nextPhase),
            "p_next_phase_data": try toAnyJSON(nextPhaseData)
        ]

        do {
            let result: Bool = try await supabase
                .rpc("resolve_night_atomic", params: params)
                .single()
                .execute()
                .value

            // If RPC succeeded, update is_game_over and winner if needed
            if result && (isGameOver != nil || winner != nil) {
                struct GameOverUpdate: Encodable {
                    let isGameOver: Bool?
                    let winner: String?

                    enum CodingKeys: String, CodingKey {
                        case isGameOver = "is_game_over"
                        case winner
                    }
                }

                let gameOverData = GameOverUpdate(
                    isGameOver: isGameOver,
                    winner: winner?.rawValue
                )

                try await supabase
                    .from("game_sessions")
                    .update(gameOverData)
                    .eq("id", value: sessionId.uuidString.lowercased())
                    .execute()
            }

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
            isReady: isBot // Bots are always ready
        )

        do {
            // CRITICAL: Verify session is still valid right before insert
            // This ensures the JWT token is fresh and included in the request
            guard let _authSession = try? await supabase.auth.session else {
                throw SessionError.notAuthenticated
            }

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
        } catch {
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
            .eq("id", value: playerId.uuidString.lowercased())
            .execute()
    }

    /// Reset ready status for all human players in a session (single batch update)
    func resetAllPlayersReady(sessionId: UUID) async throws {
        try await supabase.rpc(
            "reset_players_ready",
            params: ["p_session_id": AnyJSON.string(sessionId.uuidString.lowercased())]
        ).execute()
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
        // Build assignment array for batch RPC
        let assignmentData: [[String: Any]] = assignments.map { assignment in
            [
                "player_id": assignment.playerId.uuidString.lowercased(),
                "role": assignment.role.rawValue,
                "number": assignment.number
            ]
        }

        // Try batch RPC first (single database transaction)
        do {
            // Convert to AnyJSON for Supabase RPC
            let assignmentsJSON = try JSONSerialization.data(withJSONObject: assignmentData)
            let assignmentsString = String(data: assignmentsJSON, encoding: .utf8) ?? "[]"

            let params: [String: AnyJSON] = [
                "p_session_id": .string(sessionId.uuidString.lowercased()),
                "p_assignments": .string(assignmentsString)
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

    // MARK: - Play Again (HAMZA-88)

    /// Reset session for playing again - keeps players but resets game state
    func resetSessionForPlayAgain(sessionId: UUID) async throws {
        // 1. Reset game_sessions to lobby state
        struct SessionResetData: Encodable {
            let currentPhase: String
            let currentPhaseData: PhaseData?
            let currentRoundId: String?
            let dayIndex: Int
            let nightHistory: [NightActionRecord]
            let dayHistory: [DayActionRecord]
            let isGameOver: Bool
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
        }

        try await supabase
            .from("game_sessions")
            .update(SessionResetData(
                currentPhase: "lobby",
                currentPhaseData: nil,
                currentRoundId: nil,
                dayIndex: 0,
                nightHistory: [],
                dayHistory: [],
                isGameOver: false,
                winner: nil
            ))
            .eq("id", value: sessionId.uuidString.lowercased())
            .execute()

        // 2. Reset all session_players
        struct PlayerResetData: Encodable {
            let isAlive: Bool
            let isReady: Bool
            let role: String?
            let playerNumber: Int?

            enum CodingKeys: String, CodingKey {
                case isAlive = "is_alive"
                case isReady = "is_ready"
                case role
                case playerNumber = "player_number"
            }
        }

        try await supabase
            .from("session_players")
            .update(PlayerResetData(
                isAlive: true,
                isReady: false,
                role: nil,
                playerNumber: nil
            ))
            .eq("session_id", value: sessionId.uuidString.lowercased())
            .execute()

        // 3. Delete all game_actions for this session
        try await supabase
            .from("game_actions")
            .delete()
            .eq("session_id", value: sessionId.uuidString.lowercased())
            .execute()
    }

    // MARK: - Rematch Flow

    /// Start rematch confirmation phase (sets deadline, marks initiator and all bots as ready)
    func startRematchConfirmation(sessionId: UUID, initiatorPlayerId: UUID) async throws {
        let deadline = Date().addingTimeInterval(45) // 45 seconds

        // Update session with deadline
        struct SessionUpdate: Encodable {
            let rematchDeadline: Date

            enum CodingKeys: String, CodingKey {
                case rematchDeadline = "rematch_deadline"
            }
        }

        try await supabase
            .from("game_sessions")
            .update(SessionUpdate(rematchDeadline: deadline))
            .eq("id", value: sessionId.uuidString.lowercased())
            .execute()

        // Mark initiator as ready (confirmed for rematch)
        try await updatePlayerReady(playerId: initiatorPlayerId, isReady: true)

        // Auto-mark all bots as ready (they can't decline)
        let players = try await getSessionPlayers(sessionId: sessionId)
        let bots = players.filter { $0.isBot }
        for bot in bots {
            try await updatePlayerReady(playerId: bot.id, isReady: true)
        }
    }

    /// Execute rematch via atomic RPC - handles host transfer, removes non-confirmed players
    func executeRematch(sessionId: UUID) async throws -> (success: Bool, error: String?) {
        struct RematchResponse: Decodable {
            let success: Bool
            let error: String?
            let newHostUserId: String?
            let confirmedCount: Int?
        }

        do {
            let response: RematchResponse = try await supabase
                .rpc("execute_rematch", params: ["p_session_id": AnyJSON.string(sessionId.uuidString.lowercased())])
                .single()
                .execute()
                .value

            return (response.success, response.error)
        } catch {
            print("❌ executeRematch RPC failed: \(error)")
            // Fallback for environments where the RPC isn't deployed yet
            do {
                return try await executeRematchClientSide(sessionId: sessionId)
            } catch {
                print("❌ executeRematch client-side fallback failed: \(error)")
                return (false, error.localizedDescription)
            }
        }
    }

    /// Rematch fallback that mirrors the server RPC for setups missing the SQL function
    private func executeRematchClientSide(sessionId: UUID) async throws -> (Bool, String?) {
        // Non-hosts cannot perform the updates directly due to RLS
        if
            let authSession = try? await supabase.auth.session,
            let session = try? await getSession(sessionId: sessionId),
            session.hostUserId != authSession.user.id
        {
            return (false, "Only the host can start a rematch right now")
        }

        // Fetch players to determine readiness and host candidate
        let players: [SessionPlayer] = try await supabase
            .from("session_players")
            .select()
            .eq("session_id", value: sessionId.uuidString.lowercased())
            .order("joined_at")
            .execute()
            .value

        let readyPlayers = players.filter { $0.isReady }
        guard readyPlayers.count >= 4 else {
            return (false, "Not enough players")
        }

        // Remove non-confirmed humans
        _ = try await supabase
            .from("session_players")
            .delete()
            .eq("session_id", value: sessionId.uuidString.lowercased())
            .eq("is_bot", value: false)
            .eq("is_ready", value: false)
            .select()
            .execute()

        // Oldest confirmed human becomes host
        let readyHumans = readyPlayers
            .filter { !$0.isBot && $0.userId != nil }
            .sorted { $0.joinedAt < $1.joinedAt }

        guard let newHostUserId = readyHumans.first?.userId else {
            return (false, "No valid host found")
        }

        struct SessionReset: Encodable {
            let hostUserId: String
            let status: String
            let currentPhase: String
            let currentPhaseData: PhaseData?
            let currentRoundId: String?
            let dayIndex: Int
            let nightHistory: [NightActionRecord]
            let dayHistory: [DayActionRecord]
            let isGameOver: Bool
            let winner: String?
            let rematchDeadline: Date?
            let updatedAt: Date

            enum CodingKeys: String, CodingKey {
                case hostUserId = "host_user_id"
                case status
                case currentPhase = "current_phase"
                case currentPhaseData = "current_phase_data"
                case currentRoundId = "current_round_id"
                case dayIndex = "day_index"
                case nightHistory = "night_history"
                case dayHistory = "day_history"
                case isGameOver = "is_game_over"
                case winner
                case rematchDeadline = "rematch_deadline"
                case updatedAt = "updated_at"
            }
        }

        try await supabase
            .from("game_sessions")
            .update(SessionReset(
                hostUserId: newHostUserId.uuidString.lowercased(),
                status: SessionStatus.waiting.rawValue,
                currentPhase: "lobby",
                currentPhaseData: .lobby,
                currentRoundId: nil,
                dayIndex: 0,
                nightHistory: [],
                dayHistory: [],
                isGameOver: false,
                winner: nil,
                rematchDeadline: nil,
                updatedAt: Date()
            ))
            .eq("id", value: sessionId.uuidString.lowercased())
            .execute()

        struct PlayerReset: Encodable {
            let isAlive: Bool
            let isReady: Bool
            let role: String?
            let playerNumber: Int?

            enum CodingKeys: String, CodingKey {
                case isAlive = "is_alive"
                case isReady = "is_ready"
                case role
                case playerNumber = "player_number"
            }
        }

        try await supabase
            .from("session_players")
            .update(PlayerReset(
                isAlive: true,
                isReady: false,
                role: nil,
                playerNumber: nil
            ))
            .eq("session_id", value: sessionId.uuidString.lowercased())
            .execute()

        try await supabase
            .from("game_actions")
            .delete()
            .eq("session_id", value: sessionId.uuidString.lowercased())
            .execute()

        return (true, nil)
    }

    /// Cancel rematch (clear deadline)
    func cancelRematch(sessionId: UUID) async throws {
        struct SessionUpdate: Encodable {
            let rematchDeadline: Date?

            enum CodingKeys: String, CodingKey {
                case rematchDeadline = "rematch_deadline"
            }
        }

        try await supabase
            .from("game_sessions")
            .update(SessionUpdate(rematchDeadline: nil))
            .eq("id", value: sessionId.uuidString.lowercased())
            .execute()
    }

}

// MARK: - Helper Structs

struct ActionResponse: Decodable, Sendable {
    let success: Bool
    let result: String?  // Inspector result: "mafia" or "not_mafia"
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
        }
    }
}
