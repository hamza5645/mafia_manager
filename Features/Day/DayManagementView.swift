import SwiftUI

struct DayManagementView: View {
    @EnvironmentObject private var store: GameStore
    @State private var removedToday: [UUID: Bool] = [:]
    @State private var notes: [UUID: String] = [:]
    @State private var goToNextNight = false
    @State private var goToGameOver = false

    var body: some View {
        List {
            Section("Alive Players") {
                ForEach(store.alivePlayers.sorted(by: { $0.number < $1.number })) { p in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            PlayerChip(player: p)
                            Spacer()
                            Toggle("Removed today", isOn: Binding(
                                get: { removedToday[p.id] == true },
                                set: { removedToday[p.id] = $0 }
                            ))
                            .labelsHidden()
                        }
                        if removedToday[p.id] == true {
                            TextField("Optional removal note", text: Binding(
                                get: { notes[p.id, default: ""] },
                                set: { notes[p.id] = $0 }
                            ))
                            .textInputAutocapitalization(.sentences)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Counts") {
                let mafia = store.aliveMafia.count
                let nonMafia = store.aliveNonMafia.count
                HStack { Text("Mafia:"); Spacer(); Text("\(mafia)") }
                HStack { Text("Non-Mafia:"); Spacer(); Text("\(nonMafia)") }
            }
        }
        .navigationTitle("Day \(store.currentDayIndex + 1)")
        .background(
            Group {
                NavigationLink(destination: NightPhaseView(), isActive: $goToNextNight) { EmptyView() }.hidden()
                NavigationLink(destination: GameOverView(), isActive: $goToGameOver) { EmptyView() }.hidden()
            }
        )
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    store.applyDayRemovals(removed: removedToday, notes: notes)
                    if store.state.isGameOver {
                        goToNextNight = false
                        goToGameOver = true
                    } else {
                        goToNextNight = true
                    }
                } label: {
                    Text("Lock Day \(store.currentDayIndex + 1) & Start Night \(store.currentNightIndex)")
                }
                .buttonStyle(.borderedProminent)
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
