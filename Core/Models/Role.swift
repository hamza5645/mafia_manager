import Foundation

enum Role: String, Codable, CaseIterable, Sendable {
    case mafia
    case doctor
    case inspector
    case citizen

    var displayName: String {
        switch self {
        case .mafia: return "Mafia"
        case .doctor: return "Doctor"
        case .inspector: return "Police"
        case .citizen: return "Citizen"
        }
    }
}
