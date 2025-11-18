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

    // Current phase timer
    @Published var activeTimer: PhaseTimer?

    // Heartbeat timer
    private var heartbeatTimer: Timer?
    private var timerUpdateTimer: Timer?
    private var playerRefreshTimer: Timer?

    // Auth store reference
    private weak var authStore: AuthStore?

    func setAuthStore(_ authStore: AuthStore) {
        self.authStore = authStore
    }

    // MARK: - Session Lifecycle

    /// Create a new multiplayer session
    func createSession(
        playerName: String,
        botCount: Int = 0,
        nightTimerSeconds: Int = 60,
        dayTimerSeconds: Int = 180
    ) async throws {
        guard let userId = authStore?.currentUserId else {
            throw SessionError.notHost
        }

        isConnecting = true
        connectionError = nil

        do {
            // Create session
            let session = try await sessionService.createSession(
                hostUserId: userId,
                maxPlayers: 19,
                botCount: botCount,
                nightTimerSeconds: nightTimerSeconds,
                dayTimerSeconds: dayTimerSeconds
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

            // Subscribe to real-time updates
            try await subscribeToSession(sessionId: session.id)

            // Start heartbeat
            startHeartbeat()

            // Refresh players
            try await refreshPlayers()
            
            // Start periodic player refresh (fallback for missed real-time events)
            startPlayerRefreshTimer()

            isConnecting = false
        } catch {
            isConnecting = false
            connectionError = error.localizedDescription
            throw error
        }
    }

    /// Join an existing session
    func joinSession(roomCode: String, playerName: String) async throws {
        guard let userId = authStore?.currentUserId else {
            throw SessionError.notHost
        }

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

            // Subscribe to real-time updates
            try await subscribeToSession(sessionId: session.id)

            // Start heartbeat
            startHeartbeat()

            // Refresh players
            try await refreshPlayers()
            
            // Start periodic player refresh (fallback for missed real-time events)
            startPlayerRefreshTimer()

            isConnecting = false
        } catch {
            isConnecting = false
            connectionError = error.localizedDescription
            throw error
        }
    }

    /// Leave the current session
    func leaveSession() async throws {
        guard let sessionId = currentSession?.id,
              let userId = authStore?.currentUserId else {
            return
        }

        stopHeartbeat()
        stopPlayerRefreshTimer()
        await realtimeService.unsubscribeAll()

        try await sessionService.leaveSession(sessionId: sessionId, userId: userId)

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
        activeTimer = nil
    }

    // MARK: - Real-time Subscriptions

    private func subscribeToSession(sessionId: UUID) async throws {
        print("🔔 [MultiplayerGameStore] Subscribing to session: \(sessionId)")
        try await realtimeService.subscribeToSession(
            sessionId: sessionId,
            onSessionUpdate: { [weak self] session in
                Task { @MainActor in
                    print("📨 [MultiplayerGameStore] Session update received")
                    self?.handleSessionUpdate(session)
                }
            },
            onPlayerUpdate: { [weak self] player in
                Task { @MainActor in
                    print("📨 [MultiplayerGameStore] Player update received via callback")
                    self?.handlePlayerUpdate(player)
                }
            },
            onActionUpdate: { [weak self] action in
                Task { @MainActor in
                    self?.handleActionUpdate(action)
                }
            }
        )
        print("✅ [MultiplayerGameStore] Successfully subscribed to session updates")
    }

    private func handleSessionUpdate(_ session: GameSession) {
        let previousPhase = currentSession?.currentPhase
        currentSession = session

        // Update timer if phase changed
        if session.currentPhase != previousPhase {
            Task {
                try? await refreshActiveTimer()
            }
        }
    }

    private func handlePlayerUpdate(_ player: SessionPlayer) {
        print("📥 [MultiplayerGameStore] handlePlayerUpdate called for player: \(player.playerName) (ID: \(player.id))")
        
        if let index = allPlayers.firstIndex(where: { $0.id == player.id }) {
            print("🔄 [MultiplayerGameStore] Updating existing player at index \(index)")
            allPlayers[index] = player
        } else {
            print("➕ [MultiplayerGameStore] Adding new player to list (current count: \(allPlayers.count))")
            allPlayers.append(player)
        }

        // Update my player if it's me
        if player.id == myPlayer?.id {
            myPlayer = player
            myRole = player.role
            myNumber = player.playerNumber
        }

        print("👥 [MultiplayerGameStore] Total players after update: \(allPlayers.count)")
        updateVisiblePlayers()
        print("👁️ [MultiplayerGameStore] Visible players count: \(visiblePlayers.count)")
    }
    
    /// Handle player removal (called when a player leaves)
    private func handlePlayerRemoval(playerId: UUID) {
        print("🗑️ [MultiplayerGameStore] Player removed: \(playerId)")
        allPlayers.removeAll(where: { $0.id == playerId })
        
        // If it was me, clear my player state
        if playerId == myPlayer?.id {
            myPlayer = nil
            myRole = nil
            myNumber = nil
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
        print("Action received: \(action.actionType.rawValue) for phase \(action.phaseIndex)")
    }

    // MARK: - Player Management

    private func refreshSession() async throws {
        guard let sessionId = currentSession?.id else { return }
        
        if let latestSession = try await sessionService.getSession(sessionId: sessionId) {
            currentSession = latestSession
        }
    }
    
    private func refreshPlayers() async throws {
        guard let sessionId = currentSession?.id else { return }

        let players = try await sessionService.getSessionPlayers(sessionId: sessionId)
        guard sessionId == currentSession?.id else { return } // Session changed; drop stale data.

        allPlayers = players

        // Find my player
        if let userId = authStore?.currentUserId {
            myPlayer = allPlayers.first(where: { $0.userId == userId })
            myRole = myPlayer?.role
            myNumber = myPlayer?.playerNumber
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
    
    /// Mark that player has seen their role
    func markRoleAsSeen() async throws {
        guard let playerId = myPlayer?.id else { return }
        
        print("🎭 [MultiplayerGameStore] Player marking role as seen")
        
        // Mark player as having seen their role by setting ready status
        try await sessionService.updatePlayerReady(playerId: playerId, isReady: true)
        
        // Update optimistically
        myPlayer?.isReady = true
        
        // If host and all players have seen their roles, advance to night phase
        if isHost {
            // Refresh to get latest ready states
            try await refreshPlayers()
            
            let allPlayersReady = allPlayers.allSatisfy { $0.isReady }
            
            if allPlayersReady {
                print("✅ [MultiplayerGameStore] All players have seen roles, advancing to night phase")
                
                guard let session = currentSession else { return }
                
                // Reset ready status for next phase
                for player in allPlayers {
                    try? await sessionService.updatePlayerReady(playerId: player.id, isReady: false)
                }
                
                // Advance to night phase
                try await sessionService.updateSessionPhase(
                    sessionId: session.id,
                    currentPhase: "night",
                    phaseData: .night(nightIndex: 0, activeRole: nil)
                )
                
                // Refresh to get updated phase
                try await refreshSession()
                try await refreshPlayers()
            } else {
                print("⏳ [MultiplayerGameStore] Waiting for other players to see their roles")
            }
        }
    }

    // MARK: - Game Flow (Host Only)

    /// Start the game (host only)
    func startGame() async throws {
        print("🎮 [MultiplayerGameStore] startGame() called")
        print("🎮 [MultiplayerGameStore] isHost: \(isHost)")
        print("🎮 [MultiplayerGameStore] currentSession: \(currentSession?.id.uuidString ?? "nil")")
        
        guard isHost, let session = currentSession else {
            print("❌ [MultiplayerGameStore] Not host or no session")
            throw SessionError.notHost
        }

        // Ensure we have enough players
        let humanPlayers = allPlayers.filter { !$0.isBot }
        let totalPlayers = allPlayers.count
        
        print("🎮 [MultiplayerGameStore] Total players: \(totalPlayers)")
        print("🎮 [MultiplayerGameStore] Human players: \(humanPlayers.count)")
        print("🎮 [MultiplayerGameStore] Bot players: \(totalPlayers - humanPlayers.count)")

        guard totalPlayers >= 4, totalPlayers <= 19 else {
            print("❌ [MultiplayerGameStore] Invalid player count: \(totalPlayers)")
            throw SessionError.invalidPhase
        }

        print("🎮 [MultiplayerGameStore] Assigning roles and numbers...")
        // Assign roles and numbers
        let playerNames = allPlayers.map { $0.playerName }
        let assignments = assignRolesAndNumbers(playerNames: playerNames)
        
        print("🎮 [MultiplayerGameStore] Assignments created: \(assignments.count)")

        print("🎮 [MultiplayerGameStore] Updating database with role assignments...")
        // Update database with assignments
        try await sessionService.assignRolesAndNumbers(
            sessionId: session.id,
            assignments: assignments
        )
        print("✅ [MultiplayerGameStore] Roles assigned in database")

        print("🎮 [MultiplayerGameStore] Updating session status to inProgress...")
        // Update session status and phase
        try await sessionService.updateSessionStatus(sessionId: session.id, status: .inProgress)
        print("✅ [MultiplayerGameStore] Session status updated")
        
        print("🎮 [MultiplayerGameStore] Updating phase to role_reveal...")
        try await sessionService.updateSessionPhase(
            sessionId: session.id,
            currentPhase: "role_reveal",
            phaseData: .roleReveal(currentPlayerIndex: 0)
        )
        print("✅ [MultiplayerGameStore] Phase updated to role_reveal")

        print("🎮 [MultiplayerGameStore] Refreshing local player state...")
        // Refresh local state
        try await refreshSession()
        try await refreshPlayers()
        print("✅ [MultiplayerGameStore] Game started successfully!")
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
    func submitNightAction(
        actionType: ActionType,
        nightIndex: Int,
        targetPlayerId: UUID?
    ) async throws {
        guard let session = currentSession,
              let myPlayerId = myPlayer?.playerId else {
            return
        }

        let action: GameAction

        switch actionType {
        case .mafiaTarget:
            action = .mafiaAction(
                sessionId: session.id,
                nightIndex: nightIndex,
                actorPlayerId: myPlayerId,
                targetPlayerId: targetPlayerId
            )
        case .inspectorCheck:
            // Calculate result
            var result: String?
            if let targetId = targetPlayerId,
               let target = allPlayers.first(where: { $0.playerId == targetId }) {
                if target.role == .inspector {
                    result = "blocked"
                } else if target.role == .mafia {
                    result = "mafia"
                } else {
                    result = "not_mafia"
                }
            }

            action = .inspectorAction(
                sessionId: session.id,
                nightIndex: nightIndex,
                actorPlayerId: myPlayerId,
                targetPlayerId: targetPlayerId,
                result: result
            )
        case .doctorProtect:
            action = .doctorAction(
                sessionId: session.id,
                nightIndex: nightIndex,
                actorPlayerId: myPlayerId,
                targetPlayerId: targetPlayerId
            )
        case .vote:
            // Voting handled separately
            return
        }

        try await sessionService.submitAction(action)
    }

    /// Submit a vote
    func submitVote(dayIndex: Int, targetPlayerId: UUID?) async throws {
        guard let session = currentSession,
              let myPlayerId = myPlayer?.playerId else {
            return
        }

        let action = GameAction.voteAction(
            sessionId: session.id,
            dayIndex: dayIndex,
            actorPlayerId: myPlayerId,
            targetPlayerId: targetPlayerId
        )

        try await sessionService.submitAction(action)
    }

    // MARK: - Timer Management

    private func refreshActiveTimer() async throws {
        guard let sessionId = currentSession?.id else { return }

        let timer = try await sessionService.getActiveTimer(sessionId: sessionId)
        guard sessionId == currentSession?.id else { return }

        activeTimer = timer

        // Start auto-refresh timer
        startTimerAutoRefresh()
    }

    private func startTimerAutoRefresh() {
        timerUpdateTimer?.invalidate()
        timerUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.objectWillChange.send() // Trigger UI refresh
            }
        }
    }

    private func stopTimerAutoRefresh() {
        timerUpdateTimer?.invalidate()
        timerUpdateTimer = nil
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
    
    // MARK: - Player Refresh Timer
    
    /// Start periodic refresh of players list (fallback for missed real-time events)
    private func startPlayerRefreshTimer() {
        stopPlayerRefreshTimer()
        
        // Refresh every 3 seconds as a fallback
        playerRefreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isInSession else { return }
                // Only refresh if we're in the lobby phase
                if self.currentSession?.currentPhase == "lobby" {
                    print("🔄 [MultiplayerGameStore] Periodic player refresh triggered")
                    try? await self.refreshSession()
                    try? await self.refreshPlayers()
                }
            }
        }
    }
    
    private func stopPlayerRefreshTimer() {
        playerRefreshTimer?.invalidate()
        playerRefreshTimer = nil
    }

    // MARK: - Bot Actions (Host Only)

    /// Process bot actions for current phase
    func processBotActions(nightIndex: Int) async throws {
        guard isHost else { return }

        let aliveBots = allPlayers.filter { $0.isBot && $0.isAlive }

        for bot in aliveBots {
            guard let botRole = bot.role else { continue }

            let alivePlayersList = allPlayers.filter { $0.isAlive }
            let botAsPlayer = Player(
                id: bot.playerId,
                number: bot.playerNumber ?? 0,
                name: bot.playerName,
                role: botRole,
                alive: bot.isAlive,
                isBot: true,
                removalNote: nil
            )

            let alivePlayers = alivePlayersList.map { Player(
                id: $0.playerId,
                number: $0.playerNumber ?? 0,
                name: $0.playerName,
                role: $0.role ?? .citizen,
                alive: $0.isAlive,
                isBot: $0.isBot,
                removalNote: nil
            )}

            var targetId: UUID?

            switch botRole {
            case .mafia:
                targetId = botService.chooseMafiaTarget(
                    botPlayer: botAsPlayer,
                    alivePlayers: alivePlayers,
                    nightHistory: []
                )
            case .doctor:
                targetId = botService.chooseDoctorProtection(
                    botPlayer: botAsPlayer,
                    alivePlayers: alivePlayers,
                    nightHistory: []
                )
            case .inspector:
                targetId = botService.chooseInspectorTarget(
                    botPlayer: botAsPlayer,
                    alivePlayers: alivePlayers,
                    nightHistory: []
                )
            case .citizen:
                // Citizens don't have night actions
                continue
            }

            // Submit bot action
            let actionType: ActionType = switch botRole {
            case .mafia: .mafiaTarget
            case .doctor: .doctorProtect
            case .inspector: .inspectorCheck
            case .citizen: .vote // Not used for night
            }

            if actionType != .vote {
                try await submitBotAction(
                    botPlayerId: bot.playerId,
                    actionType: actionType,
                    nightIndex: nightIndex,
                    targetPlayerId: targetId
                )
            }
        }
    }

    private func submitBotAction(
        botPlayerId: UUID,
        actionType: ActionType,
        nightIndex: Int,
        targetPlayerId: UUID?
    ) async throws {
        guard let session = currentSession else { return }

        let action: GameAction

        switch actionType {
        case .mafiaTarget:
            action = .mafiaAction(
                sessionId: session.id,
                nightIndex: nightIndex,
                actorPlayerId: botPlayerId,
                targetPlayerId: targetPlayerId
            )
        case .inspectorCheck:
            var result: String?
            if let targetId = targetPlayerId,
               let target = allPlayers.first(where: { $0.playerId == targetId }) {
                result = (target.role == .mafia) ? "mafia" : "not_mafia"
            }

            action = .inspectorAction(
                sessionId: session.id,
                nightIndex: nightIndex,
                actorPlayerId: botPlayerId,
                targetPlayerId: targetPlayerId,
                result: result
            )
        case .doctorProtect:
            action = .doctorAction(
                sessionId: session.id,
                nightIndex: nightIndex,
                actorPlayerId: botPlayerId,
                targetPlayerId: targetPlayerId
            )
        case .vote:
            return
        }

        try await sessionService.submitAction(action)
    }

    // MARK: - Cleanup

    deinit {
        // Schedule cleanup on main thread since this is a @MainActor class
        DispatchQueue.main.async { [weak self] in
            self?.heartbeatTimer?.invalidate()
            self?.heartbeatTimer = nil
            self?.timerUpdateTimer?.invalidate()
            self?.timerUpdateTimer = nil
            self?.playerRefreshTimer?.invalidate()
            self?.playerRefreshTimer = nil
        }
    }
}
