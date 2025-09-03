import Foundation

struct DayAction: Codable, Sendable, Identifiable {
    var id: UUID = UUID()
    var dayIndex: Int
    var removedPlayerIDs: [UUID]
}

