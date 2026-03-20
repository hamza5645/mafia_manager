import Foundation

struct CustomRoleConfig: Codable, Identifiable, Sendable {
    let id: UUID
    let userId: UUID
    var configName: String
    var roleDistribution: RoleDistribution
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case configName = "config_name"
        case roleDistribution = "role_distribution"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    struct RoleDistribution: Codable, Sendable {
        var mafiaCount: Int
        var doctorCount: Int
        var inspectorCount: Int
        var citizenCount: Int
        var totalPlayers: Int

        enum CodingKeys: String, CodingKey {
            case mafiaCount = "mafia_count"
            case doctorCount = "doctor_count"
            case inspectorCount = "inspector_count"
            case citizenCount = "citizen_count"
            case totalPlayers = "total_players"
        }
    }
}
