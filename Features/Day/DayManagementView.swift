import SwiftUI

struct DayManagementView: View {
    @EnvironmentObject private var store: GameStore
    @State private var removedToday: [UUID: Bool] = [:]
    @State private var notes: [UUID: String] = [:]
    @State private var showEndGameConfirmation = false
    @State private var botVotes: [UUID: UUID] = [:] // Bot ID -> Target ID
    @State private var botsHaveVoted = false
    private let botService = BotDecisionService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Counts chips
                HStack(spacing: 8) {
                    Chip(text: "Mafia: \(store.aliveMafia.count)", style: .filled(Design.Colors.dangerRed))
                    Chip(text: "Others: \(store.aliveNonMafia.count)", style: .filled(Design.Colors.textSecondary))
                    Spacer()
                }
                .padding(.horizontal)

                VStack(spacing: 10) {
                    ForEach(store.alivePlayers.sorted(by: { $0.number < $1.number })) { p in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Text(p.name)
                                    .font(.headline)
                                Spacer()
                                if removedToday[p.id] == true {
                                    Button("Undo") { removedToday[p.id] = false }
                                        .buttonStyle(CTAButtonStyle(kind: .secondary))
                                        .frame(width: 110)
                                } else {
                                    Button("Vote Out") { removedToday[p.id] = true }
                                        .buttonStyle(CTAButtonStyle(kind: .danger))
                                        .frame(width: 110)
                                }
                            }
                            if removedToday[p.id] == true {
                                HStack {
                                    Image(systemName: "text.quote")
                                        .foregroundStyle(Design.Colors.textSecondary)
                                    TextField("Optional removal note", text: Binding(
                                        get: { notes[p.id, default: ""] },
                                        set: { notes[p.id] = $0 }
                                    ))
                                    .textInputAutocapitalization(.sentences)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Design.Colors.surface2)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                        .cardStyle()
                    }
                }
                .padding(.horizontal)

                // Bot votes summary
                if !botVotes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "cpu.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Design.Colors.brandGold)
                            Text("Bot Votes")
                                .font(Design.Typography.headline)
                                .foregroundStyle(Design.Colors.textPrimary)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(botVotes.keys), id: \.self) { botID in
                                if let bot = store.player(by: botID),
                                   let targetID = botVotes[botID],
                                   let target = store.player(by: targetID) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "cpu")
                                            .font(.system(size: 14))
                                            .foregroundStyle(Design.Colors.textSecondary)
                                        Text(bot.name)
                                            .font(Design.Typography.body)
                                            .foregroundStyle(Design.Colors.textSecondary)
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Design.Colors.textTertiary)
                                        Text("#\(target.number) \(target.name)")
                                            .font(Design.Typography.body)
                                            .foregroundStyle(Design.Colors.textPrimary)
                                            .fontWeight(.semibold)
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .background(Design.Colors.surface2)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                        }
                    }
                    .cardStyle()
                    .padding(.horizontal)
                }

                Spacer(minLength: 8)
            }
        }
        .navigationTitle("Day \(store.currentDayIndex + 1)")
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
        .onAppear {
            castBotVotes()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Button {
                    store.applyDayRemovals(removed: removedToday, notes: notes)

                    // Check if game is over, otherwise start next night
                    if !store.state.isGameOver {
                        // Start next night by waking up mafia
                        store.wakeUpRole(.mafia)
                    }
                    // If game is over, phase is already set to .gameOver in evaluateWinners
                } label: {
                    Text("Lock Votes")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CTAButtonStyle(kind: .primary))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Design.Colors.surface0.opacity(0.95))
        }
    }

    // MARK: - Bot Voting

    /// Automatically casts votes for all alive bot players
    private func castBotVotes() {
        guard !botsHaveVoted else { return }

        let aliveBots = store.aliveBots
        guard !aliveBots.isEmpty else { return }

        Task {
            // Add a small delay to simulate bots "thinking"
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            await MainActor.run {
                for bot in aliveBots {
                    if let targetID = botService.chooseVotingTarget(
                        botPlayer: bot,
                        alivePlayers: store.alivePlayers,
                        nightHistory: store.state.nightHistory,
                        dayHistory: store.state.dayHistory
                    ) {
                        botVotes[bot.id] = targetID
                        // Mark the target as removed in our tracking
                        removedToday[targetID] = true
                    }
                }
                botsHaveVoted = true
            }
        }
    }
}

struct PlayerChip: View {
    let player: Player
    var body: some View {
        HStack(spacing: 8) {
            Text("#\(player.number)")
                .font(.subheadline).bold()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.15))
                .clipShape(Capsule())
            Text(player.name)
            Spacer()
        }
    }
}

// Removed local GlassButtonStyle; using global CTAButtonStyle instead.
