import Foundation

/// `views:getSessionView`: the session projected for this viewer, plus who the viewer is.
struct SessionView: Decodable, Sendable, Equatable {
    let session: GameSession
    let viewer: Viewer

    struct Viewer: Decodable, Sendable, Equatable {
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
struct RoundState: Decodable, Sendable, Equatable {
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

/// `views:getHostPresence`: the host's last heartbeat on the server's clock. Only the
/// host's presence row is read, so other players' heartbeats never re-send it.
struct HostPresence: Decodable, Sendable, Equatable {
    let hostUserId: UUID
    /// nil when the server holds no heartbeat for the host.
    let hostLastHeartbeat: Date?
    let serverNow: Date
    /// 90 s while the room is waiting, else 15 s (the server's `claimHost` threshold).
    let staleAfterSeconds: TimeInterval

    enum CodingKeys: String, CodingKey {
        case hostUserId = "host_user_id"
        case hostLastHeartbeat = "host_last_heartbeat"
        case serverNow = "server_now"
        case staleAfterSeconds = "stale_after_seconds"
    }

    /// How long the host had been silent when the server sent this value.
    var silenceAtReceipt: TimeInterval {
        hostLastHeartbeat.map { serverNow.timeIntervalSince($0) } ?? .infinity
    }
}

/// Returned by `sessions:createSession` and `sessions:joinSession`.
struct EnterResult: Decodable, Sendable {
    let sessionId: UUID
    let roomCode: String
    let playerRecordId: UUID
    let playerId: UUID
    /// The seat existed before this join (re-entry), so cancelling must not give it back.
    let rejoined: Bool

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case roomCode = "room_code"
        case playerRecordId = "player_record_id"
        case playerId = "player_id"
        case rejoined
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

/// One entry of `play:submitBotActions`' per-bot results.
struct BotActionResult: Decodable, Sendable, Equatable {
    let actorPlayerId: UUID
    let ok: Bool
    /// The server message for a rejected item.
    let error: String?
    /// The inspector result: "mafia", "not_mafia" or "blocked".
    let result: String?

    enum CodingKeys: String, CodingKey {
        case actorPlayerId = "actor_player_id"
        case ok
        case error
        case result
    }
}

/// Returned by `play:submitBotActions`.
struct BotActionResults: Decodable, Sendable {
    let results: [BotActionResult]
}
