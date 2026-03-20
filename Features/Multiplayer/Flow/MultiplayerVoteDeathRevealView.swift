import SwiftUI
import AudioToolbox

struct MultiplayerVoteDeathRevealView: View {
    @EnvironmentObject private var multiplayerStore: MultiplayerGameStore
    let dayIndex: Int

    // Animation state
    @State private var isCardFlipped = false
    @State private var showMysteryCard = true
    @State private var revealTriggered = false
    @State private var isTransitioning = false

    // Extracted reveal data from phase
    private var revealData: VoteRevealData? {
        guard let session = multiplayerStore.currentSession,
              case .voteDeathReveal(
                  let idx,
                  let playerId,
                  let name,
                  let number,
                  let roleStr,
                  let votes
              ) = session.currentPhaseData,
              idx == dayIndex else {
            return nil
        }
        return VoteRevealData(
            eliminatedPlayerId: playerId,
            playerName: name,
            playerNumber: number,
            role: roleStr.flatMap { Role(rawValue: $0) },
            voteCount: votes
        )
    }

    private var isEliminated: Bool {
        guard let myPlayer = multiplayerStore.myPlayer,
              let data = revealData else { return false }
        return data.eliminatedPlayerId == myPlayer.playerId
    }

    private var hasElimination: Bool {
        revealData?.eliminatedPlayerId != nil
    }

    var body: some View {
        ZStack {
            Design.Colors.surface0.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Header
                Text("The Town Has Voted")
                    .font(Design.Typography.title1)
                    .foregroundStyle(Design.Colors.textPrimary)

                // Card container
                cardRevealSection
                    .frame(width: 280, height: 380)

                Spacer()

                // Bottom message
                bottomMessageSection

                // Host continue button
                if multiplayerStore.isHost && isCardFlipped {
                    hostContinueButton
                }
            }
            .padding(24)
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            startRevealSequence()
        }
    }

    // MARK: - Card Reveal Section

    private var cardRevealSection: some View {
        ZStack {
            // Mystery card (back)
            mysteryCard
                .opacity(showMysteryCard ? 1 : 0)
                .rotation3DEffect(
                    .degrees(isCardFlipped ? 180 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.5
                )

            // Reveal card (front)
            revealCard
                .opacity(showMysteryCard ? 0 : 1)
                .rotation3DEffect(
                    .degrees(isCardFlipped ? 0 : -180),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.5
                )
        }
    }

    private var mysteryCard: some View {
        VStack(spacing: 24) {
            // Question mark with silhouette
            ZStack {
                Circle()
                    .fill(Design.Colors.surface2)
                    .frame(width: 100, height: 100)

                Image(systemName: "person.fill.questionmark")
                    .font(.system(size: 48))
                    .foregroundStyle(Design.Colors.textTertiary)
            }

            Text("???")
                .font(Design.Typography.largeTitle)
                .foregroundStyle(Design.Colors.textTertiary)

            Text("Who will be revealed?")
                .font(Design.Typography.body)
                .foregroundStyle(Design.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Design.Radii.extraLarge)
                .fill(Design.Colors.surface1)
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radii.extraLarge)
                        .stroke(Design.Colors.stroke, lineWidth: 2)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
    }

    @ViewBuilder
    private var revealCard: some View {
        if let data = revealData, let role = data.role, data.eliminatedPlayerId != nil {
            // Player elimination card
            eliminationCard(data: data, role: role)
        } else {
            // No elimination card
            noEliminationCard
        }
    }

    private func eliminationCard(data: VoteRevealData, role: Role) -> some View {
        VStack(spacing: 16) {
            // Eliminated icon
            ZStack {
                Circle()
                    .fill(Design.Colors.dangerRed.opacity(0.2))
                    .frame(width: 80, height: 80)

                Image(systemName: "person.slash.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Design.Colors.dangerRed)
            }

            // Player name
            Text(data.playerName ?? "Unknown")
                .font(Design.Typography.title1)
                .foregroundStyle(Design.Colors.textPrimary)

            // Player number
            if let number = data.playerNumber {
                Text("#\(number)")
                    .font(Design.Typography.title3)
                    .foregroundStyle(Design.Colors.brandGold)
            }

            Divider()
                .background(Design.Colors.stroke)
                .padding(.horizontal, 24)

            // Role reveal with accent color
            VStack(spacing: 8) {
                Text("Was a")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.textSecondary)

                HStack(spacing: 12) {
                    Image(systemName: role.symbolName)
                        .font(Design.Typography.title2)
                    Text(role.displayName.uppercased())
                        .font(Design.Typography.title2)
                        .fontWeight(.bold)
                }
                .foregroundStyle(role.accentColor)
            }

            // Vote count
            if let votes = data.voteCount {
                Text("\(votes) vote\(votes == 1 ? "" : "s")")
                    .font(Design.Typography.footnote)
                    .foregroundStyle(Design.Colors.textTertiary)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Design.Radii.extraLarge)
                    .fill(
                        LinearGradient(
                            colors: [Design.Colors.surface1, role.accentColor.opacity(0.15)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                RoundedRectangle(cornerRadius: Design.Radii.extraLarge)
                    .stroke(
                        LinearGradient(
                            colors: [role.accentColor.opacity(0.7), role.accentColor.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
            }
        )
        .shadow(color: role.accentColor.opacity(0.3), radius: 25, y: 8)
    }

    private var noEliminationCard: some View {
        VStack(spacing: 20) {
            // Peace icon
            ZStack {
                Circle()
                    .fill(Design.Colors.surface2)
                    .frame(width: 80, height: 80)

                Image(systemName: "hand.raised.slash.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Design.Colors.textSecondary)
            }

            Text("No Elimination")
                .font(Design.Typography.title1)
                .foregroundStyle(Design.Colors.textPrimary)

            Text("The town couldn't decide")
                .font(Design.Typography.body)
                .foregroundStyle(Design.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Design.Radii.extraLarge)
                .fill(Design.Colors.surface1)
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radii.extraLarge)
                        .stroke(Design.Colors.stroke, lineWidth: 2)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
    }

    // MARK: - Animation

    private func startRevealSequence() {
        guard !revealTriggered else { return }
        revealTriggered = true

        // Delay before flip (2.5-3 seconds of suspense)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            triggerCardFlip()
        }
    }

    private func triggerCardFlip() {
        // Prepare haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()

        // Play system sound (card flip)
        AudioServicesPlaySystemSound(1057)

        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            isCardFlipped = true
        }

        // After half the animation, swap visibility and trigger haptic
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showMysteryCard = false
            generator.notificationOccurred(.success)
        }
    }

    // MARK: - Bottom Section

    @ViewBuilder
    private var bottomMessageSection: some View {
        if isCardFlipped {
            if isEliminated {
                // Eliminated player sees special message
                VStack(spacing: 8) {
                    Text("The town has spoken.")
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.textSecondary)

                    if let role = revealData?.role {
                        Text("Your time as \(role.displayName) has ended.")
                            .font(Design.Typography.body)
                            .foregroundStyle(role.accentColor)
                    }
                }
                .padding()
                .background(Design.Colors.surface1)
                .cornerRadius(Design.Radii.medium)
            } else if !multiplayerStore.isHost {
                Text("Waiting for host to continue...")
                    .font(Design.Typography.footnote)
                    .foregroundStyle(Design.Colors.textSecondary)
            }
        } else {
            // Pre-reveal message
            Text("The votes have been counted...")
                .font(Design.Typography.body)
                .foregroundStyle(Design.Colors.textSecondary)
        }
    }

    private var hostContinueButton: some View {
        Button {
            Task {
                isTransitioning = true
                try? await multiplayerStore.completeVoteDeathReveal(dayIndex: dayIndex)
                isTransitioning = false
            }
        } label: {
            HStack {
                if isTransitioning {
                    ProgressView()
                        .tint(Design.Colors.surface0)
                } else {
                    Text("Continue to Night")
                        .font(Design.Typography.body)
                        .fontWeight(.bold)
                }
            }
            .foregroundStyle(Design.Colors.surface0)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Design.Colors.brandGold)
            .cornerRadius(Design.Radii.medium)
        }
        .disabled(isTransitioning)
        .padding(.bottom, 20)
    }
}

// MARK: - Supporting Types

private struct VoteRevealData {
    let eliminatedPlayerId: UUID?
    let playerName: String?
    let playerNumber: Int?
    let role: Role?
    let voteCount: Int?
}

#Preview {
    MultiplayerVoteDeathRevealView(dayIndex: 1)
        .environmentObject(MultiplayerGameStore())
        .preferredColorScheme(.dark)
}
