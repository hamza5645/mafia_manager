import Foundation

// Represents a multiplayer game session
struct GameSession: Codable, Identifiable, Sendable {
    let id: UUID
    let roomCode: String
    var hostUserId: UUID // Mutable to allow host transfer
    var status: SessionStatus
    let createdAt: Date
    var startedAt: Date?
    var completedAt: Date?

    // Game settings
    var maxPlayers: Int
    var botCount: Int

    // Current game state
    var currentPhase: String // lobby, role_reveal, night, morning, death_reveal, voting, game_over
    var currentPhaseData: PhaseData?
    var dayIndex: Int
    var isGameOver: Bool
    var winner: Role?

    // Game data snapshots
    var assignedNumbers: [PlayerNumberAssignment]
    var nightHistory: [NightActionRecord]
    var dayHistory: [DayActionRecord]

    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case roomCode = "room_code"
        case hostUserId = "host_user_id"
        case status
        case createdAt = "created_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case maxPlayers = "max_players"
        case botCount = "bot_count"
        case currentPhase = "current_phase"
        case currentPhaseData = "current_phase_data"
        case dayIndex = "day_index"
        case isGameOver = "is_game_over"
        case winner
        case assignedNumbers = "assigned_numbers"
        case nightHistory = "night_history"
        case dayHistory = "day_history"
        case updatedAt = "updated_at"
    }
}

enum SessionStatus: String, Codable, Sendable {
    case waiting
    case inProgress = "in_progress"
    case completed
    case cancelled
}

// Phase data stored as JSON in the database
enum PhaseData: Codable, Sendable, Equatable {
    case lobby
    case roleReveal(currentPlayerIndex: Int)
    case night(nightIndex: Int, activeRole: String?)
    case morning(nightIndex: Int)
    case deathReveal(nightIndex: Int)
    case voting(dayIndex: Int)
    case gameOver(winner: String?)

    private enum CodingKeys: String, CodingKey {
        case type
        case currentPlayerIndex
        case nightIndex
        case dayIndex
        case activeRole
        case winner
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "lobby":
            self = .lobby
        case "roleReveal":
            let index = try container.decode(Int.self, forKey: .currentPlayerIndex)
            self = .roleReveal(currentPlayerIndex: index)
        case "night":
            let nightIndex = try container.decode(Int.self, forKey: .nightIndex)
            let activeRole = try container.decodeIfPresent(String.self, forKey: .activeRole)
            self = .night(nightIndex: nightIndex, activeRole: activeRole)
        case "morning":
            let nightIndex = try container.decode(Int.self, forKey: .nightIndex)
            self = .morning(nightIndex: nightIndex)
        case "deathReveal":
            let nightIndex = try container.decode(Int.self, forKey: .nightIndex)
            self = .deathReveal(nightIndex: nightIndex)
        case "voting":
            let dayIndex = try container.decode(Int.self, forKey: .dayIndex)
            self = .voting(dayIndex: dayIndex)
        case "gameOver":
            let winner = try container.decodeIfPresent(String.self, forKey: .winner)
            self = .gameOver(winner: winner)
        default:
            self = .lobby
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .lobby:
            try container.encode("lobby", forKey: .type)
        case .roleReveal(let index):
            try container.encode("roleReveal", forKey: .type)
            try container.encode(index, forKey: .currentPlayerIndex)
        case .night(let nightIndex, let activeRole):
            try container.encode("night", forKey: .type)
            try container.encode(nightIndex, forKey: .nightIndex)
            try container.encodeIfPresent(activeRole, forKey: .activeRole)
        case .morning(let nightIndex):
            try container.encode("morning", forKey: .type)
            try container.encode(nightIndex, forKey: .nightIndex)
        case .deathReveal(let nightIndex):
            try container.encode("deathReveal", forKey: .type)
            try container.encode(nightIndex, forKey: .nightIndex)
        case .voting(let dayIndex):
            try container.encode("voting", forKey: .type)
            try container.encode(dayIndex, forKey: .dayIndex)
        case .gameOver(let winner):
            try container.encode("gameOver", forKey: .type)
            try container.encodeIfPresent(winner, forKey: .winner)
        }
    }
}

// Player number assignment
struct PlayerNumberAssignment: Codable, Sendable {
    let playerId: UUID
    let number: Int

    enum CodingKeys: String, CodingKey {
        case playerId = "player_id"
        case number
    }
}

// Night action record (snapshot)
struct NightActionRecord: Codable, Sendable {
    let nightIndex: Int
    let mafiaTargetId: UUID?
    let inspectorCheckedId: UUID?
    let inspectorResult: String?
    let doctorProtectedId: UUID?
    let resultingDeaths: [UUID]
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case nightIndex = "night_index"
        case mafiaTargetId = "mafia_target_id"
        case inspectorCheckedId = "inspector_checked_id"
        case inspectorResult = "inspector_result"
        case doctorProtectedId = "doctor_protected_id"
        case resultingDeaths = "resulting_deaths"
        case timestamp
    }
}

// Day action record (snapshot)
struct DayActionRecord: Codable, Sendable {
    let dayIndex: Int
    let removedPlayerIds: [UUID]
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case dayIndex = "day_index"
        case removedPlayerIds = "removed_player_ids"
        case timestamp
    }
}
