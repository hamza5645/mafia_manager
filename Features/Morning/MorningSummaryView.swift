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

            HStack {
                if store.state.isGameOver {
                    NavigationLink(destination: GameOverView()) {
                        Text("View Result")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    NavigationLink(isActive: $goToDay) { DayManagementView() } label: { EmptyView() }
                    Button { goToDay = true } label: {
                        Text("Continue to Day \(store.currentDayIndex + 1) (Mark Removals)")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
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
            NavigationLink(destination: GameOverView(), isActive: $goToGameOver) { EmptyView() }
                .hidden()
        )
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack {
            Text("\(title):").fontWeight(.semibold)
            Spacer()
            Text(value)
        }
    }
}
