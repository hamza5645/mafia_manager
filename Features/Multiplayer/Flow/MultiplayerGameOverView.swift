import SwiftUI

struct MultiplayerGameOverView: View {
    @EnvironmentObject private var multiplayerStore: MultiplayerGameStore
    @Environment(\.dismiss) private var dismiss

    // Error handling state
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLeaving = false
    @State private var isReturningToLobby = false

    private var winner: Role? {
        multiplayerStore.currentSession?.winner
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 20) {
                winnerBanner

                // Player list showing roles
                if !multiplayerStore.allPlayers.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Final Standings")
                            .font(Design.Typography.title3)
                            .foregroundStyle(Design.Colors.textPrimary)

                        ForEach(multiplayerStore.allPlayers.sorted { $0.playerNumber ?? 0 < $1.playerNumber ?? 0 }) { player in
                            playerRow(player: player)
                        }
                    }
                    .cardStyle(padding: 18)
                }

                buttonRow

                Spacer(minLength: 20)
            }
            .padding(20)
        }
        .navigationTitle("Game Over")
        .navigationBarBackButtonHidden(true)
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }

    private func playerRow(player: SessionPlayer) -> some View {
        HStack(spacing: 12) {
            // Player number
            if let number = player.playerNumber {
                Text("#\(number)")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.textSecondary)
                    .frame(width: 30)
            }

            // Player name
            Text(player.playerName)
                .font(Design.Typography.body)
                .foregroundStyle(player.isAlive ? Design.Colors.textPrimary : Design.Colors.textSecondary)

            Spacer()

            // Role badge
            if let role = player.role {
                roleChip(role: role)
            }

            // Alive/dead status
            if !player.isAlive {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Design.Colors.dangerRed.opacity(0.6))
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Design.Colors.successGreen.opacity(0.6))
            }
        }
        .padding(.vertical, 8)
        .opacity(player.isAlive ? 1.0 : 0.6)
    }

    private func roleChip(role: Role) -> some View {
        let color: Color = switch role {
        case .mafia: Design.Colors.dangerRed
        case .doctor: Design.Colors.successGreen
        case .inspector: Design.Colors.actionBlue
        case .citizen: Design.Colors.brandGold
        }

        return Text(role.displayName)
            .font(Design.Typography.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .cornerRadius(Design.Radii.small)
    }

    private var winnerBanner: some View {
        let isMafiaWin = winner == .mafia
        let isNoWinner = winner == nil
        let winColor = isNoWinner ? Design.Colors.textSecondary : (isMafiaWin ? Design.Colors.dangerRed : Design.Colors.brandGold)
        let glowColor = isNoWinner ? Design.Colors.surface2 : (isMafiaWin ? Design.Colors.glowRed : Design.Colors.glowGold)

        return ZStack {
            // Enhanced gradient background with glassmorphism
            ZStack {
                RoundedRectangle(cornerRadius: Design.Radii.large, style: .continuous)
                    .fill(Design.Colors.surface1)

                // Animated gradient overlay
                RoundedRectangle(cornerRadius: Design.Radii.large, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                winColor.opacity(0.3),
                                winColor.opacity(0.15),
                                .clear,
                                winColor.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Shimmer effect
                RoundedRectangle(cornerRadius: Design.Radii.large, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.1), .clear],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )
            }

            VStack(spacing: 14) {
                Text("GAME OVER")
                    .font(Design.Typography.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Design.Colors.textTertiary)
                    .tracking(2)

                // Enhanced win title with gradient
                let title = isNoWinner ? "GAME ENDED" : (isMafiaWin ? "MAFIA WIN!" : "CITIZENS WIN!")
                Text(title)
                    .font(Design.Typography.largeTitle)
                    .fontWeight(.heavy)
                    .foregroundStyle(
                        isNoWinner ?
                            LinearGradient(
                                colors: [Design.Colors.textPrimary, Design.Colors.textSecondary],
                                startPoint: .leading,
                                endPoint: .trailing
                            ) :
                            LinearGradient(
                                colors: isMafiaWin ?
                                    [Design.Colors.dangerRed, Design.Colors.dangerRedBright] :
                                    [Design.Colors.brandGold, Design.Colors.brandGoldBright],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                    )
                    .shadow(color: glowColor, radius: 16, y: 0)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                    .tracking(2)

                // Enhanced winner chip
                if !isNoWinner {
                    HStack(spacing: 10) {
                        if isMafiaWin {
                            Chip(text: "MAFIA", style: .filled(Design.Colors.dangerRed), icon: "flame.fill")
                        } else {
                            Chip(text: "CITIZENS", style: .filled(Design.Colors.successGreen), icon: "checkmark.seal.fill")
                        }
                    }
                } else {
                    Text("No Winner Determined")
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.textSecondary)
                }
            }
            .padding(.vertical, 32)
            .padding(.horizontal, 24)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radii.large, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            winColor.opacity(0.7),
                            winColor.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        )
        .shadow(color: glowColor.opacity(0.4), radius: 20, y: 4)
        .shadow(color: Design.Shadows.large.color, radius: Design.Shadows.large.radius, x: Design.Shadows.large.x, y: Design.Shadows.large.y)
    }

    private var buttonRow: some View {
        let mafiaWon = winner == .mafia
        let isNoWinner = winner == nil
        let lobbyCount = multiplayerStore.playersInLobbyCount

        return VStack(spacing: Design.Spacing.md) {
            // Show how many players are in lobby waiting
            if lobbyCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                    Text("\(lobbyCount) in lobby")
                }
                .font(Design.Typography.body)
                .foregroundStyle(Design.Colors.textSecondary)
                .padding(.bottom, 4)
            }

            // Play Again button - instantly returns to lobby
            Button {
                Task {
                    guard !isReturningToLobby else { return }
                    isReturningToLobby = true
                    do {
                        try await multiplayerStore.returnToLobby()
                        // Navigation to lobby happens automatically via phase change
                    } catch {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                    isReturningToLobby = false
                }
            } label: {
                HStack(spacing: 10) {
                    if isReturningToLobby {
                        ProgressView()
                            .tint(Design.Colors.textPrimary)
                    } else {
                        Image(systemName: (mafiaWon && !isNoWinner) ? "flame.fill" : "arrow.clockwise")
                            .font(Design.Typography.callout)
                            .fontWeight(.semibold)
                            .accessibilityHidden(true)
                        Text("Play Again")
                            .font(Design.Typography.headline)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CTAButtonStyle(kind: (mafiaWon && !isNoWinner) ? .danger : .primary))
            .disabled(isReturningToLobby)

            // Leave / Return to Menu
            Button {
                Task {
                    guard !isLeaving else { return }
                    isLeaving = true
                    do {
                        try await multiplayerStore.declinePlayAgain()
                        await MainActor.run { dismiss() }
                    } catch {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                    isLeaving = false
                }
            } label: {
                HStack(spacing: 10) {
                    if isLeaving {
                        ProgressView()
                            .tint(Design.Colors.textPrimary)
                    } else {
                        Image(systemName: "house.fill")
                            .font(Design.Typography.callout)
                            .fontWeight(.semibold)
                            .accessibilityHidden(true)
                        Text("Return to Menu")
                            .font(Design.Typography.headline)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CTAButtonStyle(kind: .secondary))
            .disabled(isLeaving)
        }
    }
}

#Preview {
    MultiplayerGameOverView()
        .environmentObject(MultiplayerGameStore())
        .preferredColorScheme(.dark)
}
