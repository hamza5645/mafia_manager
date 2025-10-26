import SwiftUI

struct MorningSummaryView: View {
    @EnvironmentObject private var store: GameStore
    @State private var goToDay = false
    @State private var goToGameOver = false

    private var lastNight: NightAction? { store.state.nightHistory.last }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let night = lastNight {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.stars.fill").foregroundStyle(Design.Colors.brandGold)
                        Text("Night \(night.nightIndex) Summary").font(.headline)
                    }
                    summaryRow(title: "Mafia", value: night.mafiaNumbers.map { "#\($0)" }.joined(separator: ", "))
                    if let t = store.number(for: night.mafiaTargetPlayerID) {
                        summaryRow(title: "Targeted", value: "#\(t)")
                    }
                    // Removed "Killed tonight" row; deaths are resolved during Day
                    // Inspector: show inspector number(s) and the number inspected
                    let inspectorNumbers = store.state.players.filter { $0.role == .inspector }.map { $0.number }.sorted()
                    let inspectorLabel = inspectorNumbers.isEmpty ? "—" : inspectorNumbers.map { "#\($0)" }.joined(separator: ", ")
                    if let inspectedNum = store.number(for: night.inspectorCheckedPlayerID) {
                        summaryRow(title: "Inspector", value: "\(inspectorLabel) → #\(inspectedNum)")
                    } else {
                        summaryRow(title: "Inspector", value: inspectorLabel)
                    }

                    // Doctor: show doctor number(s) and the number protected
                    let doctorNumbers = store.state.players.filter { $0.role == .doctor }.map { $0.number }.sorted()
                    let doctorLabel = doctorNumbers.isEmpty ? "—" : doctorNumbers.map { "#\($0)" }.joined(separator: ", ")
                    if let protectedNum = store.number(for: night.doctorProtectedPlayerID) {
                        summaryRow(title: "Doctor", value: "\(doctorLabel) → #\(protectedNum)")
                    } else {
                        summaryRow(title: "Doctor", value: doctorLabel)
                    }
                }
                .cardStyle()
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
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
                    .buttonStyle(CTAButtonStyle(kind: .primary))
                } else {
                    Button { goToDay = true } label: {
                        Text("Continue to Day \(store.currentDayIndex + 1) (Mark Removals)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CTAButtonStyle(kind: .primary))
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

// Removed local GlassButtonStyle; using global CTAButtonStyle instead.
