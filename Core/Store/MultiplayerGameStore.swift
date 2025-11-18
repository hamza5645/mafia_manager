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
    private var pendingAutoAdvanceTask: Task<Void, Never>?
    private var processedBotNightIndices: Set<Int> = []
    private var processedBotVotingDays: Set<Int> = []
    private var isResolvingPhase = false

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
        let previousPhaseData = currentSession?.currentPhaseData
        currentSession = session

        // Update timer if phase changed
        if session.currentPhase != previousPhase {
            Task {
                try? await refreshActiveTimer()
            }
        }

        if session.currentPhaseData != previousPhaseData {
            scheduleAutoAdvance(for: session.currentPhaseData)
            if isHost {
                Task {
                    await self.handlePhaseEntry(for: session.currentPhaseData)
                }
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
        
        if isHost {
            Task {
                try? await self.advanceFromRoleRevealIfReady(forceRefresh: false)
            }
        }
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

        if isHost {
            Task {
                await self.evaluatePhaseProgression(trigger: "action_update")
            }
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
            try await advanceFromRoleRevealIfReady(forceRefresh: true)
        } else {
            // Non-host players: refresh session to check if phase changed
            // This ensures they see the phase update when host advances
            try await refreshSession()
        }
    }

    /// Host-only helper to advance to the first night once every player confirmed their role
    private func advanceFromRoleRevealIfReady(forceRefresh: Bool) async throws {
        guard isHost else { return }
        
        if forceRefresh {
            try await refreshPlayers()
        }
        
        guard currentSession?.currentPhase == "role_reveal" else { return }
        
        let readyCount = allPlayers.filter { $0.isReady }.count
        let totalCount = allPlayers.count
        
        guard readyCount == totalCount else {
            print("⏳ [MultiplayerGameStore] Waiting for all players to confirm roles (\(readyCount)/\(totalCount))")
            return
        }
        
        print("✅ [MultiplayerGameStore] All players ready — advancing to night phase")
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
            // No local logic - handled by server RPC
            action = .inspectorAction(
                sessionId: session.id,
                nightIndex: nightIndex,
                actorPlayerId: myPlayerId,
                targetPlayerId: targetPlayerId,
                result: nil // Result will be populated by server
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
        
        // If I'm the host, immediately check if this action completes the phase
        // This avoids relying solely on the real-time event which might be delayed
        if isHost {
            print("👑 [MultiplayerGameStore] Host submitted action - evaluating phase progression")
            Task {
                // Small delay to ensure DB consistency
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                await self.evaluatePhaseProgression(trigger: "host_submission")
            }
        }
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
        
        // If I'm the host, immediately check if this action completes the phase
        if isHost {
            print("👑 [MultiplayerGameStore] Host submitted vote - evaluating phase progression")
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                await self.evaluatePhaseProgression(trigger: "host_vote")
            }
        }
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
        // Refresh for lobby and role_reveal phases to catch phase transitions
        playerRefreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isInSession else { return }
                let currentPhase = self.currentSession?.currentPhase ?? ""
                // Refresh periodically for ALL players to ensure phase synchronization
                // This is critical for clients who might miss the real-time phase change event
                // We only skip if we're not in a session at all
                let shouldRefresh = true

                if shouldRefresh {
                    print("🔄 [MultiplayerGameStore] Periodic refresh triggered (phase: \(currentPhase))")
                    try? await self.refreshSession()
                    try? await self.refreshPlayers()
                    
                    if self.isHost {
                        if currentPhase == "role_reveal" {
                            try? await self.advanceFromRoleRevealIfReady(forceRefresh: false)
                        } else if currentPhase == "night" || currentPhase == "voting" {
                            await self.evaluatePhaseProgression(trigger: "periodic_check")
                        }
                    }
                }
            }
        }
    }
    
    private func stopPlayerRefreshTimer() {
        playerRefreshTimer?.invalidate()
        playerRefreshTimer = nil
    }

    // MARK: - Phase Coordination

    private func handlePhaseEntry(for phaseData: PhaseData?) async {
        guard isHost else { return }
        guard let phaseData else { return }

        switch phaseData {
        case .night(let nightIndex, _):
            if !processedBotNightIndices.contains(nightIndex) {
                processedBotNightIndices.insert(nightIndex)
                do {
                    try await processBotActions(nightIndex: nightIndex)
                } catch {
                    print("❌ [MultiplayerGameStore] Failed to process bot night actions: \(error)")
                }
            }
            await evaluatePhaseProgression(trigger: "enter_night")
        case .voting(let dayIndex):
            if !processedBotVotingDays.contains(dayIndex) {
                processedBotVotingDays.insert(dayIndex)
                do {
                    try await processBotVotes(dayIndex: dayIndex)
                } catch {
                    print("❌ [MultiplayerGameStore] Failed to process bot votes: \(error)")
                }
            }
            await evaluatePhaseProgression(trigger: "enter_voting")
        default:
            break
        }
    }

    private func evaluatePhaseProgression(trigger: String) async {
        guard isHost, !isResolvingPhase else { return }
        guard let session = currentSession, let phaseData = session.currentPhaseData else { return }

        isResolvingPhase = true
        defer { isResolvingPhase = false }

        do {
            try await refreshPlayers()
            switch phaseData {
            case .night(let nightIndex, _):
                try await resolveNightIfReady(nightIndex: nightIndex)
            case .voting(let dayIndex):
                try await resolveVotingIfReady(dayIndex: dayIndex)
            default:
                break
            }
        } catch {
            print("❌ [MultiplayerGameStore] Failed to evaluate phase (\(trigger)): \(error)")
        }
    }

    private func resolveNightIfReady(nightIndex: Int) async throws {
        guard isHost else { return }
        guard case .night(let activeNightIndex, _) = currentSession?.currentPhaseData,
              activeNightIndex == nightIndex else {
            return
        }
        guard let session = currentSession else { return }

        let aliveMafia = allPlayers.filter { $0.isAlive && $0.role == .mafia }
        let aliveDoctors = allPlayers.filter { $0.isAlive && $0.role == .doctor }
        let aliveInspectors = allPlayers.filter { $0.isAlive && $0.role == .inspector }

        let mafiaActions = try await sessionService.getActionsForPhase(
            sessionId: session.id,
            actionType: .mafiaTarget,
            phaseIndex: nightIndex
        )
        let inspectorActions = try await sessionService.getActionsForPhase(
            sessionId: session.id,
            actionType: .inspectorCheck,
            phaseIndex: nightIndex
        )
        let doctorActions = try await sessionService.getActionsForPhase(
            sessionId: session.id,
            actionType: .doctorProtect,
            phaseIndex: nightIndex
        )

        func didEveryoneAct(requiredPlayers: [SessionPlayer], actions: [GameAction], roleName: String) -> Bool {
            guard !requiredPlayers.isEmpty else { return true }
            let actors = Set(actions.map { $0.actorPlayerId })
            let ready = actors.count >= requiredPlayers.count
            
            if !ready {
                let missingIds = requiredPlayers.filter { !actors.contains($0.playerId) }.map { $0.playerName }
                print("⏳ [MultiplayerGameStore] Waiting for \(roleName): Missing \(missingIds.joined(separator: ", "))")
            }
            
            return ready
        }

        let mafiaReady = didEveryoneAct(requiredPlayers: aliveMafia, actions: mafiaActions, roleName: "Mafia")
        let doctorReady = didEveryoneAct(requiredPlayers: aliveDoctors, actions: doctorActions, roleName: "Doctor")
        let inspectorReady = didEveryoneAct(requiredPlayers: aliveInspectors, actions: inspectorActions, roleName: "Inspector")

        guard mafiaReady && doctorReady && inspectorReady else {
            print("⏳ [MultiplayerGameStore] Night phase incomplete (Mafia: \(mafiaReady), Doc: \(doctorReady), Cop: \(inspectorReady))")
            return
        }

        let mafiaTargetId = determineMajorityTarget(from: mafiaActions)
        let doctorProtectionIds = Set(doctorActions.compactMap { $0.targetPlayerId })
        let targetWasSaved = mafiaTargetId.flatMap { doctorProtectionIds.contains($0) } ?? false
        let doctorProtectedId = targetWasSaved ? mafiaTargetId : doctorProtectionIds.first

        var resultingDeaths: [UUID] = []
        if let targetId = mafiaTargetId, !targetWasSaved {
            resultingDeaths = [targetId]
            try await applyEliminations(resultingDeaths, reason: "Eliminated at night")
        }

        let nightRecord = NightActionRecord(
            nightIndex: nightIndex,
            mafiaTargetId: mafiaTargetId,
            inspectorCheckedId: nil, // Sanitize: Private action
            inspectorResult: nil, // Sanitize: Private result
            doctorProtectedId: doctorProtectedId,
            resultingDeaths: resultingDeaths,
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

        try await sessionService.updateSessionState(
            sessionId: session.id,
            currentPhase: nextPhaseName,
            phaseData: nextPhaseData,
            nightHistory: updatedHistory,
            isGameOver: winnerCheck.isGameOver ? true : nil,
            winner: winnerCheck.winner
        )
    }

    private func resolveVotingIfReady(dayIndex: Int) async throws {
        guard isHost else { return }
        guard case .voting(let activeDayIndex) = currentSession?.currentPhaseData,
              activeDayIndex == dayIndex else {
            return
        }
        guard let session = currentSession else { return }

        let alivePlayers = allPlayers.filter { $0.isAlive }
        let votes = try await sessionService.getActionsForPhase(
            sessionId: session.id,
            actionType: .vote,
            phaseIndex: dayIndex
        )

        let uniqueVoters = Set(votes.map { $0.actorPlayerId })
        guard uniqueVoters.count >= alivePlayers.count else {
            print("⏳ [MultiplayerGameStore] Waiting for votes (\(uniqueVoters.count)/\(alivePlayers.count))")
            return
        }

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
        if let eliminated = eliminatedPlayerId {
            removedPlayerIds = [eliminated]
            try await applyEliminations(removedPlayerIds, reason: "Voted out")
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

        try await sessionService.updateSessionState(
            sessionId: session.id,
            currentPhase: nextPhaseName,
            phaseData: nextPhaseData,
            dayIndex: newDayIndex,
            dayHistory: updatedDayHistory,
            isGameOver: winnerCheck.isGameOver ? true : nil,
            winner: winnerCheck.winner
        )
    }

    private func determineMajorityTarget(from actions: [GameAction]) -> UUID? {
        var counts: [UUID: Int] = [:]
        for action in actions {
            guard let targetId = action.targetPlayerId else { continue }
            counts[targetId, default: 0] += 1
        }

        guard let maxVotes = counts.values.max(), maxVotes > 0 else {
            return nil
        }

        let leaders = counts.filter { $0.value == maxVotes }
        return leaders.count == 1 ? leaders.first?.key : nil
    }

    private func applyEliminations(_ playerIds: [UUID], reason: String) async throws {
        guard !playerIds.isEmpty else { return }

        for playerId in playerIds {
            guard let index = allPlayers.firstIndex(where: { $0.playerId == playerId }) else { continue }
            guard allPlayers[index].isAlive else { continue }

            var updatedPlayer = allPlayers[index]
            updatedPlayer.isAlive = false
            updatedPlayer.removalNote = reason
            allPlayers[index] = updatedPlayer

            try await sessionService.updatePlayerLifeStatus(
                recordId: updatedPlayer.id,
                isAlive: false,
                removalNote: reason
            )
        }

        updateVisiblePlayers()
    }

    private func evaluateWinners(startOfDay: Bool) -> (winner: Role?, isGameOver: Bool) {
        let mafiaCount = allPlayers.filter { $0.isAlive && $0.role == .mafia }.count
        let nonMafiaCount = allPlayers.filter { $0.isAlive && $0.role != .mafia }.count

        if mafiaCount == 0 {
            return (winner: .citizen, isGameOver: true)
        }

        if mafiaCount >= nonMafiaCount {
            if startOfDay || !startOfDay {
                return (winner: .mafia, isGameOver: true)
            }
        }

        return (winner: nil, isGameOver: false)
    }

    private func scheduleAutoAdvance(for phaseData: PhaseData?) {
        pendingAutoAdvanceTask?.cancel()
        pendingAutoAdvanceTask = nil

        guard isHost else { return }
        guard let phaseData else { return }

        switch phaseData {
        case .morning(let nightIndex):
            pendingAutoAdvanceTask = Task { [weak self] in
                // Give players time to read the summary (and clients time to sync)
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s
                await self?.advanceToDeathRevealIfStillOn(nightIndex: nightIndex)
            }
        case .deathReveal(let nightIndex):
            pendingAutoAdvanceTask = Task { [weak self] in
                // Give players time to see who died
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s
                await self?.advanceToVotingIfStillOn(nightIndex: nightIndex)
            }
        default:
            break
        }
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
        try await sessionService.updateSessionState(
            sessionId: session.id,
            currentPhase: "voting",
            phaseData: .voting(dayIndex: session.dayIndex)
        )
    }

    // MARK: - Bot Actions (Host Only)

    /// Process bot actions for current phase
    func processBotActions(nightIndex: Int) async throws {
        guard isHost else { return }
        guard let session = currentSession else { return }

        let aliveBots = allPlayers.filter { $0.isBot && $0.isAlive }
        guard !aliveBots.isEmpty else { return }

        let alivePlayersList = allPlayers.filter { $0.isAlive }
        let localAlivePlayers = alivePlayersList.map { makeLocalPlayer(from: $0) }
        let nightHistory = convertNightHistoryToLocalModel(session.nightHistory)

        for bot in aliveBots {
            guard let botRole = bot.role else { continue }

            let botAsPlayer = makeLocalPlayer(from: bot)

            var targetId: UUID?

            switch botRole {
            case .mafia:
                targetId = botService.chooseMafiaTarget(
                    botPlayer: botAsPlayer,
                    alivePlayers: localAlivePlayers,
                    nightHistory: nightHistory
                )
            case .doctor:
                targetId = botService.chooseDoctorProtection(
                    botPlayer: botAsPlayer,
                    alivePlayers: localAlivePlayers,
                    nightHistory: nightHistory
                )
            case .inspector:
                targetId = botService.chooseInspectorTarget(
                    botPlayer: botAsPlayer,
                    alivePlayers: localAlivePlayers,
                    nightHistory: nightHistory
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

    /// Process bot votes during the day phase
    func processBotVotes(dayIndex: Int) async throws {
        guard isHost else { return }
        guard let session = currentSession else { return }

        let aliveBots = allPlayers.filter { $0.isBot && $0.isAlive }
        guard !aliveBots.isEmpty else { return }

        let alivePlayers = allPlayers.filter { $0.isAlive }.map { makeLocalPlayer(from: $0) }
        let nightHistory = convertNightHistoryToLocalModel(session.nightHistory)
        let dayHistory = convertDayHistoryToLocalModel(session.dayHistory)

        for bot in aliveBots {
            let botPlayer = makeLocalPlayer(from: bot)
            let targetId = botService.chooseVotingTarget(
                botPlayer: botPlayer,
                alivePlayers: alivePlayers,
                nightHistory: nightHistory,
                dayHistory: dayHistory
            )

            try await submitBotVote(
                botPlayerId: bot.playerId,
                dayIndex: dayIndex,
                targetPlayerId: targetId
            )
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
            // No local logic - handled by server RPC
            action = .inspectorAction(
                sessionId: session.id,
                nightIndex: nightIndex,
                actorPlayerId: botPlayerId,
                targetPlayerId: targetPlayerId,
                result: nil // Result will be populated by server
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

    private func submitBotVote(
        botPlayerId: UUID,
        dayIndex: Int,
        targetPlayerId: UUID?
    ) async throws {
        guard let session = currentSession else { return }

        let action = GameAction.voteAction(
            sessionId: session.id,
            dayIndex: dayIndex,
            actorPlayerId: botPlayerId,
            targetPlayerId: targetPlayerId
        )

        try await sessionService.submitAction(action)
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
                mafiaNumbers: [],
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
            self?.pendingAutoAdvanceTask?.cancel()
            self?.pendingAutoAdvanceTask = nil
        }
    }
}
