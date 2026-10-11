import Foundation

struct Player: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var number: Int
    var name: String
    var role: Role
    var alive: Bool
    var isBot: Bool = false
    var removalNote: String?
}

extension Player {
    /// `isBot` falls back to its default when an older save lacks it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        number = try c.decode(Int.self, forKey: .number)
        name = try c.decode(String.self, forKey: .name)
        role = try c.decode(Role.self, forKey: .role)
        alive = try c.decode(Bool.self, forKey: .alive)
        isBot = try c.decodeIfPresent(Bool.self, forKey: .isBot) ?? false
        removalNote = try c.decodeIfPresent(String.self, forKey: .removalNote)
    }
}
