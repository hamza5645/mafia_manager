import SwiftUI

struct MultiplayerGameOverView: View {
    @EnvironmentObject private var multiplayerStore: MultiplayerGameStore
    @Environment(\.dismiss) private var dismiss

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

            // Status
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
        return VStack(spacing: Design.Spacing.md) {
            // Play Again button (host only) - HAMZA-88
            if multiplayerStore.isHost {
                Button {
                    Task {
                        try? await multiplayerStore.playAgain()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: (mafiaWon && !isNoWinner) ? "flame.fill" : "arrow.clockwise")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Play Again")
                            .font(Design.Typography.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(CTAButtonStyle(kind: (mafiaWon && !isNoWinner) ? .danger : .primary))
            }

            Button {
                Task {
                    try? await multiplayerStore.leaveSession()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Return to Menu")
                        .font(Design.Typography.headline)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CTAButtonStyle(kind: multiplayerStore.isHost ? .secondary : ((mafiaWon && !isNoWinner) ? .danger : .primary)))
        }
    }
}

#Preview {
    MultiplayerGameOverView()
        .environmentObject(MultiplayerGameStore())
        .preferredColorScheme(.dark)
}
