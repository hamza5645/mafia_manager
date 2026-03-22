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
    // Snapshot of alive police numbers for this night (numbers only)
    var inspectorNumbers: [Int]?
    // Snapshot of alive doctor numbers for this night (numbers only)
    var doctorNumbers: [Int]?
    // Flag to track if night has been resolved (outcomes determined)
    var isResolved: Bool = false
    // BUG FIX: Track alive mafia IDs for accurate kill attribution
    var aliveMafiaIDs: [UUID]?
    // BUG FIX: Phase completion tracking for robust transitions
    var mafiaPhaseCompleted: Bool = false
    var inspectorPhaseCompleted: Bool = false
    var doctorPhaseCompleted: Bool = false
}
