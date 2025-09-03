import SwiftUI

struct MorningSummaryView: View {
    @EnvironmentObject private var store: GameStore
    @State private var goToDay = false
    @State private var goToGameOver = false

    private var lastNight: NightAction? { store.state.nightHistory.last }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let night = lastNight {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        summaryRow(title: "Mafia", value: night.mafiaNumbers.map { "#\($0)" }.joined(separator: ", "))
                        if let t = store.number(for: night.mafiaTargetPlayerID) {
                            summaryRow(title: "Targeted", value: "#\(t)")
                        }
                        let killed = night.resultingDeaths.compactMap { store.number(for: $0) }.sorted()
                        summaryRow(title: "Killed tonight", value: killed.isEmpty ? "—" : killed.map { "#\($0)" }.joined(separator: ", "))
                        if let n = store.number(for: night.inspectorCheckedPlayerID) {
                            let ident = night.inspectorResultRole?.displayName ?? (night.inspectorResultIsMafia == true ? "Mafia" : (night.inspectorResultIsMafia == false ? "Not Mafia" : "—"))
                            summaryRow(title: "Inspector checked", value: "#\(n) → \(ident)")
                        }

                        if store.state.players.contains(where: { $0.role == .doctor && $0.alive }) {
                            if let n = store.number(for: night.doctorProtectedPlayerID) {
                                summaryRow(title: "Doctor protected", value: "#\(n)")
                            }
                        }
                    }
                } label: {
                    Text("Night \(night.nightIndex) Summary")
                }
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Morning Summary")
        .onAppear {
            if store.state.isGameOver {
                // If a win was reached at start-of-day, auto-offer Game Over
                goToGameOver = true
            }
        }
        .background(
            Group {
                NavigationLink(destination: DayManagementView(), isActive: $goToDay) { EmptyView() }.hidden()
                NavigationLink(destination: GameOverView(), isActive: $goToGameOver) { EmptyView() }.hidden()
            }
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                if store.state.isGameOver {
                    Button { goToGameOver = true } label: {
                        Text("View Result")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassButtonStyle())
                } else {
                    Button { goToDay = true } label: {
                        Text("Continue to Day \(store.currentDayIndex + 1) (Mark Removals)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.clear)
        }
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack {
            Text("\(title):").fontWeight(.semibold)
            Spacer()
            Text(value)
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
