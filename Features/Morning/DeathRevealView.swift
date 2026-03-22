import SwiftUI

struct DeathRevealView: View {
    @EnvironmentObject private var store: GameStore
    @State private var showEndGameConfirmation = false

    private enum RevealContext {
        case night
        case vote
    }

    private var revealContext: RevealContext {
        if case .voteDeathReveal = store.state.currentPhase {
            return .vote
        }
        return .night
    }

    private var lastNight: NightAction? { store.state.nightHistory.last }
    private var lastDay: DayAction? { store.state.dayHistory.last }

    private var revealedPlayers: [Player] {
        switch revealContext {
        case .night:
            guard let night = lastNight else { return [] }
            return night.resultingDeaths.compactMap { deathID in
                store.player(by: deathID)
            }
        case .vote:
            guard let day = lastDay else { return [] }
            return day.removedPlayerIDs.compactMap { removedPlayerID in
                store.player(by: removedPlayerID)
            }
        }
    }

    private var emptyStateTitle: String {
        switch revealContext {
        case .night:
            return "No Deaths"
        case .vote:
            return "No Elimination"
        }
    }

    private var emptyStateSubtitle: String {
        switch revealContext {
        case .night:
            return "Everyone survived the night"
        case .vote:
            return "Nobody was voted out today"
        }
    }

    private var emptyStateAccessibilityLabel: String {
        switch revealContext {
        case .night:
            return "No deaths tonight. Everyone survived."
        case .vote:
            return "No elimination today. Nobody was voted out."
        }
    }

    private var eliminationIconName: String {
        switch revealContext {
        case .night:
            return "moon.zzz.fill"
        case .vote:
            return "person.fill.xmark"
        }
    }

    private var eliminationTitleVerb: String {
        switch revealContext {
        case .night:
            return "has Died"
        case .vote:
            return "was Voted Out"
        }
    }

    private var continueButtonTitle: String {
        if store.state.isGameOver {
            return "View Result"
        }

        switch revealContext {
        case .night:
            return "Continue to Day \(store.currentDayIndex + 1)"
        case .vote:
            return "Continue to Night \(store.currentNightIndex)"
        }
    }

    private var continueButtonAccessibilityLabel: String {
        if store.state.isGameOver {
            return "View game result"
        }

        switch revealContext {
        case .night:
            return "Continue to Day \(store.currentDayIndex + 1)"
        case .vote:
            return "Continue to Night \(store.currentNightIndex)"
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
        if revealedPlayers.isEmpty {
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
                Text(emptyStateTitle)
                    .font(Design.Typography.largeTitle)
                    .foregroundStyle(Design.Colors.textPrimary)

                Text(emptyStateSubtitle)
                    .font(Design.Typography.title3)
                    .foregroundColor(Design.Colors.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(emptyStateAccessibilityLabel)

            Spacer()

            continueButton
        }
        .padding(.horizontal, Design.Spacing.lg)
    }

    private var deathRevealContent: some View {
        // Adaptive spacing based on number of deaths
        let cardSpacing: CGFloat = revealedPlayers.count > 2 ? 20 : 32
        let topPadding: CGFloat = revealedPlayers.count == 1 ? 40 : 20

        return ScrollView {
            VStack(spacing: cardSpacing) {
                // Death cards
                ForEach(revealedPlayers, id: \.id) { player in
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

                Image(systemName: eliminationIconName)
                    .font(Design.Typography.displayEmoji)
                    .foregroundStyle(Design.Colors.dangerRed)
                    .accessibilityHidden(true)
            }
            .padding(.top, 8)

            // Title: Name has Died
            Text("\(player.name) \(eliminationTitleVerb)")
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
        .accessibilityLabel(accessibilityLabel(for: player))
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
                switch revealContext {
                case .night:
                    store.transitionToDay()
                case .vote:
                    store.completeVoteDeathReveal()
                }
            }
        } label: {
            Text(continueButtonTitle)
                .font(Design.Typography.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(CTAButtonStyle(kind: .primary))
        .accessibleButton(continueButtonAccessibilityLabel)
    }

    private func accessibilityLabel(for player: Player) -> String {
        switch revealContext {
        case .night:
            return "\(player.name) has died. They were player number \(player.number). Their role was \(player.role.displayName)."
        case .vote:
            return "\(player.name) was voted out. They were player number \(player.number). Their role was \(player.role.displayName)."
        }
    }
}

// RoleCardPalette now located in Core/Components/RoleCardPalette.swift
