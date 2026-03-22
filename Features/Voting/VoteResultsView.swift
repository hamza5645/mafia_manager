import SwiftUI

struct VoteResultsView: View {
    @EnvironmentObject private var store: GameStore
    @State private var showEndGameConfirmation = false

    private var votingSession: VotingSession? {
        store.state.currentVotingSession
    }

    private var eliminatedPlayer: Player? {
        guard let eliminatedID = votingSession?.eliminatedPlayerID else { return nil }
        return store.player(by: eliminatedID)
    }

    private var sortedVoteCounts: [(player: Player, votes: Int)] {
        guard let session = votingSession else { return [] }

        return session.voteCounts.compactMap { (playerID, voteCount) -> (Player, Int)? in
            guard let player = store.player(by: playerID) else { return nil }
            return (player, voteCount)
        }
        .sorted { $0.votes > $1.votes }
    }

    private var continueButtonTitle: String {
        eliminatedPlayer == nil ? "Continue to Night" : "Reveal Eliminated Player"
    }

    var body: some View {
        ZStack {
            Design.Colors.surface0.ignoresSafeArea()

            VStack(spacing: 32) {
                // Title
                Text("Voting Results")
                    .font(Design.Typography.largeTitle)
                    .foregroundStyle(Design.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 40)

                // Vote tally
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(sortedVoteCounts, id: \.player.id) { item in
                            VoteCountRow(
                                player: item.player,
                                voteCount: item.votes,
                                isEliminated: item.player.id == eliminatedPlayer?.id
                            )
                        }
                    }
                    .padding(.horizontal)
                }

                // Elimination result
                if let eliminated = eliminatedPlayer {
                    VStack(spacing: 16) {
                        Divider()
                            .background(Design.Colors.textTertiary)
                            .padding(.horizontal)

                        VStack(spacing: 8) {
                            Text("Eliminated")
                                .font(Design.Typography.caption)
                                .foregroundStyle(Design.Colors.textSecondary)

                            HStack(spacing: 12) {
                                Text("#\(eliminated.number)")
                                    .font(Design.Typography.title2)
                                    .foregroundStyle(Design.Colors.dangerRed)
                                    .frame(width: 60)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Design.Colors.surface2)
                                    )

                                Text(eliminated.name)
                                    .font(Design.Typography.title3)
                                    .foregroundStyle(Design.Colors.textPrimary)
                            }
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
                } else {
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

                Spacer()

                // Continue button
                Button {
                    store.applyVotingResult()
                } label: {
                    Text(continueButtonTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CTAButtonStyle(kind: .primary))
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
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
}

struct VoteCountRow: View {
    let player: Player
    let voteCount: Int
    let isEliminated: Bool
    @ScaledMetric(relativeTo: .subheadline) private var voteIconSize: CGFloat = 16

    var body: some View {
        HStack(spacing: 16) {
            // Player number
            Text("#\(player.number)")
                .font(Design.Typography.headline)
                .foregroundStyle(isEliminated ? Design.Colors.dangerRed : Design.Colors.textPrimary)
                .frame(width: 50)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Design.Colors.surface2)
                )

            // Player name
            Text(player.name)
                .font(Design.Typography.body)
                .foregroundStyle(Design.Colors.textPrimary)

            Spacer()

            // Vote count
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: voteIconSize, weight: .semibold))
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(player.name) received \(voteCount) vote\(voteCount == 1 ? "" : "s")\(isEliminated ? ", eliminated" : "")")
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        VoteResultsView()
            .environmentObject({
                let store = GameStore()
                store.assignNumbersAndRoles(names: ["Alice", "Bob", "Charlie", "Diana"], numberOfBots: 2)
                // Simulate voting session
                var session = VotingSession(dayIndex: 0)
                let players = store.state.players
                if players.count >= 4 {
                    session.recordVote(from: players[0].id, for: players[1].id)
                    session.recordVote(from: players[1].id, for: players[2].id)
                    session.recordVote(from: players[2].id, for: players[1].id)
                    session.recordVote(from: players[3].id, for: players[1].id)
                    _ = session.tallyVotes()
                    store.setVotingSessionForPreview(session)
                }
                return store
            }())
    }
}
#endif
