import SwiftUI

struct AssignmentsView: View {
    @EnvironmentObject private var store: GameStore
    @State private var goToNight = false

    // Column widths for tidy alignment
    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 16, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Reveal numbers and roles privately to each player. All assignments are randomised.")
                    .font(.footnote)
                    .foregroundStyle(Design.Colors.textSecondary)
                    .padding(.horizontal, 4)

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(sortedPlayers) { p in
                        PlayerRoleCard(player: p)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
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
            HStack {
                Button {
                    goToNight = true
                } label: {
                    Text(store.currentNightIndex == 1 ? "Start Night 1" : "Continue Night \(store.currentNightIndex)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CTAButtonStyle(kind: .primary))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Design.Colors.surface0.opacity(0.95))
        }
    }

    private var sortedPlayers: [Player] {
        store.state.players.sorted { $0.number < $1.number }
    }
}

// Card for each player's number, name and role
private struct PlayerRoleCard: View {
    let player: Player
    var body: some View {
        let palette = RoleCardPalette(role: player.role)
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Text("#\(player.number)")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(palette.numberColor)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 2)
                Spacer(minLength: 8)
                RoleBadge(role: player.role)
            }

            HStack(alignment: .center, spacing: 12) {
                Image(systemName: player.role.symbolName)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(palette.iconColor)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(palette.iconBackground)
                    )
                Text(player.name)
                    .font(.headline)
                    .foregroundStyle(Design.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Design.Radii.card + 4, style: .continuous)
                .fill(palette.backgroundGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radii.card + 4, style: .continuous)
                .stroke(palette.borderColor, lineWidth: 1.4)
        )
        .shadow(color: .black.opacity(0.28), radius: 10, y: 6)
    }

    // roleColor and icon centralized in RoleStyle extension
}

private struct RoleBadge: View {
    let role: Role

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: role.symbolName)
                .font(.caption.weight(.bold))
            Text(role.displayName.uppercased())
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .foregroundStyle(role.accentColor)
        .background(
            Capsule()
                .fill(role.accentColor.opacity(0.18))
        )
        .overlay(
            Capsule()
                .stroke(role.accentColor.opacity(0.55), lineWidth: 1)
        )
        .frame(minWidth: 92, alignment: .center)
        .accessibilityLabel(role.displayName)
    }
}

private struct RoleCardPalette {
    let numberColor: Color
    let iconColor: Color
    let iconBackground: Color
    let borderColor: Color
    let backgroundGradient: LinearGradient

    init(role: Role) {
        let accent = role.accentColor
        self.iconColor = accent
        self.iconBackground = accent.opacity(0.18)
        self.borderColor = accent.opacity(0.6)
        self.numberColor = Color.white.opacity(0.95)

        let top = accent.opacity(role == .citizen ? 0.16 : 0.26)
        let bottom = Design.Colors.surface1.opacity(0.9)
        self.backgroundGradient = LinearGradient(
            colors: [top, bottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
