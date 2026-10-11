import SwiftUI
import AudioToolbox

struct MultiplayerVoteDeathRevealView: View {
    @EnvironmentObject private var multiplayerStore: MultiplayerGameStore
    /// The phase payload, from the router (which gives each day a fresh view).
    let reveal: VoteRevealData

    // Animation state
    @State private var isCardFlipped = false
    @State private var showMysteryCard = true

    private var isEliminated: Bool {
        guard let myPlayer = multiplayerStore.myPlayer,
              let eliminatedId = reveal.eliminatedPlayerId else { return false }
        return eliminatedId == myPlayer.playerId
    }

    private var hasElimination: Bool {
        reveal.eliminatedPlayerId != nil
    }

    var body: some View {
        ZStack {
            Design.Colors.surface0.ignoresSafeArea()

            // Scrolls when the card and buttons don't fit (short windows, iPad mini landscape).
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 32) {
                        Spacer()

                        // Header
                        Text("The Town Has Voted")
                            .font(Design.Typography.title1)
                            .foregroundStyle(Design.Colors.textPrimary)
                            .multilineTextAlignment(.center)

                        // Card container
                        cardRevealSection
                            .frame(width: 280, height: 380)

                        Spacer()

                        // Bottom message
                        bottomMessageSection

                        // Host continue button
                        if multiplayerStore.isHost && isCardFlipped {
                            HostTransitionButton(title: "Continue to Night") {
                                try await multiplayerStore.continueFromVoteReveal()
                            }
                            .padding(.bottom, 20)
                        }
                    }
                    .padding(24)
                    .frame(minHeight: proxy.size.height)
                    .readableContentWidth()
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .navigationBarBackButtonHidden(true)
        .task {
            await runRevealSequence()
        }
        .sensoryFeedback(.success, trigger: showMysteryCard) { wasShowing, isShowing in
            wasShowing && !isShowing
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
        if let role = reveal.role, reveal.eliminatedPlayerId != nil {
            // Player elimination card
            eliminationCard(data: reveal, role: role)
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

    /// 2.5 s of suspense, the flip sound and the flip, then the haptic as the card turns.
    /// Tied to the view's lifetime, so a player who leaves early hears and feels nothing later.
    private func runRevealSequence() async {
        guard !isCardFlipped else { return }
        guard (try? await Task.sleep(for: .seconds(2.5))) != nil else { return }

        // Play system sound (card flip)
        AudioServicesPlaySystemSound(1057)

        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            isCardFlipped = true
        }

        // After half the animation, swap visibility (the haptic follows via .sensoryFeedback)
        try? await Task.sleep(for: .seconds(0.3))
        showMysteryCard = false
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

                    if let role = reveal.role {
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
}

// MARK: - Supporting Types

/// The `voteDeathReveal` phase payload.
struct VoteRevealData {
    let eliminatedPlayerId: UUID?
    let playerName: String?
    let playerNumber: Int?
    let role: Role?
    let voteCount: Int?
}

#Preview {
    MultiplayerVoteDeathRevealView(
        reveal: VoteRevealData(eliminatedPlayerId: nil, playerName: nil, playerNumber: nil, role: nil, voteCount: nil)
    )
        .environmentObject(MultiplayerGameStore())
        .preferredColorScheme(.dark)
}
