import Foundation

// Represents a multiplayer game session
struct GameSession: Decodable, Identifiable, Sendable {
    let id: UUID
    let roomCode: String
    var hostUserId: UUID
    var originalHostUserId: UUID?
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

    // Round ID for action isolation (prevents action replay across rounds)
    var currentRoundId: UUID?

    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case roomCode = "room_code"
        case hostUserId = "host_user_id"
        case originalHostUserId = "original_host_user_id"
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
        case currentRoundId = "current_round_id"
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
enum PhaseData: Decodable, Sendable, Equatable {
    case lobby
    case roleReveal(currentPlayerIndex: Int)
    case night(nightIndex: Int, activeRole: String?)
    case morning(nightIndex: Int)
    case deathReveal(nightIndex: Int)
    case voting(dayIndex: Int)
    case votingResults(dayIndex: Int, voteCounts: [UUID: Int], eliminatedPlayerId: UUID?)
    case voteDeathReveal(
        dayIndex: Int,
        eliminatedPlayerId: UUID?,
        eliminatedPlayerName: String?,
        eliminatedPlayerNumber: Int?,
        eliminatedPlayerRole: String?,
        voteCount: Int?
    )
    case gameOver(winner: String?)

    private enum CodingKeys: String, CodingKey {
        case type
        case currentPlayerIndex
        case nightIndex
        case dayIndex
        case activeRole
        case winner
        case voteCounts
        case eliminatedPlayerId
        case eliminatedPlayerName
        case eliminatedPlayerNumber
        case eliminatedPlayerRole
        case voteCount
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
        case "votingResults":
            let dayIndex = try container.decode(Int.self, forKey: .dayIndex)
            let voteCounts = try Self.decodeVoteCounts(from: container)
            let eliminatedPlayerId = try container.decodeIfPresent(UUID.self, forKey: .eliminatedPlayerId)
            self = .votingResults(dayIndex: dayIndex, voteCounts: voteCounts, eliminatedPlayerId: eliminatedPlayerId)
        case "voteDeathReveal":
            let dayIndex = try container.decode(Int.self, forKey: .dayIndex)
            let eliminatedPlayerId = try container.decodeIfPresent(UUID.self, forKey: .eliminatedPlayerId)
            let eliminatedPlayerName = try container.decodeIfPresent(String.self, forKey: .eliminatedPlayerName)
            let eliminatedPlayerNumber = try container.decodeIfPresent(Int.self, forKey: .eliminatedPlayerNumber)
            let eliminatedPlayerRole = try container.decodeIfPresent(String.self, forKey: .eliminatedPlayerRole)
            let voteCount = try container.decodeIfPresent(Int.self, forKey: .voteCount)
            self = .voteDeathReveal(
                dayIndex: dayIndex,
                eliminatedPlayerId: eliminatedPlayerId,
                eliminatedPlayerName: eliminatedPlayerName,
                eliminatedPlayerNumber: eliminatedPlayerNumber,
                eliminatedPlayerRole: eliminatedPlayerRole,
                voteCount: voteCount
            )
        case "gameOver":
            let winner = try container.decodeIfPresent(String.self, forKey: .winner)
            self = .gameOver(winner: winner)
        default:
            self = .lobby
        }
    }

    /// `voteCounts` is a `{ player_id: count }` object. Games started before
    /// api_contract 4 stored Swift's alternating `[id, count, id, count, …]` array.
    private static func decodeVoteCounts(from container: KeyedDecodingContainer<CodingKeys>) throws -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        if let object = try? container.decode([String: Int].self, forKey: .voteCounts) {
            for (key, count) in object {
                if let id = UUID(uuidString: key) { counts[id] = count }
            }
            return counts
        }
        var legacy = try container.nestedUnkeyedContainer(forKey: .voteCounts)
        while !legacy.isAtEnd {
            let key = try legacy.decode(String.self)
            let count = try legacy.decode(Int.self)
            if let id = UUID(uuidString: key) { counts[id] = count }
        }
        return counts
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

// Night record written by the server; ignores `round_id` and `next_phase`.
struct NightActionRecord: Decodable, Sendable {
    let nightIndex: Int
    let isResolved: Bool
    let mafiaTargetId: UUID?
    let inspectorCheckedId: UUID?
    let doctorProtectedId: UUID?
    let targetWasSaved: Bool?
    let resultingDeaths: [UUID]
    let revealedDeathRoles: [String: String]
    let mafiaPlayerNumbers: [Int]
    let doctorPlayerNumbers: [Int]
    let inspectorPlayerNumbers: [Int]
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case nightIndex = "night_index"
        case isResolved = "is_resolved"
        case mafiaTargetId = "mafia_target_id"
        case inspectorCheckedId = "inspector_checked_id"
        case doctorProtectedId = "doctor_protected_id"
        case targetWasSaved = "target_was_saved"
        case resultingDeaths = "resulting_deaths"
        case revealedDeathRoles = "revealed_death_roles"
        case mafiaPlayerNumbers = "mafia_player_numbers"
        case doctorPlayerNumbers = "doctor_player_numbers"
        case inspectorPlayerNumbers = "inspector_player_numbers"
        case timestamp
    }

    // Custom decoder to handle old records without role-specific numbers and isResolved
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nightIndex = try container.decode(Int.self, forKey: .nightIndex)
        // Default to false for backwards compatibility with old records
        isResolved = (try? container.decode(Bool.self, forKey: .isResolved)) ?? false
        mafiaTargetId = try container.decodeIfPresent(UUID.self, forKey: .mafiaTargetId)
        inspectorCheckedId = try container.decodeIfPresent(UUID.self, forKey: .inspectorCheckedId)
        doctorProtectedId = try container.decodeIfPresent(UUID.self, forKey: .doctorProtectedId)
        targetWasSaved = try container.decodeIfPresent(Bool.self, forKey: .targetWasSaved)
        resultingDeaths = try container.decode([UUID].self, forKey: .resultingDeaths)
        revealedDeathRoles = (try? container.decode([String: String].self, forKey: .revealedDeathRoles)) ?? [:]
        // Default to empty arrays for backwards compatibility
        mafiaPlayerNumbers = (try? container.decode([Int].self, forKey: .mafiaPlayerNumbers)) ?? []
        doctorPlayerNumbers = (try? container.decode([Int].self, forKey: .doctorPlayerNumbers)) ?? []
        inspectorPlayerNumbers = (try? container.decode([Int].self, forKey: .inspectorPlayerNumbers)) ?? []
        timestamp = try container.decode(Date.self, forKey: .timestamp)
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
