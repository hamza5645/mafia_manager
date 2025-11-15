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
            for i in 1...botCount {
                _ = try await sessionService.addPlayer(
                    sessionId: session.id,
                    userId: nil,
                    playerName: "Bot \(i)",
                    isBot: true
                )
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
        try await realtimeService.subscribeToSession(
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
                    self?.handleActionUpdate(action)
                }
            }
        )
    }

    private func handleSessionUpdate(_ session: GameSession) {
        currentSession = session

        // Update timer if phase changed
        if session.currentPhase != currentSession?.currentPhase {
            Task {
                try? await refreshActiveTimer()
            }
        }
    }

    private func handlePlayerUpdate(_ player: SessionPlayer) {
        if let index = allPlayers.firstIndex(where: { $0.id == player.id }) {
            allPlayers[index] = player
        } else {
            allPlayers.append(player)
        }

        // Update my player if it's me
        if player.id == myPlayer?.id {
            myPlayer = player
            myRole = player.role
            myNumber = player.playerNumber
        }

        updateVisiblePlayers()
    }

    private func handleActionUpdate(_ action: GameAction) {
        // Handle action updates (e.g., voting progress, night actions)
        // This can trigger UI updates for action confirmation
        print("Action received: \(action.actionType.rawValue) for phase \(action.phaseIndex)")
    }

    // MARK: - Player Management

    private func refreshPlayers() async throws {
        guard let sessionId = currentSession?.id else { return }

        allPlayers = try await sessionService.getSessionPlayers(sessionId: sessionId)

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

    // MARK: - Game Flow (Host Only)

    /// Start the game (host only)
    func startGame() async throws {
        guard isHost, let session = currentSession else {
            throw SessionError.notHost
        }

        // Ensure we have enough players
        let humanPlayers = allPlayers.filter { !$0.isBot }
        let totalPlayers = allPlayers.count

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
        try await sessionService.updateSessionPhase(
            sessionId: session.id,
            currentPhase: "role_reveal",
            phaseData: .roleReveal(currentPlayerIndex: 0)
        )

        // Refresh local state
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

        activeTimer = try await sessionService.getActiveTimer(sessionId: sessionId)

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
                    nightHistory: [],
                    dayHistory: []
                )
            case .doctor:
                targetId = botService.chooseDoctorTarget(
                    botPlayer: botAsPlayer,
                    alivePlayers: alivePlayers
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
        stopHeartbeat()
        stopTimerAutoRefresh()
    }
}

// Add roleDistribution as static method to GameStore so we can access it
extension GameStore {
    static func roleDistribution(for playerCount: Int) -> (mafia: Int, doctors: Int, inspectors: Int) {
        let p = min(max(playerCount, 4), 19)
        switch p {
        case 4:
            return (mafia: 1, doctors: 0, inspectors: 1)
        case 5:
            return (mafia: 1, doctors: 0, inspectors: 1)
        case 6...8:
            return (mafia: 2, doctors: 1, inspectors: 1)
        case 9...14:
            return (mafia: 4, doctors: 1, inspectors: 2)
        default: // 15...19
            return (mafia: 5, doctors: 2, inspectors: 2)
        }
    }
}
