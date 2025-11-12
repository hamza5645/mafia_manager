import SwiftUI

struct AssignmentsView: View {
    @EnvironmentObject private var store: GameStore
    @State private var goToNight = false

    // Column widths for tidy alignment
    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 16, alignment: .top)]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // Enhanced instruction text
                VStack(alignment: .leading, spacing: 8) {
                    Text("Player Assignments")
                        .font(Design.Typography.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Design.Colors.textPrimary, Design.Colors.textSecondary],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    Text("Reveal numbers and roles privately to each player. All assignments are randomised.")
                        .font(Design.Typography.footnote)
                        .foregroundStyle(Design.Colors.textSecondary)
                }
                .padding(.horizontal, 4)

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(sortedPlayers) { player in
                        PlayerRoleCard(player: player)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .navigationTitle("Assignments")
        .background(
            NavigationLink(destination: NightPhaseView(), isActive: $goToNight) { EmptyView() }
                .hidden()
        )
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    store.resetAll()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Button {
                    goToNight = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 18, weight: .semibold))
                        Text(store.currentNightIndex == 1 ? "Start Night 1" : "Continue Night \(store.currentNightIndex)")
                            .font(Design.Typography.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(CTAButtonStyle(kind: .primary))
            }
            .padding(.horizontal, Design.Spacing.lg)
            .padding(.vertical, Design.Spacing.md)
            .background(
                ZStack {
                    Design.Colors.surface0.opacity(0.98)

                    LinearGradient(
                        colors: [
                            Design.Colors.strokeLight.opacity(0.3),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            )
            .shadow(color: .black.opacity(0.2), radius: 20, y: -5)
        }
    }

    private var sortedPlayers: [Player] {
        store.state.players.sorted { $0.number < $1.number }
    }
}

// Enhanced card for each player's number, name and role
private struct PlayerRoleCard: View {
    let player: Player

    var body: some View {
        let palette = RoleCardPalette(role: player.role)

        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                // Simple, visible player number
                Text("#\(player.number)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Design.Colors.brandGold)
                    .shadow(color: Design.Colors.glowGold, radius: 4, y: 0)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
                    .frame(minWidth: 32, alignment: .leading)

                Spacer(minLength: 8)

                RoleBadge(role: player.role)
            }

            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    // Glow background
                    Circle()
                        .fill(palette.iconBackground)
                        .shadow(color: palette.glowColor, radius: 8)

                    // Icon
                    Image(systemName: player.role.symbolName)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(palette.iconColor)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.name)
                        .font(Design.Typography.headline)
                        .foregroundStyle(Design.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    if player.isBot {
                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                                .font(.system(size: 10))
                            Text("Bot")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(Design.Colors.textSecondary)
                    }
                }

                Spacer()
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .background(
            ZStack {
                // Base gradient background
                RoundedRectangle(cornerRadius: Design.Radii.large, style: .continuous)
                    .fill(palette.backgroundGradient)

                // Shimmer overlay
                RoundedRectangle(cornerRadius: Design.Radii.large, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.08), .clear],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radii.large, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [palette.borderColor, palette.borderColor.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: palette.glowColor.opacity(0.3), radius: 16, y: 4)
        .shadow(color: Design.Shadows.medium.color, radius: Design.Shadows.medium.radius, x: Design.Shadows.medium.x, y: Design.Shadows.medium.y)
    }
}

private struct RoleBadge: View {
    let role: Role

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: role.symbolName)
                .font(.system(size: 11, weight: .bold))
            Text(role.displayName.uppercased())
                .font(Design.Typography.caption)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .foregroundStyle(role.accentColor)
        .background(
            ZStack {
                Capsule()
                    .fill(role.accentColor.opacity(0.22))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.12), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            Capsule()
                .stroke(role.accentColor.opacity(0.65), lineWidth: 1.5)
        )
        .shadow(color: role.accentColor.opacity(0.3), radius: 6, y: 2)
        .frame(minWidth: 96, alignment: .center)
        .accessibilityLabel(role.displayName)
    }
}

private struct RoleCardPalette {
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
