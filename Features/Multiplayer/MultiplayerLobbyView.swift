import SwiftUI

struct MultiplayerLobbyView: View {
    @EnvironmentObject private var multiplayerStore: MultiplayerGameStore
    @EnvironmentObject private var authStore: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var showingLeaveConfirmation = false
    @State private var isStarting = false

    var body: some View {
        ZStack {
            Design.Colors.surface0.ignoresSafeArea()

            if let session = multiplayerStore.currentSession {
                // Debug logging
                let _ = print("🔍 [MultiplayerLobbyView] Current phase: \(session.currentPhase)")
                let _ = print("🔍 [MultiplayerLobbyView] Current phaseData: \(String(describing: session.currentPhaseData))")
                
                // Phase-based routing
                Group {
                    switch session.currentPhaseData {
                    case .lobby, .none:
                        let _ = print("📍 [MultiplayerLobbyView] Showing lobby content")
                        lobbyContent
                        
                    case .roleReveal(let index):
                        let _ = print("📍 [MultiplayerLobbyView] Showing role reveal (index: \(index))")
                        MultiplayerRoleRevealView(currentPlayerIndex: index)
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                        
                    case .night:
                        let _ = print("📍 [MultiplayerLobbyView] Showing night view")
                        MultiplayerNightView()
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                        
                    case .voting:
                        let _ = print("📍 [MultiplayerLobbyView] Showing voting view")
                        MultiplayerVotingView()
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                        
                    case .gameOver:
                        let _ = print("📍 [MultiplayerLobbyView] Showing game over view")
                        GameOverView()
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                        
                    default:
                        let _ = print("📍 [MultiplayerLobbyView] Showing default phase view")
                        Text("Phase: \(session.currentPhase)")
                            .font(Design.Typography.title2)
                            .foregroundStyle(Design.Colors.textPrimary)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: session.currentPhaseData)
            } else {
                ProgressView()
            }
        }
        .navigationBarBackButtonHidden(true)
        .confirmationDialog("Leave Game", isPresented: $showingLeaveConfirmation) {
            Button("Leave", role: .destructive) {
                leaveGame()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to leave this game?")
        }
    }
    
    private var lobbyContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Room Code Display
                if let session = multiplayerStore.currentSession {
                    VStack(spacing: 12) {
                        Text("Room Code")
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Colors.textSecondary)

                        Text(session.roomCode)
                                .font(.system(size: 48, weight: .bold, design: .monospaced))
                                .foregroundStyle(Design.Colors.brandGold)
                                .tracking(8)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 16)
                                .background(Design.Colors.surface1)
                                .cornerRadius(Design.Radii.large)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Design.Radii.large)
                                        .stroke(Design.Colors.brandGold.opacity(0.3), lineWidth: 2)
                                )

                            Text("Share this code with friends to join")
                                .font(Design.Typography.footnote)
                                .foregroundStyle(Design.Colors.textSecondary)
                        }
                        .padding(.top, 20)
                        .padding(.horizontal, 20)
                    }

                    // Game Status
                    HStack(spacing: 16) {
                            StatusBadge(
                                icon: "person.3.fill",
                                label: "\(multiplayerStore.visiblePlayers.count)",
                                color: Design.Colors.brandGold
                            )

                            StatusBadge(
                                icon: "cpu",
                                label: "\(multiplayerStore.visiblePlayers.filter { $0.isBot }.count)",
                                color: Design.Colors.textSecondary
                            )

                            if multiplayerStore.isHost {
                                StatusBadge(
                                    icon: "crown.fill",
                                    label: "Host",
                                    color: Design.Colors.brandGold
                                )
                            }
                        }
                    .padding(.horizontal, 20)

                    // Players List
                    if let session = multiplayerStore.currentSession {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Players (\(multiplayerStore.visiblePlayers.count)/\(session.maxPlayers))")
                                .font(Design.Typography.body)
                                .foregroundStyle(Design.Colors.textPrimary)
                                .padding(.horizontal, 20)

                            VStack(spacing: 12) {
                                ForEach(multiplayerStore.visiblePlayers) { playerInfo in
                                    PlayerRow(
                                        playerInfo: playerInfo,
                                        isMe: playerInfo.id == multiplayerStore.myPlayer?.id,
                                        isHost: playerInfo.id == multiplayerStore.allPlayers.first?.id
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // Ready Status (if not host)
                        if !multiplayerStore.isHost, let myPlayer = multiplayerStore.myPlayer {
                            Button {
                                Task {
                                    try? await multiplayerStore.toggleReady()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: myPlayer.isReady ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20))

                                    Text(myPlayer.isReady ? "Ready" : "Not Ready")
                                        .font(Design.Typography.body)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    myPlayer.isReady
                                        ? Design.Colors.successGreen.opacity(0.2)
                                        : Design.Colors.surface1
                                )
                                .foregroundColor(
                                    myPlayer.isReady
                                        ? Design.Colors.successGreen
                                        : Design.Colors.textPrimary
                                )
                                .cornerRadius(Design.Radii.medium)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Design.Radii.medium)
                                        .stroke(
                                            myPlayer.isReady
                                                ? Design.Colors.successGreen
                                                : Design.Colors.stroke.opacity(0.3),
                                            lineWidth: 1
                                        )
                                )
                            }
                            .padding(.horizontal, 20)
                        }

                        // Start Game Button (host only)
                        if multiplayerStore.isHost {
                            VStack(spacing: 12) {
                                Button {
                                    startGame()
                                } label: {
                                    HStack {
                                        if isStarting {
                                            ProgressView()
                                                .tint(.white)
                                        } else {
                                            Text("Start Game")
                                                .font(Design.Typography.body)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        canStart
                                            ? Design.Colors.brandGold
                                            : Design.Colors.textSecondary.opacity(0.3)
                                    )
                                    .foregroundColor(Design.Colors.surface0)
                                    .cornerRadius(Design.Radii.medium)
                                }
                                .disabled(!canStart || isStarting)

                                if !canStart {
                                    Text("Need 4-19 total players to start")
                                        .font(Design.Typography.footnote)
                                        .foregroundStyle(Design.Colors.dangerRed)
                                }
                            }
                            .padding(.horizontal, 20)
                        }

                        // Leave Button
                        Button {
                            showingLeaveConfirmation = true
                        } label: {
                            Text("Leave Game")
                                .font(Design.Typography.body)
                                .foregroundStyle(Design.Colors.dangerRed)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
    }

    private var canStart: Bool {
        let playerCount = multiplayerStore.visiblePlayers.count
        return playerCount >= 4 && playerCount <= 19
    }

    private func startGame() {
        print("🔘 [MultiplayerLobbyView] Start Game button tapped")
        print("🔘 [MultiplayerLobbyView] isHost: \(multiplayerStore.isHost)")
        
        guard multiplayerStore.isHost else {
            print("❌ [MultiplayerLobbyView] Not host, returning early")
            return
        }

        print("🔘 [MultiplayerLobbyView] Setting isStarting = true")
        isStarting = true

        Task {
            do {
                print("🔘 [MultiplayerLobbyView] Calling multiplayerStore.startGame()...")
                try await multiplayerStore.startGame()
                print("✅ [MultiplayerLobbyView] Game started successfully")
                // Game has started - navigation will be handled by phase updates
                await MainActor.run {
                    isStarting = false
                    print("🔘 [MultiplayerLobbyView] isStarting = false")
                }
            } catch {
                print("❌ [MultiplayerLobbyView] Failed to start game: \(error)")
                print("❌ [MultiplayerLobbyView] Error description: \(error.localizedDescription)")
                await MainActor.run {
                    isStarting = false
                    // Show error
                    print("❌ [MultiplayerLobbyView] isStarting = false (error path)")
                }
            }
        }
    }

    private func leaveGame() {
        Task {
            try? await multiplayerStore.leaveSession()
            await MainActor.run {
                dismiss()
            }
        }
    }
}

// MARK: - Player Row

struct PlayerRow: View {
    let playerInfo: PublicPlayerInfo
    let isMe: Bool
    let isHost: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Status Indicator
            Circle()
                .fill(playerInfo.isOnline ? Design.Colors.successGreen : Design.Colors.textSecondary.opacity(0.5))
                .frame(width: 10, height: 10)

            // Player Icon
            ZStack {
                Circle()
                    .fill(
                        playerInfo.isBot
                            ? Design.Colors.textSecondary.opacity(0.2)
                            : Design.Colors.brandGold.opacity(0.2)
                    )
                    .frame(width: 40, height: 40)

                Image(systemName: playerInfo.isBot ? "cpu" : "person.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(
                        playerInfo.isBot
                            ? Design.Colors.textSecondary
                            : Design.Colors.brandGold
                    )
            }

            // Player Name
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(playerInfo.playerName)
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.textPrimary)

                    if isMe {
                        Text("(You)")
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Colors.brandGold)
                    }

                    if isHost {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Design.Colors.brandGold)
                    }
                }

                if !playerInfo.isBot && !playerInfo.isReady {
                    Text("Not ready")
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.textSecondary)
                }
            }

            Spacer()

            // Ready Checkmark
            if !playerInfo.isBot && playerInfo.isReady {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Design.Colors.successGreen)
            }
        }
        .padding(12)
        .background(Design.Colors.surface1)
        .cornerRadius(Design.Radii.medium)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
            Text(label)
                .font(Design.Typography.caption)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .cornerRadius(Design.Radii.small)
    }
}

#Preview {
    NavigationStack {
        MultiplayerLobbyView()
            .environmentObject(MultiplayerGameStore())
            .environmentObject(AuthStore())
            .preferredColorScheme(.dark)
    }
}
