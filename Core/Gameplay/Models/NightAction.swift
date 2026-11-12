import Foundation

struct NightAction: Codable, Sendable, Identifiable, Equatable {
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
}

extension NightAction {
    /// Fields with a default fall back to it when an older save lacks them.
    /// Keys this model no longer has (the old `*PhaseCompleted` flags) are ignored.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        nightIndex = try c.decode(Int.self, forKey: .nightIndex)
        mafiaTargetPlayerID = try c.decodeIfPresent(UUID.self, forKey: .mafiaTargetPlayerID)
        inspectorCheckedPlayerID = try c.decodeIfPresent(UUID.self, forKey: .inspectorCheckedPlayerID)
        inspectorResultIsMafia = try c.decodeIfPresent(Bool.self, forKey: .inspectorResultIsMafia)
        inspectorResultRole = try c.decodeIfPresent(Role.self, forKey: .inspectorResultRole)
        doctorProtectedPlayerID = try c.decodeIfPresent(UUID.self, forKey: .doctorProtectedPlayerID)
        resultingDeaths = try c.decode([UUID].self, forKey: .resultingDeaths)
        mafiaNumbers = try c.decode([Int].self, forKey: .mafiaNumbers)
        inspectorNumbers = try c.decodeIfPresent([Int].self, forKey: .inspectorNumbers)
        doctorNumbers = try c.decodeIfPresent([Int].self, forKey: .doctorNumbers)
        isResolved = try c.decodeIfPresent(Bool.self, forKey: .isResolved) ?? false
        aliveMafiaIDs = try c.decodeIfPresent([UUID].self, forKey: .aliveMafiaIDs)
    }
}
