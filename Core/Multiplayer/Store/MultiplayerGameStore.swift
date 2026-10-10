import Combine
import Foundation

/// Multiplayer state. Three Convex snapshots are assigned as they arrive and
/// everything else is derived from them; the server computes all outcomes.
/// Connection handling, host phase calls and bots live in the sibling files.
@MainActor
final class MultiplayerGameStore: ObservableObject {
    let sessionService = SessionService()
    let botDirector: BotDirector

    // Snapshots (`views:getSessionView`, `views:getPlayers`, `views:getRoundState`)
    @Published var sessionView: SessionView?
    @Published var players: [SessionPlayer] = []
    @Published var roundState: RoundState?

    // Connection state
    @Published var isConnecting = false
    /// A ConvexError from a subscription; cleared by a successful retry.
    @Published var connectionError: String?
    @Published var isRealtimeConnected = false
    @Published var isRealtimeReconnecting = false
    @Published var showsReconnectBanner = false

    @Published var isHostOffline = false
    @Published var wasKicked = false

    var sessionId: UUID?
    var subscriptions: [SubscriptionSupervisor] = []
    var tickTask: Task<Void, Never>?
    var isLeaving = false
    var isCompletingNight = false
    var isAdvancingFromRoleReveal = false
    weak var authStore: AuthStore?
    var identityObserver: AnyCancellable?
    private var lifecycleObservers: [NSObjectProtocol] = []

    init() {
        botDirector = BotDirector(sessionService: sessionService)
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(forName: .appDidBecomeActive, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.handleAppResume() }
            },
            center.addObserver(forName: .appWillEnterBackground, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.prepareForBackground() }
            },
        ]
    }

    deinit {
        tickTask?.cancel()
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Derived state

    var currentSession: GameSession? { sessionView?.session }
    var isHost: Bool { sessionView?.viewer.isHost ?? false }
    var isInSession: Bool { sessionId != nil }

    var myPlayer: SessionPlayer? { players.first(where: \.isMe) }
    var myRole: Role? { myPlayer?.role }
    var myNumber: Int? { myPlayer?.playerNumber }

    var visiblePlayers: [PublicPlayerInfo] { players.map(PublicPlayerInfo.init(from:)) }

    /// Only populated if I'm mafia.
    var mafiaTeammates: [PublicPlayerInfo] {
        guard myRole == .mafia else { return [] }
        return players.filter { $0.role == .mafia && !$0.isMe }.map(PublicPlayerInfo.init(from:))
    }

    var mafiaTeammatePlayerIds: Set<UUID> { Set(mafiaTeammates.map(\.playerId)) }

    /// `[actionType: [targetId: count]]` from the current phase's draft selections.
    var tentativeVoteCounts: [ActionType: [UUID: Int]] {
        var counts: [ActionType: [UUID: Int]] = [:]
        for selection in roundState?.tentative ?? [] {
            guard let target = selection.targetPlayerId else { continue }
            counts[selection.actionType, default: [:]][target, default: 0] += 1
        }
        return counts
    }

    var isPhaseReadyToAdvance: Bool { roundState?.readyToAdvance ?? false }

    /// The server clears every seat's readiness at game over; Play Again marks it again.
    var playersInLobbyCount: Int { players.filter(\.isReady).count }

    /// My submitted night action this round (restores the inspector result after a relaunch).
    var myNightAction: GameAction? {
        guard let me = myPlayer else { return nil }
        return roundState?.actions.first { $0.actorPlayerId == me.playerId && $0.actionType != .vote }
    }

    // MARK: - Snapshots

    func apply(sessionView value: SessionView?) {
        guard sessionId != nil else { return }
        guard let value, value.viewer.isMember, value.session.status != .cancelled else {
            // Removed by the host, or the host ended the game.
            guard !isLeaving else { return }
            clearLocalSession()
            wasKicked = true
            return
        }
        sessionView = value
        runHostAutomation()
    }

    func apply(players value: [SessionPlayer]) {
        guard sessionId != nil else { return }
        players = value
        runHostAutomation()
    }

    func apply(roundState value: RoundState?) {
        guard sessionId != nil else { return }
        roundState = value
        runHostAutomation()
    }

    // MARK: - Session lifecycle

    func createSession(playerName: String, botCount: Int = 0) async throws {
        try await enter { try await self.sessionService.createSession(playerName: playerName, botCount: botCount) }
    }

    func joinSession(roomCode: String, playerName: String) async throws {
        try await enter { try await self.sessionService.joinSession(roomCode: roomCode, playerName: playerName) }
    }

    private func enter(_ call: () async throws -> EnterResult) async throws {
        clearLocalSession()
        isConnecting = true
        defer { isConnecting = false }
        let result = try await call()
        sessionId = result.sessionId
        startSubscriptions(sessionId: result.sessionId)
        startTicking()
    }

    /// Leave this seat; the backend transfers host or cancels an empty room.
    func leaveSession() async throws {
        guard let sessionId else { throw SessionError.noActiveSession }
        // Keep the connection intact if the request fails so the user can retry.
        isLeaving = true
        do {
            try await sessionService.leaveSession(sessionId: sessionId)
        } catch {
            isLeaving = false
            throw error
        }
        clearLocalSession()
    }

    /// The host's End Game action cancels the room for every participant.
    func endSession() async throws {
        guard isHost, let sessionId else { throw SessionError.notHost }
        isLeaving = true
        do {
            try await sessionService.cancelSession(sessionId: sessionId)
        } catch {
            isLeaving = false
            throw error
        }
        clearLocalSession()
    }

    func clearLocalSession() {
        subscriptions.forEach { $0.stop() }
        subscriptions = []
        tickTask?.cancel()
        tickTask = nil
        sessionId = nil
        sessionView = nil
        players = []
        roundState = nil
        isLeaving = false
        isHostOffline = false
        wasKicked = false
        botDirector.reset()
        updateConnectionStatus()
    }

    /// Play Again: resets the room to the lobby and marks me ready.
    func returnToLobby() async throws {
        guard let sessionId else { throw SessionError.noActiveSession }
        try await sessionService.returnToLobby(sessionId: sessionId)
    }

    func declinePlayAgain() async throws {
        try await leaveSession()
    }

    /// Remove a player from the session (host only).
    func removePlayer(withId playerRecordId: UUID) async throws {
        guard isHost, let sessionId else { return }
        try await sessionService.removePlayer(sessionId: sessionId, playerRecordId: playerRecordId)
    }

    // MARK: - My actions

    func setReadyStatus(_ isReady: Bool) async throws {
        guard let sessionId else { return }
        try await sessionService.setReady(sessionId: sessionId, isReady: isReady)
    }

    func markRoleAsSeen() async throws {
        try await setReadyStatus(true)
    }

    /// Returns the investigation result for inspector checks, nil otherwise.
    func submitNightAction(actionType: ActionType, nightIndex: Int, targetPlayerId: UUID?) async throws -> String? {
        let response = try await submit(actionType, phaseIndex: nightIndex, target: targetPlayerId)
        return actionType == .inspectorCheck ? response.result : nil
    }

    func submitVote(dayIndex: Int, targetPlayerId: UUID?) async throws {
        try await submit(.vote, phaseIndex: dayIndex, target: targetPlayerId)
    }

    @discardableResult
    private func submit(_ type: ActionType, phaseIndex: Int, target: UUID?) async throws -> ActionResponse {
        // The round id arrives in the same snapshot as the phase; never fetch it.
        guard let session = currentSession, let roundId = session.currentRoundId,
              let me = myPlayer else { throw SessionError.noActiveSession }
        return try await sessionService.submitAction(
            sessionId: session.id, roundId: roundId, actionType: type,
            phaseIndex: phaseIndex, actorPlayerId: me.playerId, targetPlayerId: target
        )
    }

    /// Shares a draft target with teammates as soon as it is tapped.
    func broadcastTentativeSelection(actionType: ActionType, targetPlayerId: UUID?, phaseIndex: Int) async {
        guard let sessionId, let me = myPlayer else { return }
        do {
            try await sessionService.setTentativeSelection(
                sessionId: sessionId, actorPlayerId: me.playerId, actionType: actionType,
                phaseIndex: phaseIndex, targetPlayerId: targetPlayerId
            )
        } catch {
            print("❌ [TentativeVote] Failed to share selection: \(error.localizedDescription)")
        }
    }
}
