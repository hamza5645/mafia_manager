import SwiftUI

/// Shared palette for role-based card styling.
/// Provides consistent colors, gradients, and effects for role cards across the app.
struct RoleCardPalette {
    let numberColor: Color
    let iconColor: Color
    let iconBackground: Color
    let borderColor: Color
    let glowColor: Color
    let backgroundGradient: LinearGradient

    init(role: Role) {
        let accent = role.accentColor
        self.iconColor = accent
        self.iconBackground = accent.opacity(0.2)
        self.borderColor = accent.opacity(0.7)
        self.numberColor = Design.Colors.textPrimary

        // Role-specific glow colors
        switch role {
        case .mafia:
            self.glowColor = Design.Colors.glowRed
        case .doctor:
            self.glowColor = Design.Colors.glowGreen
        case .inspector:
            self.glowColor = Design.Colors.glowBlue
        case .citizen:
            self.glowColor = Color.clear
        }

        // Enhanced gradient with richer colors
        let top = accent.opacity(role == .citizen ? 0.12 : 0.2)
        let middle = Design.Colors.surface1.opacity(0.95)
        let bottom = Design.Colors.surface2.opacity(0.9)
        self.backgroundGradient = LinearGradient(
            colors: [top, middle, bottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
