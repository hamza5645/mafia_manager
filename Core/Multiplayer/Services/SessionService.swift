import Foundation
import ConvexMobile

/// Multiplayer Convex mutations (api_contract 4). The server identifies the caller;
/// `ConvexService` adds the guest proof to every request.
@MainActor
final class SessionService {
    private let convex = ConvexService.shared

    // MARK: - Lobby and membership

    func createSession(playerName: String, maxPlayers: Int = 19, botCount: Int) async throws -> EnterResult {
        try await convex.mutation("sessions:createSession", with: [
            "player_name": playerName,
            "max_players": Double(maxPlayers),
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
        try await convex.mutation("sessions:leaveSession", with: ["session_id": id(sessionId)])
    }

    func cancelSession(sessionId: UUID) async throws {
        try await convex.mutation("sessions:cancelSession", with: ["session_id": id(sessionId)])
    }

    func removePlayer(sessionId: UUID, playerRecordId: UUID) async throws {
        try await convex.mutation("sessions:removePlayer", with: [
            "session_id": id(sessionId),
            "player_record_id": id(playerRecordId),
        ])
    }

    func claimHost(sessionId: UUID) async throws {
        try await convex.mutation("sessions:claimHost", with: ["session_id": id(sessionId)])
    }

    func heartbeat(sessionId: UUID) async throws {
        try await convex.mutation("sessions:heartbeat", with: ["session_id": id(sessionId)])
    }

    func setReady(sessionId: UUID, isReady: Bool) async throws {
        try await convex.mutation("sessions:setReady", with: [
            "session_id": id(sessionId),
            "is_ready": isReady,
        ])
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
        ])
    }

    func returnToLobby(sessionId: UUID) async throws {
        try await convex.mutation("sessions:returnToLobby", with: ["session_id": id(sessionId)])
    }

    // MARK: - Phases (host)

    func advancePhase(sessionId: UUID, to phase: PhaseTarget) async throws {
        try await convex.mutation("phases:advancePhase", with: [
            "session_id": id(sessionId),
            "to_phase": phase.rawValue,
        ])
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
        ])
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

    @discardableResult
    func recordNightActions(sessionId: UUID, roundId: UUID) async throws -> NightActionRecord {
        try await convex.mutation("night:recordNightActions", with: ["session_id": id(sessionId), "round_id": id(roundId)])
    }

    @discardableResult
    func resolveNightAtomic(sessionId: UUID, roundId: UUID) async throws -> NightOutcome {
        try await convex.mutation("night:resolveNightAtomic", with: ["session_id": id(sessionId), "round_id": id(roundId)])
    }

    @discardableResult
    func closeVoting(sessionId: UUID, roundId: UUID) async throws -> VoteClose {
        try await convex.mutation("voting:closeVoting", with: ["session_id": id(sessionId), "round_id": id(roundId)])
    }

    @discardableResult
    func resolveVoteAtomic(sessionId: UUID, roundId: UUID) async throws -> VoteOutcome {
        try await convex.mutation("voting:resolveVoteAtomic", with: ["session_id": id(sessionId), "round_id": id(roundId)])
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
