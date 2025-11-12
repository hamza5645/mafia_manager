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

    private func instructionView(for player: Player, at index: Int) -> some View {
        VStack(spacing: 32) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<store.state.players.count, id: \.self) { i in
                    Circle()
                        .fill(i <= index ? Design.Colors.brandGold : Design.Colors.surface2)
                        .frame(width: 8, height: 8)
                }
            }
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
                    .font(.system(size: 50, weight: .bold))
                    .foregroundStyle(Design.Colors.brandGold)
            }

            VStack(spacing: 12) {
                Text(player.isBot ? "Bot Player" : "Give phone to")
                    .font(Design.Typography.title3)
                    .foregroundColor(Design.Colors.textSecondary)

                HStack(spacing: 12) {
                    if player.isBot {
                        Image(systemName: "cpu.fill")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(Design.Colors.brandGold)
                    }
                    Text(player.name)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
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
                        .font(.system(size: 20, weight: .semibold))
                    Text("I'm Ready - Show My Role")
                        .font(Design.Typography.headline)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CTAButtonStyle(kind: .primary))
            .padding(.top, 16)
        }
    }

    private func roleRevealView(for player: Player, at index: Int) -> some View {
        let palette = RoleCardPalette(role: player.role)

        return VStack(spacing: 32) {
            // Role card
            VStack(alignment: .center, spacing: 24) {
                // Number
                Text("#\(player.number)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(Design.Colors.brandGold)
                    .shadow(color: Design.Colors.glowGold, radius: 8, y: 0)

                // Role icon
                ZStack {
                    Circle()
                        .fill(palette.iconBackground)
                        .shadow(color: palette.glowColor, radius: 20)
                        .frame(width: 120, height: 120)

                    Image(systemName: player.role.symbolName)
                        .font(.system(size: 60, weight: .bold))
                        .foregroundStyle(palette.iconColor)
                }

                // Role name
                Text(player.role.displayName.uppercased())
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(player.role.accentColor)
                    .shadow(color: palette.glowColor.opacity(0.5), radius: 8)

                // Player name
                HStack(spacing: 8) {
                    if player.isBot {
                        Image(systemName: "cpu")
                            .font(.system(size: 18))
                            .foregroundStyle(Design.Colors.textSecondary)
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

            // Action button
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showBlur = true
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    store.advanceToNextPlayer()

                    withAnimation(.easeInOut(duration: 0.3)) {
                        isRoleRevealed = false
                        showBlur = false
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Text(index < store.state.players.count - 1 ? "I've Seen It - Pass Phone" : "Done - Start Game")
                        .font(Design.Typography.headline)
                    Image(systemName: index < store.state.players.count - 1 ? "arrow.right.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CTAButtonStyle(kind: .secondary))
        }
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

// Role card styling (reused from AssignmentsView)
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
