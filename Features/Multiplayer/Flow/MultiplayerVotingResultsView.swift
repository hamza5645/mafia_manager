import SwiftUI

struct MultiplayerVotingResultsView: View {
    @EnvironmentObject private var multiplayerStore: MultiplayerGameStore
    /// The phase payload, from the router.
    let voteCounts: [UUID: Int]
    let eliminatedPlayerId: UUID?

    @State private var isTransitioning = false
    @State private var transitionError: String?

    /// HAMZA-FIX: never silently drop a vote entry; a player missing from the roster gets a placeholder.
    private static func placeholder(_ id: UUID, name: String) -> PublicPlayerInfo {
        PublicPlayerInfo(
            id: id,
            playerId: id,
            playerName: name,
            playerNumber: nil,
            isBot: false,
            isAlive: false,
            isOnline: false,
            isReady: false
        )
    }

    /// Most votes first; ties by player number, then id, so every device shows the same order.
    static func sortedTallies(
        _ voteCounts: [UUID: Int],
        lookup: [UUID: PublicPlayerInfo]
    ) -> [(player: PublicPlayerInfo, votes: Int)] {
        voteCounts
            .map { playerID, voteCount in
                (player: lookup[playerID] ?? placeholder(playerID, name: "Unknown Player"), votes: voteCount)
            }
            .sorted { a, b in
                if a.votes != b.votes { return a.votes > b.votes }
                return (a.player.playerNumber ?? .max, a.player.playerId.uuidString)
                    < (b.player.playerNumber ?? .max, b.player.playerId.uuidString)
            }
    }

    private var nextPhaseButtonLabel: String {
        // The phase transition in applyVotingResult() will determine if game ends
        // based on actual win conditions. Just show a generic "Continue" label.
        "Continue"
    }

    var body: some View {
        // Built once per render, outside the ForEach.
        let lookup = Dictionary(
            multiplayerStore.visiblePlayers.map { ($0.playerId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let tallies = Self.sortedTallies(voteCounts, lookup: lookup)
        let eliminatedPlayer = eliminatedPlayerId.map { lookup[$0] ?? Self.placeholder($0, name: "Eliminated Player") }

        ZStack {
            Design.Colors.surface0.ignoresSafeArea()

            VStack(spacing: 32) {
                // Title
                Text("Voting Results")
                    .font(Design.Typography.largeTitle)
                    .foregroundStyle(Design.Colors.textPrimary)
                    .padding(.top, 40)

                // Vote tally (scrollable)
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(tallies, id: \.player.playerId) { item in
                            MultiplayerVoteCountRow(
                                player: item.player,
                                voteCount: item.votes,
                                isEliminated: item.player.playerId == eliminatedPlayerId
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .layoutPriority(1)

                // Elimination result
                if let eliminatedPlayer {
                    eliminationSection(for: eliminatedPlayer)
                } else {
                    noEliminationSection
                }

                Spacer()

                // Continue button (host only)
                if multiplayerStore.isHost {
                    VStack(spacing: 12) {
                        Button {
                            Task {
                                isTransitioning = true
                                transitionError = nil
                                do {
                                    try await multiplayerStore.continueFromVotingResults()
                                } catch {
                                    transitionError = HostTransition.errorMessage(for: error)
                                }
                                isTransitioning = false
                            }
                        } label: {
                            HStack {
                                if isTransitioning {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text(nextPhaseButtonLabel)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CTAButtonStyle(kind: .primary))
                        .disabled(isTransitioning)

                        if let error = transitionError {
                            Text(error)
                                .font(Design.Typography.caption)
                                .foregroundStyle(Design.Colors.dangerRed)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                } else {
                    Text("Waiting for host to continue...")
                        .font(Design.Typography.footnote)
                        .foregroundStyle(Design.Colors.textSecondary)
                        .padding(.bottom, 32)
                }
            }
            .readableContentWidth()
        }
        .navigationBarBackButtonHidden(true)
    }

    private func eliminationSection(for player: PublicPlayerInfo) -> some View {
        VStack(spacing: 16) {
            Divider()
                .background(Design.Colors.textTertiary)
                .padding(.horizontal)

            VStack(spacing: 8) {
                Text("Eliminated")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.textSecondary)

                Text(player.playerName)
                    .font(Design.Typography.title3)
                    .foregroundStyle(Design.Colors.textPrimary)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Design.Colors.surface1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Design.Colors.dangerRed, lineWidth: 2)
                        )
                )
            }
        }
    }

    private var noEliminationSection: some View {
        VStack(spacing: 8) {
            Divider()
                .background(Design.Colors.textTertiary)
                .padding(.horizontal)

            Text("No Elimination")
                .font(Design.Typography.title3)
                .foregroundStyle(Design.Colors.textSecondary)

            Text("Vote was tied or no votes cast")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.textTertiary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Design.Colors.surface1)
        )
    }
}

struct MultiplayerVoteCountRow: View {
    let player: PublicPlayerInfo
    let voteCount: Int
    let isEliminated: Bool

    var body: some View {
        HStack(spacing: 16) {
            // Player name
            Text(player.playerName)
                .font(Design.Typography.body)
                .foregroundStyle(Design.Colors.textPrimary)

            Spacer()

            // Vote count
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .font(Design.Typography.subheadline)
                    .foregroundStyle(isEliminated ? Design.Colors.dangerRed : Design.Colors.textSecondary)
                    .accessibilityHidden(true)

                Text("\(voteCount)")
                    .font(Design.Typography.headline)
                    .foregroundStyle(isEliminated ? Design.Colors.dangerRed : Design.Colors.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isEliminated ? Design.Colors.dangerRed.opacity(0.2) : Design.Colors.surface2)
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Design.Colors.surface1)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isEliminated ? Design.Colors.dangerRed : Color.clear, lineWidth: 2)
                )
        )
    }
}

#Preview {
    NavigationStack {
        MultiplayerVotingResultsView(voteCounts: [:], eliminatedPlayerId: nil)
            .environmentObject(MultiplayerGameStore())
            .preferredColorScheme(.dark)
    }
}
