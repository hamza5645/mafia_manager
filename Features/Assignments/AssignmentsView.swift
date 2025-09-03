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
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) { store.resetAll() } label: { Text("Reset") }
            }
        }
        // Use a safe-area inset CTA with a custom glass style to avoid
        // toolbar rendering artifacts on newer iOS "liquid" design.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Button {
                    goToNight = true
                } label: {
                    Text(store.currentNightIndex == 1 ? "Start Night 1" : "Continue Night \(store.currentNightIndex)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.clear)
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

// MARK: - Glass Button Style (Liquid-like)
private struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.accentColor)
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(
                // Translucent, blurred material encapsulated in a capsule
                Capsule().fill(.ultraThinMaterial)
            )
            .overlay(
                // Subtle inner highlight
                Capsule()
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.6)
                    .blendMode(.plusLighter)
                    .opacity(configuration.isPressed ? 0.35 : 1)
            )
            .overlay(
                // Accent-tinted rim for the "liquid" sheen
                Capsule()
                    .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(configuration.isPressed ? 0.12 : 0.2), radius: 10, y: 6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: configuration.isPressed)
    }
}
