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

// MARK: - Tentative Selection (for real-time vote preview)

/// A draft target shown to teammates before submission (`RoundState.tentative`).
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
