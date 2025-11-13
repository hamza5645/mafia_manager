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

                    // Alive players to vote for
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(alivePlayers.sorted(by: { $0.number < $1.number })) { player in
                                VotingPlayerCard(
                                    player: player,
                                    isSelected: selectedTargetID == player.id,
                                    onTap: {
                                        selectedTargetID = player.id
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }

                    Spacer()
                }

                // Bottom button
                VStack {
                    Spacer()

                    Button {
                        showConfirmation = true
                    } label: {
                        Text("Lock Vote")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CTAButtonStyle(kind: .primary))
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                    .disabled(selectedTargetID == nil)
                    .opacity(selectedTargetID == nil ? 0.5 : 1.0)
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
                Text("You are voting to eliminate #\(target.number) \(target.name). This cannot be changed.")
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
            HStack(spacing: 16) {
                // Player number badge
                Text("#\(player.number)")
                    .font(Design.Typography.headline)
                    .foregroundStyle(Design.Colors.textPrimary)
                    .frame(width: 50)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Design.Colors.surface2)
                    )

                // Player name
                Text(player.name)
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Colors.textPrimary)

                Spacer()

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Design.Colors.brandGold)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Design.Colors.surface2 : Design.Colors.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Design.Colors.brandGold : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
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
