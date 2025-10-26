import SwiftUI

struct MorningSummaryView: View {
    @EnvironmentObject private var store: GameStore
    @State private var goToDay = false
    @State private var goToGameOver = false

    private var lastNight: NightAction? { store.state.nightHistory.last }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let night = lastNight {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "moon.stars.fill").foregroundStyle(Design.Colors.brandGold)
                            Text("Night \(night.nightIndex) Summary").font(.headline)
                        }
                        summaryRow(title: "Mafia", value: mafiaSummary(for: night))
                        summaryRow(title: "Targeted", value: targetedSummary(for: night))
                        summaryRow(title: "Killed", value: killedSummary(for: night))
                        summaryRow(title: "Inspector", value: inspectorSummary(for: night))
                        summaryRow(title: "Doctor", value: doctorSummary(for: night))
                    }
                    .cardStyle()
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .navigationTitle("Morning Summary")
        .background(Design.Colors.surface0.ignoresSafeArea())
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
            .background(Design.Colors.surface0.opacity(0.95))
        }
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack {
            Text("\(title):")
                .fontWeight(.semibold)
                .foregroundStyle(Design.Colors.textPrimary)
            Spacer()
            Text(value)
                .foregroundStyle(Design.Colors.textSecondary)
        }
    }
}

// Removed local GlassButtonStyle; using global CTAButtonStyle instead.

private extension MorningSummaryView {
    func mafiaSummary(for night: NightAction) -> String {
        let numbers = night.mafiaNumbers.sorted()
        return numbers.isEmpty ? "—" : numbers.map { "#\($0)" }.joined(separator: ", ")
    }

    func targetedSummary(for night: NightAction) -> String {
        guard let targetNumber = store.number(for: night.mafiaTargetPlayerID) else { return "—" }
        return "#\(targetNumber)"
    }

    func killedSummary(for night: NightAction) -> String {
        let deathNumbers = night.resultingDeaths.compactMap { store.number(for: $0) }.sorted()
        guard !deathNumbers.isEmpty else {
            if let targetNumber = store.number(for: night.mafiaTargetPlayerID),
               night.doctorProtectedPlayerID == night.mafiaTargetPlayerID {
                return "None (Doctor saved #\(targetNumber))"
            }
            return "None"
        }
        return deathNumbers.map { "#\($0)" }.joined(separator: ", ")
    }

    func inspectorSummary(for night: NightAction) -> String {
        let inspectorNumbers = store.state.players.filter { $0.role == .inspector }.map { $0.number }.sorted()
        let inspectorLabel = inspectorNumbers.isEmpty ? "—" : inspectorNumbers.map { "#\($0)" }.joined(separator: ", ")
        if let inspectedNum = store.number(for: night.inspectorCheckedPlayerID) {
            return "\(inspectorLabel) → #\(inspectedNum)"
        }
        return inspectorLabel
    }

    func doctorSummary(for night: NightAction) -> String {
        let doctorNumbers = store.state.players.filter { $0.role == .doctor }.map { $0.number }.sorted()
        let doctorLabel = doctorNumbers.isEmpty ? "—" : doctorNumbers.map { "#\($0)" }.joined(separator: ", ")
        if let protectedNum = store.number(for: night.doctorProtectedPlayerID) {
            return "\(doctorLabel) → #\(protectedNum)"
        }
        return doctorLabel
    }
}
