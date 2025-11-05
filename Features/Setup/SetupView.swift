import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var store: GameStore
    private let minPlayers = 4
    private let maxPlayers = 19
    @State private var names: [String]
    @State private var isAddingPlayer = false

    init() {
        _names = State(initialValue: Array(repeating: "", count: minPlayers))
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
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

                    if names.count == minPlayers {
                        Text("Minimum \(minPlayers) players required for gameplay.")
                            .font(.caption2)
                            .foregroundStyle(Design.Colors.textSecondary.opacity(0.7))
                    }

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
                                    // Extra safety check to ensure we don't go below minimum
                                    if names.count > minPlayers {
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.85, blendDuration: 0.25)) {
                                            let removalIndex = names.index(names.startIndex, offsetBy: idx)
                                            names.remove(at: removalIndex)
                                            // Final safety check - if somehow we went below minimum, reset to minimum
                                            if names.count < minPlayers {
                                                resetNameFields(animated: true)
                                            }
                                        }
                                    }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(Design.Colors.dangerRed)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove row")
                                .disabled(isAddingPlayer)
                                .opacity(isAddingPlayer ? 0.3 : 1.0)
                            }
                        }
                    }

                    HStack {
                        let filled = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.count
                        let allFilled = filled == names.count && filled >= minPlayers
                        Button {
                            if names.count < maxPlayers {
                                isAddingPlayer = true
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.82, blendDuration: 0.25)) {
                                    names.append("")
                                }
                                // Add a small delay before allowing removals again
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    isAddingPlayer = false
                                }
                            }
                        } label: {
                            Label("Add Another Player", systemImage: "plus")
                                .lineLimit(1)
                        }
                        .buttonStyle(PillButtonStyle(background: Design.Colors.actionBlue))
                        .opacity(names.count >= maxPlayers ? 0.5 : 1)
                        .disabled(names.count >= maxPlayers)

                        Spacer()
                        Text("Players: \(names.count)/\(maxPlayers)")
                            .foregroundStyle(allFilled ? Design.Colors.successGreen : Design.Colors.dangerRed)
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
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(Design.Colors.brandGold)
                }
            }
        }
        .onAppear {
            if store.isFreshSetup {
                resetNameFields(animated: false)
            }
        }
        .onChange(of: store.isFreshSetup) { fresh in
            if fresh {
                resetNameFields()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                if store.hasSavedGame {
                    Button("Load Last Game") { store.loadLastGame() }
                        .buttonStyle(CTAButtonStyle(kind: .secondary))
                }
                HStack(spacing: 12) {
                    Button("Reset All", role: .destructive) {
                        store.resetAll()
                        resetNameFields()
                    }
                    .buttonStyle(CTAButtonStyle(kind: .danger))
                    Button {
                        store.assignNumbersAndRoles(names: validInput)
                    } label: {
                        Text("Assign Roles").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CTAButtonStyle(kind: .primary))
                    .disabled(!isValid)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Design.Colors.surface0.opacity(0.95))
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

    private func resetNameFields(animated: Bool = true) {
        isAddingPlayer = false
        let base = Array(repeating: "", count: minPlayers)
        if animated {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82, blendDuration: 0.25)) {
                names = base
            }
        } else {
            names = base
        }
    }
}

// Removed local GlassButtonStyle; using global CTAButtonStyle instead.
