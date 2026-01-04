import Foundation
import SwiftUI
import Combine

@MainActor
final class MultiplayerGameStore: ObservableObject {
    // Services
    private let sessionService = SessionService()
    private let realtimeService = RealtimeService()
    private let botService = BotDecisionService()

    // Published state
    @Published var currentSession: GameSession?
    @Published var myPlayer: SessionPlayer?
    @Published var allPlayers: [SessionPlayer] = []
    @Published var isHost: Bool = false
    @Published var isInSession: Bool = false

    // Connection state
    @Published var isConnecting: Bool = false
    @Published var connectionError: String?

    // Game state (filtered for privacy)
    @Published var visiblePlayers: [PublicPlayerInfo] = []
    @Published var myRole: Role?
    @Published var myNumber: Int?
    @Published var mafiaTeammates: [PublicPlayerInfo] = [] // Only populated if I'm mafia

    // Phase progression state
    @Published var isPhaseReadyToAdvance: Bool = false

    // Kick detection
    @Published var wasKicked: Bool = false

    // Rematch state
    @Published var rematchDeadline: Date?
    @Published var isInRematchPhase: Bool = false
    private var rematchTimer: Timer?

    // Heartbeat timer
    private var heartbeatTimer: Timer?
    private var playerRefreshTimer: Timer?
    private var pendingAutoAdvanceTask: Task<Void, Never>?
    private var processedBotNightIndices: Set<Int> = []
    private var processedBotVotingDays: Set<Int> = []
    private var isResolvingPhase = false
    private var isProcessingBotVotes = false // HAMZA-FIX: Recursion guard for bot voting
    private var eliminatedPlayerIds: Set<UUID> = [] // Keep dead players dead across refreshes

    // HAMZA-FIX: Bot reactive voting - track which bots have submitted night actions
    private var botNightActionsSubmitted: Set<UUID> = []  // Track bot playerIds that already voted this night
    private var previousNightVotes: [UUID: UUID] = [:]  // [actorId: previousTargetId] for vote change tracking

    // Vote counts for real-time UI updates
    @Published var nightVoteCounts: [ActionType: [UUID: Int]] = [:]  // [actionType: [targetId: count]]

    // Tentative selection counts (before submission) for real-time vote preview
    @Published var tentativeVoteCounts: [ActionType: [UUID: Int]] = [:]  // [actionType: [targetId: count]]
    private var tentativeSelections: [UUID: UUID] = [:]  // [actorId: currentTargetId] for change tracking

    // Combine subscription storage (prevents immediate deallocation)
    private var reconnectingSubscription: AnyCancellable?

    // App lifecycle observers (background/foreground transitions)
    private var appLifecycleObservers: [NSObjectProtocol] = []

    // Host health monitoring (HAMZA-165: Host disconnect detection)
    private var hostMonitorTimer: Timer?
    private let hostOfflineThreshold: TimeInterval = 15.0 // 3 missed heartbeats (5s each)
    @Published var isHostOffline: Bool = false

    // Reconnect state (for pure Realtime recovery)
    private var currentSessionId: UUID?
    @Published var isRealtimeConnected: Bool = false
    @Published var isRealtimeReconnecting: Bool = false

    // Auth store reference
    private weak var authStore: AuthStore?

    func setAuthStore(_ authStore: AuthStore) {
        self.authStore = authStore
    }

    /// Clear per-game caches so bots/actions get re-processed for a brand new game
    private func resetPhaseProcessingState() {
        processedBotNightIndices.removeAll()
        processedBotVotingDays.removeAll()
        isPhaseReadyToAdvance = false
        isResolvingPhase = false
        botNightActionsSubmitted.removeAll()
        previousNightVotes.removeAll()
        nightVoteCounts.removeAll()
        tentativeVoteCounts.removeAll()
        tentativeSelections.removeAll()
    }

    // MARK: - PERF: Single-Pass Player Categorization

    /// Categories of alive players computed in a single pass
    /// PERF: Reduces O(n*k) filtering passes to O(n) where k is number of categories
    private struct AlivePlayerCategories {
        var mafia: [SessionPlayer] = []
        var doctors: [SessionPlayer] = []
        var inspectors: [SessionPlayer] = []
        var citizens: [SessionPlayer] = []
        var humans: [SessionPlayer] = []
        var bots: [SessionPlayer] = []
        var nonHostHumans: [SessionPlayer] = []
        var all: [SessionPlayer] = []
    }

    /// Categorize all alive players in a single pass
    /// - Parameter hostUserId: The host's user ID (to identify non-host players)
    /// - Returns: Categorized alive players
    private func categorizeAlivePlayers(hostUserId: UUID?) -> AlivePlayerCategories {
        var categories = AlivePlayerCategories()

        for player in allPlayers where player.isAlive {
            categories.all.append(player)

            // Categorize by role
            switch player.role {
            case .mafia:
                categories.mafia.append(player)
            case .doctor:
                categories.doctors.append(player)
            case .inspector:
                categories.inspectors.append(player)
            case .citizen:
                categories.citizens.append(player)
            case .none:
                break
            }

            // Categorize by player type
            if player.isBot {
                categories.bots.append(player)
            } else {
                categories.humans.append(player)
                if player.userId != hostUserId {
                    categories.nonHostHumans.append(player)
                }
            }
        }

        return categories
    }

    /// Detects when a session has been fully reset to lobby (e.g., after rematch)
    private func isFreshLobbyState(_ session: GameSession) -> Bool {
        session.currentPhase == "lobby"
            && session.dayIndex == 0
            && session.nightHistory.isEmpty
            && session.dayHistory.isEmpty
    }

    // MARK: - Bot Reactive Voting Helpers

    /// Check if there are alive human players with a specific role
    /// Used to determine if bots should wait for human votes or vote independently
    private func hasHumanWithRole(_ role: Role) -> Bool {
        allPlayers.contains { !$0.isBot && $0.isAlive && $0.role == role }
    }

    /// Get bots with a specific role that are alive
    private func getAliveBotsWithRole(_ role: Role) -> [SessionPlayer] {
        allPlayers.filter { $0.isBot && $0.isAlive && $0.role == role }
    }

    /// Convert ActionType to Role for matching
    private func roleFromActionType(_ actionType: ActionType) -> Role? {
        switch actionType {
        case .mafiaTarget: return .mafia
        case .doctorProtect: return .doctor
        case .inspectorCheck: return .inspector
        case .vote: return nil  // Day voting, not role-specific
        }
    }

    init() {
        // Observe RealtimeService connection state changes
        // CRITICAL: Store subscription to prevent immediate deallocation
        reconnectingSubscription = realtimeService.$isReconnecting
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isReconnecting in
                self?.isRealtimeReconnecting = isReconnecting
            }

        // Wire up disconnect recovery - this is called when channel status becomes unsubscribed
        realtimeService.onDisconnect = { [weak self] sessionId in
            Task { @MainActor in
                await self?.handleRealtimeDisconnect(sessionId: sessionId)
            }
        }

        // Setup app lifecycle observers for background/foreground transitions
        setupAppLifecycleObservers()
    }

    /// Setup NotificationCenter observers for app lifecycle events
    private func setupAppLifecycleObservers() {
        // Observer for app becoming active (returning from background)
        let activeObserver = NotificationCenter.default.addObserver(
            forName: .appDidBecomeActive,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleAppResume()
            }
        }
        appLifecycleObservers.append(activeObserver)

        // Observer for app entering background
        let backgroundObserver = NotificationCenter.default.addObserver(
            forName: .appWillEnterBackground,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.prepareForBackground()
            }
        }
        appLifecycleObservers.append(backgroundObserver)
    }

    // MARK: - Session Lifecycle

    /// Create a new multiplayer session
    func createSession(
        playerName: String,
        botCount: Int = 0
    ) async throws {
        guard let userId = authStore?.currentUserId else {
            throw SessionError.notHost
        }

        resetPhaseProcessingState()
        eliminatedPlayerIds.removeAll()

        // Reset connection state from any previous session
        isRealtimeConnected = false
        isRealtimeReconnecting = false
        isHostOffline = false
        currentSessionId = nil
        wasKicked = false

        isConnecting = true
        connectionError = nil

        do {
            // Create session
            let session = try await sessionService.createSession(
                hostUserId: userId,
                maxPlayers: 19,
                botCount: botCount
            )

            // Add host as first player
            let player = try await sessionService.addPlayer(
                sessionId: session.id,
                userId: userId,
                playerName: playerName,
                isBot: false
            )

            // Add bots
            if botCount > 0 {
                for i in 1...botCount {
                    _ = try await sessionService.addPlayer(
                        sessionId: session.id,
                        userId: nil,
                        playerName: "Bot \(i)",
                        isBot: true
                    )
                }
            }

            // Update local state
            currentSession = session
            myPlayer = player
            isHost = true
            isInSession = true
            wasKicked = false // Reset kick status when creating new session

            // Subscribe to real-time updates
            try await subscribeToSession(sessionId: session.id)

            // Start heartbeat
            startHeartbeat()
            startHostMonitorTimer() // HAMZA-165: Monitor host's heartbeat (no-op for host)

            // Refresh players
            try await refreshPlayers()

            // Start periodic player refresh (fallback for missed real-time events)
            startPlayerRefreshTimer()

            isConnecting = false
        } catch {
            isConnecting = false
            connectionError = mapSessionError(error)
            throw error
        }
    }

    /// Join an existing session
    func joinSession(roomCode: String, playerName: String) async throws {
        guard let userId = authStore?.currentUserId else {
            throw SessionError.notHost
        }

        resetPhaseProcessingState()
        eliminatedPlayerIds.removeAll()

        // Reset connection state from any previous session
        isRealtimeConnected = false
        isRealtimeReconnecting = false
        isHostOffline = false
        currentSessionId = nil
        wasKicked = false

        isConnecting = true
        connectionError = nil

        do {
            let (session, player) = try await sessionService.joinSession(
                roomCode: roomCode,
                userId: userId,
                playerName: playerName
            )

            // Update local state
            currentSession = session
            myPlayer = player
            isHost = (session.hostUserId == userId)
            isInSession = true
            wasKicked = false // Reset kick status when joining session

            // Subscribe to real-time updates
            try await subscribeToSession(sessionId: session.id)

            // Start heartbeat
            startHeartbeat()
            startHostMonitorTimer() // HAMZA-165: Monitor host's heartbeat

            // Refresh players
            try await refreshPlayers()

            // Start periodic player refresh (fallback for missed real-time events)
            startPlayerRefreshTimer()

            isConnecting = false
        } catch {
            isConnecting = false
            connectionError = mapSessionError(error)
            throw error
        }
    }

    /// Leave the current session
    func leaveSession() async throws {
        guard let playerId = myPlayer?.id else {
            throw SessionError.playerNotFound
        }

        resetPhaseProcessingState()
        eliminatedPlayerIds.removeAll()

        stopHeartbeat()
        stopHostMonitorTimer() // HAMZA-165: Stop monitoring host
        stopPlayerRefreshTimer()
        await realtimeService.unsubscribeAll()

        // Remove player directly by their session player ID (works for both authenticated and unauthenticated users)
        try await sessionService.removePlayer(playerId: playerId)

        // Clear local state
        currentSession = nil
        myPlayer = nil
        allPlayers = []
        isHost = false
        isInSession = false
        visiblePlayers = []
        myRole = nil
        myNumber = nil
        mafiaTeammates = []
    }

    // MARK: - Rematch / Play Again

    /// Confirmed players count (ready during game_over with deadline)
    var rematchConfirmedCount: Int {
        guard isInRematchPhase else { return 0 }
        return allPlayers.filter { !$0.isBot && $0.isReady }.count
    }

    /// Total human players
    var totalHumanPlayers: Int {
        allPlayers.filter { !$0.isBot }.count
    }

    /// Whether current player has confirmed rematch (only true if rematch phase is active)
    var hasConfirmedRematch: Bool {
        guard isInRematchPhase else { return false }
        return myPlayer?.isReady ?? false
    }

    /// Any player initiates rematch confirmation
    func initiateRematch() async throws {
        guard let sessionId = currentSession?.id else {
            throw SessionError.noActiveSession
        }
        guard let playerId = myPlayer?.id else {
            throw SessionError.playerNotFound
        }

        try await sessionService.startRematchConfirmation(
            sessionId: sessionId,
            initiatorPlayerId: playerId
        )

        // Optimistic update
        isInRematchPhase = true
        myPlayer?.isReady = true
    }

    /// Confirm wanting to rematch (mark ready)
    func confirmRematch() async throws {
        guard let playerId = myPlayer?.id else {
            throw SessionError.playerNotFound
        }
        try await sessionService.updatePlayerReady(playerId: playerId, isReady: true)
    }

    /// Decline rematch (leave session)
    func declineRematch() async throws {
        try await leaveSession()
    }

    /// Timer expired - execute rematch
    func executeRematch() async throws {
        guard let sessionId = currentSession?.id else { return }

        let (success, error) = try await sessionService.executeRematch(sessionId: sessionId)

        if success {
            resetRematchState()
            try await refreshSession()
            try await refreshPlayers()
            updateVisiblePlayers()
        } else if error != nil {
            // Handle "Not enough players" - cancel rematch
            try await sessionService.cancelRematch(sessionId: sessionId)
            resetRematchState()
        }
    }

    private func resetRematchState() {
        rematchDeadline = nil
        isInRematchPhase = false
        stopRematchTimer()
        myRole = nil
        myNumber = nil
        mafiaTeammates = []
        resetPhaseProcessingState()
        eliminatedPlayerIds.removeAll()
    }

    /// Check if all human players confirmed rematch and execute immediately
    private func checkAndExecuteRematchIfAllReady() {
        guard isInRematchPhase else { return }

        // Need minimum 4 total players (humans + bots)
        guard allPlayers.count >= 4 else { return }

        // All human players must confirm (bots are auto-ready)
        let humanPlayers = allPlayers.filter { !$0.isBot }
        let allConfirmed = humanPlayers.allSatisfy { $0.isReady }
        guard allConfirmed else { return }

        // All players confirmed - execute rematch immediately
        // Stop the timer first to prevent duplicate execution
        stopRematchTimer()

        Task {
            try? await executeRematch()
        }
    }

    private func startRematchTimer() {
        stopRematchTimer()
        guard let deadline = rematchDeadline, deadline > Date() else {
            handleRematchTimeout()
            return
        }

        rematchTimer = Timer.scheduledTimer(
            withTimeInterval: deadline.timeIntervalSinceNow,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in self?.handleRematchTimeout() }
        }
    }

    private func stopRematchTimer() {
        rematchTimer?.invalidate()
        rematchTimer = nil
    }

    private func handleRematchTimeout() {
        // Anyone can trigger execution when timer expires
        Task {
            try? await executeRematch()
        }
    }

    /// Legacy playAgain for host-only reset (not used in rematch flow)
    func playAgain() async throws {
        guard isHost, let sessionId = currentSession?.id else {
            throw SessionError.notHost
        }

        resetPhaseProcessingState()
        eliminatedPlayerIds.removeAll()

        // Reset session via service
        try await sessionService.resetSessionForPlayAgain(sessionId: sessionId)

        // Clear local game state (but keep session connection)
        myRole = nil
        myNumber = nil
        mafiaTeammates = []
        isPhaseReadyToAdvance = false

        // Refresh session and players to get updated state
        try await refreshSession()
        try await refreshPlayers()
        updateVisiblePlayers()
    }

    /// Remove a player from the session (Host only)
    func removePlayer(withId playerId: UUID) async throws {
        guard isHost, let sessionId = currentSession?.id else { return }
        guard let player = allPlayers.first(where: { $0.id == playerId }) else { return }
        
        // If removing a bot, we just delete the record
        // If removing a human, same thing, they will get disconnected
        
        // Using sessionService directly to delete the player record
        // Note: We're using the player.id (UUID) which is the primary key of session_players
        // The SessionService.leaveSession uses userId, but we might want to remove by player ID
        
        // We'll assume we can use the same mechanism as leaveSession if we have userId
        if let userId = player.userId {
            try await sessionService.leaveSession(sessionId: sessionId, userId: userId)
        } else {
            // For bots or if we need to remove by player ID directly...
            // Since SessionService.leaveSession takes userId, let's add a specific removePlayer method to SessionService later if needed.
            // For now, I'll check if I can use the existing leaveSession or if I need to extend it.
            // The existing leaveSession selects by userId. Bots don't have userId.
            
            // Workaround: Since I can't easily add to SessionService without editing it (which I should avoid if possible or do in a separate step), 
            // I will rely on the fact that I'm the host and I can probably delete the record.
            // But wait, I can edit SessionService. The plan says "Ensure sessionService has removePlayer".
            
            // Let's skip the implementation details here and assume I'll add `removePlayer(playerId:)` to SessionService.
            // Wait, I previously used try await sessionService.removePlayer(playerId: player.id)
            // But I didn't add it to SessionService yet.
            
            // I will add it to SessionService in the next step.
             try await sessionService.removePlayer(playerId: player.id)
        }
        
        // Local cleanup will happen via real-time update, but we can do it optimistically
        handlePlayerRemoval(playerId: player.id)
    }
    
    /// Force start the night phase (Host only)
    func forceStartNight() async throws {
        guard isHost else { return }
        try await advanceFromRoleRevealIfReady(forceRefresh: true, forceStart: true)
    }
    
    /// Manually complete the night phase (Host only)
    func completeNightPhase() async throws {
        guard isHost, 
              case .night(let nightIndex, _) = currentSession?.currentPhaseData else { return }
        
        try await resolveNightPhase(nightIndex: nightIndex)
    }
    
    // MARK: - Real-time Subscriptions

    private func subscribeToSession(sessionId: UUID) async throws {
        // Store sessionId for reconnects
        currentSessionId = sessionId

        try await realtimeService.subscribeToSession(
            sessionId: sessionId,
            onSessionUpdate: { [weak self] session in
                Task { @MainActor in
                    self?.isRealtimeConnected = true
                    self?.handleSessionUpdate(session)
                }
            },
            onPlayerUpdate: { [weak self] player in
                Task { @MainActor in
                    self?.isRealtimeConnected = true
                    self?.handlePlayerUpdate(player)
                }
            },
            onActionUpdate: { [weak self] action in
                Task { @MainActor in
                    self?.isRealtimeConnected = true
                    self?.handleActionUpdate(action)
                }
            },
            onTentativeSelection: { [weak self] selection in
                Task { @MainActor in
                    self?.handleTentativeSelection(selection)
                }
            }
        )
        isRealtimeConnected = true
    }

    // MARK: - Realtime Disconnect Recovery

    /// Handle Realtime disconnection by triggering auto-recovery
    /// Called when channel status transitions to unsubscribed
    private func handleRealtimeDisconnect(sessionId: UUID) async {
        // Only attempt recovery if we're still in a session and the sessionId matches
        guard isInSession, currentSessionId == sessionId else {
            print("⚠️ [MultiplayerGameStore] Ignoring disconnect - not in session or sessionId mismatch")
            return
        }

        print("🔴 [MultiplayerGameStore] Realtime disconnected - triggering auto-recovery for session: \(sessionId)")
        isRealtimeConnected = false

        // Use RealtimeService's exponential backoff recovery
        realtimeService.attemptResubscribe(
            sessionId: sessionId,
            onSessionUpdate: { [weak self] session in
                Task { @MainActor in
                    self?.isRealtimeConnected = true
                    self?.handleSessionUpdate(session)
                }
            },
            onPlayerUpdate: { [weak self] player in
                Task { @MainActor in
                    self?.isRealtimeConnected = true
                    self?.handlePlayerUpdate(player)
                }
            },
            onActionUpdate: { [weak self] action in
                Task { @MainActor in
                    self?.isRealtimeConnected = true
                    self?.handleActionUpdate(action)
                }
            },
            onReconnected: { [weak self] in
                // Perform snapshot resync to heal any missed events during disconnection
                await self?.performSnapshotResync()
            }
        )
    }

    private func handleSessionUpdate(_ session: GameSession) {
        let previousSessionId = currentSession?.id
        let previousPhaseData = currentSession?.currentPhaseData
        let previousRematchDeadline = currentSession?.rematchDeadline

        // New session or a full lobby reset (e.g., rematch) -> clear bot/night caches
        if session.id != previousSessionId || isFreshLobbyState(session) {
            resetPhaseProcessingState()
        }

        currentSession = session

        updateHostStatus(using: session)

        // Handle rematch deadline changes
        if let deadline = session.rematchDeadline {
            // Rematch phase active
            if previousRematchDeadline == nil || previousRematchDeadline != deadline {
                rematchDeadline = deadline
                isInRematchPhase = true
                startRematchTimer()
            }
        } else if isInRematchPhase && session.rematchDeadline == nil {
            // Rematch was cancelled or executed (session reset to lobby)
            resetRematchState()
        }

        if session.currentPhaseData != previousPhaseData {
            scheduleAutoAdvance(for: session.currentPhaseData)

            // Reset isReady for all players when entering game_over (so rematch starts fresh)
            if case .gameOver = session.currentPhaseData {
                if isHost {
                    Task {
                        await self.resetAllPlayersReadyForGameOver()
                    }
                }
            }

            if isHost {
                Task {
                    await self.handlePhaseEntry(for: session.currentPhaseData)
                }
            }
        }
    }

    private func updateHostStatus(using session: GameSession) {
        guard let userId = authStore?.currentUserId else { return }
        let newIsHost = (session.hostUserId == userId)
        if newIsHost != isHost {
            isHost = newIsHost
            // HAMZA-165: Toggle host monitoring based on new host status
            if newIsHost {
                print("👑 [MultiplayerGameStore] I am now the host - stopping host monitor")
                stopHostMonitorTimer()
            } else {
                print("👤 [MultiplayerGameStore] I am no longer host - starting host monitor")
                startHostMonitorTimer()
            }
        }
    }

    private func handlePlayerUpdate(_ player: SessionPlayer) {
        if let index = allPlayers.firstIndex(where: { $0.id == player.id }) {
            var updated = player
            if !updated.isAlive {
                eliminatedPlayerIds.insert(updated.playerId)
            }
            if eliminatedPlayerIds.contains(player.playerId) {
                updated.isAlive = false
            }
            allPlayers[index] = updated
        } else {
            var updated = player
            if !updated.isAlive {
                eliminatedPlayerIds.insert(updated.playerId)
            }
            if eliminatedPlayerIds.contains(player.playerId) {
                updated.isAlive = false
            }
            allPlayers.append(updated)
        }

        // Update my player if it's me
        if player.id == myPlayer?.id {
            myPlayer = player
            myRole = player.role
            myNumber = player.playerNumber
        }

        updateVisiblePlayers()

        // Check if all players confirmed rematch - execute immediately
        if isInRematchPhase {
            checkAndExecuteRematchIfAllReady()
        }

        if isHost {
            Task {
                try? await self.advanceFromRoleRevealIfReady(forceRefresh: false)
                // Also check readiness for night/voting phases
                await self.evaluatePhaseProgression(trigger: "player_update")
            }
        }
    }
    
    /// Handle player removal (called when a player leaves)
    private func handlePlayerRemoval(playerId: UUID) {
        allPlayers.removeAll(where: { $0.id == playerId })

        // If it was me, clear my player state and trigger auto-dismiss
        if playerId == myPlayer?.id {
            myPlayer = nil
            myRole = nil
            myNumber = nil
            wasKicked = true  // Signal to UI that we were removed
        }

        updateVisiblePlayers()

        // Refresh players from server to ensure consistency
        Task {
            try? await refreshPlayers()
        }
    }

    private func handleActionUpdate(_ action: GameAction) {
        // Handle action updates (e.g., voting progress, night actions)
        // This can trigger UI updates for action confirmation

        // ✅ CRITICAL FIX: Only process actions for the CURRENT active phase
        // This prevents stale actions from previous phases (Realtime replays) from triggering duplicate resolution
        guard let session = currentSession else { return }

        var isNightPhase = false
        var activeNightIndex: Int?

        switch session.currentPhaseData {
        case .night(let nightIndex, _):
            // Only process night actions for the current night
            guard action.actionType == .mafiaTarget || action.actionType == .doctorProtect || action.actionType == .inspectorCheck else {
                return
            }
            guard action.phaseIndex == nightIndex else {
                return
            }
            isNightPhase = true
            activeNightIndex = nightIndex

        case .voting(let activeDayIndex):
            // Only process vote actions for the current day
            guard action.actionType == .vote else {
                return
            }
            guard action.phaseIndex == activeDayIndex else {
                return
            }

        default:
            // Ignore actions outside night/voting phases (lobby, role_reveal, morning, etc.)
            return
        }

        // HAMZA-FIX: Update vote counts for real-time UI
        if isNightPhase, let targetId = action.targetPlayerId {
            updateNightVoteCount(action: action)
        }

        // HAMZA-FIX: Bot coordination - if this is a human action, trigger bots to follow
        if isNightPhase, let nightIndex = activeNightIndex {
            handleNightActionForBotCoordination(action: action, nightIndex: nightIndex)
        }

        // If we made it here, the action is for the current active phase
        if isHost {
            Task {
                await self.evaluatePhaseProgression(trigger: "action_update")
            }
        }
    }

    // MARK: - Bot Reactive Voting & Vote Count Tracking

    /// Update vote counts for real-time UI display
    /// Handles vote changes by decrementing old target and incrementing new target
    private func updateNightVoteCount(action: GameAction) {
        guard let targetId = action.targetPlayerId else { return }

        let actorId = action.actorPlayerId
        let actionType = action.actionType

        // Initialize counts for this action type if not exists
        if nightVoteCounts[actionType] == nil {
            nightVoteCounts[actionType] = [:]
        }

        // Check if this actor has a previous vote (vote change)
        if let previousTargetId = previousNightVotes[actorId], previousTargetId != targetId {
            // Decrement old target count
            if let oldCount = nightVoteCounts[actionType]?[previousTargetId], oldCount > 0 {
                nightVoteCounts[actionType]?[previousTargetId] = oldCount - 1
            }
        }

        // Increment new target count
        nightVoteCounts[actionType]?[targetId, default: 0] += 1

        // Track this vote for future change detection
        previousNightVotes[actorId] = targetId

        print("📊 [VoteCount] \(actionType): updated counts = \(nightVoteCounts[actionType] ?? [:])")
    }

    /// Handle bot coordination when a human submits a night action
    /// Bots with the same role will immediately match the human's target
    private func handleNightActionForBotCoordination(action: GameAction, nightIndex: Int) {
        // Only host can submit bot actions
        guard isHost else { return }

        // Get the role for this action type
        guard let role = roleFromActionType(action.actionType) else { return }

        // Check if the action is from a human player
        let isHumanAction = allPlayers.contains { player in
            player.playerId == action.actorPlayerId && !player.isBot
        }

        guard isHumanAction else { return }

        // Get the target from this action
        guard let humanTargetId = action.targetPlayerId else { return }

        // Get bots with the same role that haven't submitted yet
        let botsToSubmit = getAliveBotsWithRole(role).filter { bot in
            !botNightActionsSubmitted.contains(bot.playerId)
        }

        guard !botsToSubmit.isEmpty else { return }

        print("🤖 [BotCoordination] Human \(role) voted for target. Triggering \(botsToSubmit.count) bot(s) to follow.")

        // Submit matching actions for each bot
        Task {
            for bot in botsToSubmit {
                do {
                    try await submitBotAction(
                        botPlayerId: bot.playerId,
                        actionType: action.actionType,
                        nightIndex: nightIndex,
                        targetPlayerId: humanTargetId
                    )
                    botNightActionsSubmitted.insert(bot.playerId)
                    print("🤖 [BotCoordination] Bot \(bot.playerName) submitted \(action.actionType) matching human target")
                } catch {
                    print("❌ [BotCoordination] Failed to submit bot action for \(bot.playerName): \(error)")
                }
            }
        }
    }

    /// Clear bot night action tracking when entering a new night phase
    func clearBotNightActionsForNewNight() {
        botNightActionsSubmitted.removeAll()
        previousNightVotes.removeAll()
        nightVoteCounts.removeAll()
        tentativeVoteCounts.removeAll()
        tentativeSelections.removeAll()
        print("🔄 [BotCoordination] Cleared bot night action tracking for new night")
    }

    // MARK: - Tentative Selection (Real-time Vote Preview)

    /// Handle incoming tentative selection broadcast from another player
    private func handleTentativeSelection(_ selection: TentativeSelection) {
        let actorId = selection.actorPlayerId
        let actionType = selection.actionType

        // Skip if this is my own selection (already handled locally)
        if actorId == myPlayer?.playerId {
            return
        }

        // Initialize counts for this action type if not exists
        if tentativeVoteCounts[actionType] == nil {
            tentativeVoteCounts[actionType] = [:]
        }

        // Check if this actor has a previous tentative selection (selection change)
        if let previousTargetId = tentativeSelections[actorId] {
            // Decrement old target count
            if let oldCount = tentativeVoteCounts[actionType]?[previousTargetId], oldCount > 0 {
                tentativeVoteCounts[actionType]?[previousTargetId] = oldCount - 1
                // Remove entry if count reaches 0
                if tentativeVoteCounts[actionType]?[previousTargetId] == 0 {
                    tentativeVoteCounts[actionType]?.removeValue(forKey: previousTargetId)
                }
            }
        }

        // Handle new selection
        if let targetId = selection.targetPlayerId {
            // Increment new target count
            tentativeVoteCounts[actionType]?[targetId, default: 0] += 1
            tentativeSelections[actorId] = targetId
        } else {
            // Player deselected - remove from tracking
            tentativeSelections.removeValue(forKey: actorId)
        }

        print("📊 [TentativeVote] \(actionType): updated tentative counts = \(tentativeVoteCounts[actionType] ?? [:])")
    }

    /// Broadcast a tentative selection to other players (called when tapping on a target)
    func broadcastTentativeSelection(
        actionType: ActionType,
        targetPlayerId: UUID?,
        phaseIndex: Int
    ) async {
        guard let sessionId = currentSession?.id,
              let myPlayerId = myPlayer?.playerId else {
            print("⚠️ [TentativeVote] Cannot broadcast - not in session")
            return
        }

        let selection = TentativeSelection(
            actorPlayerId: myPlayerId,
            targetPlayerId: targetPlayerId,
            actionType: actionType,
            phaseIndex: phaseIndex
        )

        // Update local counts immediately for instant feedback
        handleTentativeSelectionLocally(selection)

        // Broadcast to other players
        do {
            try await realtimeService.broadcastMessage(
                sessionId: sessionId,
                event: "tentative_selection",
                payload: selection
            )
            print("📡 [TentativeVote] Broadcasted selection: \(actionType) -> \(targetPlayerId?.uuidString.prefix(8) ?? "nil")")
        } catch {
            print("❌ [TentativeVote] Failed to broadcast selection: \(error)")
        }
    }

    /// Handle local tentative selection (for the current player)
    private func handleTentativeSelectionLocally(_ selection: TentativeSelection) {
        let actorId = selection.actorPlayerId
        let actionType = selection.actionType

        // Initialize counts for this action type if not exists
        if tentativeVoteCounts[actionType] == nil {
            tentativeVoteCounts[actionType] = [:]
        }

        // Check if this actor has a previous tentative selection (selection change)
        if let previousTargetId = tentativeSelections[actorId] {
            // Decrement old target count
            if let oldCount = tentativeVoteCounts[actionType]?[previousTargetId], oldCount > 0 {
                tentativeVoteCounts[actionType]?[previousTargetId] = oldCount - 1
                // Remove entry if count reaches 0
                if tentativeVoteCounts[actionType]?[previousTargetId] == 0 {
                    tentativeVoteCounts[actionType]?.removeValue(forKey: previousTargetId)
                }
            }
        }

        // Handle new selection
        if let targetId = selection.targetPlayerId {
            // Increment new target count
            tentativeVoteCounts[actionType]?[targetId, default: 0] += 1
            tentativeSelections[actorId] = targetId
        } else {
            // Player deselected - remove from tracking
            tentativeSelections.removeValue(forKey: actorId)
        }
    }

    // MARK: - Player Management

    func refreshSession() async throws {
        guard let sessionId = currentSession?.id else { return }
        
        if let latestSession = try await sessionService.getSession(sessionId: sessionId) {
            // Use handleSessionUpdate to ensure all side effects (timers, auto-advance) run
            // just as if we received a real-time update
            handleSessionUpdate(latestSession)
        }
    }
    
    private func refreshPlayers() async throws {
        guard let sessionId = currentSession?.id else { return }

        let players = try await sessionService.getSessionPlayers(sessionId: sessionId)
        guard sessionId == currentSession?.id else { return } // Session changed; drop stale data.

        // Check if current player was removed (kicked)
        let wasInSession = myPlayer != nil
        let currentUserId = authStore?.currentUserId

        allPlayers = players

        // Find my player
        if let userId = currentUserId {
            let foundPlayer = allPlayers.first(where: { $0.userId == userId })
            myPlayer = foundPlayer
            myRole = foundPlayer?.role
            myNumber = foundPlayer?.playerNumber

            // If player was in session but is no longer found, they were kicked
            if wasInSession && foundPlayer == nil {
                print("⚠️ [MultiplayerGameStore] Current user not found in refreshed players - was kicked")
                myPlayer = nil
                myRole = nil
                myNumber = nil
                isInSession = false
                wasKicked = true
            }
        }

        // Never resurrect eliminated players even if a stale update arrives
        for index in allPlayers.indices {
            if !allPlayers[index].isAlive {
                eliminatedPlayerIds.insert(allPlayers[index].playerId)
            }

            if eliminatedPlayerIds.contains(allPlayers[index].playerId) {
                allPlayers[index].isAlive = false
            }
        }

        updateVisiblePlayers()
    }

    private func updateVisiblePlayers() {
        // Create public player info list (everyone can see names, numbers, alive status)
        visiblePlayers = allPlayers.map { PublicPlayerInfo(from: $0) }

        // If I'm mafia, populate mafia teammates
        if myRole == .mafia {
            mafiaTeammates = allPlayers
                .filter { $0.role == .mafia && $0.id != myPlayer?.id }
                .map { PublicPlayerInfo(from: $0) }
        } else {
            mafiaTeammates = []
        }
    }

    /// Toggle ready status
    func toggleReady() async throws {
        guard let player = myPlayer else { return }

        let newReadyStatus = !player.isReady
        try await sessionService.updatePlayerReady(playerId: player.id, isReady: newReadyStatus)

        // Update optimistically
        myPlayer?.isReady = newReadyStatus
    }

    /// Explicitly set ready state (used for auto-ready flows like citizens)
    func setReadyStatus(_ isReady: Bool) async throws {
        guard let playerId = myPlayer?.id else { return }
        try await sessionService.updatePlayerReady(playerId: playerId, isReady: isReady)
        myPlayer?.isReady = isReady
    }
    
    /// Mark that player has seen their role
    func markRoleAsSeen() async throws {
        guard let playerId = myPlayer?.id else { return }

        // Mark player as having seen their role by setting ready status
        try await sessionService.updatePlayerReady(playerId: playerId, isReady: true)

        // Update optimistically
        myPlayer?.isReady = true

        // If host and all players have seen their roles, advance to night phase
        if isHost {
            try await advanceFromRoleRevealIfReady(forceRefresh: true)
        } else {
            // Non-host players: refresh session to check if phase changed
            // This ensures they see the phase update when host advances
            try await refreshSession()
        }
    }

    /// Host-only helper to advance to the first night once every player confirmed their role
    private func advanceFromRoleRevealIfReady(forceRefresh: Bool, forceStart: Bool = false) async throws {
        guard isHost else { return }
        
        if forceRefresh {
            try await refreshPlayers()
        }
        
        guard currentSession?.currentPhase == "role_reveal" else { return }
        
        // Check readiness: bots are always ready, humans must confirm their role
        let humanPlayers = allPlayers.filter { !$0.isBot }
        let readyHumans = humanPlayers.filter { $0.isReady }
        
        if !forceStart {
            // All humans must have confirmed their role, bots are always considered ready
            guard readyHumans.count == humanPlayers.count else {
                return
            }
        }
        guard let session = currentSession else { return }
        
        // 1. Update phase first so clients transition to Night view immediately
        try await sessionService.updateSessionPhase(
            sessionId: session.id,
            currentPhase: "night",
            phaseData: .night(nightIndex: 0, activeRole: nil)
        )
        
        // 2. Reset ready status for all players (background task)
        // We do this after phase change to avoid UI flickering "Not Ready" in the Role Reveal view
        Task {
            for player in allPlayers {
                try? await sessionService.updatePlayerReady(playerId: player.id, isReady: false)
            }
        }
        
        try await refreshSession()
        try await refreshPlayers()
    }

    // MARK: - Game Flow (Host Only)

    /// Start the game (host only)
    func startGame() async throws {
        guard isHost, let session = currentSession else {
            throw SessionError.notHost
        }

        // Ensure we have enough players
        let humanPlayers = allPlayers.filter { !$0.isBot }
        let totalPlayers = allPlayers.count

        // Check readiness: bots are always ready, non-host humans must be explicitly ready
        // Host is excluded from readiness check since they can't mark themselves ready in the UI
        let nonHostHumans = humanPlayers.filter { $0.id != myPlayer?.id }
        let readyNonHostHumans = nonHostHumans.filter { $0.isReady }

        // All non-host humans must be ready, bots and host are always considered ready
        guard readyNonHostHumans.count == nonHostHumans.count else {
            throw SessionError.invalidPhase
        }

        guard totalPlayers >= 4, totalPlayers <= 19 else {
            throw SessionError.invalidPhase
        }

        // Assign roles and numbers
        let playerNames = allPlayers.map { $0.playerName }
        let assignments = assignRolesAndNumbers(playerNames: playerNames)

        // Update database with assignments
        try await sessionService.assignRolesAndNumbers(
            sessionId: session.id,
            assignments: assignments
        )

        // Update session status and phase
        try await sessionService.updateSessionStatus(sessionId: session.id, status: .inProgress)

        // Reset readiness before role reveal so hosts can't advance until everyone confirms
        await resetAllPlayersReady()

        try await sessionService.updateSessionPhase(
            sessionId: session.id,
            currentPhase: "role_reveal",
            phaseData: .roleReveal(currentPlayerIndex: 0)
        )

        // Refresh local state
        try await refreshSession()
        try await refreshPlayers()
    }

    private func assignRolesAndNumbers(playerNames: [String]) -> [(playerId: UUID, role: Role, number: Int)] {
        let count = playerNames.count

        // Generate random unique numbers
        var rng = SystemRandomNumberGenerator()
        let numberPool = Array(1...(count * 2)).shuffled(using: &rng)
        let assignedNumbers = Array(numberPool.prefix(count))

        // Determine role counts
        let roleCounts = GameStore.roleDistribution(for: count)

        // Build roles array
        var roles: [Role] = []
        roles += Array(repeating: .mafia, count: roleCounts.mafia)
        roles += Array(repeating: .doctor, count: roleCounts.doctors)
        roles += Array(repeating: .inspector, count: roleCounts.inspectors)
        let remaining = max(0, count - roles.count)
        roles += Array(repeating: .citizen, count: remaining)
        roles.shuffle(using: &rng)

        // Create assignments
        return allPlayers.enumerated().map { index, player in
            (playerId: player.playerId, role: roles[index], number: assignedNumbers[index])
        }
    }

    /// Advance to next phase (host only)
    func advancePhase(to phase: String, phaseData: PhaseData?) async throws {
        guard isHost, let session = currentSession else {
            throw SessionError.notHost
        }

        try await sessionService.updateSessionPhase(
            sessionId: session.id,
            currentPhase: phase,
            phaseData: phaseData
        )
    }

    // MARK: - Game Actions

    /// Submit a night action
    /// Returns the investigation result for inspector checks, nil otherwise
    func submitNightAction(
        actionType: ActionType,
        nightIndex: Int,
        targetPlayerId: UUID?
    ) async throws -> String? {
        guard let session = currentSession,
              let myPlayerId = myPlayer?.playerId else {
            return nil
        }

        // FIX: Use resolved round ID instead of fallback to prevent orphan actions
        // when Realtime hasn't propagated currentRoundId yet (same fix as submitVote)
        let roundId = try await resolvedRoundId()

        let action: GameAction

        switch actionType {
        case .mafiaTarget:
            action = .mafiaAction(
                sessionId: session.id,
                roundId: roundId,
                nightIndex: nightIndex,
                actorPlayerId: myPlayerId,
                targetPlayerId: targetPlayerId
            )
        case .inspectorCheck:
            // No local logic - handled by server RPC
            action = .inspectorAction(
                sessionId: session.id,
                roundId: roundId,
                nightIndex: nightIndex,
                actorPlayerId: myPlayerId,
                targetPlayerId: targetPlayerId,
                result: nil // Result will be populated by server
            )
        case .doctorProtect:
            action = .doctorAction(
                sessionId: session.id,
                roundId: roundId,
                nightIndex: nightIndex,
                actorPlayerId: myPlayerId,
                targetPlayerId: targetPlayerId
            )
        case .vote:
            // Voting handled separately
            return nil
        }

        let response = try await sessionService.submitAction(action)

        // If I'm the host, immediately check if this action completes the phase
        // This avoids relying solely on the real-time event which might be delayed
        if isHost {
            Task {
                // Small delay to ensure DB consistency
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                await self.evaluatePhaseProgression(trigger: "host_submission")
            }
        }

        // Return investigation result for inspector checks
        return actionType == .inspectorCheck ? response.result : nil
    }

    /// Ensures we have a valid round ID, refreshing session if needed
    /// HAMZA-FIX: Prevents orphan votes that don't get counted
    private func resolvedRoundId() async throws -> UUID {
        // First check if we already have it
        if let id = currentSession?.currentRoundId {
            return id
        }

        // Refresh session to get latest round ID
        try await refreshSession()

        if let id = currentSession?.currentRoundId {
            return id
        }

        // If still nil, this is an error state - phase hasn't been properly initialized
        throw SessionError.noActiveSession
    }

    /// Submit a vote
    func submitVote(dayIndex: Int, targetPlayerId: UUID?) async throws {
        guard let session = currentSession,
              let myPlayerId = myPlayer?.playerId else {
            return
        }

        // HAMZA-FIX: Use resolved round ID instead of fallback to prevent orphan votes
        let roundId = try await resolvedRoundId()

        let action = GameAction.voteAction(
            sessionId: session.id,
            roundId: roundId,
            dayIndex: dayIndex,
            actorPlayerId: myPlayerId,
            targetPlayerId: targetPlayerId
        )

        try await sessionService.submitAction(action)
        
        // If I'm the host, immediately check if this action completes the phase
        if isHost {
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                await self.evaluatePhaseProgression(trigger: "host_vote")
            }
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        stopHeartbeat()

        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let playerId = self.myPlayer?.id else { return }
                try? await self.sessionService.updatePlayerHeartbeat(playerId: playerId)
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // MARK: - Snapshot Resync (Pure Realtime Recovery)

    /// Perform a one-time snapshot resync after Realtime reconnect
    /// This fetches the latest session and player state to heal missed events
    private func performSnapshotResync() async {
        do {
            try await refreshSession()
            try await refreshPlayers()
        } catch {
            print("❌ [MultiplayerGameStore] Snapshot resync failed: \(error)")
        }
    }

    // MARK: - App Lifecycle Handling

    /// Called when app returns from background - reconnect Realtime and restart timers
    /// This fixes the freeze bug when returning after 5+ minutes in background
    private func handleAppResume() async {
        guard isInSession, let sessionId = currentSessionId else {
            print("🔄 [MultiplayerGameStore] App resumed but not in session - skipping reconnect")
            return
        }

        print("🔄 [MultiplayerGameStore] App resumed - reconnecting to session: \(sessionId)")

        // 1. Ensure auth token is fresh (handles hour+ background periods)
        await authStore?.ensureValidSession()

        // 2. Force reconnect Realtime (don't trust stale WebSocket connection)
        await realtimeService.forceReconnect(
            sessionId: sessionId,
            onSessionUpdate: { [weak self] session in
                Task { @MainActor in
                    self?.handleSessionUpdate(session)
                }
            },
            onPlayerUpdate: { [weak self] player in
                Task { @MainActor in
                    self?.handlePlayerUpdate(player)
                }
            },
            onActionUpdate: { [weak self] action in
                Task { @MainActor in
                    await self?.handleActionUpdate(action)
                }
            },
            onTentativeSelection: { [weak self] selection in
                Task { @MainActor in
                    self?.handleTentativeSelection(selection)
                }
            },
            onReconnected: { [weak self] in
                await self?.performSnapshotResync()
            }
        )

        // 3. Restart timers (they were paused in prepareForBackground)
        restartAllTimers()

        // 4. Immediately send heartbeat to mark player online
        if let playerId = myPlayer?.id {
            try? await sessionService.updatePlayerHeartbeat(playerId: playerId)
        }

        print("✅ [MultiplayerGameStore] App resume handling complete")
    }

    /// Called when app enters background - pause timers to save battery
    private func prepareForBackground() {
        guard isInSession else { return }

        print("🌙 [MultiplayerGameStore] App entering background - pausing timers")

        // Stop timers to save battery (no point sending heartbeats when iOS suspends us)
        stopHeartbeat()
        stopPlayerRefreshTimer()
        stopHostMonitorTimer()

        // Note: We don't disconnect Realtime here - iOS will handle suspension
        // The forceReconnect on resume will handle any stale connections
    }

    /// Restart all timers after app resume
    private func restartAllTimers() {
        guard isInSession else { return }

        print("🔄 [MultiplayerGameStore] Restarting timers...")

        startHeartbeat()

        if isHost {
            startPlayerRefreshTimer()
        } else {
            startHostMonitorTimer()
        }
    }

    // MARK: - Player Refresh Timer
    
    /// Start adaptive fallback polling (only for host, only when Realtime disconnected)
    /// This is a safety net for the host to detect stale state if Realtime fails
    private func startPlayerRefreshTimer() {
        stopPlayerRefreshTimer()

        // Only host polls as a fallback, interval is 30 seconds (not 3)
        // This prevents unnecessary DB load during normal Realtime operation
        playerRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                guard self.isInSession && self.isHost else { return }

                // Only poll if Realtime appears disconnected
                if !self.isRealtimeConnected {
                    let currentPhase = self.currentSession?.currentPhase ?? ""

                    try? await self.refreshSession()
                    try? await self.refreshPlayers()

                    if currentPhase == "role_reveal" {
                        try? await self.advanceFromRoleRevealIfReady(forceRefresh: false)
                    } else if currentPhase == "night" || currentPhase == "voting" {
                        await self.evaluatePhaseProgression(trigger: "fallback_check")
                    }
                }
            }
        }
    }

    private func stopPlayerRefreshTimer() {
        playerRefreshTimer?.invalidate()
        playerRefreshTimer = nil
    }

    // MARK: - Host Offline Detection (HAMZA-165)

    /// Start monitoring host's heartbeat (non-hosts only)
    private func startHostMonitorTimer() {
        stopHostMonitorTimer()
        guard !isHost else { return } // Only non-hosts monitor

        hostMonitorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkHostHeartbeat()
            }
        }
    }

    private func stopHostMonitorTimer() {
        hostMonitorTimer?.invalidate()
        hostMonitorTimer = nil
        isHostOffline = false
    }

    /// Check if host's heartbeat is stale and attempt transfer if so
    private func checkHostHeartbeat() async {
        guard !isHost, isInSession, let session = currentSession else { return }

        // Get fresh player data
        try? await refreshPlayers()

        // Find host player
        guard let hostPlayer = allPlayers.first(where: { $0.userId == session.hostUserId }),
              !hostPlayer.isBot else { return }

        // Check staleness
        let timeSinceHeartbeat = Date().timeIntervalSince(hostPlayer.lastHeartbeat)
        let wasOffline = isHostOffline
        isHostOffline = timeSinceHeartbeat > hostOfflineThreshold

        if isHostOffline && !wasOffline {
            print("⚠️ [MultiplayerGameStore] Host offline detected (last heartbeat: \(Int(timeSinceHeartbeat))s ago)")
        }

        if isHostOffline {
            await attemptHostTransfer(session: session)
        } else if wasOffline {
            print("✅ [MultiplayerGameStore] Host heartbeat recovered")
        }
    }

    /// Attempt to claim host role when current host is offline
    private func attemptHostTransfer(session: GameSession) async {
        // Determine next host (oldest alive human by joinedAt)
        guard let newHostUserId = determineNextHostUserId(
            excluding: session.hostUserId,
            requireRecentHeartbeat: true
        ) else {
            print("⚠️ [MultiplayerGameStore] No eligible player to become host")
            return
        }

        print("🔄 [MultiplayerGameStore] Initiating host transfer to next eligible player")

        do {
            try await sessionService.updateSessionHost(sessionId: session.id, newHostUserId: newHostUserId)
            // Realtime should sync the change to all clients, but also refresh locally in case it was missed
            try? await refreshSession()
            print("✅ [MultiplayerGameStore] Host transfer initiated successfully")
        } catch {
            print("❌ [MultiplayerGameStore] Failed to transfer host: \(error)")
        }
    }

    // MARK: - Phase Coordination

    private func handlePhaseEntry(for phaseData: PhaseData?) async {
        guard isHost else { return }
        guard let phaseData else { return }

        switch phaseData {
        case .night(let nightIndex, _):
            // Reset all players' ready status at the start of night phase
            await resetAllPlayersReady()

            // CRITICAL: Refresh session to get correct roundId before processing bots
            // Fixes bug where inspector bot actions get wrong roundId due to Realtime delay
            try? await refreshSession()

            if !processedBotNightIndices.contains(nightIndex) {
                do {
                    try await processBotActions(nightIndex: nightIndex)
                    processedBotNightIndices.insert(nightIndex) // Only mark after successful completion
                } catch {
                    print("❌ [MultiplayerGameStore] Failed to process bot night actions: \(error)")
                    // Don't mark as processed so we can retry on next phase entry
                }
            }
            await evaluatePhaseProgression(trigger: "enter_night")
        case .voting(let dayIndex):
            // Reset all players' ready status at the start of voting phase
            await resetAllPlayersReady()

            // HAMZA-FIX: SIMPLIFIED - Always process bot votes if ANY bots are missing valid votes
            // This is the PRIMARY trigger for bot voting - don't rely on processedBotVotingDays
            let missingBots = await botsMissingVotes(dayIndex: dayIndex)

            if !missingBots.isEmpty {
                print("🤖 [handlePhaseEntry] \(missingBots.count) bots missing votes for day \(dayIndex) - processing NOW")
                do {
                    try await processBotVotes(dayIndex: dayIndex)
                    processedBotVotingDays.insert(dayIndex)
                } catch {
                    print("❌ [handlePhaseEntry] Failed to process bot votes: \(error)")
                    // Don't mark as processed so we can retry
                }
            } else if !processedBotVotingDays.contains(dayIndex) {
                // No bots missing votes but not yet marked processed - mark it now
                print("🤖 [handlePhaseEntry] All bots already have votes for day \(dayIndex)")
                processedBotVotingDays.insert(dayIndex)
            }

            await evaluatePhaseProgression(trigger: "enter_voting")
        default:
            break
        }
    }

    /// Returns alive bots that do not yet have a VALID vote recorded for the given day
    /// HAMZA-FIX: Now checks for non-nil targetPlayerId - votes without targets don't count
    private func botsMissingVotes(dayIndex: Int) async -> [SessionPlayer] {
        guard let session = currentSession else { return [] }
        let aliveBots = allPlayers.filter { $0.isBot && $0.isAlive }
        guard !aliveBots.isEmpty else { return [] }

        let existingVotes = await loadActionsSafely(
            sessionId: session.id,
            actionType: .vote,
            phaseIndex: dayIndex,
            roundId: session.currentRoundId
        )

        // HAMZA-FIX: Only count votes that have a non-nil target as valid
        let validVotedIds = Set(existingVotes.filter { $0.targetPlayerId != nil }.map { $0.actorPlayerId })
        return aliveBots.filter { !validVotedIds.contains($0.playerId) }
    }

    private func resetAllPlayersReady() async {
        guard let session = currentSession else { return }

        do {
            // Single RPC call instead of N sequential updates
            try await sessionService.resetAllPlayersReady(sessionId: session.id)

            // Update local state for immediate UI feedback
            for index in allPlayers.indices where !allPlayers[index].isBot {
                allPlayers[index].isReady = false
            }

            if let myId = myPlayer?.id,
               let updatedMe = allPlayers.first(where: { $0.id == myId }) {
                myPlayer = updatedMe
                myRole = updatedMe.role
                myNumber = updatedMe.playerNumber
            }

            updateVisiblePlayers()
        } catch {
            print("❌ Failed to reset all players ready: \(error)")
        }
    }

    /// Reset isReady for all players when game ends (for clean rematch state)
    private func resetAllPlayersReadyForGameOver() async {
        guard currentSession != nil else { return }

        var updatedPlayers = allPlayers

        // Reset isReady for ALL players (human and bot) so rematch starts fresh
        for index in updatedPlayers.indices {
            let player = updatedPlayers[index]
            // Only update if currently ready
            guard player.isReady else { continue }

            do {
                try await sessionService.updatePlayerReady(playerId: player.id, isReady: false)
                updatedPlayers[index].isReady = false
            } catch {
                print("❌ Failed to reset ready status for player \(player.playerName): \(error)")
            }
        }

        allPlayers = updatedPlayers

        if let myId = myPlayer?.id,
           let updatedMe = updatedPlayers.first(where: { $0.id == myId }) {
            myPlayer = updatedMe
        }

        updateVisiblePlayers()
    }

    private func evaluatePhaseProgression(trigger: String) async {
        guard isHost, !isResolvingPhase else { return }
        guard let session = currentSession, let phaseData = session.currentPhaseData else { return }

        isResolvingPhase = true
        defer { isResolvingPhase = false }

        do {
            try await refreshPlayers()
        } catch {
            // Don't block readiness evaluation on transient network issues
            print("⚠️ [MultiplayerGameStore] refreshPlayers() failed during \(trigger): \(error)")
        }

        do {
            switch phaseData {
            case .night(let nightIndex, _):
                try await checkNightPhaseReadiness(nightIndex: nightIndex)
            case .voting(let dayIndex):
                try await checkVotingPhaseReadiness(dayIndex: dayIndex)
            default:
                break
            }
        } catch {
            print("❌ [MultiplayerGameStore] Failed to evaluate phase (\(trigger)): \(error)")
        }
    }

    private func checkNightPhaseReadiness(nightIndex: Int) async throws {
        guard isHost else {
            return
        }
        guard case .night(let activeNightIndex, _) = currentSession?.currentPhaseData,
              activeNightIndex == nightIndex else {
            return
        }
        guard let session = currentSession else {
            return
        }

        // ✅ CRITICAL FIX: Check if this night is already resolved (prevents duplicate resolution)
        if let nightRecord = session.nightHistory.first(where: { $0.nightIndex == nightIndex }),
           nightRecord.isResolved {
            await MainActor.run {
                self.isPhaseReadyToAdvance = false
            }
            return
        }

        // PERF: Single-pass categorization instead of 6+ separate filter calls
        let categories = categorizeAlivePlayers(hostUserId: session.hostUserId)

        let mafiaActions = await loadActionsSafely(
            sessionId: session.id,
            actionType: .mafiaTarget,
            phaseIndex: nightIndex
        )
        let inspectorActions = await loadActionsSafely(
            sessionId: session.id,
            actionType: .inspectorCheck,
            phaseIndex: nightIndex
        )
        let doctorActions = await loadActionsSafely(
            sessionId: session.id,
            actionType: .doctorProtect,
            phaseIndex: nightIndex
        )

        // Track who has already submitted an action so we don't block on missing ready flags
        let mafiaActors = Set(mafiaActions.map { $0.actorPlayerId })
        let doctorActors = Set(doctorActions.map { $0.actorPlayerId })
        let inspectorActors = Set(inspectorActions.map { $0.actorPlayerId })

        // Check if the host has an active role and has submitted their action
        let hostPlayer = allPlayers.first { $0.userId == session.hostUserId }
        let hostHasActiveRole = hostPlayer?.role != nil && hostPlayer?.role != .citizen
        let hostHasSubmitted = hostPlayer.map { player in
            switch player.role {
            case .mafia:
                return mafiaActors.contains(player.playerId)
            case .doctor:
                return doctorActors.contains(player.playerId)
            case .inspector:
                return inspectorActors.contains(player.playerId)
            default:
                return true // No action needed for citizens
            }
        } ?? true

        // PERF: Use pre-categorized nonHostHumans instead of filtering again
        let readyNonHostHumans = categories.nonHostHumans.filter { player in
            let role = player.role
            let passive = (role == .citizen)

            let hasAction: Bool = {
                switch role {
                case .mafia:
                    return mafiaActors.contains(player.playerId)
                case .doctor:
                    return doctorActors.contains(player.playerId)
                case .inspector:
                    return inspectorActors.contains(player.playerId)
                default:
                    return false
                }
            }()

            return passive || player.isReady || hasAction
        }

        let nonHostReady = categories.nonHostHumans.isEmpty || readyNonHostHumans.count == categories.nonHostHumans.count
        let allReady = nonHostReady && (!hostHasActiveRole || hostHasSubmitted)

        await MainActor.run {
            self.isPhaseReadyToAdvance = allReady
        }
    }

    /// Resilient action fetch that won't block readiness checks if Supabase temporarily fails
    private func loadActionsSafely(
        sessionId: UUID,
        actionType: ActionType,
        phaseIndex: Int,
        roundId: UUID? = nil
    ) async -> [GameAction] {
        do {
            return try await sessionService.getActionsForPhase(
                sessionId: sessionId,
                actionType: actionType,
                phaseIndex: phaseIndex,
                roundId: roundId
            )
        } catch {
            print("⚠️ [MultiplayerGameStore] Failed to load actions for \(actionType.rawValue) @ phase \(phaseIndex): \(error)")
            return []
        }
    }
    
    // MARK: - Two-Phase Night Resolution Pattern

    /// Phase 1: Record night actions without applying deaths (guards against duplicate resolution)
    func recordNightActions(nightIndex: Int) async throws {
        guard isHost else { return }
        guard case .night(let activeNightIndex, _) = currentSession?.currentPhaseData,
              activeNightIndex == nightIndex else {
            return
        }
        guard let session = currentSession else { return }

        // Check if this night is already recorded
        if let existingRecord = session.nightHistory.first(where: { $0.nightIndex == nightIndex }) {
            if existingRecord.isResolved {
                return
            }
            // If recorded but not resolved, continue to phase 2
            return
        }

        // FIX: Refresh players from database to ensure we have latest playerNumber values
        // This prevents stale data race condition where human player actions from other devices
        // have actorPlayerId that doesn't match the host's outdated visiblePlayers lookup
        try await refreshPlayers()
        updateVisiblePlayers()

        // Re-fetch actions to ensure we have latest state (filtered by round_id to prevent action replay)
        let mafiaActions = try await sessionService.getActionsForPhase(
            sessionId: session.id,
            actionType: .mafiaTarget,
            phaseIndex: nightIndex,
            roundId: session.currentRoundId
        )
        let doctorActions = try await sessionService.getActionsForPhase(
            sessionId: session.id,
            actionType: .doctorProtect,
            phaseIndex: nightIndex,
            roundId: session.currentRoundId
        )
        let inspectorActions = try await sessionService.getActionsForPhase(
            sessionId: session.id,
            actionType: .inspectorCheck,
            phaseIndex: nightIndex,
            roundId: session.currentRoundId
        )

        // HAMZA-FIX: Compute valid targets for each role (used as fallback in tie-breaker)
        let alivePlayers = allPlayers.filter { $0.isAlive }
        let validMafiaTargets = alivePlayers.filter { $0.role != .mafia }.map { $0.playerId }
        let validInspectorTargets = alivePlayers.filter { $0.role != .inspector }.map { $0.playerId }
        let validDoctorTargets = alivePlayers.map { $0.playerId }  // Doctor can protect anyone

        // HAMZA-FIX: Use new determineMajorityTarget with tie-breakers (NEVER returns nil when valid targets exist)
        let mafiaTargetId = determineMajorityTarget(from: mafiaActions, validTargets: validMafiaTargets)
        let doctorTargetId = determineMajorityTarget(from: doctorActions, validTargets: validDoctorTargets)
        let inspectorTargetId = determineMajorityTarget(from: inspectorActions, validTargets: validInspectorTargets)

        let doctorProtectionIds = Set(doctorActions.compactMap { $0.targetPlayerId })
        let targetWasSaved = mafiaTargetId.flatMap { doctorProtectionIds.contains($0) } ?? false
        let doctorProtectedId = doctorTargetId ?? (targetWasSaved ? mafiaTargetId : doctorProtectionIds.first)

        // Build lookup from visiblePlayers (same source that works for target resolution)
        let playerNumberLookup = Dictionary(uniqueKeysWithValues:
            visiblePlayers.map { ($0.playerId, $0.playerNumber) }
        )

        // Get player numbers from who submitted each action type
        let mafiaPlayerNumbers = mafiaActions
            .compactMap { playerNumberLookup[$0.actorPlayerId] }
            .compactMap { $0 }
            .sorted()
        let doctorPlayerNumbers = doctorActions
            .compactMap { playerNumberLookup[$0.actorPlayerId] }
            .compactMap { $0 }
            .sorted()
        let inspectorPlayerNumbers = inspectorActions
            .compactMap { playerNumberLookup[$0.actorPlayerId] }
            .compactMap { $0 }
            .sorted()

        // Inspector checked ID uses majority vote with tie-breakers (same as other roles)
        let inspectorCheckedId = inspectorTargetId

        // Phase 1: Record actions WITHOUT applying deaths (isResolved=false, resultingDeaths=[])
        let nightRecord = NightActionRecord(
            nightIndex: nightIndex,
            isResolved: false,  // NOT resolved yet - Phase 2 will set this to true
            mafiaTargetId: mafiaTargetId,
            inspectorCheckedId: inspectorCheckedId,
            inspectorResult: nil,
            doctorProtectedId: doctorProtectedId,
            resultingDeaths: [],  // Empty - deaths not applied yet
            mafiaPlayerNumbers: mafiaPlayerNumbers,
            doctorPlayerNumbers: doctorPlayerNumbers,
            inspectorPlayerNumbers: inspectorPlayerNumbers,
            timestamp: Date()
        )

        var updatedHistory = session.nightHistory.filter { $0.nightIndex != nightIndex }
        updatedHistory.append(nightRecord)
        updatedHistory.sort { $0.nightIndex < $1.nightIndex }
        currentSession?.nightHistory = updatedHistory

        // Update ONLY night_history, don't touch players or phase
        try await sessionService.updateSessionState(
            sessionId: session.id,
            nightHistory: updatedHistory
        )
    }

    /// Phase 2: Apply night outcomes atomically (with duplicate resolution guard)
    func resolveNightOutcome(nightIndex: Int, targetWasSaved: Bool) async throws {
        guard isHost else { return }
        guard let session = currentSession else {
            print("ERROR: [resolveNightOutcome] No current session - cannot resolve night \(nightIndex)")
            return
        }
        guard var nightRecord = session.nightHistory.first(where: { $0.nightIndex == nightIndex }) else {
            print("ERROR: [resolveNightOutcome] Night record missing for nightIndex \(nightIndex) in session \(session.id)")
            print("ERROR: [resolveNightOutcome] Current nightHistory: \(session.nightHistory.map { "night \($0.nightIndex), resolved: \($0.isResolved)" })")
            return
        }

        // CRITICAL: Guard against duplicate resolution
        if nightRecord.isResolved {
            return
        }

        var resultingDeaths: [UUID] = []
        if let targetId = nightRecord.mafiaTargetId, !targetWasSaved {
            resultingDeaths = [targetId]
        }

        // Update the record with final results
        nightRecord.resultingDeaths = resultingDeaths
        nightRecord.isResolved = true  // Mark as resolved

        // Update local history
        var updatedHistory = session.nightHistory.filter { $0.nightIndex != nightIndex }
        updatedHistory.append(nightRecord)
        updatedHistory.sort { $0.nightIndex < $1.nightIndex }
        currentSession?.nightHistory = updatedHistory

        // CRITICAL: Apply deaths to local state BEFORE win check so evaluateWinners sees correct counts
        for playerId in resultingDeaths {
            if let index = allPlayers.firstIndex(where: { $0.playerId == playerId }) {
                allPlayers[index].isAlive = false
            }
        }

        // Check win conditions AFTER death but BEFORE phase transition
        let winnerCheck = evaluateWinners(startOfDay: true)
        let nextPhaseName: String
        let nextPhaseData: PhaseData

        if winnerCheck.isGameOver {
            nextPhaseName = "game_over"
            nextPhaseData = .gameOver(winner: winnerCheck.winner?.rawValue)
        } else {
            nextPhaseName = "morning"
            nextPhaseData = .morning(nightIndex: nightIndex)
        }

        // Reset readiness flag
        await MainActor.run {
            self.isPhaseReadyToAdvance = false
        }

        // ATOMIC OPERATION: Apply deaths + update history + advance phase in single transaction
        let success = try await sessionService.resolveNightAtomic(
            sessionId: session.id,
            nightRecord: nightRecord,
            eliminatedPlayerIds: resultingDeaths,
            nextPhase: nextPhaseName,
            nextPhaseData: nextPhaseData,
            isGameOver: winnerCheck.isGameOver ? true : nil,
            winner: winnerCheck.winner
        )

        if success {
            // Update local player state to match DB
            for playerId in resultingDeaths {
                if let index = allPlayers.firstIndex(where: { $0.playerId == playerId }) {
                    allPlayers[index].isAlive = false
                }
            }

            let hostEliminated = resultingDeaths.contains(where: { playerId in
                allPlayers.first(where: { $0.playerId == playerId })?.userId == session.hostUserId
            })

            await transferHostIfNeeded(hostEliminated: hostEliminated, session: session)
        } else {
            print("❌ Failed to resolve night \(nightIndex) atomically")
        }
    }

    /// Legacy single-phase resolution (DEPRECATED - kept for backwards compatibility, will be removed)
    private func resolveNightPhase(nightIndex: Int) async throws {
        guard isHost else { return }
        guard case .night(let activeNightIndex, _) = currentSession?.currentPhaseData,
              activeNightIndex == nightIndex else {
            return
        }
        guard let session = currentSession else { return }

        // FIX: Refresh players from database to ensure we have latest playerNumber values
        try await refreshPlayers()
        updateVisiblePlayers()

        // Re-fetch actions to ensure we have latest state (filtered by round_id to prevent action replay)
        let mafiaActions = try await sessionService.getActionsForPhase(
            sessionId: session.id,
            actionType: .mafiaTarget,
            phaseIndex: nightIndex,
            roundId: session.currentRoundId
        )
        let doctorActions = try await sessionService.getActionsForPhase(
            sessionId: session.id,
            actionType: .doctorProtect,
            phaseIndex: nightIndex,
            roundId: session.currentRoundId
        )
        let inspectorActions = try await sessionService.getActionsForPhase(
            sessionId: session.id,
            actionType: .inspectorCheck,
            phaseIndex: nightIndex,
            roundId: session.currentRoundId
        )

        // HAMZA-FIX: Compute valid targets for each role (used as fallback in tie-breaker)
        let alivePlayers = allPlayers.filter { $0.isAlive }
        let validMafiaTargets = alivePlayers.filter { $0.role != .mafia }.map { $0.playerId }
        let validInspectorTargets = alivePlayers.filter { $0.role != .inspector }.map { $0.playerId }
        let validDoctorTargets = alivePlayers.map { $0.playerId }

        // HAMZA-FIX: Use new determineMajorityTarget with tie-breakers
        let mafiaTargetId = determineMajorityTarget(from: mafiaActions, validTargets: validMafiaTargets)
        let doctorTargetId = determineMajorityTarget(from: doctorActions, validTargets: validDoctorTargets)
        let _ = determineMajorityTarget(from: inspectorActions, validTargets: validInspectorTargets)  // Inspector result logged

        let doctorProtectionIds = Set(doctorActions.compactMap { $0.targetPlayerId })
        let targetWasSaved = mafiaTargetId.flatMap { doctorProtectionIds.contains($0) } ?? false
        let doctorProtectedId = doctorTargetId ?? (targetWasSaved ? mafiaTargetId : doctorProtectionIds.first)

        var resultingDeaths: [UUID] = []
        var hostEliminated = false
        if let targetId = mafiaTargetId, !targetWasSaved {
            resultingDeaths = [targetId]
            hostEliminated = try await applyEliminations(resultingDeaths, reason: "Eliminated at night")
        }

        // Build lookup from visiblePlayers (same source that works for target resolution)
        let playerNumberLookup = Dictionary(uniqueKeysWithValues:
            visiblePlayers.map { ($0.playerId, $0.playerNumber) }
        )

        // Get player numbers from who submitted each action type
        let mafiaPlayerNumbers = mafiaActions
            .compactMap { playerNumberLookup[$0.actorPlayerId] }
            .compactMap { $0 }
            .sorted()
        let doctorPlayerNumbers = doctorActions
            .compactMap { playerNumberLookup[$0.actorPlayerId] }
            .compactMap { $0 }
            .sorted()
        let inspectorPlayerNumbers = inspectorActions
            .compactMap { playerNumberLookup[$0.actorPlayerId] }
            .compactMap { $0 }
            .sorted()

        // Inspector checked ID can be public (but result stays private)
        let inspectorCheckedId = inspectorActions.first?.targetPlayerId

        let nightRecord = NightActionRecord(
            nightIndex: nightIndex,
            mafiaTargetId: mafiaTargetId,
            inspectorCheckedId: inspectorCheckedId, // Public: Who was checked
            inspectorResult: nil, // Private: Result stays hidden
            doctorProtectedId: doctorProtectedId,
            resultingDeaths: resultingDeaths,
            mafiaPlayerNumbers: mafiaPlayerNumbers,
            doctorPlayerNumbers: doctorPlayerNumbers,
            inspectorPlayerNumbers: inspectorPlayerNumbers,
            timestamp: Date()
        )

        var updatedHistory = session.nightHistory.filter { $0.nightIndex != nightIndex }
        updatedHistory.append(nightRecord)
        updatedHistory.sort { $0.nightIndex < $1.nightIndex }
        currentSession?.nightHistory = updatedHistory

        let winnerCheck = evaluateWinners(startOfDay: true)
        let nextPhaseName: String
        let nextPhaseData: PhaseData

        if winnerCheck.isGameOver {
            nextPhaseName = "game_over"
            nextPhaseData = .gameOver(winner: winnerCheck.winner?.rawValue)
        } else {
            nextPhaseName = "morning"
            nextPhaseData = .morning(nightIndex: nightIndex)
        }
        
        // Reset readiness flag
        await MainActor.run {
            self.isPhaseReadyToAdvance = false
        }

        try await sessionService.updateSessionState(
            sessionId: session.id,
            currentPhase: nextPhaseName,
            phaseData: nextPhaseData,
            nightHistory: updatedHistory,
            isGameOver: winnerCheck.isGameOver ? true : nil,
            winner: winnerCheck.winner
        )

        await transferHostIfNeeded(hostEliminated: hostEliminated, session: session)
    }

    private func checkVotingPhaseReadiness(dayIndex: Int) async throws {
        guard isHost else { return }
        guard case .voting(let activeDayIndex) = currentSession?.currentPhaseData,
              activeDayIndex == dayIndex else {
            return
        }
        guard let session = currentSession else { return }

        // PERF: Single-pass categorization instead of multiple filter chains
        let categories = categorizeAlivePlayers(hostUserId: session.hostUserId)
        let aliveBotIds = categories.bots.map { $0.playerId }

        // HAMZA-FIX: Fetch current vote actions FIRST to check real state
        var voteActions = await loadActionsSafely(
            sessionId: session.id,
            actionType: .vote,
            phaseIndex: dayIndex,
            roundId: session.currentRoundId
        )

        // HAMZA-FIX: Count how many alive bots have valid votes (non-nil target)
        let botVotesWithTargets = voteActions.filter { action in
            aliveBotIds.contains(action.actorPlayerId) && action.targetPlayerId != nil
        }
        let missingBotVoteCount = aliveBotIds.count - botVotesWithTargets.count

        // HAMZA-FIX: CRITICAL - If ANY alive bot is missing a vote, force processBotVotes NOW
        if missingBotVoteCount > 0 {
            print("🤖 [checkVotingPhaseReadiness] \(missingBotVoteCount)/\(aliveBotIds.count) bots missing votes - FORCING processBotVotes()")
            do {
                try await processBotVotes(dayIndex: dayIndex)
                // Re-fetch votes after processing
                voteActions = await loadActionsSafely(
                    sessionId: session.id,
                    actionType: .vote,
                    phaseIndex: dayIndex,
                    roundId: session.currentRoundId
                )
            } catch {
                print("❌ [checkVotingPhaseReadiness] Force bot voting failed: \(error)")
            }
        }

        // PERF: Use pre-categorized players instead of chained filters
        let readyNonHostHumans = categories.nonHostHumans.filter { $0.isReady }
        let nonHostReady = categories.nonHostHumans.isEmpty || readyNonHostHumans.count == categories.nonHostHumans.count

        // Check if host has voted (only required if host is alive)
        let hostPlayer = allPlayers.first { $0.userId == session.hostUserId }
        let hostIsAlive = hostPlayer?.isAlive ?? false
        let hostVote = voteActions.first { $0.actorPlayerId == hostPlayer?.playerId }
        let hostHasVoted = hostVote != nil

        // HAMZA-FIX: Re-count bot votes after potential processing
        let finalBotVotes = voteActions.filter { action in
            aliveBotIds.contains(action.actorPlayerId) && action.targetPlayerId != nil
        }
        let botsReady = finalBotVotes.count == aliveBotIds.count

        // Ready when all non-host players are ready AND (host has voted OR host is dead) AND bots have voted
        let ready = nonHostReady && (!hostIsAlive || hostHasVoted) && botsReady

        if !botsReady {
            print("⚠️ [checkVotingPhaseReadiness] STILL not ready: \(finalBotVotes.count)/\(aliveBotIds.count) bot votes")
        }

        await MainActor.run {
            self.isPhaseReadyToAdvance = ready
        }
    }

    func showVotingResults(dayIndex: Int) async throws {
        guard isHost else { return }
        guard case .voting(let activeDayIndex) = currentSession?.currentPhaseData,
              activeDayIndex == dayIndex else {
            return
        }
        guard let session = currentSession else { return }

        // Fetch all votes for this day
        let votes = try await sessionService.getActionsForPhase(
            sessionId: session.id,
            actionType: .vote,
            phaseIndex: dayIndex,
            roundId: session.currentRoundId
        )

        // DEBUG: Log fetched votes
        print("📊 [showVotingResults] Fetched \(votes.count) votes for day \(dayIndex), roundId: \(session.currentRoundId?.uuidString ?? "nil")")
        for vote in votes {
            let actorName = visiblePlayers.first { $0.playerId == vote.actorPlayerId }?.playerName ?? "Unknown"
            let targetName = vote.targetPlayerId.flatMap { tid in visiblePlayers.first { $0.playerId == tid }?.playerName } ?? "Abstain"
            print("   - \(actorName) voted for \(targetName)")
        }

        // Seed vote counts with all alive players (0 votes)
        var voteCounts: [UUID: Int] = [:]
        for player in visiblePlayers where player.isAlive {
            voteCounts[player.playerId] = 0
        }
        print("📊 [showVotingResults] Seeded \(voteCounts.count) alive players with 0 votes")

        // Tally actual votes
        for action in votes {
            guard let targetId = action.targetPlayerId else {
                print("   ⚠️ Skipping vote with nil target from actor: \(action.actorPlayerId)")
                continue
            }
            voteCounts[targetId, default: 0] += 1
        }

        // DEBUG: Log final tallies
        print("📊 [showVotingResults] Final vote tallies:")
        for (playerId, count) in voteCounts.sorted(by: { $0.value > $1.value }) {
            let name = visiblePlayers.first { $0.playerId == playerId }?.playerName ?? "Unknown(\(playerId))"
            print("   - \(name): \(count) votes")
        }

        // Determine elimination (but DON'T apply yet)
        var eliminatedPlayerId: UUID?
        if let maxVotes = voteCounts.values.max(), maxVotes > 0 {
            let leaders = voteCounts.filter { $0.value == maxVotes }
            if leaders.count == 1 {
                eliminatedPlayerId = leaders.first?.key
            }
        }

        // Transition to voting results phase
        let nextPhaseData: PhaseData = .votingResults(
            dayIndex: dayIndex,
            voteCounts: voteCounts,
            eliminatedPlayerId: eliminatedPlayerId
        )

        try await sessionService.updateSessionState(
            sessionId: session.id,
            currentPhase: "voting_results",
            phaseData: nextPhaseData,
            dayIndex: session.dayIndex,
            dayHistory: session.dayHistory,
            isGameOver: nil,
            winner: nil
        )
    }

    func applyVotingResult(dayIndex: Int) async throws {
        guard isHost else { return }
        guard case .votingResults(let activeDayIndex, let voteCounts, let eliminatedPlayerId) = currentSession?.currentPhaseData,
              activeDayIndex == dayIndex else {
            return
        }
        guard let session = currentSession else { return }

        // Validate vote data exists
        guard !voteCounts.isEmpty else {
            print("⚠️ No vote data available for voting results phase")
            return
        }

        // Cache eliminated player info BEFORE any elimination occurs
        var eliminatedName: String?
        var eliminatedNumber: Int?
        var eliminatedRole: String?
        var eliminatedVoteCount: Int?

        if let eliminatedId = eliminatedPlayerId {
            if let player = allPlayers.first(where: { $0.playerId == eliminatedId }) {
                eliminatedName = player.playerName
                eliminatedNumber = player.playerNumber
                eliminatedRole = player.role?.rawValue
            }
            eliminatedVoteCount = voteCounts[eliminatedId]
        }

        // Transition to vote death reveal phase (NOT applying elimination yet)
        let revealPhaseData: PhaseData = .voteDeathReveal(
            dayIndex: dayIndex,
            eliminatedPlayerId: eliminatedPlayerId,
            eliminatedPlayerName: eliminatedName,
            eliminatedPlayerNumber: eliminatedNumber,
            eliminatedPlayerRole: eliminatedRole,
            voteCount: eliminatedVoteCount
        )

        try await sessionService.updateSessionState(
            sessionId: session.id,
            currentPhase: "vote_death_reveal",
            phaseData: revealPhaseData,
            dayIndex: session.dayIndex,
            dayHistory: session.dayHistory,
            isGameOver: nil,
            winner: nil
        )
    }

    /// Called by host after vote death reveal animation completes
    func completeVoteDeathReveal(dayIndex: Int) async throws {
        guard isHost else { throw SessionError.notHost }
        guard case .voteDeathReveal(
            let activeDayIndex,
            let eliminatedPlayerId,
            _, _, _, _
        ) = currentSession?.currentPhaseData,
              activeDayIndex == dayIndex else {
            return
        }
        guard let session = currentSession else { return }

        // NOW apply eliminations
        var removedPlayerIds: [UUID] = []
        var hostEliminated = false
        if let eliminated = eliminatedPlayerId {
            removedPlayerIds = [eliminated]
            hostEliminated = try await applyEliminations(removedPlayerIds, reason: "Voted out")
        }

        // Create day record
        let dayRecord = DayActionRecord(
            dayIndex: dayIndex,
            removedPlayerIds: removedPlayerIds,
            timestamp: Date()
        )

        var updatedDayHistory = session.dayHistory.filter { $0.dayIndex != dayIndex }
        updatedDayHistory.append(dayRecord)
        updatedDayHistory.sort { $0.dayIndex < $1.dayIndex }
        currentSession?.dayHistory = updatedDayHistory

        // Check win conditions
        let newDayIndex = dayIndex + 1
        let winnerCheck = evaluateWinners(startOfDay: false)
        let nextPhaseName: String
        let nextPhaseData: PhaseData

        if winnerCheck.isGameOver {
            nextPhaseName = "game_over"
            nextPhaseData = .gameOver(winner: winnerCheck.winner?.rawValue)
        } else {
            let nextNightIndex = dayIndex + 1
            nextPhaseName = "night"
            nextPhaseData = .night(nightIndex: nextNightIndex, activeRole: nil)
        }

        // Reset readiness flag
        await MainActor.run {
            self.isPhaseReadyToAdvance = false
        }

        // Update session - phase and history changes
        try await sessionService.updateSessionState(
            sessionId: session.id,
            currentPhase: nextPhaseName,
            phaseData: nextPhaseData,
            dayIndex: newDayIndex,
            dayHistory: updatedDayHistory,
            isGameOver: winnerCheck.isGameOver ? true : nil,
            winner: winnerCheck.winner
        )

        // CRITICAL: Small delay to let Realtime propagate the new roundId before processing bot actions
        // Without this, bot actions might use stale/nil roundId and generate individual UUIDs
        if nextPhaseName == "night" {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        }

        // CRITICAL: Host transfer happens AFTER reveal completes
        await transferHostIfNeeded(hostEliminated: hostEliminated, session: session)
    }

    private func resolveVotingPhase(dayIndex: Int) async throws {
        guard isHost else { return }
        guard case .voting(let activeDayIndex) = currentSession?.currentPhaseData,
              activeDayIndex == dayIndex else {
            return
        }
        guard let session = currentSession else { return }

        let votes = try await sessionService.getActionsForPhase(
            sessionId: session.id,
            actionType: .vote,
            phaseIndex: dayIndex,
            roundId: session.currentRoundId
        )

        var voteCounts: [UUID: Int] = [:]
        for action in votes {
            guard let targetId = action.targetPlayerId else { continue }
            voteCounts[targetId, default: 0] += 1
        }

        var eliminatedPlayerId: UUID?
        if let maxVotes = voteCounts.values.max(), maxVotes > 0 {
            let leaders = voteCounts.filter { $0.value == maxVotes }
            if leaders.count == 1 {
                eliminatedPlayerId = leaders.first?.key
            }
        }

        var removedPlayerIds: [UUID] = []
        var hostEliminated = false
        if let eliminated = eliminatedPlayerId {
            removedPlayerIds = [eliminated]
            hostEliminated = try await applyEliminations(removedPlayerIds, reason: "Voted out")
        }

        let dayRecord = DayActionRecord(
            dayIndex: dayIndex,
            removedPlayerIds: removedPlayerIds,
            timestamp: Date()
        )

        var updatedDayHistory = session.dayHistory.filter { $0.dayIndex != dayIndex }
        updatedDayHistory.append(dayRecord)
        updatedDayHistory.sort { $0.dayIndex < $1.dayIndex }
        currentSession?.dayHistory = updatedDayHistory

        let newDayIndex = dayIndex + 1
        let winnerCheck = evaluateWinners(startOfDay: false)
        let nextPhaseName: String
        let nextPhaseData: PhaseData

        if winnerCheck.isGameOver {
            nextPhaseName = "game_over"
            nextPhaseData = .gameOver(winner: winnerCheck.winner?.rawValue)
        } else {
            let nextNightIndex = dayIndex + 1
            nextPhaseName = "night"
            nextPhaseData = .night(nightIndex: nextNightIndex, activeRole: nil)
        }
        
        // Reset readiness flag
        await MainActor.run {
            self.isPhaseReadyToAdvance = false
        }

        try await sessionService.updateSessionState(
            sessionId: session.id,
            currentPhase: nextPhaseName,
            phaseData: nextPhaseData,
            dayIndex: newDayIndex,
            dayHistory: updatedDayHistory,
            isGameOver: winnerCheck.isGameOver ? true : nil,
            winner: winnerCheck.winner
        )

        await transferHostIfNeeded(hostEliminated: hostEliminated, session: session)
    }

    /// Determine the target from multiple actions using majority vote
    /// Returns nil if no actions exist (role doesn't exist in game), uses tie-breakers otherwise
    /// - Parameters:
    ///   - actions: The submitted actions to count votes from
    ///   - validTargets: Fallback list of valid targets if no votes exist but actors submitted actions
    /// - Returns: The chosen target UUID, or nil if no actions exist (role doesn't exist in game)
    private func determineMajorityTarget(from actions: [GameAction], validTargets: [UUID]) -> UUID? {
        // FIX: If no actions at all, return nil (no actors of this role exist in the game)
        // This prevents phantom doctor/inspector protection in games without those roles (4-5 players)
        guard !actions.isEmpty else { return nil }

        var counts: [UUID: Int] = [:]
        for action in actions {
            guard let targetId = action.targetPlayerId else { continue }
            counts[targetId, default: 0] += 1
        }

        guard let maxVotes = counts.values.max(), maxVotes > 0 else {
            // FALLBACK: Role actors exist but haven't submitted targets - pick first valid target
            print("⚠️ [determineMajorityTarget] No votes found, using fallback target")
            return validTargets.first
        }

        let leaders = counts.filter { $0.value == maxVotes }

        // Single winner - return it
        if leaders.count == 1 {
            return leaders.first?.key
        }

        // TIE-BREAKER 1: Prefer targets voted by humans
        let humanActorIds = Set(allPlayers.filter { !$0.isBot }.map { $0.playerId })
        let humanVotedTargets = actions
            .filter { humanActorIds.contains($0.actorPlayerId) }
            .compactMap { $0.targetPlayerId }

        let leadersWithHumanVotes = leaders.keys.filter { humanVotedTargets.contains($0) }
        if leadersWithHumanVotes.count == 1 {
            print("🎯 [determineMajorityTarget] Tie broken by human vote priority")
            return leadersWithHumanVotes.first
        }

        // TIE-BREAKER 2: First vote wins (chronological)
        let leaderSet = Set(leaders.keys)
        let firstAction = actions
            .filter { action in
                guard let targetId = action.targetPlayerId else { return false }
                return leaderSet.contains(targetId)
            }
            .sorted { $0.createdAt < $1.createdAt }
            .first

        if let target = firstAction?.targetPlayerId {
            print("🎯 [determineMajorityTarget] Tie broken by first vote (chronological)")
            return target
        }

        // FINAL FALLBACK: Return any leader (should never reach here)
        print("⚠️ [determineMajorityTarget] Using final fallback - any leader")
        return leaders.keys.first ?? validTargets.first
    }

    /// Legacy wrapper for backward compatibility - returns nil on empty actions
    /// Use the new version with validTargets for guaranteed non-nil results
    private func determineMajorityTargetLegacy(from actions: [GameAction]) -> UUID? {
        return determineMajorityTarget(from: actions, validTargets: [])
    }

    @discardableResult
    private func applyEliminations(_ playerIds: [UUID], reason: String) async throws -> Bool {
        guard !playerIds.isEmpty else { return false }

        var hostEliminated = false

        for playerId in playerIds {
            guard let index = allPlayers.firstIndex(where: { $0.playerId == playerId }) else { continue }
            guard allPlayers[index].isAlive else { continue }

            var updatedPlayer = allPlayers[index]
            updatedPlayer.isAlive = false
            updatedPlayer.removalNote = reason
            allPlayers[index] = updatedPlayer
            eliminatedPlayerIds.insert(updatedPlayer.playerId)

            if let hostUserId = currentSession?.hostUserId,
               updatedPlayer.userId == hostUserId {
                hostEliminated = true
            }

            try await sessionService.updatePlayerLifeStatus(
                recordId: updatedPlayer.id,
                isAlive: false,
                removalNote: reason
            )
        }

        updateVisiblePlayers()
        return hostEliminated
    }

    private func transferHostIfNeeded(hostEliminated: Bool, session: GameSession) async {
        guard hostEliminated else { return }

        guard let newHostUserId = determineNextHostUserId(
            excluding: session.hostUserId,
            requireRecentHeartbeat: true
        ) else {
            print("⚠️ [MultiplayerGameStore] No eligible player to inherit host role for session \(session.id)")
            return
        }

        do {
            try await sessionService.updateSessionHost(sessionId: session.id, newHostUserId: newHostUserId)
            try? await refreshSession()
        } catch {
            print("❌ [MultiplayerGameStore] Failed to transfer host after elimination: \(error)")
        }
    }

    private func determineNextHostUserId(
        excluding currentHostId: UUID,
        requireRecentHeartbeat: Bool = false
    ) -> UUID? {
        let now = Date()

        let eligiblePlayers = allPlayers
            .filter { player in
                guard player.isAlive && !player.isBot else { return false }
                guard let userId = player.userId, userId != currentHostId else { return false }

                if requireRecentHeartbeat {
                    let timeSinceHeartbeat = now.timeIntervalSince(player.lastHeartbeat)
                    return timeSinceHeartbeat <= hostOfflineThreshold
                }

                return true
            }
            .sorted { $0.joinedAt < $1.joinedAt }

        for player in eligiblePlayers {
            if let userId = player.userId {
                return userId
            }
        }

        return nil
    }

    private func evaluateWinners(startOfDay: Bool) -> (winner: Role?, isGameOver: Bool) {
        let alivePlayers = allPlayers.filter { $0.isAlive }
        let mafiaCount = alivePlayers.filter { $0.role == .mafia }.count
        let nonMafiaCount = alivePlayers.filter { $0.role != .mafia }.count
        let aliveHumans = alivePlayers.filter { !$0.isBot }

        // Edge case: Everyone is dead - game ends with no winner
        if alivePlayers.isEmpty {
            print("🎮 [evaluateWinners] All players are dead - Game ends with no winner")
            return (winner: nil, isGameOver: true)
        }

        // HAMZA-167: End game when all humans die or leave (no point playing with just bots)
        // Determine winner based on remaining bot composition
        if aliveHumans.isEmpty {
            if mafiaCount == 0 {
                print("🎮 [evaluateWinners] All humans gone, no mafia bots remain - Citizens win")
                return (winner: .citizen, isGameOver: true)
            } else {
                print("🎮 [evaluateWinners] All humans gone, mafia bots remain - Mafia wins")
                return (winner: .mafia, isGameOver: true)
            }
        }

        // Citizens win: All mafia eliminated (humans or bots)
        if mafiaCount == 0 {
            return (winner: .citizen, isGameOver: true)
        }

        // Mafia wins: All non-mafia eliminated (humans or bots)
        if nonMafiaCount == 0 {
            return (winner: .mafia, isGameOver: true)
        }

        return (winner: nil, isGameOver: false)
    }

    private func scheduleAutoAdvance(for phaseData: PhaseData?) {
        pendingAutoAdvanceTask?.cancel()
        pendingAutoAdvanceTask = nil
        
        // Automatic advancement is disabled per user request
        // Host must manually advance phases
    }

    func advanceToDeathRevealManual(nightIndex: Int) async throws {
        guard isHost else { throw SessionError.notHost }
        try await advanceToDeathReveal(nightIndex: nightIndex)
    }
    
    func advanceToVotingManual(nightIndex: Int) async throws {
        guard isHost else { throw SessionError.notHost }
        try await advanceToVoting(afterNightIndex: nightIndex)
    }

    private func advanceToDeathRevealIfStillOn(nightIndex: Int) async {
        guard isHost else { return }
        guard case .morning(let currentIndex)? = currentSession?.currentPhaseData,
              currentIndex == nightIndex else { return }

        do {
            try await advanceToDeathReveal(nightIndex: nightIndex)
        } catch {
            print("❌ [MultiplayerGameStore] Failed to advance to death reveal: \(error)")
        }
    }

    private func advanceToVotingIfStillOn(nightIndex: Int) async {
        guard isHost else { return }
        guard case .deathReveal(let currentIndex)? = currentSession?.currentPhaseData,
              currentIndex == nightIndex else { return }

        do {
            try await advanceToVoting(afterNightIndex: nightIndex)
        } catch {
            print("❌ [MultiplayerGameStore] Failed to advance to voting: \(error)")
        }
    }

    private func advanceToDeathReveal(nightIndex: Int) async throws {
        guard let session = currentSession, !session.isGameOver else { return }
        try await sessionService.updateSessionState(
            sessionId: session.id,
            currentPhase: "death_reveal",
            phaseData: .deathReveal(nightIndex: nightIndex)
        )
    }

    private func advanceToVoting(afterNightIndex nightIndex: Int) async throws {
        guard let session = currentSession, !session.isGameOver else { return }
        let dayIndex = session.dayIndex
        try await sessionService.updateSessionState(
            sessionId: session.id,
            currentPhase: "voting",
            phaseData: .voting(dayIndex: dayIndex)
        )

        // HAMZA-FIX: Call handlePhaseEntry synchronously to ensure bot voting triggers immediately
        // Don't rely on Realtime event which can be delayed or lost
        print("🗳️ [advanceToVoting] Phase updated, calling handlePhaseEntry directly for day \(dayIndex)")
        await handlePhaseEntry(for: .voting(dayIndex: dayIndex))
    }

    // MARK: - Bot Actions (Host Only)

    /// Process bot actions for current phase
    /// HAMZA-FIX: Bots now follow humans - only process independently if no humans have that role
    func processBotActions(nightIndex: Int) async throws {
        guard isHost else { return }
        guard let session = currentSession else { return }

        // Clear tracking for this new night phase
        clearBotNightActionsForNewNight()

        let aliveBots = allPlayers.filter { $0.isBot && $0.isAlive }
        guard !aliveBots.isEmpty else { return }

        let alivePlayersList = allPlayers.filter { $0.isAlive }
        let localAlivePlayers = alivePlayersList.map { makeLocalPlayer(from: $0) }
        let nightHistory = convertNightHistoryToLocalModel(session.nightHistory)

        // Group bots by role to process each role's coordination separately
        let mafiaBots = aliveBots.filter { $0.role == .mafia }
        let doctorBots = aliveBots.filter { $0.role == .doctor }
        let inspectorBots = aliveBots.filter { $0.role == .inspector }

        // MAFIA: Only process independently if NO human Mafia
        if !mafiaBots.isEmpty && !hasHumanWithRole(.mafia) {
            // No human Mafia - bots vote independently but coordinated with each other
            let sharedMafiaTarget = botService.chooseCoordinatedMafiaTarget(
                mafiaBots: mafiaBots.map { makeLocalPlayer(from: $0) },
                alivePlayers: localAlivePlayers,
                nightHistory: nightHistory
            )
            for bot in mafiaBots {
                let targetId = sharedMafiaTarget ?? botService.chooseMafiaTarget(
                    botPlayer: makeLocalPlayer(from: bot),
                    alivePlayers: localAlivePlayers,
                    nightHistory: nightHistory
                )
                try await submitBotActionAndTrack(bot: bot, actionType: .mafiaTarget, nightIndex: nightIndex, targetId: targetId)
            }
            print("🤖 [processBotActions] Mafia bots voted independently (no human Mafia)")
        } else if !mafiaBots.isEmpty {
            print("🤖 [processBotActions] Mafia bots waiting for human vote via Realtime")
        }

        // DOCTOR: Only process independently if NO human Doctor
        if !doctorBots.isEmpty && !hasHumanWithRole(.doctor) {
            for bot in doctorBots {
                let targetId = botService.chooseDoctorProtection(
                    botPlayer: makeLocalPlayer(from: bot),
                    alivePlayers: localAlivePlayers,
                    nightHistory: nightHistory
                )
                try await submitBotActionAndTrack(bot: bot, actionType: .doctorProtect, nightIndex: nightIndex, targetId: targetId)
            }
            print("🤖 [processBotActions] Doctor bots voted independently (no human Doctor)")
        } else if !doctorBots.isEmpty {
            print("🤖 [processBotActions] Doctor bots waiting for human vote via Realtime")
        }

        // INSPECTOR: Only process independently if NO human Inspector
        if !inspectorBots.isEmpty && !hasHumanWithRole(.inspector) {
            for bot in inspectorBots {
                let targetId = botService.chooseInspectorTarget(
                    botPlayer: makeLocalPlayer(from: bot),
                    alivePlayers: localAlivePlayers,
                    nightHistory: nightHistory
                )
                try await submitBotActionAndTrack(bot: bot, actionType: .inspectorCheck, nightIndex: nightIndex, targetId: targetId)
            }
            print("🤖 [processBotActions] Inspector bots voted independently (no human Inspector)")
        } else if !inspectorBots.isEmpty {
            print("🤖 [processBotActions] Inspector bots waiting for human vote via Realtime")
        }
    }

    /// Helper to submit bot action and track it
    private func submitBotActionAndTrack(bot: SessionPlayer, actionType: ActionType, nightIndex: Int, targetId: UUID?) async throws {
        do {
            try await submitBotAction(
                botPlayerId: bot.playerId,
                actionType: actionType,
                nightIndex: nightIndex,
                targetPlayerId: targetId
            )
            botNightActionsSubmitted.insert(bot.playerId)
        } catch {
            print("❌ [processBotActions] Failed to submit action for \(bot.playerName): \(error)")
            // Continue processing other bots even if one fails
        }
    }

    /// Process bot votes during the day phase
    /// HAMZA-149: Bots must always vote every day (no abstaining)
    func processBotVotes(dayIndex: Int) async throws {
        guard isHost else { return }
        guard let session = currentSession else { return }

        // HAMZA-FIX: Recursion guard - prevent multiple concurrent bot voting attempts
        guard !isProcessingBotVotes else {
            print("🤖 [processBotVotes] Already processing bot votes, skipping duplicate call")
            return
        }
        isProcessingBotVotes = true
        defer { isProcessingBotVotes = false }

        let aliveBots = allPlayers.filter { $0.isBot && $0.isAlive }
        guard !aliveBots.isEmpty else { return }

        let alivePlayers = allPlayers.filter { $0.isAlive }.map { makeLocalPlayer(from: $0) }
        let nightHistory = convertNightHistoryToLocalModel(session.nightHistory)
        let dayHistory = convertDayHistoryToLocalModel(session.dayHistory)

        // Skip bots that already have VALID votes (non-nil target) - supports retries without double-submitting
        // HAMZA-FIX: Only count votes with non-nil targets as valid
        let initialExistingVotes = await loadActionsSafely(
            sessionId: session.id,
            actionType: .vote,
            phaseIndex: dayIndex,
            roundId: session.currentRoundId
        )
        let botsWithValidVotes = Set(initialExistingVotes.filter { $0.targetPlayerId != nil }.map { $0.actorPlayerId })
        print("🤖 [processBotVotes] \(botsWithValidVotes.count) bots already have valid votes")

        // Get valid vote targets (alive players excluding current bot)
        let validTargetIds = alivePlayers.filter { $0.alive }.map { $0.id }

        var failedBots: [String] = []

        for bot in aliveBots where !botsWithValidVotes.contains(bot.playerId) {
            let botPlayer = makeLocalPlayer(from: bot)
            // HAMZA-FIX: chooseVotingTarget now returns non-optional UUID (always votes)
            let targetId = botService.chooseVotingTarget(
                botPlayer: botPlayer,
                alivePlayers: alivePlayers,
                nightHistory: nightHistory,
                dayHistory: dayHistory
            )

            do {
                try await submitBotVote(
                    botPlayerId: bot.playerId,
                    dayIndex: dayIndex,
                    targetPlayerId: targetId
                )
            } catch {
                // Log but continue with other bots
                print("⚠️ [processBotVotes] Bot \(bot.playerName) failed to vote: \(error)")
                failedBots.append(bot.playerName)
            }
        }

        // Second pass: ensure every bot has a recorded VALID vote (no abstaining allowed)
        // HAMZA-FIX: Only count votes with non-nil targets
        let postFirstPassVotes = await loadActionsSafely(
            sessionId: session.id,
            actionType: .vote,
            phaseIndex: dayIndex,
            roundId: session.currentRoundId
        )

        let botsMissingValidVotes = aliveBots.filter { bot in
            !postFirstPassVotes.contains { $0.actorPlayerId == bot.playerId && $0.targetPlayerId != nil }
        }
        print("🤖 [processBotVotes] Second pass: \(botsMissingValidVotes.count) bots still need valid votes")

        for bot in botsMissingValidVotes {
            let fallbackTargets = validTargetIds.filter { $0 != bot.playerId }
            // HAMZA-FIX: Always force a target; self-vote as last resort to ensure a ballot exists
            let fallbackTarget = fallbackTargets.randomElement() ?? validTargetIds.first ?? bot.playerId
            print("🤖 [processBotVotes] Retry: \(bot.playerName) voting for fallback target")

            do {
                try await submitBotVote(
                    botPlayerId: bot.playerId,
                    dayIndex: dayIndex,
                    targetPlayerId: fallbackTarget
                )
            } catch {
                print("⚠️ [processBotVotes] Bot \(bot.playerName) retry vote failed: \(error)")
                failedBots.append(bot.playerName)
            }
        }

        // HAMZA-FIX: Always verify all bots have VALID votes (mandatory voting, non-nil targets)
        let refreshedVotes = await loadActionsSafely(
            sessionId: session.id,
            actionType: .vote,
            phaseIndex: dayIndex,
            roundId: session.currentRoundId
        )

        let stillMissingBots = aliveBots.filter { bot in
            !refreshedVotes.contains { $0.actorPlayerId == bot.playerId && $0.targetPlayerId != nil }
        }

        if !stillMissingBots.isEmpty {
            let names = stillMissingBots.map { $0.playerName }.joined(separator: ", ")
            print("❌ [processBotVotes] STILL missing valid bot votes after retries: \(names)")
            // Throw to allow re-processing on next phase entry and keep host blocked from advancing
            throw NSError(domain: "BotVoting", code: -3, userInfo: [NSLocalizedDescriptionKey: "Missing bot votes: \(names)"])
        } else {
            print("✅ [processBotVotes] All \(aliveBots.count) bots have valid votes")
        }

        // Throw only if ALL bots failed (so we can retry)
        if failedBots.count == aliveBots.count {
            throw NSError(domain: "BotVoting", code: -1, userInfo: [NSLocalizedDescriptionKey: "All bot votes failed"])
        }
    }

    private func submitBotAction(
        botPlayerId: UUID,
        actionType: ActionType,
        nightIndex: Int,
        targetPlayerId: UUID?
    ) async throws {
        guard let session = currentSession else { return }

        // FIX: Use resolved round ID instead of fallback to prevent orphan actions
        // when Realtime hasn't propagated currentRoundId yet (same fix as submitVote)
        let roundId = try await resolvedRoundId()

        let action: GameAction

        switch actionType {
        case .mafiaTarget:
            action = .mafiaAction(
                sessionId: session.id,
                roundId: roundId,
                nightIndex: nightIndex,
                actorPlayerId: botPlayerId,
                targetPlayerId: targetPlayerId
            )
        case .inspectorCheck:
            // No local logic - handled by server RPC
            action = .inspectorAction(
                sessionId: session.id,
                roundId: roundId,
                nightIndex: nightIndex,
                actorPlayerId: botPlayerId,
                targetPlayerId: targetPlayerId,
                result: nil // Result will be populated by server
            )
        case .doctorProtect:
            action = .doctorAction(
                sessionId: session.id,
                roundId: roundId,
                nightIndex: nightIndex,
                actorPlayerId: botPlayerId,
                targetPlayerId: targetPlayerId
            )
        case .vote:
            return
        }

        do {
            try await sessionService.submitAction(action)
        } catch let error as DecodingError {
            // Response parsing failed, but action was likely submitted successfully
            // Don't throw - allow bot processing to continue
        } catch {
            // Re-throw other errors (network, auth, etc.)
            throw error
        }
    }

    /// HAMZA-FIX: targetPlayerId is now required (non-optional) - bots MUST always vote for someone
    private func submitBotVote(
        botPlayerId: UUID,
        dayIndex: Int,
        targetPlayerId: UUID
    ) async throws {
        guard let session = currentSession else { return }

        // HAMZA-FIX: Use resolved round ID instead of fallback to prevent orphan votes
        let roundId = try await resolvedRoundId()

        let action = GameAction.voteAction(
            sessionId: session.id,
            roundId: roundId,
            dayIndex: dayIndex,
            actorPlayerId: botPlayerId,
            targetPlayerId: targetPlayerId
        )

        do {
            try await sessionService.submitAction(action)
        } catch let error as DecodingError {
            // Response parsing failed, but action was likely submitted successfully
            print("⚠️ [submitBotVote] Response decoding failed (action likely submitted): \(error)")
            // Don't throw - allow bot processing to continue
        } catch {
            // Re-throw other errors (network, auth, etc.)
            throw error
        }
    }

    private func convertNightHistoryToLocalModel(_ history: [NightActionRecord]) -> [NightAction] {
        history.map { record in
            var action = NightAction(
                nightIndex: record.nightIndex,
                mafiaTargetPlayerID: record.mafiaTargetId,
                inspectorCheckedPlayerID: record.inspectorCheckedId,
                inspectorResultIsMafia: nil,
                inspectorResultRole: nil,
                doctorProtectedPlayerID: record.doctorProtectedId,
                resultingDeaths: record.resultingDeaths,
                mafiaNumbers: record.mafiaPlayerNumbers,
                isResolved: true,
                aliveMafiaIDs: nil,
                mafiaPhaseCompleted: true,
                inspectorPhaseCompleted: true,
                doctorPhaseCompleted: true
            )

            if let result = record.inspectorResult {
                switch result {
                case "mafia":
                    action.inspectorResultIsMafia = true
                    action.inspectorResultRole = .mafia
                case "not_mafia":
                    action.inspectorResultIsMafia = false
                    action.inspectorResultRole = .citizen
                case "blocked":
                    action.inspectorResultIsMafia = nil
                    action.inspectorResultRole = .inspector
                default:
                    break
                }
            }

            return action
        }
    }

    private func convertDayHistoryToLocalModel(_ history: [DayActionRecord]) -> [DayAction] {
        history.map { record in
            DayAction(dayIndex: record.dayIndex, removedPlayerIDs: record.removedPlayerIds)
        }
    }

    private func makeLocalPlayer(from sessionPlayer: SessionPlayer) -> Player {
        Player(
            id: sessionPlayer.playerId,
            number: sessionPlayer.playerNumber ?? 0,
            name: sessionPlayer.playerName,
            role: sessionPlayer.role ?? .citizen,
            alive: sessionPlayer.isAlive,
            isBot: sessionPlayer.isBot,
            removalNote: sessionPlayer.removalNote
        )
    }

    // MARK: - Error Mapping

    /// Maps raw errors to user-friendly messages, following AuthStore.mapAuthError() pattern
    private func mapSessionError(_ error: Error) -> String {
        // 1. Handle known error types with LocalizedError descriptions
        if let sessionError = error as? SessionError {
            return sessionError.errorDescription ?? "Session error occurred"
        }
        if let realtimeError = error as? RealtimeError {
            return realtimeError.errorDescription ?? "Connection error occurred"
        }

        // 2. Network errors
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "Network error. Please check your internet connection."
        }

        // 3. Extract and map Supabase/PostgREST errors
        if let message = extractSupabaseMessage(from: nsError) {
            let normalized = message.lowercased()

            if normalized.contains("jwt expired") || normalized.contains("token expired") {
                return "Your session has expired. Please sign in again."
            }
            if normalized.contains("not found") || normalized.contains("does not exist") {
                return "Game session not found. It may have ended."
            }
            if normalized.contains("connection refused") || normalized.contains("pgrst") {
                return "Unable to connect to game server. Please try again."
            }
            if normalized.contains("permission denied") || normalized.contains("rls") {
                return "You don't have permission to perform this action."
            }
            if normalized.contains("duplicate") || normalized.contains("unique") {
                return "You're already in this session."
            }
        }

        // 4. Generic fallback
        return "Connection error. Please check your internet and try again."
    }

    /// Extracts Supabase error messages from NSError userInfo
    private func extractSupabaseMessage(from error: NSError) -> String? {
        // Check various NSError userInfo locations for Supabase messages
        if let message = error.userInfo["error_description"] as? String, !message.isEmpty {
            return message
        }
        if let message = error.userInfo[NSLocalizedDescriptionKey] as? String, !message.isEmpty {
            return message
        }
        return nil
    }

    // MARK: - Cleanup

    // PERF: Ensure all timers and tasks are cleaned up to prevent memory leaks
    deinit {
        // Capture timer references directly before self is deallocated
        // Timer.invalidate() is thread-safe, so we can call it synchronously
        let heartbeat = heartbeatTimer
        let playerRefresh = playerRefreshTimer
        let hostMonitor = hostMonitorTimer
        let rematch = rematchTimer
        let autoAdvance = pendingAutoAdvanceTask
        let combineSubscription = reconnectingSubscription
        let lifecycleObservers = appLifecycleObservers

        // Invalidate timers synchronously
        heartbeat?.invalidate()
        playerRefresh?.invalidate()
        hostMonitor?.invalidate()
        rematch?.invalidate()

        // Cancel pending tasks and subscriptions
        autoAdvance?.cancel()
        combineSubscription?.cancel()

        // Remove app lifecycle notification observers
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }

        // Schedule realtime service cleanup on MainActor
        // (can't directly access @MainActor properties from deinit)
        // Use Task.detached to avoid MainActor requirement in deinit
        let service = realtimeService
        Task.detached { @MainActor in
            service.onDisconnect = nil
            // unsubscribeAll() now cancels reconnectTask internally
            await service.unsubscribeAll()
        }

        print("🧹 [MultiplayerGameStore] deinit - cleaned up timers, tasks, scheduled realtime cleanup")
    }
}
