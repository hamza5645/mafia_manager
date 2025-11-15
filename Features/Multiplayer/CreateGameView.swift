import SwiftUI

struct CreateGameView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var multiplayerStore: MultiplayerGameStore
    @EnvironmentObject private var authStore: AuthStore

    @State private var playerName: String = ""
    @State private var botCount: Int = 0
    @State private var nightTimerSeconds: Int = 60
    @State private var dayTimerSeconds: Int = 180
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showingLobby = false

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.surface0.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Create Online Game")
                                .font(Design.Typography.title1)
                                .foregroundStyle(Design.Colors.textPrimary)

                            Text("Set up your multiplayer room")
                                .font(Design.Typography.body)
                                .foregroundStyle(Design.Colors.textSecondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                        // Player Name
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Your Name")
                                .font(Design.Typography.bodyMedium)
                                .foregroundStyle(Design.Colors.textPrimary)

                            TextField("Enter your name", text: $playerName)
                                .font(Design.Typography.body)
                                .textInputAutocapitalization(.words)
                                .disableAutocorrection(true)
                                .padding(.vertical, 14)
                                .padding(.horizontal, 16)
                                .background(Design.Colors.surface2)
                                .cornerRadius(Design.Radii.medium)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Design.Radii.medium)
                                        .stroke(Design.Colors.stroke.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .padding(.horizontal, 20)

                        // Bot Count
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Bot Players")
                                    .font(Design.Typography.bodyMedium)
                                    .foregroundStyle(Design.Colors.textPrimary)

                                Spacer()

                                Text("\(botCount)")
                                    .font(Design.Typography.bodyMedium)
                                    .foregroundStyle(Design.Colors.brandGold)
                            }

                            Slider(value: Binding(
                                get: { Double(botCount) },
                                set: { botCount = Int($0) }
                            ), in: 0...10, step: 1)
                            .tint(Design.Colors.brandGold)

                            Text("Add AI players to fill the game")
                                .font(Design.Typography.footnote)
                                .foregroundStyle(Design.Colors.textSecondary)
                        }
                        .padding(.horizontal, 20)

                        // Timer Settings
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Timer Settings")
                                .font(Design.Typography.bodyMedium)
                                .foregroundStyle(Design.Colors.textPrimary)

                            // Night Timer
                            HStack {
                                Text("Night Phase")
                                    .font(Design.Typography.body)
                                    .foregroundStyle(Design.Colors.textSecondary)

                                Spacer()

                                Picker("Night Timer", selection: $nightTimerSeconds) {
                                    Text("30s").tag(30)
                                    Text("60s").tag(60)
                                    Text("90s").tag(90)
                                    Text("120s").tag(120)
                                }
                                .pickerStyle(.menu)
                                .tint(Design.Colors.accent)
                            }

                            // Day Timer
                            HStack {
                                Text("Day Phase")
                                    .font(Design.Typography.body)
                                    .foregroundStyle(Design.Colors.textSecondary)

                                Spacer()

                                Picker("Day Timer", selection: $dayTimerSeconds) {
                                    Text("2 min").tag(120)
                                    Text("3 min").tag(180)
                                    Text("5 min").tag(300)
                                    Text("10 min").tag(600)
                                }
                                .pickerStyle(.menu)
                                .tint(Design.Colors.accent)
                            }
                        }
                        .padding(16)
                        .background(Design.Colors.surface1)
                        .cornerRadius(Design.Radii.medium)
                        .padding(.horizontal, 20)

                        // Error Message
                        if let error = errorMessage {
                            Text(error)
                                .font(Design.Typography.footnote)
                                .foregroundStyle(Design.Colors.dangerRed)
                                .padding(.horizontal, 20)
                        }

                        // Create Button
                        Button {
                            createGame()
                        } label: {
                            HStack {
                                if isCreating {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Create Room")
                                        .font(Design.Typography.bodyMedium)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Design.Colors.textSecondary.opacity(0.3)
                                    : Design.Colors.brandGold
                            )
                            .foregroundColor(Design.Colors.surface0)
                            .cornerRadius(Design.Radii.medium)
                        }
                        .disabled(playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .navigationDestination(isPresented: $showingLobby) {
                MultiplayerLobbyView()
                    .environmentObject(multiplayerStore)
                    .environmentObject(authStore)
            }
        }
    }

    private func createGame() {
        let trimmedName = playerName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            errorMessage = "Please enter your name"
            return
        }

        isCreating = true
        errorMessage = nil

        Task {
            do {
                try await multiplayerStore.createSession(
                    playerName: trimmedName,
                    botCount: botCount,
                    nightTimerSeconds: nightTimerSeconds,
                    dayTimerSeconds: dayTimerSeconds
                )

                await MainActor.run {
                    isCreating = false
                    showingLobby = true
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    CreateGameView()
        .environmentObject(MultiplayerGameStore())
        .environmentObject(AuthStore())
        .preferredColorScheme(.dark)
}
