import Foundation

/// `views:getSessionView`: the session projected for this viewer, plus who the viewer is.
struct SessionView: Decodable, Sendable {
    let session: GameSession
    let viewer: Viewer

    struct Viewer: Decodable, Sendable {
        let userId: UUID?
        let playerRecordId: UUID?
        let playerId: UUID?
        let isMember: Bool
        let isHost: Bool

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case playerRecordId = "player_record_id"
            case playerId = "player_id"
            case isMember = "is_member"
            case isHost = "is_host"
        }
    }
}

/// `views:getRoundState`: the current round's actions and draft selections.
struct RoundState: Decodable, Sendable {
    let roundId: UUID?
    let phase: String
    let phaseIndex: Int?
    /// Server-computed for the host; always false for everyone else.
    let readyToAdvance: Bool
    let actions: [GameAction]
    let tentative: [TentativeSelection]

    enum CodingKeys: String, CodingKey {
        case roundId = "round_id"
        case phase
        case phaseIndex = "phase_index"
        case readyToAdvance = "ready_to_advance"
        case actions
        case tentative
    }
}

/// Returned by `sessions:createSession` and `sessions:joinSession`.
struct EnterResult: Decodable, Sendable {
    let sessionId: UUID
    let roomCode: String
    let playerRecordId: UUID
    let playerId: UUID

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case roomCode = "room_code"
        case playerRecordId = "player_record_id"
        case playerId = "player_id"
    }
}

struct NightOutcome: Decodable, Sendable {
    let nightIndex: Int
    let resultingDeaths: [UUID]
    let nextPhase: String
    let winner: Role?

    enum CodingKeys: String, CodingKey {
        case nightIndex = "night_index"
        case resultingDeaths = "resulting_deaths"
        case nextPhase = "next_phase"
        case winner
    }
}

struct VoteClose: Decodable, Sendable {
    let dayIndex: Int
    let eliminatedPlayerId: UUID?

    enum CodingKeys: String, CodingKey {
        case dayIndex = "day_index"
        case eliminatedPlayerId = "eliminated_player_id"
    }
}

struct VoteOutcome: Decodable, Sendable {
    let dayIndex: Int
    let eliminatedPlayerId: UUID?
    let nextPhase: String
    let winner: Role?

    enum CodingKeys: String, CodingKey {
        case dayIndex = "day_index"
        case eliminatedPlayerId = "eliminated_player_id"
        case nextPhase = "next_phase"
        case winner
    }
}
