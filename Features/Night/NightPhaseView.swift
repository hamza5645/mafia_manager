import SwiftUI

struct NightPhaseView: View {
    @EnvironmentObject private var store: GameStore
    @State private var mafiaTargetID: UUID?
    @State private var inspectorID: UUID?
    @State private var doctorID: UUID?
    @State private var goToMorning = false

    var body: some View {
        List {
            SelectionCard(
                title: "1) Mafia killed",
                selectionID: $mafiaTargetID,
                players: store.state.players,
                help: "Required.",
                filter: { p in p.role != .mafia && p.alive }
            )

            SelectionCard(
                title: "2) Inspector checked",
                selectionID: $inspectorID,
                players: store.state.players,
                help: "Shows full identity (role).",
                filter: { p in p.role != .inspector },
                resultKind: .inspector
            )

            if store.state.players.contains(where: { $0.role == .doctor && $0.alive }) {
                SelectionCard(
                    title: "3) Doctor protected",
                    selectionID: $doctorID,
                    players: store.state.players,
                    help: "Can protect self.",
                    filter: { p in p.alive },
                    resultKind: .none
                )
            }
        }
        .navigationTitle("Night \(store.currentNightIndex)")
        .background(
            NavigationLink(destination: MorningSummaryView(), isActive: $goToMorning) { EmptyView() }
                .hidden()
        )
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    store.endNight(mafiaTargetID: mafiaTargetID, inspectorCheckedID: inspectorID, doctorProtectedID: doctorID)
                    goToMorning = true
                } label: { Text("End Night") }
                .buttonStyle(.borderedProminent)
                .disabled(mafiaTargetID == nil)
            }
        }
    }
}

private struct SelectionCard: View {
    let title: String
    @Binding var selectionID: UUID?
    let players: [Player]
    var help: String
    var filter: (Player) -> Bool = { _ in true }
    enum ResultKind { case none, inspector }
    var resultKind: ResultKind = .none
    @State private var query: String = ""

    var filtered: [Player] {
        let base = players.filter(filter).sorted { $0.number < $1.number }
        guard !query.isEmpty else { return base }
        let q = query.lowercased()
        return base.filter { p in p.name.lowercased().contains(q) || "#\(p.number)".contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(help).font(.footnote).foregroundStyle(.secondary)
            TextField("Search by name or #", text: $query)
                .textInputAutocapitalization(.none)
                .disableAutocorrection(true)
                .textFieldStyle(.roundedBorder)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(filtered) { p in
                        Button {
                            selectionID = p.id
                        } label: {
                            HStack(spacing: 6) {
                                Text("#\(p.number)").bold()
                                Text(p.name)
                                if !p.alive { Text("✖").foregroundStyle(.secondary) }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(selectionID == p.id ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.15))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            if let sel = selectionID, let p = players.first(where: { $0.id == sel }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selected: #\(p.number) – \(p.name)")
                        .font(.subheadline)
                    switch resultKind {
                    case .none:
                        EmptyView()
                    case .inspector:
                        Text("Identity: \(p.role.displayName)")
                            .font(.subheadline.bold())
                            .foregroundStyle(roleColor(p.role))
                    }
                }
            } else {
                Text("No selection yet").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func roleColor(_ role: Role) -> Color {
        switch role {
        case .mafia: return .red
        case .doctor: return .green
        case .inspector: return .blue
        case .citizen: return .gray
        }
    }
}
