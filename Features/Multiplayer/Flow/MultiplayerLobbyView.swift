import SwiftUI
import UIKit

struct MultiplayerLobbyView: View {
    @EnvironmentObject private var multiplayerStore: MultiplayerGameStore
    @EnvironmentObject private var authStore: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var showingLeaveConfirmation = false
    @State private var isStarting = false
    @State private var hasLeftSession = false
    @State private var startGameError: String?
    @State private var leaveGameError: String?
    @State private var showingLeaveError = false
    /// Shown for a few seconds when the original host takes the lobby back.
    @State private var hostNotice: String?

    private static var slide: AnyTransition {
        .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
    }

    var body: some View {
        ZStack {
            Design.Colors.surface0.ignoresSafeArea()

            // Route only once both the session and the roster have arrived, so nothing
            // renders a half-loaded room (for example "Players (0/19)").
            if let session = multiplayerStore.currentSession, !multiplayerStore.players.isEmpty {
                phaseView(for: session)
                    .animation(.easeInOut(duration: 0.3), value: session.currentPhaseData)
            } else {
                LobbyConnectingView(roomCode: multiplayerStore.roomCode ?? multiplayerStore.currentSession?.roomCode)
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if let problem = multiplayerStore.connectionProblem {
                    ConnectionBanner(message: problem, onRetry: multiplayerStore.retryConnection)
                } else if multiplayerStore.showsReconnectBanner {
                    ConnectionBanner(message: "Reconnecting…", onRetry: multiplayerStore.retryConnection)
                }
                if let hostNotice {
                    HostNoticeView(message: hostNotice)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: hostNotice)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showingLeaveConfirmation = true
                } label: {
                    Image(systemName: "xmark")
                        .font(Design.Typography.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(Design.Colors.brandGold)
                }
                .accessibilityLabel("Leave game")
                .automationID("multiplayer.lobby.close")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if let code = inGameRoomCode {
                    RoomCodeMenu(code: code)
                }
            }
        }
        .alert(multiplayerStore.isHost ? "End this game for everyone?" : "Leave this game?", isPresented: $showingLeaveConfirmation) {
            Button(multiplayerStore.isHost ? "End Game" : "Leave Game", role: .destructive) {
                leaveGame()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(multiplayerStore.isHost
                 ? "This will end the current game for everyone without determining a winner."
                 : "You will leave the room. The other players can continue.")
        }
        .alert("Could Not Leave Game", isPresented: $showingLeaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(leaveGameError ?? "Please try again.")
        }
        .onChange(of: multiplayerStore.wasKicked) { _, wasKicked in
            if wasKicked {
                // Auto-dismiss when kicked from session
                dismiss()
            }
        }
        .onChange(of: multiplayerStore.currentSession?.hostUserId) { oldHost, newHost in
            showHostNoticeIfReclaimed(from: oldHost, to: newHost)
        }
        .task(id: hostNotice) {
            guard hostNotice != nil, (try? await Task.sleep(for: .seconds(4))) != nil else { return }
            hostNotice = nil
        }
    }

    /// Phase-based routing. Each phase view gets its payload as `let` values, so an outgoing view
    /// never re-renders against the next phase; `.id` gives each night or day a fresh view.
    @ViewBuilder
    private func phaseView(for session: GameSession) -> some View {
        switch session.currentPhaseData {
        case .lobby, .none:
            lobbyContent(session: session)

        case .roleReveal(let index):
            MultiplayerRoleRevealView(currentPlayerIndex: index)
                .transition(Self.slide)

        case .night(let nightIndex, _):
            MultiplayerNightView(nightIndex: nightIndex)
                .id(nightIndex)
                .transition(Self.slide)

        case .morning(let nightIndex):
            MultiplayerMorningView(nightIndex: nightIndex)
                .id(nightIndex)
                .transition(Self.slide)

        case .deathReveal(let nightIndex):
            MultiplayerDeathRevealView(nightIndex: nightIndex)
                .id(nightIndex)
                .transition(Self.slide)

        case .voting(let dayIndex):
            MultiplayerVotingView(dayIndex: dayIndex)
                .id(dayIndex)
                .transition(Self.slide)

        case .votingResults(let dayIndex, let voteCounts, let eliminatedPlayerId):
            MultiplayerVotingResultsView(voteCounts: voteCounts, eliminatedPlayerId: eliminatedPlayerId)
                .id(dayIndex)
                .transition(Self.slide)

        case .voteDeathReveal(let dayIndex, let playerId, let name, let number, let role, let votes):
            MultiplayerVoteDeathRevealView(
                reveal: VoteRevealData(
                    eliminatedPlayerId: playerId,
                    playerName: name,
                    playerNumber: number,
                    role: role.flatMap { Role(rawValue: $0) },
                    voteCount: votes
                )
            )
            .id(dayIndex)
            .transition(Self.slide)

        case .gameOver:
            MultiplayerGameOverView()
                .transition(Self.slide)
        }
    }

    private func lobbyContent(session: GameSession) -> some View {
        let players = multiplayerStore.visiblePlayers
        let isHost = multiplayerStore.isHost
        let myId = multiplayerStore.myPlayer?.id
        let hostId = multiplayerStore.players.first { $0.userId == session.hostUserId }?.id

        return ScrollView {
            VStack(spacing: 24) {
                RoomCodeCard(code: session.roomCode, showsShareHint: true)
                    .padding(.top, 20)
                    .padding(.horizontal, 20)

                LobbyStatusRow(players: players, isHost: isHost)
                    .padding(.horizontal, 20)

                LobbyPlayerList(
                    players: players.sortedForLobby(hostId: hostId),
                    maxPlayers: session.maxPlayers,
                    myId: myId,
                    hostId: hostId,
                    isHostOffline: multiplayerStore.isHostOffline,
                    // A closure, not `removePlayer`: complete concurrency checking can't type-check
                    // a main-actor method reference inside the ternary ("ambiguous use of 'init'").
                    onRemove: isHost ? { removePlayer($0) } : nil
                )
            }
            .padding(.bottom, 20)
            .readableContentWidth()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            LobbyFooter(
                isHost: isHost,
                playerCount: players.count,
                isStarting: isStarting,
                startGameError: startGameError,
                onStart: startGame,
                onLeave: { showingLeaveConfirmation = true }
            )
        }
    }

    /// During the game the room code moves to the toolbar, so a player whose app closed can rejoin.
    private var inGameRoomCode: String? {
        guard let session = multiplayerStore.currentSession else { return nil }
        switch session.currentPhaseData {
        case .lobby, .none: return nil
        default: return session.roomCode
        }
    }

    /// The original host took the lobby back from an interim host.
    private func showHostNoticeIfReclaimed(from oldHost: UUID?, to newHost: UUID?) {
        guard let oldHost, let newHost, oldHost != newHost,
              let session = multiplayerStore.currentSession,
              session.status == .waiting, newHost == session.originalHostUserId else { return }
        if newHost == multiplayerStore.sessionView?.viewer.userId {
            hostNotice = "You're the host again."
        } else {
            let name = multiplayerStore.players.first { $0.userId == newHost }?.playerName ?? "The original host"
            hostNotice = "\(name) is the host again."
        }
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
                print("❌ [MultiplayerLobbyView] Failed to start game: Invalid player count")
                await MainActor.run {
                    isStarting = false
                    startGameError = "Need 4-19 players to start"
                }
            } catch {
                print("❌ [MultiplayerLobbyView] Failed to start game: \(error)")
                print("❌ [MultiplayerLobbyView] Error description: \(error.localizedDescription)")
                await MainActor.run {
                    isStarting = false
                    // A timed-out request may still start the game, so it is not called a failure.
                    if let error = error as? BackendError, error.isTimeout {
                        startGameError = error.message
                    } else {
                        startGameError = "Failed to start game: \(error.localizedDescription)"
                    }
                    print("❌ [MultiplayerLobbyView] isStarting = false (error path)")
                }
            }
        }
    }

    private func leaveGame() {
        guard !hasLeftSession else { return }
        hasLeftSession = true
        Task {
            do {
                if multiplayerStore.isHost {
                    try await multiplayerStore.endSession()
                } else {
                    try await multiplayerStore.leaveSession()
                }
                dismiss()
            } catch {
                hasLeftSession = false
                leaveGameError = error.localizedDescription
                showingLeaveError = true
            }
        }
    }

    private func removePlayer(_ playerInfo: PublicPlayerInfo) {
        Task {
            try? await multiplayerStore.removePlayer(withId: playerInfo.id)
        }
    }
}

// MARK: - Lobby Pieces

/// The big room code shown in the lobby and while the room connects.
private struct RoomCodeCard: View {
    let code: String
    var showsShareHint = false

    var body: some View {
        VStack(spacing: 12) {
            Text("Room Code")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.textSecondary)

            Text(code)
                .font(Design.Typography.roomCode)
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
                .accessibilityLabel("Room code: \(code.map { String($0) }.joined(separator: " "))")

            if showsShareHint {
                Text("Share this code with friends to join")
                    .font(Design.Typography.footnote)
                    .foregroundStyle(Design.Colors.textSecondary)
            }
        }
    }
}

/// Until the first session and roster snapshots arrive: the room code (known from create/join)
/// and a connecting indicator instead of a bare spinner.
private struct LobbyConnectingView: View {
    let roomCode: String?

    var body: some View {
        VStack(spacing: 24) {
            if let roomCode {
                RoomCodeCard(code: roomCode)
            }

            HStack(spacing: 10) {
                ProgressView()
                    .tint(Design.Colors.brandGold)
                Text("Connecting…")
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Colors.textSecondary)
            }
        }
        .padding(20)
        .readableContentWidth()
    }
}

private struct LobbyStatusRow: View {
    let players: [PublicPlayerInfo]
    let isHost: Bool

    var body: some View {
        let botCount = players.filter(\.isBot).count
        HStack(spacing: 16) {
            StatusBadge(
                icon: "person.3.fill",
                label: "\(players.count - botCount)",
                color: Design.Colors.brandGold
            )

            StatusBadge(
                icon: "cpu",
                label: "\(botCount)",
                color: Design.Colors.textSecondary
            )

            if isHost {
                StatusBadge(
                    icon: "crown.fill",
                    label: "Host",
                    color: Design.Colors.brandGold
                )
            }
        }
    }
}

private struct LobbyPlayerList: View {
    /// Already sorted: host first, then humans, then bots (HAMZA-94).
    let players: [PublicPlayerInfo]
    let maxPlayers: Int
    let myId: UUID?
    let hostId: UUID?
    let isHostOffline: Bool
    /// Host only.
    let onRemove: ((PublicPlayerInfo) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Players (\(players.count)/\(maxPlayers))")
                .font(Design.Typography.body)
                .foregroundStyle(Design.Colors.textPrimary)
                .padding(.horizontal, 20)

            VStack(spacing: 12) {
                ForEach(players, id: \.id) { playerInfo in
                    PlayerRow(
                        playerInfo: playerInfo,
                        isMe: playerInfo.id == myId,
                        isHost: playerInfo.id == hostId,
                        isHostOffline: isHostOffline, // HAMZA-165
                        onRemove: removeAction(for: playerInfo)
                    )
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func removeAction(for playerInfo: PublicPlayerInfo) -> (() -> Void)? {
        guard let onRemove, playerInfo.id != myId else { return nil }
        return { onRemove(playerInfo) }
    }
}

/// Start Game (host), validation, Leave. Sits in the bottom safe-area inset, so the player
/// list always scrolls clear of it at any text size.
private struct LobbyFooter: View {
    let isHost: Bool
    let playerCount: Int
    let isStarting: Bool
    let startGameError: String?
    let onStart: () -> Void
    let onLeave: () -> Void

    private var canStart: Bool { (4...19).contains(playerCount) }

    var body: some View {
        VStack(spacing: 12) {
            // Start Game Button (host only)
            if isHost {
                VStack(spacing: 8) {
                    Button(action: onStart) {
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
                    .automationID("multiplayer.lobby.startGame")

                    // Validation messages
                    if !canStart {
                        Text("Need 4-19 total players to start")
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

            // Leave Button
            Button(action: onLeave) {
                Text("Leave")
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Colors.dangerRed)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .automationID("multiplayer.lobby.leave")
        }
        .padding(.horizontal, 20)
        .readableContentWidth()
        .padding(.vertical, 20)
        .background(Design.Colors.surface0)
    }
}

/// The in-game room code: shown in the toolbar, with a Copy action.
private struct RoomCodeMenu: View {
    let code: String

    var body: some View {
        Menu {
            Section("Room code \(code)") {
                Button {
                    UIPasteboard.general.string = code
                } label: {
                    Label("Copy Room Code", systemImage: "doc.on.doc")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "number")
                    .accessibilityHidden(true)
                Text(code)
                    .monospacedDigit()
            }
            .font(Design.Typography.subheadline)
            .foregroundStyle(Design.Colors.brandGold)
        }
        .accessibilityLabel("Room code \(code.map { String($0) }.joined(separator: " "))")
        .accessibilityHint("Shows a copy option")
        .automationID("multiplayer.game.roomCode")
    }
}

private struct HostNoticeView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "crown.fill")
            .font(Design.Typography.footnote)
            .foregroundStyle(Design.Colors.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Design.Colors.surface1, in: Capsule())
            .overlay(Capsule().stroke(Design.Colors.brandGold.opacity(0.4), lineWidth: 1))
            .padding(.horizontal, 16)
    }
}


// MARK: - Player Row

struct PlayerRow: View {
    let playerInfo: PublicPlayerInfo
    let isMe: Bool
    let isHost: Bool
    var isHostOffline: Bool = false // HAMZA-165: Whether the host is offline
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
                    .font(Design.Typography.callout)
                    .foregroundStyle(
                        playerInfo.isBot
                            ? Design.Colors.textSecondary
                            : Design.Colors.brandGold
                    )
            }
            .accessibilityHidden(true)

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

                    // HAMZA-165: Host crown with offline indicator
                    if isHost {
                        if isHostOffline {
                            // Offline host: dimmed crown + wifi.slash
                            HStack(spacing: 4) {
                                Image(systemName: "crown.fill")
                                    .font(Design.Typography.caption2)
                                    .foregroundStyle(Design.Colors.textSecondary.opacity(0.5))
                                Image(systemName: "wifi.slash")
                                    .font(Design.Typography.caption2)
                                    .foregroundStyle(Design.Colors.dangerRed)
                            }
                            .accessibilityLabel("Host, offline")
                        } else {
                            // Online host: normal gold crown
                            Image(systemName: "crown.fill")
                                .font(Design.Typography.caption2)
                                .foregroundStyle(Design.Colors.brandGold)
                                .accessibilityLabel("Host")
                        }
                    }
                }
            }

            Spacer()

            // Remove Button (Host only)
            if let onRemove = onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(Design.Typography.title3)
                        .foregroundStyle(Design.Colors.dangerRed)
                }
                .padding(.leading, 8)
                .accessibilityLabel("Remove player")
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
                .font(Design.Typography.body)
                .accessibilityHidden(true)
            Text(label)
                .font(Design.Typography.caption)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .cornerRadius(Design.Radii.small)
        .accessibilityElement(children: .combine)
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
        Dictionary(multiplayerStore.visiblePlayers.map { ($0.playerId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var eliminatedPlayers: [PublicPlayerInfo] {
        guard let record = nightRecord else { return [] }
        return record.resultingDeaths.compactMap { playerLookup[$0] }
    }

    private func playerName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return playerLookup[id]?.playerName
    }

    private func playerNumber(for id: UUID?, in lookup: [UUID: PublicPlayerInfo]) -> Int? {
        guard let id else { return nil }
        return lookup[id]?.playerNumber
    }

    private func summaryVisiblePlayerNumbers(in record: NightActionRecord, lookup: [UUID: PublicPlayerInfo]) -> Set<Int> {
        let recentlyEliminatedIDs = Set(record.resultingDeaths)
        return Set(
            lookup.values
                .filter { $0.isAlive || recentlyEliminatedIDs.contains($0.playerId) }
                .compactMap(\.playerNumber)
        )
    }

    private func summaryRoleNumbers(_ recordedNumbers: [Int], visibleNumbers: Set<Int>) -> [Int] {
        recordedNumbers
            .filter { visibleNumbers.contains($0) }
            .sorted()
    }

    // Helper functions matching local game format
    private func mafiaSummary(for record: NightActionRecord, lookup: [UUID: PublicPlayerInfo], visibleNumbers: Set<Int>) -> String {
        let numbers = summaryRoleNumbers(record.mafiaPlayerNumbers, visibleNumbers: visibleNumbers)
        let mafiaLabel = numbers.isEmpty ? "—" : numbers.map { "#\($0)" }.joined(separator: ", ")

        // Only show target if there are actual mafia actors
        if !numbers.isEmpty, let targetNumber = playerNumber(for: record.mafiaTargetId, in: lookup) {
            return "\(mafiaLabel) → #\(targetNumber)"
        }
        return mafiaLabel
    }

    private func policeSummary(for record: NightActionRecord, lookup: [UUID: PublicPlayerInfo], visibleNumbers: Set<Int>) -> String {
        let numbers = summaryRoleNumbers(record.inspectorPlayerNumbers, visibleNumbers: visibleNumbers)
        let policeLabel = numbers.isEmpty ? "—" : numbers.map { "#\($0)" }.joined(separator: ", ")

        // Only show target if there are actual police actors
        if !numbers.isEmpty, let inspectedNumber = playerNumber(for: record.inspectorCheckedId, in: lookup) {
            return "\(policeLabel) → #\(inspectedNumber)"
        }
        return policeLabel
    }

    private func doctorSummary(for record: NightActionRecord, lookup: [UUID: PublicPlayerInfo], visibleNumbers: Set<Int>) -> String {
        let numbers = summaryRoleNumbers(record.doctorPlayerNumbers, visibleNumbers: visibleNumbers)
        let doctorLabel = numbers.isEmpty ? "—" : numbers.map { "#\($0)" }.joined(separator: ", ")

        // Only show target if there are actual doctor actors
        if !numbers.isEmpty, let protectedNumber = playerNumber(for: record.doctorProtectedId, in: lookup) {
            return "\(doctorLabel) → #\(protectedNumber)"
        }
        return doctorLabel
    }

    private func killedSummary(for record: NightActionRecord, lookup: [UUID: PublicPlayerInfo], visibleNumbers: Set<Int>) -> String {
        let deathNumbers = record.resultingDeaths.compactMap { playerNumber(for: $0, in: lookup) }.sorted()

        if !deathNumbers.isEmpty {
            return deathNumbers.map { "#\($0)" }.joined(separator: ", ")
        }

        let targetWasSaved = record.targetWasSaved ?? (record.doctorProtectedId == record.mafiaTargetId)

        // No deaths - check if doctor saved someone (only if doctor actually exists!)
        if let targetNumber = playerNumber(for: record.mafiaTargetId, in: lookup),
           targetWasSaved,
           !summaryRoleNumbers(record.doctorPlayerNumbers, visibleNumbers: visibleNumbers).isEmpty {
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
                    HostTransitionButton(title: "Reveal Deaths") {
                        try await multiplayerStore.revealDeaths()
                    }
                    .padding(.bottom, 40)
                }
            }
            .padding(24)
            .readableContentWidth()
        }
        .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    private func summaryView(for record: NightActionRecord) -> some View {
        let lookup = playerLookup
        let visibleNumbers = summaryVisiblePlayerNumbers(in: record, lookup: lookup)
        VStack(alignment: .leading, spacing: 16) {
            // Night summary with role actions and full player numbers
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "moon.stars.fill")
                        .foregroundStyle(Design.Colors.brandGold)
                    Text("Night \(nightIndex + 1) Summary")
                        .font(Design.Typography.headline)
                        .foregroundStyle(Design.Colors.textPrimary)
                }

                summaryRow(title: "Mafia", value: mafiaSummary(for: record, lookup: lookup, visibleNumbers: visibleNumbers))
                summaryRow(title: "Killed", value: killedSummary(for: record, lookup: lookup, visibleNumbers: visibleNumbers))
                summaryRow(title: "Police", value: policeSummary(for: record, lookup: lookup, visibleNumbers: visibleNumbers))
                summaryRow(title: "Doctor", value: doctorSummary(for: record, lookup: lookup, visibleNumbers: visibleNumbers))
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
        Dictionary(multiplayerStore.visiblePlayers.map { ($0.playerId, $0) }, uniquingKeysWith: { first, _ in first })
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

        // Try to get role from session player first when the backend returned it
        if let sessionPlayer = multiplayerStore.players.first(where: { $0.playerId == player.playerId }),
           let role = sessionPlayer.role {
            return role
        }

        if let rawRole = record.revealedDeathRoles[player.playerId.uuidString.lowercased()],
           let role = Role(rawValue: rawRole) {
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
        let eliminatedPlayers = self.eliminatedPlayers
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
                                            .font(Design.Typography.caption)
                                            .accessibilityHidden(true)
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
                    HostTransitionButton(title: "Start Voting") {
                        try await multiplayerStore.startVoting()
                    }
                    .padding(.bottom, 40)
                }
            }
            .padding(24)
            .readableContentWidth()
        }
        .navigationBarBackButtonHidden(true)
    }
}
