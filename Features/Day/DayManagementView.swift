import SwiftUI

struct DayManagementView: View {
    @EnvironmentObject private var store: GameStore
    @State private var removedToday: [UUID: Bool] = [:]
    @State private var notes: [UUID: String] = [:]
    @State private var showEndGameConfirmation = false

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
