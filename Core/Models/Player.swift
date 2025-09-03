import Foundation

struct Player: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var number: Int
    var name: String
    var role: Role
    var alive: Bool
    var removalNote: String?
}

