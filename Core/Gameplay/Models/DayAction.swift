import Foundation

struct DayAction: Codable, Sendable, Identifiable, Equatable {
    var id: UUID = UUID()
    var dayIndex: Int
    var removedPlayerIDs: [UUID]
}

extension DayAction {
    /// `id` falls back to a new one when an older save lacks it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        dayIndex = try c.decode(Int.self, forKey: .dayIndex)
        removedPlayerIDs = try c.decode([UUID].self, forKey: .removedPlayerIDs)
    }
}
