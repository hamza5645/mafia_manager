import SwiftUI

struct AssignmentsView: View {
    @EnvironmentObject private var store: GameStore
    @State private var goToNight = false

    // Column widths for tidy alignment
    private let numberColWidth: CGFloat = 56
    private let roleColWidth: CGFloat = 96

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible(minimum: 150, maximum: .infinity)), GridItem(.flexible(minimum: 150, maximum: .infinity))], spacing: 12) {
                    ForEach(sortedPlayers) { p in
                        PlayerRoleCard(player: p)
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 8)
            }
        }
        .navigationTitle("Assignments")
        .background(
            NavigationLink(destination: NightPhaseView(), isActive: $goToNight) { EmptyView() }
                .hidden()
        )
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) { store.resetAll() } label: { Text("Reset") }
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
            .background(.clear)
        }
    }

    private var sortedPlayers: [Player] {
        store.state.players.sorted { $0.number < $1.number }
    }

    private func roleColor(_ role: Role) -> Color {
        switch role {
        case .mafia: return .red
        case .doctor: return .green
        case .inspector: return .blue
        case .citizen: return .gray
        }
    }
}

// Card for each player's number, name and role
private struct PlayerRoleCard: View {
    let player: Player
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Chip(text: "#\(player.number)", style: .outline(Design.Colors.textSecondary), icon: nil)
                Spacer(minLength: 8)
                Chip(text: player.role.displayName.uppercased(), style: .outline(player.role.accentColor), icon: player.role.symbolName)
            }
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: player.role.symbolName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(player.role.accentColor)
                Text(player.name)
                    .font(.subheadline)
                    .foregroundStyle(Design.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
            }
        }
        .cardStyle(padding: 12)
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radii.card)
                .stroke(player.role.accentColor.opacity(0.8), lineWidth: 1.2)
        )
        .frame(minHeight: 110)
    }

    // roleColor and icon centralized in RoleStyle extension
}
