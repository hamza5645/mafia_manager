import Foundation

// Represents an action taken during the game (night or day)
struct GameAction: Codable, Identifiable, Sendable {
    let id: UUID
    let sessionId: UUID
    let roundId: UUID // Links to game_sessions.current_round_id for action isolation
    let actionType: ActionType
    let phaseIndex: Int // night_index or day_index
    let actorPlayerId: UUID // Who performed the action
    let targetPlayerId: UUID? // Who was targeted (null for skipped actions)
    var actionData: ActionData? // Additional data (e.g., inspector result)
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case roundId = "round_id"
        case actionType = "action_type"
        case phaseIndex = "phase_index"
        case actorPlayerId = "actor_player_id"
        case targetPlayerId = "target_player_id"
        case actionData = "action_data"
        case createdAt = "created_at"
    }
}

enum ActionType: String, Codable, Sendable {
    case mafiaTarget = "mafia_target"
    case inspectorCheck = "inspector_check"
    case doctorProtect = "doctor_protect"
    case vote = "vote"
}

// Additional action data stored as JSON
struct ActionData: Codable, Sendable {
    var inspectorResult: String? // "mafia", "not_mafia", "blocked"
    var mafiaVoteCount: Int? // Number of mafia who voted for this target
    var voteWeight: Int? // For potential weighted voting systems

    enum CodingKeys: String, CodingKey {
        case inspectorResult = "inspector_result"
        case mafiaVoteCount = "mafia_vote_count"
        case voteWeight = "vote_weight"
    }
}

// Helper to create actions
extension GameAction {
    static func mafiaAction(
        sessionId: UUID,
        roundId: UUID,
        nightIndex: Int,
        actorPlayerId: UUID,
        targetPlayerId: UUID?
    ) -> GameAction {
        GameAction(
            id: UUID(),
            sessionId: sessionId,
            roundId: roundId,
            actionType: .mafiaTarget,
            phaseIndex: nightIndex,
            actorPlayerId: actorPlayerId,
            targetPlayerId: targetPlayerId,
            actionData: nil,
            createdAt: Date()
        )
    }

    static func inspectorAction(
        sessionId: UUID,
        roundId: UUID,
        nightIndex: Int,
        actorPlayerId: UUID,
        targetPlayerId: UUID?,
        result: String?
    ) -> GameAction {
        var actionData: ActionData? = nil
        if let result = result {
            actionData = ActionData(inspectorResult: result, mafiaVoteCount: nil, voteWeight: nil)
        }

        return GameAction(
            id: UUID(),
            sessionId: sessionId,
            roundId: roundId,
            actionType: .inspectorCheck,
            phaseIndex: nightIndex,
            actorPlayerId: actorPlayerId,
            targetPlayerId: targetPlayerId,
            actionData: actionData,
            createdAt: Date()
        )
    }

    static func doctorAction(
        sessionId: UUID,
        roundId: UUID,
        nightIndex: Int,
        actorPlayerId: UUID,
        targetPlayerId: UUID?
    ) -> GameAction {
        GameAction(
            id: UUID(),
            sessionId: sessionId,
            roundId: roundId,
            actionType: .doctorProtect,
            phaseIndex: nightIndex,
            actorPlayerId: actorPlayerId,
            targetPlayerId: targetPlayerId,
            actionData: nil,
            createdAt: Date()
        )
    }

    static func voteAction(
        sessionId: UUID,
        roundId: UUID,
        dayIndex: Int,
        actorPlayerId: UUID,
        targetPlayerId: UUID?
    ) -> GameAction {
        GameAction(
            id: UUID(),
            sessionId: sessionId,
            roundId: roundId,
            actionType: .vote,
            phaseIndex: dayIndex,
            actorPlayerId: actorPlayerId,
            targetPlayerId: targetPlayerId,
            actionData: nil,
            createdAt: Date()
        )
    }
}

// RPC Parameters for submitting actions
struct ActionParams: Encodable, Sendable {
    let p_session_id: UUID
    let p_round_id: UUID
    let p_action_type: String
    let p_phase_index: Int
    let p_actor_player_id: UUID
    let p_target_player_id: UUID?
}

// MARK: - Tentative Selection (for real-time vote preview)

/// Represents a tentative selection broadcasted via Realtime before submission.
/// This allows players to see what others are considering targeting in real-time.
struct TentativeSelection: Codable, Sendable {
    let actorPlayerId: UUID
    let targetPlayerId: UUID?  // nil means deselected
    let actionType: ActionType
    let phaseIndex: Int

    enum CodingKeys: String, CodingKey {
        case actorPlayerId = "actor_player_id"
        case targetPlayerId = "target_player_id"
        case actionType = "action_type"
        case phaseIndex = "phase_index"
    }
}
