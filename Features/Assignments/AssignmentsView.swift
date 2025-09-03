import SwiftUI

struct AssignmentsView: View {
    @EnvironmentObject private var store: GameStore
    @State private var goToNight = false

    var body: some View {
        List {
            Section("Cheat Sheet") {
                cheatSheet
            }

            Section("Public List (numbers only)") {
                ForEach(store.state.players.sorted(by: { $0.number < $1.number })) { p in
                    HStack {
                        Text("#\(p.number)")
                            .monospacedDigit()
                            .lineLimit(1)
                            .frame(width: 44, alignment: .trailing)
                        Text(p.name)
                            .lineLimit(1)
                        Spacer()
                        if !p.alive { Text("removed").foregroundStyle(.secondary) }
                    }
                }
            }
        }
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

    private var cheatSheet: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("#").font(.subheadline).frame(width: 44, alignment: .trailing)
                Text("Name").font(.subheadline)
                Spacer()
                Text("Role").font(.subheadline)
            }
            .foregroundStyle(.secondary)

            ForEach(store.state.players.sorted(by: { $0.number < $1.number })) { p in
                HStack {
                    Text("#\(p.number)")
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(width: 44, alignment: .trailing)
                    Text(p.name)
                        .lineLimit(1)
                    Spacer()
                    Text(p.role.displayName)
                        .fontWeight(.semibold)
                        .foregroundStyle(roleColor(p.role))
                }
                .padding(.vertical, 2)
            }
        }
        .font(.body)
        .padding(.vertical, 4)
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
