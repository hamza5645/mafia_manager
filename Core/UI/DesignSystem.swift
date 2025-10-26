import SwiftUI

// Centralized design tokens to match the provided reference style
// without changing app features or flows.
enum Design {
    enum Colors {
        // Dark surfaces
        static let surface0 = Color(hex: 0x0E1014)
        static let surface1 = Color(hex: 0x171A21)
        static let surface2 = Color(hex: 0x1F2430)
        static let stroke    = Color(hex: 0x2B3240)

        // Text
        static let textPrimary   = Color(hex: 0xF4F6FA)
        static let textSecondary = Color(hex: 0xB5BDCB)

        // Accents
        static let brandGold   = Color(hex: 0xFFC83D)
        static let actionBlue  = Color(hex: 0x0A84FF)
        static let dangerRed   = Color(hex: 0xFF453A)
        static let successGreen = Color(hex: 0x30D158)
    }

    enum Radii {
        static let card: CGFloat = 16
        static let button: CGFloat = 16
        static let pill: CGFloat = 22
    }

    enum Spacing {
        static let grid: CGFloat = 8
    }
}

// MARK: - Card container style
struct Card: ViewModifier {
    var padding: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Design.Colors.surface1)
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radii.card)
                    .stroke(Design.Colors.stroke, lineWidth: 1)
            )
            .cornerRadius(Design.Radii.card)
            .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }
}

extension View {
    func cardStyle(padding: CGFloat = 12) -> some View {
        modifier(Card(padding: padding))
    }
}

// MARK: - Button style
enum CTAKind { case primary, secondary, danger }

struct CTAButtonStyle: ButtonStyle {
    var kind: CTAKind = .primary
    func makeBody(configuration: Configuration) -> some View {
        let bg: Color
        let fg: Color
        switch kind {
        case .primary:
            bg = Design.Colors.brandGold
            fg = .black
        case .secondary:
            bg = Design.Colors.surface2
            fg = Design.Colors.textPrimary
        case .danger:
            bg = Design.Colors.dangerRed
            fg = .white
        }
        return configuration.label
            .font(.headline)
            .foregroundStyle(fg)
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 2)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: Design.Radii.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radii.button, style: .continuous)
                    .stroke(.white.opacity(0.08))
            )
            .shadow(color: .black.opacity(configuration.isPressed ? 0.1 : 0.25), radius: 10, y: 6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: configuration.isPressed)
    }
}

// MARK: - Chips
struct Chip: View {
    enum Style { case filled(Color), outline(Color) }
    let text: String
    var style: Style
    var icon: String?
    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon) }
            Text(text).font(.subheadline).bold()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(background)
        .overlay(
            Capsule().strokeBorder(borderColor, lineWidth: 1)
        )
        .clipShape(Capsule())
        .foregroundStyle(foreground)
    }
    private var background: Color {
        switch style {
        case .filled(let c): return c.opacity(0.18)
        case .outline: return Design.Colors.surface2
        }
    }
    private var borderColor: Color {
        switch style {
        case .filled(let c): return c.opacity(0.65)
        case .outline(let c): return c
        }
    }
    private var foreground: Color {
        switch style {
        case .filled(let c): return c
        case .outline(let c): return c
        }
    }
}

// MARK: - Helpers
extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex & 0xFF0000) >> 16) / 255.0
        let g = Double((hex & 0x00FF00) >> 8) / 255.0
        let b = Double(hex & 0x0000FF) / 255.0
        self = Color(red: r, green: g, blue: b, opacity: alpha)
    }
}

