import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var store: GameStore
    @State private var names: [String] = Array(repeating: "", count: 5)

    private let minPlayers = 5
    private let maxPlayers = 19

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Form {
                Section("Players") {
                    Text("Enter between \(minPlayers) and \(maxPlayers) names. Names must be unique.")
                }.textCase(nil)
                
                Section("Player Names") {
                    ForEach(names.indices, id: \.self) { idx in
                        HStack {
                            Text("\(idx + 1).")
                                .frame(width: 28, alignment: .trailing)
                                .foregroundStyle(.secondary)
                            TextField("Name", text: Binding(
                                get: { names[idx] },
                                set: { names[idx] = $0 }
                            ))
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)

                            if names.count > minPlayers {
                                Button {
                                    names.remove(at: idx)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(Color.red)
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
                            Label("Add Player", systemImage: "plus.circle.fill")
                        }
                        .disabled(names.count >= maxPlayers)

                        Spacer()
                        Text("Count: \(validInput.count)/\(maxPlayers)")
                            .foregroundStyle(validInput.count >= minPlayers ? Color.secondary : Color.red)
                    }
                }

                // Randomness is always non-deterministic; no extra controls
            }

            HStack {
                Button("Assign Numbers & Roles") {
                    store.assignNumbersAndRoles(names: validInput)
                }
                .buttonStyle(GlassButtonStyle())
                .disabled(!isValid)

                if store.hasSavedGame {
                    Button("Load Last Game") {
                        store.loadLastGame()
                    }
                }

                Spacer()

                Button(role: .destructive) {
                    store.resetAll()
                } label: { Text("Reset All") }
            }
            .padding(.horizontal)

            Spacer(minLength: 0)
        }
        .navigationTitle("Mafia Manager Setup")
    }

    private var header: some View {
        HStack {
            Image(systemName: "person.3.fill")
                .font(.largeTitle)
            Text("Mafia Manager")
                .font(.largeTitle).bold()
            Spacer()
        }
        .padding(.horizontal)
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
