import SwiftUI

struct RoleRevealView: View {
    @EnvironmentObject private var store: GameStore
    @State private var isRoleRevealed = false
    @State private var showBlur = false
    @State private var showEndGameConfirmation = false

    var body: some View {
        ZStack {
            Design.Colors.surface0
                .ignoresSafeArea()

            if showBlur {
                PrivacyBlurView()
                    .transition(.opacity)
            } else {
                mainContent
                    .transition(.opacity)
            }
        }
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(true)
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
        .onAppear {
            isRoleRevealed = false
            showBlur = false
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if case .roleReveal(let currentIndex) = store.state.currentPhase,
           currentIndex < store.state.players.count {
            let player = store.state.players[currentIndex]

            VStack(spacing: 0) {
                Spacer()

                if !isRoleRevealed {
                    // Instruction screen
                    instructionView(for: player, at: currentIndex)
                } else {
                    // Role reveal screen
                    roleRevealView(for: player, at: currentIndex)
                }

                Spacer()
            }
            .padding(.horizontal, Design.Spacing.lg)
        } else {
            // Fallback
            Text("Loading...")
                .foregroundColor(Design.Colors.textSecondary)
        }
    }

    // MARK: - Helper Properties & Methods

    private var humanPlayers: [Player] {
        store.state.players.filter { !$0.isBot }
    }

    private var currentHumanIndex: Int {
        guard case .roleReveal(let currentIndex) = store.state.currentPhase,
              currentIndex < store.state.players.count else { return 0 }

        // Count how many human players have been revealed so far
        let revealedPlayers = store.state.players.prefix(currentIndex + 1)
        return revealedPlayers.filter { !$0.isBot }.count
    }

    private func instructionView(for player: Player, at index: Int) -> some View {
        VStack(spacing: 32) {
            // Progress indicator with auto-wrapping grid (only showing human players)
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(8), spacing: 8), count: min(humanPlayers.count, 30)),
                spacing: 8
            ) {
                ForEach(0..<humanPlayers.count, id: \.self) { i in
                    Circle()
                        .fill(i < currentHumanIndex ? Design.Colors.brandGold : Design.Colors.surface2)
                        .frame(width: 8, height: 8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)

            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Design.Colors.brandGold.opacity(0.3),
                                Design.Colors.brandGold.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .shadow(color: Design.Colors.glowGold.opacity(0.5), radius: 20)

                Image(systemName: "hand.point.up.left.fill")
                    .font(Design.Typography.displayEmoji)
                    .foregroundStyle(Design.Colors.brandGold)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 12) {
                Text(player.isBot ? "Bot Player" : "Give phone to")
                    .font(Design.Typography.title3)
                    .foregroundColor(Design.Colors.textSecondary)

                HStack(spacing: 12) {
                    if player.isBot {
                        Image(systemName: "cpu.fill")
                            .font(Design.Typography.largeTitle)
                            .foregroundStyle(Design.Colors.brandGold)
                            .accessibilityHidden(true)
                    }
                    Text(player.name)
                        .font(Design.Typography.largeTitle)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Design.Colors.brandGold, Design.Colors.brandGold.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            }

            Button {
                withAnimation(.spring(response: 0.3)) {
                    isRoleRevealed = true
                }
                // Haptic feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "eye.fill")
                        .font(Design.Typography.title3)
                    Text("I'm Ready - Show My Role")
                        .font(Design.Typography.headline)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CTAButtonStyle(kind: .primary))
            .padding(.top, 16)
            .accessibleButton("Show my role", hint: "Reveals your secret role assignment")
            .automationID("solo.roleReveal.showRole")
        }
        .accessibilityElement(children: .contain)
    }

    private func roleRevealView(for player: Player, at index: Int) -> some View {
        let palette = RoleCardPalette(role: player.role)

        return VStack(spacing: 32) {
            // Role card
            VStack(alignment: .center, spacing: 24) {
                // Number
                Text("#\(player.number)")
                    .font(Design.Typography.playerNumber)
                    .foregroundStyle(Design.Colors.brandGold)
                    .shadow(color: Design.Colors.glowGold, radius: 8, y: 0)

                // Role icon
                ZStack {
                    Circle()
                        .fill(palette.iconBackground)
                        .shadow(color: palette.glowColor, radius: 20)
                        .frame(width: 120, height: 120)

                    Image(systemName: player.role.symbolName)
                        .font(Design.Typography.displayEmoji)
                        .foregroundStyle(palette.iconColor)
                        .accessibilityHidden(true)
                }

                // Role name
                Text(player.role.displayName.uppercased())
                    .font(Design.Typography.largeTitle)
                    .foregroundStyle(player.role.accentColor)
                    .shadow(color: palette.glowColor.opacity(0.5), radius: 8)

                // Player name
                HStack(spacing: 8) {
                    if player.isBot {
                        Image(systemName: "cpu")
                            .font(Design.Typography.headline)
                            .foregroundStyle(Design.Colors.textSecondary)
                            .accessibilityHidden(true)
                    }
                    Text(player.name)
                        .font(Design.Typography.title2)
                        .foregroundColor(Design.Colors.textPrimary)
                }

                // Role description
                Text(roleDescription(for: player.role))
                    .font(Design.Typography.body)
                    .foregroundColor(Design.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            }
            .padding(.vertical, 40)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: Design.Radii.extraLarge, style: .continuous)
                        .fill(palette.backgroundGradient)

                    RoundedRectangle(cornerRadius: Design.Radii.extraLarge, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.1), .clear],
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
                            colors: [palette.borderColor, palette.borderColor.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            )
            .shadow(color: palette.glowColor.opacity(0.4), radius: 30, y: 10)
            .accessiblePlayerCard(name: player.name, number: player.number, role: player.role.displayName)

            // Action button
            Button {
                // Show blur immediately for privacy
                withAnimation(Design.Animations.easeInOut) {
                    showBlur = true
                }

                // After blur transition delay, update state while still blurred
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    // Reset state while blur is still showing
                    isRoleRevealed = false
                    store.advanceToNextPlayer()

                    // Then hide blur after state has settled
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(Design.Animations.easeInOut) {
                            showBlur = false
                        }
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Text(index < store.state.players.count - 1 ? "I've Seen It - Pass Phone" : "Done - Start Game")
                        .font(Design.Typography.headline)
                    Image(systemName: index < store.state.players.count - 1 ? "arrow.right.circle.fill" : "checkmark.circle.fill")
                        .font(Design.Typography.title3)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CTAButtonStyle(kind: .secondary))
            .accessibleButton(index < store.state.players.count - 1 ? "I've seen my role, pass phone" : "Done, start game")
            .automationID(index < store.state.players.count - 1 ? "solo.roleReveal.passPhone" : "solo.roleReveal.startGame")
        }
        .accessibilityElement(children: .contain)
    }

    private func roleDescription(for role: Role) -> String {
        switch role {
        case .mafia:
            return "You are part of the Mafia. Your goal is to eliminate all other players without getting caught."
        case .doctor:
            return "You can protect one player each night from the Mafia's attack."
        case .inspector:
            return "You can investigate one player each night to discover if they are Mafia."
        case .citizen:
            return "You are a regular citizen. Help identify and vote out the Mafia during the day."
        }
    }
}

// RoleCardPalette now located in Core/Components/RoleCardPalette.swift
