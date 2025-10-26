import SwiftUI

struct DayManagementView: View {
    @EnvironmentObject private var store: GameStore
    @State private var removedToday: [UUID: Bool] = [:]
    @State private var notes: [UUID: String] = [:]
    @State private var goToNextNight = false
    @State private var goToGameOver = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DAY \(store.currentDayIndex + 1)")
                        .font(.system(size: 26, weight: .heavy))
                        .kerning(1)
                    Text("Discuss and vote on who to eliminate.")
                        .foregroundStyle(Design.Colors.textSecondary)
                }
                .padding(.horizontal)

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
                                Chip(text: "#\(p.number)", style: .outline(Design.Colors.textSecondary))
                                Text(p.name).font(.headline)
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
        .background(
            Group {
                NavigationLink(destination: NightPhaseView(), isActive: $goToNextNight) { EmptyView() }.hidden()
                NavigationLink(destination: GameOverView(), isActive: $goToGameOver) { EmptyView() }.hidden()
            }
        )
        .toolbar { }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Button {
                    store.applyDayRemovals(removed: removedToday, notes: notes)
                    if store.state.isGameOver {
                        goToNextNight = false
                        goToGameOver = true
                    } else {
                        goToNextNight = true
                    }
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
