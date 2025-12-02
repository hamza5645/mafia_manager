import SwiftUI

struct BotVotingRevealView: View {
    @EnvironmentObject private var store: GameStore
    @ScaledMetric(relativeTo: .title2) private var headerIconSize: CGFloat = 28

    private var botVotes: [(bot: Player, target: Player)] {
        guard let session = store.state.currentVotingSession else { return [] }

        return session.votes.compactMap { (voterID, targetID) -> (Player, Player)? in
            guard let voter = store.player(by: voterID),
                  voter.isBot,
                  let target = store.player(by: targetID) else {
                return nil
            }
            return (voter, target)
        }.sorted { $0.bot.number < $1.bot.number }
    }

    var body: some View {
        ZStack {
            Design.Colors.surface0.ignoresSafeArea()

            VStack(spacing: 32) {
                // Header
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "cpu.fill")
                            .font(.system(size: headerIconSize, weight: .semibold))
                            .foregroundStyle(Design.Colors.brandGold)

                        Text("Bot Votes")
                            .font(Design.Typography.title1)
                            .foregroundStyle(Design.Colors.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                    }

                    Text("The bots have cast their votes")
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.textSecondary)
                }
                .padding(.top, 40)

                // Bot votes list
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(botVotes, id: \.bot.id) { vote in
                            BotVoteCard(bot: vote.bot, target: vote.target)
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer()

                // Continue button
                Button {
                    store.startHumanVoting()
                } label: {
                    Text("Continue to Voting")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Continue to human voting")
                .accessibilityHint("Moves to the voting phase for players")
                .buttonStyle(CTAButtonStyle(kind: .primary))
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

struct BotVoteCard: View {
    let bot: Player
    let target: Player
    @ScaledMetric(relativeTo: .title3) private var playerIconSize: CGFloat = 18
    @ScaledMetric(relativeTo: .footnote) private var arrowIconSize: CGFloat = 16

    var body: some View {
        HStack(spacing: 16) {
            // Bot info
            HStack(spacing: 12) {
                Image(systemName: "cpu")
                    .font(.system(size: playerIconSize, weight: .semibold))
                    .foregroundStyle(Design.Colors.brandGold)

                Text(bot.name)
                    .font(Design.Typography.headline)
                    .foregroundStyle(Design.Colors.textPrimary)
            }

            Spacer()

            // Arrow
            Image(systemName: "arrow.right")
                .font(.system(size: arrowIconSize, weight: .bold))
                .foregroundStyle(Design.Colors.textTertiary)

            Spacer()

            // Target info
            HStack(spacing: 12) {
                Text(target.name)
                    .font(Design.Typography.headline)
                    .foregroundStyle(Design.Colors.textPrimary)

                Image(systemName: "hand.raised.fill")
                    .font(.system(size: playerIconSize, weight: .semibold))
                    .foregroundStyle(Design.Colors.dangerRed)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Design.Colors.surface1)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Design.Colors.stroke, lineWidth: 1.5)
                )
        )
        .shadow(color: Design.Shadows.small.color, radius: Design.Shadows.small.radius, x: Design.Shadows.small.x, y: Design.Shadows.small.y)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bot.name) voted for \(target.name)")
    }
}

#Preview {
    NavigationStack {
        BotVotingRevealView()
            .environmentObject({
                let store = GameStore()
                store.assignNumbersAndRoles(names: ["Alice"], numberOfBots: 5)
                store.startVoting()
                return store
            }())
    }
}
