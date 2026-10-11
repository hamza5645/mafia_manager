import Combine
import Foundation
import UIKit

/// Multiplayer state. Four Convex snapshots are applied as they arrive (equal values are
/// skipped) and everything else is derived from them; the server computes all outcomes.
/// Connection handling, host phase calls and bots live in the sibling files.
@MainActor
final class MultiplayerGameStore: ObservableObject {
    /// The server's AUTH message: it no longer knows who this device is.
    static let signInMessage = "Please sign in to continue."

    let sessionService: any SessionServicing
    let botDirector: BotDirector
    /// Waits for the tick interval, retries and banner delays (a fake clock in tests).
    let sleep: (Duration) async -> Void

    // Snapshots (`views:getSessionView`, `views:getPlayers`, `views:getRoundState`)
    @Published var sessionView: SessionView?
    @Published var players: [SessionPlayer] = [] {
        didSet { rebuildPlayerCaches() }
    }
    @Published var roundState: RoundState?
    /// `views:getHostPresence`. Not published: it changes with every host heartbeat.
    var hostPresence: HostPresence?
    /// When the current `hostPresence` value arrived.
    var hostPresenceReceivedAt: ContinuousClock.Instant?

    // Connection state
    /// A ConvexError from a subscription; cleared by a successful retry.
    @Published var connectionError: String?
    /// The session view arrived without a caller (e.g. a lapsed Clerk token); the last snapshots stay.
    @Published var needsSignIn = false
    @Published var showsReconnectBanner = false

    @Published var isHostOffline = false
    @Published var wasKicked = false
    /// The room code from create/join, shown before the first snapshot.
    @Published var roomCode: String?

    // Derived from `players` once per change (see `rebuildPlayerCaches`).
    private(set) var myPlayer: SessionPlayer?
    private(set) var visiblePlayers: [PublicPlayerInfo] = []
    /// Seats by `playerId`.
    private(set) var playersById: [UUID: SessionPlayer] = [:]
    /// Only populated if I'm mafia.
    private(set) var mafiaTeammatePlayerIds: Set<UUID> = []

    var sessionId: UUID?
    var subscriptions: [SubscriptionSupervisor] = []
    var tickTask: Task<Void, Never>?
    var isLeaving = false
    var isInBackground = false
    var isCompletingNight = false
    var isAdvancingFromRoleReveal = false
    /// Set on resume; the first successful heartbeat afterwards may take the lobby back.
    var isReclaimPending = false
    /// The session of the heartbeat / host claim still waiting for the server (one at a time).
    var heartbeatInFlight: UUID?
    var claimInFlight: UUID?
    /// The websocket is reconnecting (`ConvexService.connectionState`).
    var isSocketConnecting = false
    /// The socket has been reconnecting for at least `slowConnectionDelay`.
    var isConnectionSlow = false
    var slowConnectionTask: Task<Void, Never>?
    /// Interactive mutations pending longer than `slowMutationDelay`.
    var slowMutations: Set<UUID> = []
    var finalHeartbeatTask = UIBackgroundTaskIdentifier.invalid
    weak var authStore: AuthStore?
    var identityObserver: AnyCancellable?
    private var connectionObserver: AnyCancellable?
    /// Cancelled on release, so `deinit` needs no main-actor state.
    private var lifecycleObservers: [AnyCancellable] = []
    /// The caller's wait for the latest create or join.
    private var entryWait: EntryWait?
    /// The latest create or join, including the leave that gives its seat back after a Cancel.
    private var pendingEntry: Task<Void, Never>?

    /// The defaults talk to `ConvexService.shared`; tests inject fakes.
    init(
        service: (any SessionServicing)? = nil,
        sleep: @escaping (Duration) async -> Void = { duration in _ = try? await Task.sleep(for: duration) },
        connectionState: AnyPublisher<ConvexConnectionState, Never>? = nil
    ) {
        let service = service ?? SessionService()
        sessionService = service
        self.sleep = sleep
        botDirector = BotDirector { plans, sessionId, roundId, phaseIndex in
            try await service.submitBotActions(sessionId: sessionId, roundId: roundId, phaseIndex: phaseIndex, plans: plans)
        }
        connectionObserver = (connectionState ?? ConvexService.shared.connectionState.eraseToAnyPublisher())
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.handleConnectionState($0) }
        // Posted on the main thread by the app's scene phase handler.
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.publisher(for: .appDidBecomeActive).sink { [weak self] _ in
                Task { @MainActor in await self?.handleAppResume() }
            },
            center.publisher(for: .appWillEnterBackground).sink { [weak self] _ in
                Task { @MainActor in self?.prepareForBackground() }
            },
        ]
    }

    deinit {
        tickTask?.cancel()
        slowConnectionTask?.cancel()
    }

    // MARK: - Derived state

    var currentSession: GameSession? { sessionView?.session }
    var isHost: Bool { sessionView?.viewer.isHost ?? false }
    var isInSession: Bool { sessionId != nil }

    var myRole: Role? { myPlayer?.role }
    var myNumber: Int? { myPlayer?.playerNumber }

    /// Only populated if I'm mafia.
    var mafiaTeammates: [PublicPlayerInfo] {
        visiblePlayers.filter { mafiaTeammatePlayerIds.contains($0.playerId) }
    }

    private func rebuildPlayerCaches() {
        myPlayer = players.first(where: \.isMe)
        visiblePlayers = players.map(PublicPlayerInfo.init(from:))
        playersById = Dictionary(players.map { ($0.playerId, $0) }, uniquingKeysWith: { first, _ in first })
        mafiaTeammatePlayerIds = myPlayer?.role == .mafia
            ? Set(players.filter { $0.role == .mafia && !$0.isMe }.map(\.playerId))
            : []
    }

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

    /// Shown with a Retry button in the game screens.
    var connectionProblem: String? { connectionError ?? (needsSignIn ? Self.signInMessage : nil) }

    /// The server clears every seat's readiness at game over; Play Again marks it again.
    var playersInLobbyCount: Int { players.filter(\.isReady).count }

    /// My submitted night action this round (restores the inspector result after a relaunch).
    var myNightAction: GameAction? {
        guard let me = myPlayer else { return nil }
        return roundState?.actions.first { $0.actorPlayerId == me.playerId && $0.actionType != .vote }
    }

    /// My vote row this round (restores a submitted vote after a relaunch).
    var myVote: GameAction? {
        guard let me = myPlayer else { return nil }
        return roundState?.actions.first { $0.actorPlayerId == me.playerId && $0.actionType == .vote }
    }

    /// Host only: alive humans the current phase still waits for. Role reveal: not ready;
    /// night: active-role humans without an action this round; voting: humans without a vote.
    var waitingForPlayers: [SessionPlayer] {
        guard isHost, let round = roundState, round.roundId == currentSession?.currentRoundId else { return [] }
        let humans = players.filter { $0.isAlive && !$0.isBot }
        let rows = round.actions.filter { $0.phaseIndex == round.phaseIndex }
        func hasRow(_ player: SessionPlayer, _ type: ActionType) -> Bool {
            rows.contains { $0.actorPlayerId == player.playerId && $0.actionType == type }
        }
        switch round.phase {
        case "role_reveal":
            return humans.filter { !$0.isReady }
        case "night":
            let types: [Role: ActionType] = [.mafia: .mafiaTarget, .doctor: .doctorProtect, .inspector: .inspectorCheck]
            return humans.filter { player in
                guard let type = player.role.flatMap({ types[$0] }) else { return false }
                return !hasRow(player, type)
            }
        case "voting":
            return humans.filter { !hasRow($0, .vote) }
        default:
            return []
        }
    }

    // MARK: - Snapshots

    /// The only place that decides whether I was removed or the game ended.
    func apply(sessionView value: SessionView?) {
        guard sessionId != nil else { return }
        if let value, value.session.status != .cancelled, value.viewer.userId == nil {
            // The server could not identify me, which is not a kick: keep the last snapshots.
            if !needsSignIn {
                needsSignIn = true
                refreshHostOffline()
                recoverIdentity()
            }
            return
        }
        if needsSignIn {
            needsSignIn = false
            // No host presence could arrive while I was unidentified.
            restartHostPresenceClock()
        }
        guard let value, value.viewer.isMember, value.session.status != .cancelled else {
            // Removed by the host, or the host ended the game.
            guard !isLeaving else { return }
            clearLocalSession()
            wasKicked = true
            return
        }
        guard value != sessionView else { return }
        sessionView = value
        updateIdleTimer()
        refreshHostOffline()
        runHostAutomation()
    }

    func apply(players value: [SessionPlayer]) {
        // A member always sees their own seat; `[]` means "not identified" or "removed",
        // which only the session view decides.
        guard sessionId != nil, !value.isEmpty, value != players else { return }
        players = value
        runHostAutomation()
    }

    func apply(roundState value: RoundState?) {
        // nil means "not identified" or "removed"; see `apply(sessionView:)`.
        guard sessionId != nil, let value, value != roundState else { return }
        roundState = value
        runHostAutomation()
    }

    /// nil means "not a member"; the session view decides what that means.
    func apply(hostPresence value: HostPresence?) {
        guard sessionId != nil, let value, value != hostPresence else { return }
        hostPresence = value
        hostPresenceReceivedAt = .now
        refreshHostOffline()
    }

    func recoverIdentity() {
        Task { await authStore?.ensureValidSession() }
    }

    /// Keeps the screen awake while a game is running, so a narrating host is not locked out.
    func updateIdleTimer() {
        let keepAwake = currentSession?.status == .inProgress
        if UIApplication.shared.isIdleTimerDisabled != keepAwake {
            UIApplication.shared.isIdleTimerDisabled = keepAwake
        }
    }

    // MARK: - Session lifecycle

    func createSession(playerName: String, botCount: Int = 0) async throws {
        try await enter { try await self.sessionService.createSession(playerName: playerName, botCount: botCount) }
    }

    func joinSession(roomCode: String, playerName: String) async throws {
        try await enter { try await self.sessionService.joinSession(roomCode: roomCode, playerName: playerName) }
    }

    /// Cancel or onDisappear while create/join is in flight: the caller stops waiting, and when
    /// the request returns, a seat it created is given back and nothing starts. Never retries a create.
    func cancelPendingEntry() {
        entryWait?.finish(.failure(CancellationError()))
    }

    /// The user waits at most `ConvexService.interactiveMutationTimeout`. The request itself has
    /// no limit (see `SessionService`), so its result always arrives here, and a seat it returns
    /// after a Cancel or the time limit is given back.
    private func enter(_ call: @escaping () async throws -> EnterResult) async throws {
        clearLocalSession()
        entryWait?.finish(.failure(CancellationError()))
        let wait = EntryWait()
        entryWait = wait
        let previous = pendingEntry
        let service = sessionService
        pendingEntry = Task {
            // A cancelled entry may still be in flight or giving its seat back. Its leave must
            // reach the server before this create or join, or it would undo a join of the same room.
            await previous?.value
            guard !wait.isFinished else { return }
            do {
                let result = try await call()
                // Abandoned while in flight: leave a seat this entry created. A re-entry returned
                // a seat that existed before (perhaps in a running game), so that one stays.
                if !wait.finish(.success(result)), !result.rejoined {
                    try? await service.leaveSession(sessionId: result.sessionId)
                }
            } catch {
                wait.finish(.failure(error))
            }
        }
        let timer = Task { [sleep] in
            await sleep(ConvexService.interactiveMutationTimeout)
            // Not "still sending": a room or seat that arrives later is given back.
            wait.finish(.failure(BackendError(timedOut: BackendError.network)))
        }
        defer { timer.cancel() }
        let result = try await sending { try await wait.value() }
        sessionId = result.sessionId
        roomCode = result.roomCode
        startSubscriptions(sessionId: result.sessionId)
        // In the background the ticker waits for the foreground restart.
        if !isInBackground { startTicking() }
    }

    /// Leave this seat; the backend transfers host or cancels an empty room.
    func leaveSession() async throws {
        guard let sessionId else { throw SessionError.noActiveSession }
        // Keep the connection intact if the request fails so the user can retry.
        isLeaving = true
        do {
            try await sending { try await sessionService.leaveSession(sessionId: sessionId) }
        } catch {
            guard Self.leftAnyway(error) else {
                isLeaving = false
                throw error
            }
        }
        clearLocalSession()
    }

    /// The host's End Game action cancels the room for every participant.
    func endSession() async throws {
        guard isHost, let sessionId else { throw SessionError.notHost }
        isLeaving = true
        do {
            try await sending { try await sessionService.cancelSession(sessionId: sessionId) }
        } catch {
            guard Self.leftAnyway(error) else {
                isLeaving = false
                throw error
            }
        }
        clearLocalSession()
    }

    static func isSignInRequired(_ error: Error) -> Bool {
        guard let error = error as? BackendError else { return false }
        return error.isServerMessage && error.message == signInMessage
    }

    /// Leave and End Game errors after which this device still leaves the room: the server no
    /// longer knows me (so the user isn't trapped), or the request ran out of time. A timed-out
    /// request is still queued and the Convex client sends it when it reconnects; it is not a
    /// failure, and keeping the room would show the late leave as a kick.
    static func leftAnyway(_ error: Error) -> Bool {
        isSignInRequired(error) || (error as? BackendError)?.isTimeout == true
    }

    func clearLocalSession() {
        subscriptions.forEach { $0.stop() }
        subscriptions = []
        tickTask?.cancel()
        tickTask = nil
        sessionId = nil
        roomCode = nil
        sessionView = nil
        players = []
        roundState = nil
        hostPresence = nil
        hostPresenceReceivedAt = nil
        isLeaving = false
        isReclaimPending = false
        needsSignIn = false
        isHostOffline = false
        wasKicked = false
        botDirector.reset()
        updateIdleTimer()
        updateConnectionStatus()
    }

    /// Play Again: resets the room to the lobby and marks me ready.
    func returnToLobby() async throws {
        guard let sessionId else { throw SessionError.noActiveSession }
        try await sending { try await sessionService.returnToLobby(sessionId: sessionId) }
    }

    func declinePlayAgain() async throws {
        try await leaveSession()
    }

    /// Remove a player from the session (host only).
    func removePlayer(withId playerRecordId: UUID) async throws {
        guard isHost, let sessionId else { return }
        try await sending { try await sessionService.removePlayer(sessionId: sessionId, playerRecordId: playerRecordId) }
    }

    // MARK: - My actions

    func setReadyStatus(_ isReady: Bool) async throws {
        guard let sessionId else { return }
        // A resend that lands after the phase moved on is dropped by the server.
        let phase = currentSession?.currentPhase
        try await sending { try await sessionService.setReady(sessionId: sessionId, isReady: isReady, phase: phase) }
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
        guard let sessionId, let me = myPlayer else { throw SessionError.noActiveSession }
        let roundId = try await currentRoundId()
        return try await sending {
            try await sessionService.submitAction(
                sessionId: sessionId, roundId: roundId, actionType: type,
                phaseIndex: phaseIndex, actorPlayerId: me.playerId, targetPlayerId: target
            )
        }
    }

    /// The round id arrives in the same snapshot as the phase; if it is missing, wait for the
    /// next session snapshot that carries it instead of fetching (§8.1.6).
    func currentRoundId() async throws -> UUID {
        if let roundId = currentSession?.currentRoundId { return roundId }
        for await view in $sessionView.dropFirst().values {
            if let roundId = view?.session.currentRoundId { return roundId }
            if sessionId == nil { break }
        }
        throw SessionError.noActiveSession
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

/// One create or join as its caller sees it. It finishes once: with the request's result or
/// error, at the time limit, or on a Cancel. A request that returns after that was abandoned.
@MainActor
private final class EntryWait {
    private var outcome: Result<EnterResult, Error>?
    private var waiter: CheckedContinuation<EnterResult, Error>?

    var isFinished: Bool { outcome != nil }

    /// Returns false when the wait had already finished.
    @discardableResult
    func finish(_ outcome: Result<EnterResult, Error>) -> Bool {
        guard self.outcome == nil else { return false }
        self.outcome = outcome
        waiter?.resume(with: outcome)
        waiter = nil
        return true
    }

    func value() async throws -> EnterResult {
        if let outcome { return try outcome.get() }
        return try await withCheckedThrowingContinuation { waiter = $0 }
    }
}
