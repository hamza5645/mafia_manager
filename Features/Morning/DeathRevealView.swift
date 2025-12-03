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
                    .font(Design.Typography.displayEmoji)
                    .foregroundStyle(Design.Colors.successGreen)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 12) {
                Text("No Deaths")
                    .font(Design.Typography.largeTitle)
                    .foregroundStyle(Design.Colors.textPrimary)

                Text("Everyone survived the night")
                    .font(Design.Typography.title3)
                    .foregroundColor(Design.Colors.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("No deaths tonight. Everyone survived.")

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
                    .font(Design.Typography.displayEmoji)
                    .foregroundStyle(Design.Colors.dangerRed)
                    .accessibilityHidden(true)
            }
            .padding(.top, 8)

            // Title: Name has Died
            Text("\(player.name) has Died")
                .font(Design.Typography.largeTitle)
                .foregroundStyle(Design.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            // Number
            Text("#\(player.number)")
                .font(Design.Typography.title2)
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
                        .font(Design.Typography.largeTitle)
                        .foregroundStyle(player.role.accentColor)
                        .accessibilityHidden(true)

                    Text(player.role.displayName.uppercased())
                        .font(Design.Typography.title1)
                        .foregroundStyle(player.role.accentColor)
                }
            }
            .padding(.bottom, 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(player.name) has died. They were player number \(player.number). Their role was \(player.role.displayName).")
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
                .font(Design.Typography.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(CTAButtonStyle(kind: .primary))
        .accessibleButton(store.state.isGameOver ? "View game result" : "Continue to Day \(store.currentDayIndex + 1)")
    }
}

// RoleCardPalette now located in Core/Components/RoleCardPalette.swift
