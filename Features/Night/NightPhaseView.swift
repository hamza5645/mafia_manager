import SwiftUI

struct NightPhaseView: View {
    @EnvironmentObject private var store: GameStore
    @State private var mafiaTargetID: UUID?
    @State private var inspectorID: UUID?
    @State private var doctorID: UUID?
    @State private var goToMorning = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                SelectionCard(
                    title: "Mafia Action: Choose a Target",
                    selectionID: $mafiaTargetID,
                    players: store.state.players,
                    help: "Required",
                    filter: { p in p.role != .mafia && p.alive },
                    accent: Design.Colors.dangerRed,
                    icon: "flame.fill"
                )
                .cardStyle()
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radii.card).stroke(Design.Colors.dangerRed, lineWidth: 1.4)
                        .shadow(color: Design.Colors.dangerRed.opacity(0.45), radius: 8)
                )

                SelectionCard(
                    title: "Inspector Action: Check Identity",
                    selectionID: $inspectorID,
                    players: store.state.players,
                    help: "Shows full role",
                    filter: { p in p.role != .inspector },
                    resultKind: .inspector,
                    accent: Design.Colors.actionBlue,
                    icon: "eye.fill"
                )
                .cardStyle()
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radii.card).stroke(Design.Colors.actionBlue, lineWidth: 1.4)
                        .shadow(color: Design.Colors.actionBlue.opacity(0.45), radius: 8)
                )

                if store.state.players.contains(where: { $0.role == .doctor && $0.alive }) {
                    SelectionCard(
                        title: "Doctor Action: Protect Player",
                        selectionID: $doctorID,
                        players: store.state.players,
                        help: "Can protect self",
                        filter: { p in p.alive },
                        resultKind: .none,
                        accent: Design.Colors.successGreen,
                        icon: "cross.case.fill"
                    )
                    .cardStyle()
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.Radii.card).stroke(Design.Colors.successGreen, lineWidth: 1.4)
                            .shadow(color: Design.Colors.successGreen.opacity(0.45), radius: 8)
                    )
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .navigationTitle("Night \(store.currentNightIndex)")
        .background(
            NavigationLink(destination: MorningSummaryView(), isActive: $goToMorning) { EmptyView() }
                .hidden()
        )
        .toolbar { }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Button {
                    store.endNight(mafiaTargetID: mafiaTargetID, inspectorCheckedID: inspectorID, doctorProtectedID: doctorID)
                    goToMorning = true
                } label: {
                    Text("End Night & Reveal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CTAButtonStyle(kind: .primary))
                .disabled(mafiaTargetID == nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.clear)
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
    var accent: Color = Design.Colors.surface2
    var icon: String? = nil
    @State private var query: String = ""

    var filtered: [Player] {
        let base = players.filter(filter).sorted { $0.number < $1.number }
        guard !query.isEmpty else { return base }
        let q = query.lowercased()
        return base.filter { p in p.name.lowercased().contains(q) || "#\(p.number)".contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let icon {
                    ZStack {
                        Circle().fill(accent.opacity(0.22))
                        Image(systemName: icon).foregroundStyle(accent)
                    }
                    .frame(width: 28, height: 28)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(help)
                        .font(.footnote)
                        .foregroundStyle(Design.Colors.textSecondary)
                }
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Design.Colors.textSecondary)
                TextField("Search by name or #", text: $query)
                    .textInputAutocapitalization(.none)
                    .disableAutocorrection(true)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Design.Colors.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(filtered) { p in
                        Button {
                            selectionID = p.id
                        } label: {
                            HStack(spacing: 6) {
                                Text("#\(p.number)").bold()
                                Text(p.name)
                                if !p.alive { Text("✖").foregroundStyle(Design.Colors.textSecondary) }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(selectionID == p.id ? Design.Colors.actionBlue.opacity(0.18) : Design.Colors.surface2)
                            .overlay(
                                Capsule().strokeBorder(selectionID == p.id ? Design.Colors.actionBlue : Design.Colors.stroke, lineWidth: 1)
                            )
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
                        HStack(spacing: 8) {
                            Text("Result:")
                            Chip(text: p.role.displayName.uppercased(), style: .outline(p.role.accentColor))
                        }
                        .font(.subheadline.bold())
                    }
                }
            } else {
                Text("No selection yet").font(.subheadline).foregroundStyle(Design.Colors.textSecondary)
            }
        }
        .padding(.vertical, 6)
    }
}

// Removed local GlassButtonStyle; using global CTAButtonStyle instead.
