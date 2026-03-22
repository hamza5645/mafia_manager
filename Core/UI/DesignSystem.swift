import SwiftUI

// Modern, enhanced design system with gradients, glassmorphism, and refined tokens
enum Design {
    enum Colors {
        // Dark surfaces with richer tones
        static let surface0 = Color(hex: 0x0A0C10)
        static let surface1 = Color(hex: 0x141822)
        static let surface2 = Color(hex: 0x1E2432)
        static let surface3 = Color(hex: 0x252D3F)
        static let stroke    = Color(hex: 0x2D3648)
        static let strokeLight = Color(hex: 0x3A4458)

        // Text with better contrast
        static let textPrimary   = Color(hex: 0xF8FAFC)
        static let textSecondary = Color(hex: 0xC1C9D6)
        static let textTertiary  = Color(hex: 0x8B95A8)

        // Enhanced accent colors
        static let brandGold   = Color(hex: 0xFFD060)
        static let brandGoldBright = Color(hex: 0xFFE594)
        static let actionBlue  = Color(hex: 0x0A84FF)
        static let actionBlueBright = Color(hex: 0x4DA5FF)
        static let dangerRed   = Color(hex: 0xFF4757)
        static let dangerRedBright = Color(hex: 0xFF6B79)
        static let successGreen = Color(hex: 0x32D74B)
        static let successGreenBright = Color(hex: 0x66E678)

        // Role-specific gradients
        static let mafiaGradient = [Color(hex: 0xFF4757), Color(hex: 0xD43545)]
        static let doctorGradient = [Color(hex: 0x32D74B), Color(hex: 0x28B03D)]
        static let policeGradient = [Color(hex: 0x0A84FF), Color(hex: 0x086BCF)]
        static let citizenGradient = [Color(hex: 0x8B95A8), Color(hex: 0x6B7587)]

        // UI effect colors
        static let glowGold = Color(hex: 0xFFD060).opacity(0.3)
        static let glowBlue = Color(hex: 0x0A84FF).opacity(0.3)
        static let glowRed = Color(hex: 0xFF4757).opacity(0.3)
        static let glowGreen = Color(hex: 0x32D74B).opacity(0.3)
    }

    enum Radii {
        static let small: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 20
        static let extraLarge: CGFloat = 24
        static let card: CGFloat = 20
        static let button: CGFloat = 16
        static let pill: CGFloat = 24
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        static let xxxxl: CGFloat = 40
        static let grid: CGFloat = 8
    }

    enum Opacity {
        static let subtle: Double = 0.15
        static let disabled: Double = 0.3
        static let light: Double = 0.3
        static let medium: Double = 0.5
        static let strong: Double = 0.7
    }

    enum Typography {
        // Dynamic Type-aware fonts (automatically scale with user's accessibility settings)
        static let largeTitle = Font.system(.largeTitle, design: .rounded).weight(.heavy)
        static let title1 = Font.system(.title, design: .rounded).weight(.bold)
        static let title2 = Font.system(.title2, design: .rounded).weight(.bold)
        static let title3 = Font.system(.title3, design: .rounded).weight(.semibold)
        static let headline = Font.system(.headline, design: .rounded)
        static let body = Font.system(.body, design: .rounded)
        static let callout = Font.system(.callout, design: .rounded)
        static let subheadline = Font.system(.subheadline, design: .rounded).weight(.medium)
        static let footnote = Font.system(.footnote, design: .rounded)
        static let caption = Font.system(.caption, design: .rounded).weight(.medium)
        static let caption2 = Font.system(.caption2, design: .rounded)

        // Semantic styles for specialized use cases
        static let displayEmoji = Font.system(.largeTitle, design: .rounded).weight(.bold)
        static let roomCode = Font.system(.title, design: .monospaced).weight(.bold)
        static let playerNumber = Font.system(.largeTitle, design: .rounded).weight(.heavy)
    }

    enum Shadows {
        static let small = (color: Color.black.opacity(0.15), radius: CGFloat(8), x: CGFloat(0), y: CGFloat(2))
        static let medium = (color: Color.black.opacity(0.25), radius: CGFloat(12), x: CGFloat(0), y: CGFloat(4))
        static let large = (color: Color.black.opacity(0.35), radius: CGFloat(20), x: CGFloat(0), y: CGFloat(8))
        static let glow = (radius: CGFloat(20), opacity: Double(0.6))
    }

    enum Animations {
        static let quick = Animation.spring(response: 0.25, dampingFraction: 0.9)
        static let smooth = Animation.spring(response: 0.35, dampingFraction: 0.85)
        static let bouncy = Animation.spring(response: 0.4, dampingFraction: 0.75)
        static let easeInOut = Animation.easeInOut(duration: 0.3)
    }
}

// MARK: - Card container style with glassmorphism
struct Card: ViewModifier {
    var padding: CGFloat = 16
    var withGlow: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    // Base surface
                    RoundedRectangle(cornerRadius: Design.Radii.card, style: .continuous)
                        .fill(Design.Colors.surface1)

                    // Subtle gradient overlay for depth
                    RoundedRectangle(cornerRadius: Design.Radii.card, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Design.Colors.surface2.opacity(0.3),
                                    Design.Colors.surface1.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radii.card, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Design.Colors.strokeLight.opacity(0.6),
                                Design.Colors.stroke.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: Design.Shadows.medium.color, radius: Design.Shadows.medium.radius, x: Design.Shadows.medium.x, y: Design.Shadows.medium.y)
            .if(withGlow) { view in
                view.shadow(color: Design.Colors.glowGold, radius: Design.Shadows.glow.radius)
            }
    }
}

extension View {
    func cardStyle(padding: CGFloat = 16, withGlow: Bool = false) -> some View {
        modifier(Card(padding: padding, withGlow: withGlow))
    }

    // Conditional modifier helper
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Enhanced Button Styles with Gradients
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
        @ScaledMetric(relativeTo: .headline) private var scaledHeight: CGFloat = 56

        var body: some View {
            let colors = palette(for: kind)
            return configuration.label
                .font(Design.Typography.headline)
                .foregroundStyle(colors.foreground.opacity(isEnabled ? 1 : 0.5))
                .frame(height: scaledHeight)
                .frame(maxWidth: .infinity)
                .background(
                    ZStack {
                        // Gradient background
                        RoundedRectangle(cornerRadius: Design.Radii.button, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: colors.gradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .opacity(isEnabled ? (configuration.isPressed ? 0.9 : 1) : 0.4)

                        // Subtle shimmer overlay
                        RoundedRectangle(cornerRadius: Design.Radii.button, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.15), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .center
                                )
                            )
                            .opacity(isEnabled ? 1 : 0)
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radii.button, style: .continuous)
                        .stroke(colors.border.opacity(isEnabled ? 0.3 : 0.1), lineWidth: 1.5)
                )
                .shadow(color: colors.glow, radius: configuration.isPressed ? 8 : 16, y: configuration.isPressed ? 2 : 4)
                .shadow(color: Design.Shadows.large.color, radius: Design.Shadows.large.radius, x: Design.Shadows.large.x, y: Design.Shadows.large.y)
                .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1)
                .animation(Design.Animations.quick, value: configuration.isPressed)
        }

        private func palette(for kind: CTAKind) -> (gradient: [Color], foreground: Color, border: Color, glow: Color) {
            switch kind {
            case .primary:
                return (
                    [Design.Colors.brandGold, Design.Colors.brandGoldBright],
                    .black,
                    Design.Colors.brandGoldBright,
                    Design.Colors.glowGold
                )
            case .secondary:
                return (
                    [Design.Colors.surface2, Design.Colors.surface3],
                    Design.Colors.textPrimary,
                    Design.Colors.strokeLight,
                    Color.clear
                )
            case .danger:
                return (
                    [Design.Colors.dangerRed, Design.Colors.dangerRedBright],
                    .white,
                    Design.Colors.dangerRedBright,
                    Design.Colors.glowRed
                )
            }
        }
    }
}

// MARK: - Enhanced Grid Button Style
enum GridButtonKind { case primary, secondary, accent, danger }

struct CompactGridButtonStyle: ButtonStyle {
    var kind: GridButtonKind = .primary

    func makeBody(configuration: Configuration) -> some View {
        GridButton(configuration: configuration, kind: kind)
    }

    private struct GridButton: View {
        let configuration: Configuration
        let kind: GridButtonKind
        @Environment(\.isEnabled) private var isEnabled
        @ScaledMetric(relativeTo: .subheadline) private var minHeight: CGFloat = 44

        var body: some View {
            let colors = palette(for: kind)
            return configuration.label
                .font(Design.Typography.subheadline)
                .foregroundStyle(colors.foreground.opacity(isEnabled ? 1 : 0.45))
                .frame(maxWidth: .infinity)
                .frame(minHeight: minHeight)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: Design.Radii.button, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: colors.gradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.35)

                        // Shimmer effect for primary buttons
                        if kind == .primary {
                            RoundedRectangle(cornerRadius: Design.Radii.button, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [.white.opacity(0.2), .clear],
                                        startPoint: .topLeading,
                                        endPoint: .center
                                    )
                                )
                                .opacity(isEnabled ? 1 : 0)
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radii.button, style: .continuous)
                        .stroke(colors.border.opacity(isEnabled ? 0.4 : 0.15), lineWidth: 1.5)
                )
                .shadow(color: colors.glow, radius: configuration.isPressed ? 6 : 12)
                .shadow(color: Design.Shadows.small.color, radius: Design.Shadows.small.radius, x: Design.Shadows.small.x, y: Design.Shadows.small.y)
                .scaleEffect(configuration.isPressed && isEnabled ? 0.95 : 1)
                .animation(Design.Animations.quick, value: configuration.isPressed)
        }

        private func palette(for kind: GridButtonKind) -> (gradient: [Color], foreground: Color, border: Color, glow: Color) {
            switch kind {
            case .primary:
                return (
                    [Design.Colors.brandGold, Design.Colors.brandGoldBright],
                    .black,
                    Design.Colors.brandGoldBright,
                    Design.Colors.glowGold.opacity(0.5)
                )
            case .secondary:
                return (
                    [Design.Colors.surface2, Design.Colors.surface3],
                    Design.Colors.textPrimary,
                    Design.Colors.stroke,
                    Color.clear
                )
            case .accent:
                return (
                    [Design.Colors.surface2, Design.Colors.surface3],
                    Design.Colors.brandGold,
                    Design.Colors.brandGold,
                    Design.Colors.glowGold.opacity(0.3)
                )
            case .danger:
                return (
                    [Design.Colors.surface2, Design.Colors.surface3],
                    Design.Colors.dangerRed,
                    Design.Colors.dangerRed,
                    Design.Colors.glowRed.opacity(0.3)
                )
            }
        }
    }
}

// MARK: - Enhanced Pill Button Style
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
        @ScaledMetric(relativeTo: .subheadline) private var hPadding: CGFloat = 20
        @ScaledMetric(relativeTo: .subheadline) private var vPadding: CGFloat = 12

        var body: some View {
            configuration.label
                .font(Design.Typography.subheadline)
                .foregroundStyle(foreground.opacity(isEnabled ? 1 : 0.4))
                .padding(.horizontal, hPadding)
                .padding(.vertical, vPadding)
                .background(
                    ZStack {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [background, background.opacity(0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .opacity(fillOpacity)

                        // Shimmer overlay
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.2), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .center
                                )
                            )
                            .opacity(isEnabled ? 1 : 0)
                    }
                )
                .overlay(
                    Capsule()
                        .stroke(foreground.opacity(isEnabled ? 0.15 : 0.05), lineWidth: 1.5)
                )
                .shadow(color: background.opacity(0.4), radius: configuration.isPressed ? 6 : 12)
                .shadow(color: Design.Shadows.small.color, radius: Design.Shadows.small.radius, x: Design.Shadows.small.x, y: Design.Shadows.small.y)
                .scaleEffect(configuration.isPressed && isEnabled ? 0.94 : 1)
                .animation(Design.Animations.quick, value: configuration.isPressed)
        }

        private var fillOpacity: Double {
            guard isEnabled else { return 0.3 }
            return configuration.isPressed ? 0.8 : 1
        }
    }
}

// MARK: - Enhanced Chips
struct Chip: View {
    enum Style { case filled(Color), outline(Color) }
    let text: String
    var style: Style
    var icon: String?

    @ScaledMetric(relativeTo: .caption) private var iconSpacing: CGFloat = 6
    @ScaledMetric(relativeTo: .caption) private var hPadding: CGFloat = 12
    @ScaledMetric(relativeTo: .caption) private var vPadding: CGFloat = 7

    var body: some View {
        HStack(spacing: iconSpacing) {
            if let icon {
                Image(systemName: icon)
                    .font(Design.Typography.caption)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(Design.Typography.caption)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, hPadding)
        .padding(.vertical, vPadding)
        .background(
            ZStack {
                Capsule()
                    .fill(background)

                // Subtle gradient overlay for filled chips
                if case .filled = style {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.1), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
        )
        .overlay(
            Capsule()
                .strokeBorder(borderColor, lineWidth: 1.5)
        )
        .foregroundStyle(foreground)
        .shadow(color: shadowColor, radius: 6, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }

    private var background: Color {
        switch style {
        case .filled(let c): return c.opacity(0.2)
        case .outline: return Design.Colors.surface2
        }
    }

    private var borderColor: Color {
        switch style {
        case .filled(let c): return c.opacity(0.7)
        case .outline(let c): return c.opacity(0.6)
        }
    }

    private var foreground: Color {
        switch style {
        case .filled(let c): return c
        case .outline(let c): return c
        }
    }

    private var shadowColor: Color {
        switch style {
        case .filled(let c): return c.opacity(0.2)
        case .outline: return Color.clear
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

// MARK: - Accessibility Modifiers

extension View {
    /// Adds accessibility label and button trait to a view
    func accessibleButton(_ label: String, hint: String? = nil) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(accessibilityIdentifierSlug(from: label))
    }

    /// Combines child elements and adds a descriptive label for player cards
    func accessiblePlayerCard(name: String, number: Int, role: String? = nil, isAlive: Bool = true) -> some View {
        let parts = [
            "Player \(number)",
            name,
            role,
            isAlive ? nil : "Eliminated"
        ].compactMap { $0 }

        return self
            .accessibilityElement(children: .combine)
            .accessibilityLabel(parts.joined(separator: ", "))
    }

    /// Marks a view as a phase header for VoiceOver navigation
    func accessiblePhaseHeader(_ phase: String, instruction: String? = nil) -> some View {
        let label = instruction != nil ? "\(phase). \(instruction!)" : phase
        return self
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isHeader)
    }

    /// Adds accessibility for selection states (toggle buttons, selectable items)
    func accessibleSelection(_ label: String, isSelected: Bool, hint: String? = nil) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? (isSelected ? "Double tap to deselect" : "Double tap to select"))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier(accessibilityIdentifierSlug(from: label))
    }

    /// Adds a stable automation identifier for simulator and UI test flows.
    func automationID(_ identifier: String) -> some View {
        self.accessibilityIdentifier(identifier)
    }

    private func accessibilityIdentifierSlug(from label: String) -> String {
        let sanitized = label
            .lowercased()
            .replacingOccurrences(
                of: "[^a-z0-9]+",
                with: ".",
                options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        return "ui.\(sanitized)"
    }
}
