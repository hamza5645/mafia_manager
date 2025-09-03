import SwiftUI

struct AssignmentsView: View {
    @EnvironmentObject private var store: GameStore
    @State private var goToNight = false

    // Column widths for tidy alignment
    private let numberColWidth: CGFloat = 56
    private let roleColWidth: CGFloat = 96

    var body: some View {
        List {
            Section {
                ForEach(sortedPlayers) { p in
                    HStack(spacing: 12) {
                        Text("#\(p.number)")
                            .monospacedDigit()
                            .frame(width: numberColWidth, alignment: .trailing)
                            .accessibilityLabel("Number \(p.number)")

                        Text(p.name)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 12)

                        Text(p.role.displayName)
                            .fontWeight(.semibold)
                            .foregroundStyle(roleColor(p.role))
                            .frame(width: roleColWidth, alignment: .trailing)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
        }
        .listStyle(.plain) // Full-width table look
        .navigationTitle("Assignments")
        .background(
            NavigationLink(destination: NightPhaseView(), isActive: $goToNight) { EmptyView() }
                .hidden()
        )
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    goToNight = true
                } label: {
                    Text(store.currentNightIndex == 1 ? "Start Night 1" : "Continue Night \(store.currentNightIndex)")
                }
                .buttonStyle(.borderedProminent)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) { store.resetAll() } label: { Text("Reset") }
            }
        }
    }

    private var sortedPlayers: [Player] {
        store.state.players.sorted { $0.number < $1.number }
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
