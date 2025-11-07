import Foundation

struct NightAction: Codable, Sendable, Identifiable {
    var id: UUID = UUID()
    var nightIndex: Int
    var mafiaTargetPlayerID: UUID?
    var inspectorCheckedPlayerID: UUID?
    var inspectorResultIsMafia: Bool?
    var inspectorResultRole: Role?
    var doctorProtectedPlayerID: UUID?
    var resultingDeaths: [UUID]
    // Snapshot of mafia numbers for this night (numbers only)
    var mafiaNumbers: [Int]
    // Flag to track if night has been resolved (outcomes determined)
    var isResolved: Bool = false
}
