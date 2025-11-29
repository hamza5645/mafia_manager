import SwiftUI

struct MultiplayerVotingResultsView: View {
    @EnvironmentObject private var multiplayerStore: MultiplayerGameStore
    @State private var isTransitioning = false
    @State private var transitionError: String?

    private var voteData: (dayIndex: Int, voteCounts: [UUID: Int], eliminatedId: UUID?)? {
        guard let session = multiplayerStore.currentSession,
              case .votingResults(let dayIndex, let voteCounts, let eliminatedPlayerId) = session.currentPhaseData else {
            return nil
        }
        return (dayIndex, voteCounts, eliminatedPlayerId)
    }

    private var playerLookup: [UUID: PublicPlayerInfo] {
        Dictionary(uniqueKeysWithValues: multiplayerStore.visiblePlayers.map { ($0.playerId, $0) })
    }

    private var sortedVoteCounts: [(player: PublicPlayerInfo, votes: Int)] {
        guard let data = voteData else { return [] }

        // HAMZA-FIX: Use map instead of compactMap to never silently drop vote entries
        // If a player is missing from visiblePlayers, create a placeholder
        return data.voteCounts.map { (playerID, voteCount) -> (PublicPlayerInfo, Int) in
            let player = playerLookup[playerID] ?? PublicPlayerInfo(
                id: playerID,
                playerId: playerID,
                playerName: "Unknown Player",
                playerNumber: nil,
                isBot: false,
                isAlive: false,
                isOnline: false,
                isReady: false
            )
            return (player, voteCount)
        }
        .sorted(by: { $0.1 > $1.1 })
    }

    private var eliminatedPlayer: PublicPlayerInfo? {
        guard let data = voteData, let eliminatedId = data.eliminatedId else { return nil }
        // HAMZA-FIX: Handle missing eliminated player with placeholder
        return playerLookup[eliminatedId] ?? PublicPlayerInfo(
            id: eliminatedId,
            playerId: eliminatedId,
            playerName: "Eliminated Player",
            playerNumber: nil,
            isBot: false,
            isAlive: false,
            isOnline: false,
            isReady: false
        )
    }

    private var nextPhaseButtonLabel: String {
        // The phase transition in applyVotingResult() will determine if game ends
        // based on actual win conditions. Just show a generic "Continue" label.
        "Continue"
    }

    var body: some View {
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
                        ForEach(sortedVoteCounts, id: \.player.playerId) { item in
                            MultiplayerVoteCountRow(
                                player: item.player,
                                voteCount: item.votes,
                                isEliminated: item.player.playerId == eliminatedPlayer?.playerId
                            )
                        }
                    }
                    .padding(.horizontal)
                }

                // Elimination result
                if let eliminated = eliminatedPlayer {
                    eliminationSection(for: eliminated)
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
                                if let data = voteData {
                                    do {
                                        try await multiplayerStore.applyVotingResult(dayIndex: data.dayIndex)
                                    } catch {
                                        transitionError = "Failed to continue: \(error.localizedDescription)"
                                    }
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
                    .font(.system(size: 16))
                    .foregroundStyle(isEliminated ? Design.Colors.dangerRed : Design.Colors.textSecondary)

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
        MultiplayerVotingResultsView()
            .environmentObject(MultiplayerGameStore())
            .preferredColorScheme(.dark)
    }
}
