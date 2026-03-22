import SwiftUI

struct CreateGameView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var multiplayerStore: MultiplayerGameStore
    @EnvironmentObject private var authStore: AuthStore

    @State private var playerName: String = ""
    @State private var botCount: Int = 0
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showingLobby = false
    @State private var hasStartedSession = false

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
                                .font(Design.Typography.body)
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
                                .automationID("multiplayer.create.playerName")
                        }
                        .padding(.horizontal, 20)

                        // Bot Count
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Bot Players")
                                    .font(Design.Typography.body)
                                    .foregroundStyle(Design.Colors.textPrimary)

                                Spacer()

                                Text("\(botCount)")
                                    .font(Design.Typography.body)
                                    .foregroundStyle(Design.Colors.brandGold)
                            }

                            Slider(value: Binding(
                                get: { Double(botCount) },
                                set: { botCount = Int($0) }
                            ), in: 0...10, step: 1)
                            .tint(Design.Colors.brandGold)
                            .sensoryFeedback(.selection, trigger: botCount)

                            Text("Add AI players to fill the game")
                                .font(Design.Typography.footnote)
                                .foregroundStyle(Design.Colors.textSecondary)
                        }
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
                                        .tint(Design.Colors.surface0)
                                } else {
                                    Text("Create Room")
                                        .font(Design.Typography.body)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Design.Colors.textSecondary.opacity(Design.Opacity.disabled)
                                    : Design.Colors.brandGold
                            )
                            .foregroundColor(Design.Colors.surface0)
                            .cornerRadius(Design.Radii.medium)
                        }
                        .disabled(playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .automationID("multiplayer.create.submit")

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasStartedSession {
                            Task {
                                try? await multiplayerStore.leaveSession()
                                dismiss()
                            }
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $showingLobby) {
                MultiplayerLobbyView()
                    .environmentObject(multiplayerStore)
                    .environmentObject(authStore)
            }
            .onAppear {
                // Use profile display name, fall back to guest display name for anonymous users
                if let displayName = authStore.userProfile?.displayName, !displayName.isEmpty {
                    playerName = displayName
                } else if let guestName = authStore.guestDisplayName, !guestName.isEmpty {
                    playerName = guestName
                }
            }
            .onDisappear {
                // Cleanup on swipe-to-dismiss if session was started but not navigated to lobby
                if hasStartedSession && !showingLobby {
                    Task {
                        try? await multiplayerStore.leaveSession()
                    }
                }
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
            // Auto sign-in as guest if not authenticated
            if !authStore.isAuthenticated {
                let success = await authStore.signInAsGuest(displayName: trimmedName)
                if !success {
                    await MainActor.run {
                        isCreating = false
                        errorMessage = "Failed to connect. Please try again."
                    }
                    return
                }
            }

            // Now create the session
            do {
                // Mark session as started before async call
                await MainActor.run {
                    hasStartedSession = true
                }

                try await multiplayerStore.createSession(
                    playerName: trimmedName,
                    botCount: botCount
                )

                await MainActor.run {
                    isCreating = false
                    showingLobby = true
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    hasStartedSession = false // Reset on failure
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
