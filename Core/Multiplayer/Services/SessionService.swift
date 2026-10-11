import Combine
import Foundation
import ConvexMobile

/// What `MultiplayerGameStore` sends to and watches on Convex; tests replace it with a fake.
@MainActor
protocol SessionServicing {
    /// A live `views:*` query for one session (see `SubscriptionSupervisor`).
    func watch<T: Decodable>(_ query: String, sessionId: UUID, as type: T.Type) -> AnyPublisher<T, ClientError>

    func createSession(playerName: String, botCount: Int) async throws -> EnterResult
    func joinSession(roomCode: String, playerName: String) async throws -> EnterResult
    func leaveSession(sessionId: UUID) async throws
    func cancelSession(sessionId: UUID) async throws
    func removePlayer(sessionId: UUID, playerRecordId: UUID) async throws
    func claimHost(sessionId: UUID) async throws
    func heartbeat(sessionId: UUID) async throws
    /// `phase` is the phase the tap was made in; the server drops the call in any other phase.
    func setReady(sessionId: UUID, isReady: Bool, phase: String?) async throws
    func startGame(sessionId: UUID, assignments: [RoleAssignment]) async throws
    func returnToLobby(sessionId: UUID) async throws
    func advancePhase(sessionId: UUID, to phase: PhaseTarget) async throws
    @discardableResult
    func submitAction(
        sessionId: UUID, roundId: UUID, actionType: ActionType,
        phaseIndex: Int, actorPlayerId: UUID, targetPlayerId: UUID?
    ) async throws -> ActionResponse
    func submitBotActions(sessionId: UUID, roundId: UUID, phaseIndex: Int, plans: [BotPlan]) async throws -> [BotActionResult]
    func setTentativeSelection(
        sessionId: UUID, actorPlayerId: UUID, actionType: ActionType, phaseIndex: Int, targetPlayerId: UUID?
    ) async throws
    @discardableResult
    func finishNight(sessionId: UUID, roundId: UUID) async throws -> NightOutcome
    @discardableResult
    func closeVoting(sessionId: UUID, roundId: UUID) async throws -> VoteClose
    @discardableResult
    func resolveVoteAtomic(sessionId: UUID, roundId: UUID) async throws -> VoteOutcome
}

/// Multiplayer Convex mutations (api_contract 5). The server identifies the caller;
/// `ConvexService` adds the guest proof to every request.
///
/// A user's tap waits at most `ConvexService.interactiveMutationTimeout`. A timed-out mutation
/// may still be applied (`BackendError.isTimeout`), so nothing here retries it.
/// Heartbeats and host claims have the same limit, so one that never returns cannot hold up the
/// next; the store sends them one at a time, so an outage queues one per limit, not one per tick.
/// Some calls have no limit here, because a dropped late result would be lost:
/// - create and join: the store bounds the user's wait itself and gives back a room or seat
///   that arrives after a Cancel or that limit;
/// - bot batches: the Convex client resends them after a reconnect, and a second batch could
///   change a bot's target and the server's tie-break.
@MainActor
final class SessionService: SessionServicing {
    private let convex = ConvexService.shared
    private let interactive = ConvexService.interactiveMutationTimeout

    func watch<T: Decodable>(_ query: String, sessionId: UUID, as type: T.Type) -> AnyPublisher<T, ClientError> {
        convex.subscribe(query, with: ["session_id": id(sessionId)], as: type)
    }

    // MARK: - Lobby and membership

    func createSession(playerName: String, botCount: Int) async throws -> EnterResult {
        try await convex.mutation("sessions:createSession", with: [
            "player_name": playerName,
            "max_players": 19.0,
            "bot_count": Double(botCount),
        ])
    }

    func joinSession(roomCode: String, playerName: String) async throws -> EnterResult {
        try await convex.mutation("sessions:joinSession", with: [
            "room_code": roomCode,
            "player_name": playerName,
        ])
    }

    func leaveSession(sessionId: UUID) async throws {
        try await convex.mutation("sessions:leaveSession", with: ["session_id": id(sessionId)], timeout: interactive)
    }

    func cancelSession(sessionId: UUID) async throws {
        try await convex.mutation("sessions:cancelSession", with: ["session_id": id(sessionId)], timeout: interactive)
    }

    func removePlayer(sessionId: UUID, playerRecordId: UUID) async throws {
        try await convex.mutation("sessions:removePlayer", with: [
            "session_id": id(sessionId),
            "player_record_id": id(playerRecordId),
        ], timeout: interactive)
    }

    /// Any member may ask; when the host is stale the server installs its own successor.
    func claimHost(sessionId: UUID) async throws {
        try await convex.mutation("sessions:claimHost", with: ["session_id": id(sessionId)], timeout: interactive)
    }

    func heartbeat(sessionId: UUID) async throws {
        try await convex.mutation("sessions:heartbeat", with: ["session_id": id(sessionId)], timeout: interactive)
    }

    func setReady(sessionId: UUID, isReady: Bool, phase: String?) async throws {
        try await convex.mutation("sessions:setReady", with: [
            "session_id": id(sessionId),
            "is_ready": isReady,
            "phase": phase,
        ], timeout: interactive)
    }

    func startGame(sessionId: UUID, assignments: [RoleAssignment]) async throws {
        let payload: [ConvexEncodable?] = assignments.map {
            [
                "player_id": id($0.playerId),
                "role": $0.role.rawValue,
                "number": Double($0.number),
            ] as [String: ConvexEncodable?]
        }
        try await convex.mutation("sessions:startGame", with: [
            "session_id": id(sessionId),
            "assignments": payload,
        ], timeout: interactive)
    }

    func returnToLobby(sessionId: UUID) async throws {
        try await convex.mutation("sessions:returnToLobby", with: ["session_id": id(sessionId)], timeout: interactive)
    }

    // MARK: - Phases (host)

    func advancePhase(sessionId: UUID, to phase: PhaseTarget) async throws {
        try await convex.mutation("phases:advancePhase", with: [
            "session_id": id(sessionId),
            "to_phase": phase.rawValue,
        ], timeout: interactive)
    }

    // MARK: - Actions

    @discardableResult
    func submitAction(
        sessionId: UUID,
        roundId: UUID,
        actionType: ActionType,
        phaseIndex: Int,
        actorPlayerId: UUID,
        targetPlayerId: UUID?
    ) async throws -> ActionResponse {
        try await convex.mutation("play:submitAction", with: [
            "session_id": id(sessionId),
            "round_id": id(roundId),
            "action_type": actionType.rawValue,
            "phase_index": Double(phaseIndex),
            "actor_player_id": id(actorPlayerId),
            "target_player_id": targetPlayerId.map(id),
        ], timeout: interactive)
    }

    /// Host only: every bot action of one pass in one transaction, with a result per bot.
    func submitBotActions(sessionId: UUID, roundId: UUID, phaseIndex: Int, plans: [BotPlan]) async throws -> [BotActionResult] {
        let actions: [ConvexEncodable?] = plans.map { plan in
            var item: [String: ConvexEncodable?] = [
                "actor_player_id": id(plan.botPlayerId),
                "action_type": plan.actionType.rawValue,
            ]
            // `v.optional` rejects null, and only top-level nils are dropped for us.
            if let target = plan.target { item["target_player_id"] = id(target) }
            return item
        }
        let response: BotActionResults = try await convex.mutation("play:submitBotActions", with: [
            "session_id": id(sessionId),
            "round_id": id(roundId),
            "phase_index": Double(phaseIndex),
            "actions": actions,
        ])
        return response.results
    }

    func setTentativeSelection(
        sessionId: UUID,
        actorPlayerId: UUID,
        actionType: ActionType,
        phaseIndex: Int,
        targetPlayerId: UUID?
    ) async throws {
        try await convex.mutation("play:setTentativeSelection", with: [
            "session_id": id(sessionId),
            "actor_player_id": id(actorPlayerId),
            "action_type": actionType.rawValue,
            "phase_index": Double(phaseIndex),
            "target_player_id": targetPlayerId.map(id),
        ])
    }

    // MARK: - Night and voting resolution (host)

    /// Records the night's actions and resolves them in one server transaction.
    @discardableResult
    func finishNight(sessionId: UUID, roundId: UUID) async throws -> NightOutcome {
        try await convex.mutation("night:finishNight", with: ["session_id": id(sessionId), "round_id": id(roundId)],
                                  timeout: interactive)
    }

    @discardableResult
    func closeVoting(sessionId: UUID, roundId: UUID) async throws -> VoteClose {
        try await convex.mutation("voting:closeVoting", with: ["session_id": id(sessionId), "round_id": id(roundId)],
                                  timeout: interactive)
    }

    @discardableResult
    func resolveVoteAtomic(sessionId: UUID, roundId: UUID) async throws -> VoteOutcome {
        try await convex.mutation("voting:resolveVoteAtomic", with: ["session_id": id(sessionId), "round_id": id(roundId)],
                                  timeout: interactive)
    }

    private func id(_ uuid: UUID) -> String {
        uuid.uuidString.lowercased()
    }
}

/// `to_phase` values accepted by `phases:advancePhase`.
enum PhaseTarget: String, Sendable {
    case night
    case deathReveal = "death_reveal"
    case voting
    case voteDeathReveal = "vote_death_reveal"
}

struct RoleAssignment: Equatable, Sendable {
    let playerId: UUID
    let role: Role
    let number: Int
}

struct ActionResponse: Decodable, Sendable {
    let success: Bool
    let result: String?
}

enum SessionError: LocalizedError {
    case notHost
    case invalidPhase
    case noActiveSession

    var errorDescription: String? {
        switch self {
        case .notHost:
            return "Only the host can perform this action"
        case .invalidPhase:
            return "Cannot perform this action in the current phase"
        case .noActiveSession:
            return "No active game session"
        }
    }
}
