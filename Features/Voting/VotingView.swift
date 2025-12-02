import SwiftUI

struct VotingView: View {
    @EnvironmentObject private var store: GameStore
    let currentPlayerIndex: Int

    @State private var selectedTargetID: UUID?
    @State private var showConfirmation = false

    private var currentPlayer: Player? {
        guard currentPlayerIndex >= 0 && currentPlayerIndex < store.state.players.count else {
            return nil
        }
        return store.state.players[currentPlayerIndex]
    }

    private var alivePlayers: [Player] {
        store.alivePlayers.filter { $0.id != currentPlayer?.id }
    }

    var body: some View {
        ZStack {
            Design.Colors.surface0.ignoresSafeArea()

            if let currentPlayer = currentPlayer {
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            Text("\(currentPlayer.name)")
                                .font(Design.Typography.title2)
                                .foregroundStyle(Design.Colors.textPrimary)

                            Text("Who do you want to vote out?")
                                .font(Design.Typography.body)
                                .foregroundStyle(Design.Colors.textSecondary)
                        }
                        .padding(.top, 40)
                        .accessiblePhaseHeader("Voting for \(currentPlayer.name)", instruction: "Choose a player to vote out")

                        // Alive players to vote for (Grid layout)
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ], spacing: 12) {
                            ForEach(alivePlayers.sorted(by: { $0.number < $1.number })) { player in
                                VotingPlayerCard(
                                    player: player,
                                    isSelected: selectedTargetID == player.id,
                                    onTap: {
                                        withAnimation(.spring(response: 0.3)) {
                                            selectedTargetID = player.id
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Button {
                        showConfirmation = true
                    } label: {
                        Text("Lock Vote")
                            .font(Design.Typography.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CTAButtonStyle(kind: .primary))
                    .disabled(selectedTargetID == nil)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Design.Colors.surface0.opacity(0.95))
                    .accessibleButton("Lock vote", hint: "Confirms your vote. Cannot be changed.")
                }
            } else {
                Text("Error: Player not found")
                    .foregroundStyle(Design.Colors.dangerRed)
            }
        }
        .navigationBarBackButtonHidden(true)
        .alert("Confirm Vote", isPresented: $showConfirmation) {
            Button("Confirm", role: .destructive) {
                confirmVote()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let targetID = selectedTargetID,
               let target = store.player(by: targetID) {
                Text("You are voting to eliminate \(target.name). This cannot be changed.")
            }
        }
    }

    private func confirmVote() {
        guard let currentPlayer = currentPlayer,
              let targetID = selectedTargetID else { return }

        store.recordVote(from: currentPlayer.id, for: targetID)
        store.advanceToNextVoter()
    }
}

struct VotingPlayerCard: View {
    let player: Player
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Player avatar circle
                ZStack {
                    Circle()
                        .fill(isSelected ? Design.Colors.brandGold.opacity(0.2) : Design.Colors.surface2)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Circle()
                                .stroke(isSelected ? Design.Colors.brandGold : Design.Colors.stroke, lineWidth: 2)
                        )

                    Text(player.name.prefix(1).uppercased())
                        .font(Design.Typography.title2)
                        .foregroundStyle(isSelected ? Design.Colors.brandGold : Design.Colors.textSecondary)
                }
                .accessibilityHidden(true)

                // Player name
                Text(player.name)
                    .font(Design.Typography.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(Design.Colors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 36)

                // Selection indicator
                if isSelected {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(Design.Typography.caption)
                        Text("Selected")
                            .font(Design.Typography.caption2)
                            .fontWeight(.bold)
                    }
                    .foregroundStyle(Design.Colors.brandGold)
                    .accessibilityHidden(true)
                } else {
                    Text(" ")
                        .font(Design.Typography.caption2)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Design.Colors.brandGold.opacity(0.1) : Design.Colors.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSelected ? Design.Colors.brandGold : Design.Colors.stroke, lineWidth: isSelected ? 2 : 1)
                    )
            )
            .shadow(
                color: isSelected ? Design.Colors.brandGold.opacity(0.2) : Color.clear,
                radius: isSelected ? 8 : 0,
                y: isSelected ? 4 : 0
            )
        }
        .buttonStyle(.plain)
        .accessibleSelection(player.name, isSelected: isSelected, hint: isSelected ? "Selected for elimination" : "Tap to select for elimination")
    }
}

#Preview {
    NavigationStack {
        VotingView(currentPlayerIndex: 0)
            .environmentObject({
                let store = GameStore()
                store.assignNumbersAndRoles(names: ["Alice", "Bob", "Charlie", "Diana"], numberOfBots: 2)
                return store
            }())
    }
}
