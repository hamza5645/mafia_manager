import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var store: GameStore
    @State private var names: [String] = Array(repeating: "", count: 5)

    private let minPlayers = 5
    private let maxPlayers = 19

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                VStack(alignment: .leading, spacing: 4) {
                    Text("MAFIA MANAGER")
                        .font(.system(size: 28, weight: .heavy))
                        .kerning(1.2)
                        .foregroundStyle(Design.Colors.textPrimary)
                    Text("Enter player names")
                        .foregroundStyle(Design.Colors.textSecondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // Names card
                VStack(alignment: .leading, spacing: 10) {
                    Text("Between \(minPlayers) and \(maxPlayers) players. Names must be unique.")
                        .font(.footnote)
                        .foregroundStyle(Design.Colors.textSecondary)

                    ForEach(names.indices, id: \.self) { idx in
                        HStack(spacing: 12) {
                            Text("\(idx + 1)")
                                .font(.subheadline.bold())
                                .frame(width: 28)
                                .padding(.vertical, 10)
                                .background(Design.Colors.surface2)
                                .foregroundStyle(Design.Colors.textSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            TextField("Player Name", text: Binding(
                                get: { names[idx] },
                                set: { names[idx] = $0 }
                            ))
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(Design.Colors.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                            if names.count > minPlayers {
                                Button {
                                    names.remove(at: idx)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(Design.Colors.dangerRed)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove row")
                            }
                        }
                    }

                    HStack {
                        Button {
                            if names.count < maxPlayers { names.append("") }
                        } label: {
                            Label("Add Another Player", systemImage: "plus")
                                .lineLimit(1)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Design.Colors.actionBlue)
                        .clipShape(Capsule())
                        .disabled(names.count >= maxPlayers)

                        Spacer()
                        let filled = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.count
                        Text("Players: \(names.count)/\(maxPlayers)")
                            .foregroundStyle(filled < minPlayers ? Design.Colors.dangerRed : Design.Colors.textSecondary)
                    }
                }
                .cardStyle()
                .padding(.horizontal, 20)

                Spacer(minLength: 14)
            }
        }
        .background(Design.Colors.surface0)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Reset", role: .destructive) { store.resetAll() }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 12) {
                if store.hasSavedGame {
                    Button("Load Last Game") { store.loadLastGame() }
                        .buttonStyle(CTAButtonStyle(kind: .secondary))
                } else {
                    Button("Reset All", role: .destructive) { store.resetAll() }
                        .buttonStyle(CTAButtonStyle(kind: .danger))
                }
                Button {
                    store.assignNumbersAndRoles(names: validInput)
                } label: {
                    Text("Assign Roles").frame(maxWidth: .infinity)
                }
                .buttonStyle(CTAButtonStyle(kind: .primary))
                .disabled(!isValid)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.clear)
        }
    }

    private var validInput: [String] {
        let trimmed = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let unique = Array(NSOrderedSet(array: trimmed)) as! [String]
        return unique
    }

    private var isValid: Bool {
        let trimmed = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard trimmed.count >= minPlayers && trimmed.count <= maxPlayers else { return false }
        let set = Set(trimmed.map { $0.lowercased() })
        return set.count == trimmed.count
    }

    private var validationHint: String {
        let trimmed = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if trimmed.count < minPlayers { return "Need at least \(minPlayers) names" }
        if trimmed.count > maxPlayers { return "Max \(maxPlayers) players" }
        let set = Set(trimmed.map { $0.lowercased() })
        if set.count != trimmed.count { return "Names must be unique" }
        return ""
    }
}

// Removed local GlassButtonStyle; using global CTAButtonStyle instead.
