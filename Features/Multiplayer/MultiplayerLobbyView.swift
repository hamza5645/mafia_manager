import SwiftUI

struct MultiplayerLobbyView: View {
    @EnvironmentObject private var multiplayerStore: MultiplayerGameStore
    @EnvironmentObject private var authStore: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var showingLeaveConfirmation = false
    @State private var isStarting = false
    @State private var hasLeftSession = false
    @State private var startGameError: String?

    var body: some View {
        ZStack {
            Design.Colors.surface0.ignoresSafeArea()

            if let session = multiplayerStore.currentSession {
                // Phase-based routing
                Group {
                    switch session.currentPhaseData {
                    case .lobby, .none:
                        lobbyContent
                        
                    case .roleReveal(let index):
                        MultiplayerRoleRevealView(currentPlayerIndex: index)
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                        
                    case .night:
                        MultiplayerNightView()
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))

                    case .morning(let nightIndex):
                        MultiplayerMorningView(nightIndex: nightIndex)
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))

                    case .deathReveal(let nightIndex):
                        MultiplayerDeathRevealView(nightIndex: nightIndex)
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                        
                    case .voting:
                        MultiplayerVotingView()
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                        
                    case .gameOver:
                        GameOverView()
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                        
                    default:
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
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showingLeaveConfirmation = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Design.Colors.brandGold)
                }
            }
        }
        .confirmationDialog("Leave Game", isPresented: $showingLeaveConfirmation) {
            Button("Leave", role: .destructive) {
                leaveGame()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to leave this game?")
        }
        .onChange(of: multiplayerStore.wasKicked) { _, wasKicked in
            if wasKicked {
                // Auto-dismiss when kicked from session
                dismiss()
            }
        }
    }
    
    private var lobbyContent: some View {
        ZStack {
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
                                    label: "\(multiplayerStore.visiblePlayers.filter { !$0.isBot }.count)",
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
                                            isHost: playerInfo.id == multiplayerStore.allPlayers.first?.id,
                                            onRemove: (multiplayerStore.isHost && playerInfo.id != multiplayerStore.myPlayer?.id) ? {
                                                removePlayer(playerInfo)
                                            } : nil
                                        )
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }

                        // Spacer to account for sticky buttons
                        Color.clear.frame(height: calculateButtonHeight())
                    }
                .padding(.bottom, 20)
            }

            // Sticky Buttons at Bottom
            VStack {
                Spacer()

                VStack(spacing: 12) {
                    // Ready Status (non-host players only)
                    if let myPlayer = multiplayerStore.myPlayer, !multiplayerStore.isHost {
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
                    }

                    // Start Game Button (host only)
                    if multiplayerStore.isHost {
                        VStack(spacing: 8) {
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

                            // Validation messages
                            VStack(spacing: 8) {
                                let playerCount = multiplayerStore.visiblePlayers.count
                                let humanPlayers = multiplayerStore.visiblePlayers.filter { !$0.isBot }
                                let nonHostHumans = humanPlayers.filter { $0.id != multiplayerStore.myPlayer?.id }
                                let notReadyCount = nonHostHumans.filter { !$0.isReady }.count

                                if playerCount < 4 || playerCount > 19 {
                                    Text("Need 4-19 total players to start")
                                        .font(Design.Typography.footnote)
                                        .foregroundStyle(Design.Colors.dangerRed)
                                } else if notReadyCount > 0 {
                                    Text("\(notReadyCount) player\(notReadyCount == 1 ? "" : "s") not ready")
                                        .font(Design.Typography.footnote)
                                        .foregroundStyle(Design.Colors.dangerRed)
                                }

                                if let error = startGameError {
                                    Text(error)
                                        .font(Design.Typography.footnote)
                                        .foregroundStyle(Design.Colors.dangerRed)
                                        .padding(.top, 4)
                                }
                            }
                        }
                    }

                    // Leave Button
                    Button {
                        showingLeaveConfirmation = true
                    } label: {
                        Text("Leave & Quit")
                            .font(Design.Typography.body)
                            .foregroundStyle(Design.Colors.dangerRed)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
                .background(Design.Colors.surface0)
            }
        }
    }

    private func calculateButtonHeight() -> CGFloat {
        var height: CGFloat = 20 // Base padding

        // Ready button height (shown for non-host players only)
        if !multiplayerStore.isHost {
            height += 60 // Button with padding
        }

        // Start button height (host only)
        if multiplayerStore.isHost {
            height += 120 // Button + validation messages
        }

        // Leave button
        height += 56 // Leave button height

        return height
    }

    private var canStart: Bool {
        let playerCount = multiplayerStore.visiblePlayers.count
        let humanPlayers = multiplayerStore.visiblePlayers.filter { !$0.isBot }
        let nonHostHumans = humanPlayers.filter { $0.id != multiplayerStore.myPlayer?.id }
        let allNonHostHumansReady = nonHostHumans.allSatisfy { $0.isReady }

        return playerCount >= 4 && playerCount <= 19 && allNonHostHumansReady
    }

    private func startGame() {
        print("🔘 [MultiplayerLobbyView] Start Game button tapped")
        print("🔘 [MultiplayerLobbyView] isHost: \(multiplayerStore.isHost)")

        // Clear any previous errors
        startGameError = nil

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
                    startGameError = nil
                    print("🔘 [MultiplayerLobbyView] isStarting = false")
                }
            } catch SessionError.invalidPhase {
                print("❌ [MultiplayerLobbyView] Failed to start game: Not all players ready")
                await MainActor.run {
                    isStarting = false
                    startGameError = "All players must be ready before starting"
                }
            } catch {
                print("❌ [MultiplayerLobbyView] Failed to start game: \(error)")
                print("❌ [MultiplayerLobbyView] Error description: \(error.localizedDescription)")
                await MainActor.run {
                    isStarting = false
                    startGameError = "Failed to start game: \(error.localizedDescription)"
                    print("❌ [MultiplayerLobbyView] isStarting = false (error path)")
                }
            }
        }
    }

    private func leaveGame() {
        guard !hasLeftSession else { return }
        hasLeftSession = true
        Task {
            try? await multiplayerStore.leaveSession()
            await MainActor.run {
                dismiss()
            }
        }
    }
    
    private func removePlayer(_ playerInfo: PublicPlayerInfo) {
        Task {
            try? await multiplayerStore.removePlayer(withId: playerInfo.id)
        }
    }
}

// MARK: - Player Row

struct PlayerRow: View {
    let playerInfo: PublicPlayerInfo
    let isMe: Bool
    let isHost: Bool
    var onRemove: (() -> Void)? = nil

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
            
            // Remove Button (Host only)
            if let onRemove = onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Design.Colors.dangerRed)
                }
                .padding(.leading, 8)
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

// MARK: - Morning & Death Reveal Views

struct MultiplayerMorningView: View {
    @EnvironmentObject private var multiplayerStore: MultiplayerGameStore
    let nightIndex: Int

    private var nightRecord: NightActionRecord? {
        multiplayerStore.currentSession?.nightHistory.first(where: { $0.nightIndex == nightIndex })
    }

    private var playerLookup: [UUID: PublicPlayerInfo] {
        Dictionary(uniqueKeysWithValues: multiplayerStore.visiblePlayers.map { ($0.playerId, $0) })
    }

    private var eliminatedPlayers: [PublicPlayerInfo] {
        guard let record = nightRecord else { return [] }
        return record.resultingDeaths.compactMap { playerLookup[$0] }
    }

    private func playerName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return playerLookup[id]?.playerName
    }

    private func playerNumber(for id: UUID?) -> Int? {
        guard let id else { return nil }
        return playerLookup[id]?.playerNumber
    }

    // Helper functions matching local game format
    private func mafiaSummary(for record: NightActionRecord) -> String {
        let numbers = record.mafiaPlayerNumbers.sorted()
        let mafiaLabel = numbers.isEmpty ? "—" : numbers.map { "#\($0)" }.joined(separator: ", ")

        if let targetNumber = playerNumber(for: record.mafiaTargetId) {
            return "\(mafiaLabel) → #\(targetNumber)"
        }
        return mafiaLabel
    }

    private func policeSummary(for record: NightActionRecord) -> String {
        let numbers = record.inspectorPlayerNumbers.sorted()
        let policeLabel = numbers.isEmpty ? "—" : numbers.map { "#\($0)" }.joined(separator: ", ")

        if let inspectedNumber = playerNumber(for: record.inspectorCheckedId) {
            return "\(policeLabel) → #\(inspectedNumber)"
        }
        return policeLabel
    }

    private func doctorSummary(for record: NightActionRecord) -> String {
        let numbers = record.doctorPlayerNumbers.sorted()
        let doctorLabel = numbers.isEmpty ? "—" : numbers.map { "#\($0)" }.joined(separator: ", ")

        if let protectedNumber = playerNumber(for: record.doctorProtectedId) {
            return "\(doctorLabel) → #\(protectedNumber)"
        }
        return doctorLabel
    }

    private func killedSummary(for record: NightActionRecord) -> String {
        let deathNumbers = record.resultingDeaths.compactMap { playerNumber(for: $0) }.sorted()

        if !deathNumbers.isEmpty {
            return deathNumbers.map { "#\($0)" }.joined(separator: ", ")
        }

        // No deaths - check if doctor saved someone
        if let targetNumber = playerNumber(for: record.mafiaTargetId),
           record.doctorProtectedId == record.mafiaTargetId {
            return "None (Doctor saved #\(targetNumber))"
        }

        return "None"
    }

    var body: some View {
        ZStack {
            Design.Colors.surface0.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 8) {
                    Text("Morning \(nightIndex + 1)")
                        .font(Design.Typography.title1)
                        .foregroundStyle(Design.Colors.textPrimary)

                    Text("Night has ended. Here's what happened.")
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                if let record = nightRecord {
                    summaryView(for: record)
                } else {
                    ProgressView()
                        .tint(Design.Colors.brandGold)
                        .padding(.vertical, 40)
                }

                Spacer()

                Text("Waiting for host to reveal the day phase…")
                    .font(Design.Typography.footnote)
                    .foregroundStyle(Design.Colors.textSecondary)
                    .padding(.bottom, multiplayerStore.isHost ? 16 : 32)
                
                if multiplayerStore.isHost {
                    Button {
                        Task { try? await multiplayerStore.advanceToDeathRevealManual(nightIndex: nightIndex) }
                    } label: {
                        Text("Reveal Deaths")
                            .font(Design.Typography.body)
                            .fontWeight(.bold)
                            .foregroundStyle(Design.Colors.surface0)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Design.Colors.brandGold)
                            .cornerRadius(Design.Radii.medium)
                    }
                    .padding(.bottom, 40)
                }
            }
            .padding(24)
        }
        .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    private func summaryView(for record: NightActionRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Night summary with role actions
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "moon.stars.fill")
                        .foregroundStyle(Design.Colors.brandGold)
                    Text("Night \(nightIndex) Summary")
                        .font(Design.Typography.headline)
                        .foregroundStyle(Design.Colors.textPrimary)
                }

                summaryRow(title: "Mafia", value: mafiaSummary(for: record))
                summaryRow(title: "Killed", value: killedSummary(for: record))
                summaryRow(title: "Police", value: policeSummary(for: record))
                summaryRow(title: "Doctor", value: doctorSummary(for: record))
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Design.Colors.surface1)
            .cornerRadius(Design.Radii.medium)
        }
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack {
            Text("\(title):")
                .fontWeight(.semibold)
                .foregroundStyle(Design.Colors.textPrimary)
            Spacer()
            Text(value)
                .foregroundStyle(Design.Colors.textSecondary)
        }
    }
}

struct MultiplayerDeathRevealView: View {
    @EnvironmentObject private var multiplayerStore: MultiplayerGameStore
    let nightIndex: Int

    private var nightRecord: NightActionRecord? {
        multiplayerStore.currentSession?.nightHistory.first(where: { $0.nightIndex == nightIndex })
    }

    private var playerLookup: [UUID: PublicPlayerInfo] {
        Dictionary(uniqueKeysWithValues: multiplayerStore.visiblePlayers.map { ($0.playerId, $0) })
    }

    private var eliminatedPlayers: [PublicPlayerInfo] {
        guard let record = nightRecord else { return [] }
        return record.resultingDeaths.compactMap { playerLookup[$0] }
    }

    // Helper to determine role based on player number from night record
    private func roleFor(player: PublicPlayerInfo) -> Role {
        guard let record = nightRecord, let playerNum = player.playerNumber else {
            return .citizen
        }

        // Try to get role from session player first (if RLS allows)
        if let sessionPlayer = multiplayerStore.allPlayers.first(where: { $0.playerId == player.playerId }),
           let role = sessionPlayer.role {
            return role
        }

        // Otherwise, infer from role-specific number arrays in night record
        if record.mafiaPlayerNumbers.contains(playerNum) {
            return .mafia
        } else if record.doctorPlayerNumbers.contains(playerNum) {
            return .doctor
        } else if record.inspectorPlayerNumbers.contains(playerNum) {
            return .inspector
        } else {
            return .citizen
        }
    }

    var body: some View {
        ZStack {
            Design.Colors.surface0.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 8) {
                    Text("Death Reveal")
                        .font(Design.Typography.title1)
                        .foregroundStyle(Design.Colors.textPrimary)

                    Text("Night \(nightIndex + 1) results")
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.textSecondary)
                }

                if eliminatedPlayers.isEmpty {
                    Label("No deaths were reported", systemImage: "sparkles")
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.successGreen)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Design.Colors.surface1)
                        .cornerRadius(Design.Radii.medium)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Fallen Players")
                            .font(Design.Typography.body)
                            .foregroundStyle(Design.Colors.textPrimary)

                        ForEach(eliminatedPlayers) { player in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(player.playerName)
                                        .font(Design.Typography.body)
                                        .foregroundStyle(Design.Colors.textPrimary)
                                    Spacer()
                                    if let number = player.playerNumber {
                                        Text("#\(number)")
                                            .font(Design.Typography.caption)
                                            .foregroundStyle(Design.Colors.textSecondary)
                                    }
                                }
                                // Show role of eliminated player
                                let playerRole = roleFor(player: player)
                                HStack(spacing: 6) {
                                    Text("Was a")
                                        .font(Design.Typography.caption)
                                        .foregroundStyle(Design.Colors.textSecondary)
                                    HStack(spacing: 4) {
                                        Image(systemName: playerRole.symbolName)
                                            .font(.system(size: 12))
                                        Text(playerRole.displayName.uppercased())
                                            .font(Design.Typography.caption)
                                            .fontWeight(.semibold)
                                    }
                                    .foregroundStyle(playerRole.accentColor)
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Design.Colors.surface2)
                            .cornerRadius(Design.Radii.small)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Design.Colors.surface1)
                    .cornerRadius(Design.Radii.medium)
                }

                Spacer()

                Text("Get ready to vote. Host will continue shortly.")
                    .font(Design.Typography.footnote)
                    .foregroundStyle(Design.Colors.textSecondary)
                    .padding(.bottom, multiplayerStore.isHost ? 16 : 32)
                
                if multiplayerStore.isHost {
                    Button {
                        Task { try? await multiplayerStore.advanceToVotingManual(nightIndex: nightIndex) }
                    } label: {
                        Text("Start Voting")
                            .font(Design.Typography.body)
                            .fontWeight(.bold)
                            .foregroundStyle(Design.Colors.surface0)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Design.Colors.brandGold)
                            .cornerRadius(Design.Radii.medium)
                    }
                    .padding(.bottom, 40)
                }
            }
            .padding(24)
        }
        .navigationBarBackButtonHidden(true)
    }
}
