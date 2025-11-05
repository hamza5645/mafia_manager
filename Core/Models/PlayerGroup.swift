import Foundation

/// Represents a saved group of player names that can be reused across games
struct PlayerGroup: Codable, Identifiable, Sendable {
    let id: UUID
    let userId: UUID
    var groupName: String
    var playerNames: [String]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        userId: UUID,
        groupName: String,
        playerNames: [String],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.groupName = groupName
        self.playerNames = playerNames
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case groupName = "group_name"
        case playerNames = "player_names"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
