import SwiftUI

struct JoinGameView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var multiplayerStore: MultiplayerGameStore
    @EnvironmentObject private var authStore: AuthStore

    @State private var playerName: String = ""
    @State private var roomCode: String = ""
    @State private var isJoining = false
    @State private var errorMessage: String?
    @State private var showingLobby = false
    @ScaledMetric(relativeTo: .title) private var roomCodeFontSize: CGFloat = 24

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.surface0.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Join Online Game")
                                .font(Design.Typography.title1)
                                .foregroundStyle(Design.Colors.textPrimary)
                                .accessibilityAddTraits(.isHeader)

                            Text("Enter the room code to join")
                                .font(Design.Typography.body)
                                .foregroundStyle(Design.Colors.textSecondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                        VStack(spacing: 24) {
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
                                    .accessibilityLabel("Player name")
                                    .accessibilityHint("Enter the name shown to other players")
                                    .background(Design.Colors.surface2)
                                    .cornerRadius(Design.Radii.medium)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Design.Radii.medium)
                                            .stroke(Design.Colors.stroke.opacity(0.3), lineWidth: 1)
                                    )
                            }

                            // Room Code
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Room Code")
                                    .font(Design.Typography.body)
                                    .foregroundStyle(Design.Colors.textPrimary)

                                TextField("XXXXXX", text: $roomCode)
                                    .font(.system(size: roomCodeFontSize, weight: .bold, design: .monospaced))
                                    .textInputAutocapitalization(.characters)
                                    .disableAutocorrection(true)
                                    .multilineTextAlignment(.center)
                                    .padding(.vertical, 20)
                                    .accessibilityLabel("Room code")
                                    .accessibilityHint("Enter the six character room code from the host")
                                    .background(Design.Colors.surface1)
                                    .cornerRadius(Design.Radii.medium)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Design.Radii.medium)
                                            .stroke(Design.Colors.brandGold.opacity(0.3), lineWidth: 2)
                                    )
                                    .onChange(of: roomCode) { _, newValue in
                                        // Auto-uppercase and limit to 6 characters
                                        roomCode = String(newValue.uppercased().prefix(6))
                                    }

                                Text("Ask the host for the 6-character room code")
                                    .font(Design.Typography.footnote)
                                    .foregroundStyle(Design.Colors.textSecondary)
                            }
                        }
                        .padding(.horizontal, 20)

                        // Error Message
                        if let error = errorMessage {
                            Text(error)
                                .font(Design.Typography.footnote)
                                .foregroundStyle(Design.Colors.dangerRed)
                                .padding(.horizontal, 20)
                        }

                        // Join Button
                        Button {
                            joinGame()
                        } label: {
                            HStack {
                                if isJoining {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Join Room")
                                        .font(Design.Typography.body)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                canJoin
                                    ? Design.Colors.brandGold
                                    : Design.Colors.textSecondary.opacity(0.3)
                            )
                            .foregroundColor(Design.Colors.surface0)
                            .cornerRadius(Design.Radii.medium)
                        }
                        .accessibilityLabel("Join room")
                        .accessibilityHint("Attempts to join the room with your name and code")
                        .disabled(!canJoin || isJoining)
                        .padding(.horizontal, 20)

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
                    .accessibilityHint("Close join game and return to the previous screen")
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
        }
    }

    private var canJoin: Bool {
        !playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        roomCode.count == 6
    }

    private func joinGame() {
        let trimmedName = playerName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            errorMessage = "Please enter your name"
            return
        }

        guard roomCode.count == 6 else {
            errorMessage = "Room code must be 6 characters"
            return
        }

        isJoining = true
        errorMessage = nil

        Task {
            do {
                try await multiplayerStore.joinSession(
                    roomCode: roomCode,
                    playerName: trimmedName
                )

                await MainActor.run {
                    isJoining = false
                    showingLobby = true
                }
            } catch {
                await MainActor.run {
                    isJoining = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    JoinGameView()
        .environmentObject(MultiplayerGameStore())
        .environmentObject(AuthStore())
        .preferredColorScheme(.dark)
}
