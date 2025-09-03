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
                    Text("Lock Day \(store.currentDayIndex + 1) & Start Night \(store.currentNightIndex)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.clear)
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

// MARK: - Local glass style
private struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.accentColor)
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.6)
                    .blendMode(.plusLighter)
                    .opacity(configuration.isPressed ? 0.35 : 1)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(configuration.isPressed ? 0.12 : 0.2), radius: 10, y: 6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: configuration.isPressed)
    }
}
