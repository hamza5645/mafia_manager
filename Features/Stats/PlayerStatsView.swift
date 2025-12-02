import SwiftUI

struct PlayerStatsView: View {
    @EnvironmentObject var authStore: AuthStore
    @State private var playerStats: [PlayerStats] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    private let databaseService = DatabaseService()

    var body: some View {
        ZStack {
            Design.Colors.surface0
                .ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(.white)
            } else if playerStats.isEmpty {
                EmptyStatsView()
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(playerStats) { stat in
                            PlayerStatCard(stat: stat)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Player Stats")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadStats()
        }
        .refreshable {
            await loadStats()
        }
    }

    private func loadStats() async {
        guard let userId = authStore.currentUserId else { return }

        isLoading = true
        errorMessage = nil

        do {
            playerStats = try await databaseService.getPlayerStats(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

struct EmptyStatsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(Design.Typography.displayEmoji)
                .foregroundColor(.white.opacity(0.3))
                .accessibilityHidden(true)

            Text("No Stats Yet")
                .font(Design.Typography.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text("Complete some games to see player statistics here")
                .font(Design.Typography.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

struct PlayerStatCard: View {
    let stat: PlayerStats

    var body: some View {
        VStack(spacing: 16) {
            // Player Name Header
            HStack {
                Text(stat.playerName)
                    .font(Design.Typography.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Spacer()

                Text("\(stat.gamesPlayed) games")
                    .font(Design.Typography.caption)
                    .foregroundColor(.white.opacity(0.7))
            }

            // Win Rate
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Win Rate")
                        .font(Design.Typography.caption)
                        .foregroundColor(.white.opacity(0.7))

                    Text(String(format: "%.1f%%", stat.winRate * 100))
                        .font(Design.Typography.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Design.Colors.successGreen)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Record")
                        .font(Design.Typography.caption)
                        .foregroundColor(.white.opacity(0.7))

                    HStack(spacing: 4) {
                        Text("\(stat.gamesWon)W")
                            .foregroundColor(Design.Colors.successGreen)
                        Text("-")
                            .foregroundColor(.white.opacity(0.5))
                        Text("\(stat.gamesLost)L")
                            .foregroundColor(Design.Colors.dangerRed)
                    }
                    .font(Design.Typography.body)
                    .fontWeight(.bold)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(stat.playerName): \(String(format: "%.1f%%", stat.winRate * 100)) win rate, \(stat.gamesWon) wins, \(stat.gamesLost) losses")

            Divider()
                .background(.white.opacity(0.2))

            // Role Distribution
            VStack(alignment: .leading, spacing: 12) {
                Text("Role Distribution")
                    .font(Design.Typography.caption)
                    .foregroundColor(.white.opacity(0.7))

                HStack(spacing: 12) {
                    RoleStatBadge(role: .mafia, count: stat.timesMafia)
                    RoleStatBadge(role: .doctor, count: stat.timesDoctor)
                    RoleStatBadge(role: .inspector, count: stat.timesInspector)
                    RoleStatBadge(role: .citizen, count: stat.timesCitizen)
                }
            }

            // Additional Stats
            HStack(spacing: 16) {
                StatItem(icon: "target", label: "Kills", value: "\(stat.totalKills)")
                StatItem(icon: "chart.line.uptrend.xyaxis", label: "Avg Kills", value: String(format: "%.1f", stat.averageKillsPerGame))
            }
        }
        .padding()
        .background(Design.Colors.surface1)
        .cornerRadius(Design.Radii.card)
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radii.card)
                .stroke(Design.Colors.stroke, lineWidth: 1)
        )
    }
}

struct RoleStatBadge: View {
    let role: Role
    let count: Int

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: role.symbolName)
                .font(Design.Typography.caption)
                .foregroundColor(role.accentColor)
                .accessibilityHidden(true)

            Text("\(count)")
                .font(Design.Typography.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(role.accentColor.opacity(0.15))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(role.displayName): \(count) times")
    }
}

struct StatItem: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(Design.Typography.caption2)
                    .accessibilityHidden(true)
                Text(label)
                    .font(Design.Typography.caption2)
            }
            .foregroundColor(.white.opacity(0.7))

            Text(value)
                .font(Design.Typography.body)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
