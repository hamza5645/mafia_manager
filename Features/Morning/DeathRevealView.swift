import SwiftUI

struct DeathRevealView: View {
    @EnvironmentObject private var store: GameStore
    @State private var showEndGameConfirmation = false

    private var lastNight: NightAction? { store.state.nightHistory.last }

    private var deadPlayers: [Player] {
        guard let night = lastNight else { return [] }
        return night.resultingDeaths.compactMap { deathID in
            store.player(by: deathID)
        }
    }

    var body: some View {
        ZStack {
            Design.Colors.surface0
                .ignoresSafeArea()

            mainContent
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showEndGameConfirmation = true
                } label: {
                    Text("End Game")
                        .foregroundColor(Design.Colors.dangerRed)
                }
            }
        }
        .alert("Are you sure you want to end the game?", isPresented: $showEndGameConfirmation) {
            Button("End Game", role: .destructive) {
                store.endGameEarly()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will end the current game without determining a winner.")
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if deadPlayers.isEmpty {
            noDeathsView
        } else {
            deathRevealContent
        }
    }

    private var noDeathsView: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Design.Colors.successGreen.opacity(0.3),
                                Design.Colors.successGreen.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .shadow(color: Design.Colors.glowGreen, radius: 20)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(Design.Colors.successGreen)
            }

            VStack(spacing: 12) {
                Text("No Deaths")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Design.Colors.textPrimary)

                Text("Everyone survived the night")
                    .font(Design.Typography.title3)
                    .foregroundColor(Design.Colors.textSecondary)
            }

            Spacer()

            continueButton
        }
        .padding(.horizontal, Design.Spacing.lg)
    }

    private var deathRevealContent: some View {
        // Adaptive spacing based on number of deaths
        let cardSpacing: CGFloat = deadPlayers.count > 2 ? 20 : 32
        let topPadding: CGFloat = deadPlayers.count == 1 ? 40 : 20

        return ScrollView {
            VStack(spacing: cardSpacing) {
                // Death cards
                ForEach(deadPlayers, id: \.id) { player in
                    deathCard(for: player)
                }

                // Continue button
                continueButton
                    .padding(.top, 16)
            }
            .padding(.horizontal, Design.Spacing.lg)
            // Add actual padding instead of Spacers for proper scrolling
            .padding(.top, topPadding)
            .padding(.bottom, 60)
        }
    }

    private func deathCard(for player: Player) -> some View {
        let palette = RoleCardPalette(role: player.role)

        return VStack(alignment: .center, spacing: 20) {
            // Skull icon
            ZStack {
                Circle()
                    .fill(Design.Colors.dangerRed.opacity(0.2))
                    .shadow(color: Design.Colors.glowRed, radius: 20)
                    .frame(width: 100, height: 100)

                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundStyle(Design.Colors.dangerRed)
            }
            .padding(.top, 8)

            // Title: Name has Died
            Text("\(player.name) has Died")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(Design.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            // Number
            Text("#\(player.number)")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(Design.Colors.brandGold)

            Divider()
                .background(Design.Colors.stroke)
                .padding(.horizontal, 32)
                .padding(.vertical, 4)

            // Role reveal
            VStack(spacing: 10) {
                Text("Was a")
                    .font(Design.Typography.callout)
                    .foregroundColor(Design.Colors.textSecondary)

                HStack(spacing: 12) {
                    Image(systemName: player.role.symbolName)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(player.role.accentColor)

                    Text(player.role.displayName.uppercased())
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(player.role.accentColor)
                }
            }
            .padding(.bottom, 8)
        }
        .padding(.vertical, 36)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Design.Radii.extraLarge, style: .continuous)
                    .fill(palette.backgroundGradient)

                RoundedRectangle(cornerRadius: Design.Radii.extraLarge, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.05), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radii.extraLarge, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [palette.borderColor.opacity(0.5), palette.borderColor.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        )
        .shadow(color: Design.Colors.glowRed.opacity(0.3), radius: 30, y: 10)
    }

    private var continueButton: some View {
        Button {
            if store.state.isGameOver {
                store.transitionToGameOver()
            } else {
                store.transitionToDay()
            }
        } label: {
            Text(store.state.isGameOver ? "View Result" : "Continue to Day \(store.currentDayIndex + 1)")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(CTAButtonStyle(kind: .primary))
    }
}

// Reuse role card palette from RoleRevealView
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
