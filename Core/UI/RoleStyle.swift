import SwiftUI

extension Role {
    var accentColor: Color {
        switch self {
        case .mafia: return Design.Colors.dangerRed
        case .doctor: return Design.Colors.successGreen
        case .inspector: return Design.Colors.actionBlue
        case .citizen: return .gray
        }
    }

    var symbolName: String {
        switch self {
        case .mafia: return "flame.fill"
        case .doctor: return "cross.case.fill"
        case .inspector: return "eye.fill"
        case .citizen: return "person.fill"
        }
    }
}

