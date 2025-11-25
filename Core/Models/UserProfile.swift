import Foundation

struct UserProfile: Codable, Identifiable, Sendable {
    let id: UUID
    var displayName: String
    var isAnonymous: Bool
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case isAnonymous = "is_anonymous"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        // Default to false for backwards compatibility with existing profiles
        isAnonymous = try container.decodeIfPresent(Bool.self, forKey: .isAnonymous) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
