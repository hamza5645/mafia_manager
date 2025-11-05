import Foundation

struct UserProfile: Codable, Identifiable, Sendable {
    let id: UUID
    var displayName: String
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
