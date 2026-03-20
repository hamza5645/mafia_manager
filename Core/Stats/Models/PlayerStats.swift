import Foundation

struct PlayerStats: Codable, Identifiable, Sendable {
    let id: UUID
    let userId: UUID
    var playerName: String
    var gamesPlayed: Int
    var gamesWon: Int
    var gamesLost: Int
    var totalKills: Int
    var timesMafia: Int
    var timesDoctor: Int
    var timesInspector: Int
    var timesCitizen: Int
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case playerName = "player_name"
        case gamesPlayed = "games_played"
        case gamesWon = "games_won"
        case gamesLost = "games_lost"
        case totalKills = "total_kills"
        case timesMafia = "times_mafia"
        case timesDoctor = "times_doctor"
        case timesInspector = "times_inspector"
        case timesCitizen = "times_citizen"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // Computed properties for convenience
    var winRate: Double {
        guard gamesPlayed > 0 else { return 0.0 }
        return Double(gamesWon) / Double(gamesPlayed)
    }

    var averageKillsPerGame: Double {
        guard gamesPlayed > 0 else { return 0.0 }
        return Double(totalKills) / Double(gamesPlayed)
    }
}
