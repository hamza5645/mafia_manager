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
        CTAButton(configuration: configuration, kind: kind)
    }

    private struct CTAButton: View {
        let configuration: Configuration
        let kind: CTAKind
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let colors = palette(for: kind)
            return configuration.label
                .font(.headline)
                .foregroundStyle(colors.foreground.opacity(isEnabled ? 1 : 0.6))
                .frame(height: 52)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 2)
                .background(
                    RoundedRectangle(cornerRadius: Design.Radii.button, style: .continuous)
                        .fill(colors.background.opacity(isEnabled ? 1 : 0.4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radii.button, style: .continuous)
                        .stroke(.white.opacity(0.08))
                )
                .shadow(color: .black.opacity(shadowOpacity(isPressed: configuration.isPressed, enabled: isEnabled)), radius: 10, y: 6)
                .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.9), value: configuration.isPressed)
        }

        private func palette(for kind: CTAKind) -> (background: Color, foreground: Color) {
            switch kind {
            case .primary:
                return (Design.Colors.brandGold, .black)
            case .secondary:
                return (Design.Colors.surface2, Design.Colors.textPrimary)
            case .danger:
                return (Design.Colors.dangerRed, .white)
            }
        }

        private func shadowOpacity(isPressed: Bool, enabled: Bool) -> Double {
            guard enabled else { return 0.08 }
            return isPressed ? 0.1 : 0.25
        }
    }
}

// Compact pill control for inline actions (e.g., add player)
struct PillButtonStyle: ButtonStyle {
    var background: Color = Design.Colors.actionBlue
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, background: background, foreground: foreground)
    }

    private struct Pill: View {
        let configuration: Configuration
        let background: Color
        let foreground: Color
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(foreground.opacity(isEnabled ? 1 : 0.45))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(background.opacity(fillOpacity))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(isEnabled ? 0.12 : 0.04), lineWidth: 1)
                )
                .shadow(color: .black.opacity(shadowOpacity), radius: 8, y: 4)
                .scaleEffect(configuration.isPressed && isEnabled ? 0.95 : 1)
                .animation(.spring(response: 0.28, dampingFraction: 0.85), value: configuration.isPressed)
        }

        private var fillOpacity: Double {
            guard isEnabled else { return 0.35 }
            return configuration.isPressed ? 0.85 : 1
        }

        private var shadowOpacity: Double {
            guard isEnabled else { return 0 }
            return configuration.isPressed ? 0.08 : 0.18
        }
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
