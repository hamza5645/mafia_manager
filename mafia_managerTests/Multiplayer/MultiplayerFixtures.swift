import Combine
import ConvexMobile
import Foundation
import Testing

@testable import mafia_manager

/// Small builders for multiplayer unit tests.
enum Fixture {
    static func seat(
        _ role: Role?,
        bot: Bool = true,
        alive: Bool = true,
        ready: Bool = true,
        isMe: Bool = false,
        joinedAt: Date = Date()
    ) -> SessionPlayer {
        SessionPlayer(
            id: UUID(), sessionId: UUID(), userId: bot ? nil : UUID(), playerId: UUID(),
            playerName: "\(bot ? "Bot" : "Human") \(role?.rawValue ?? "unassigned")", playerNumber: nil,
            role: role, isBot: bot, isAlive: alive, isOnline: true, isReady: ready,
            joinedAt: joinedAt, isMe: isMe
        )
    }

    static func action(
        _ actor: SessionPlayer,
        _ type: ActionType,
        target: SessionPlayer?,
        round: UUID = UUID(),
        at seconds: TimeInterval = 0
    ) -> GameAction {
        GameAction(
            id: UUID(), sessionId: actor.sessionId, roundId: round, actionType: type, phaseIndex: 0,
            actorPlayerId: actor.playerId, targetPlayerId: target?.playerId,
            createdAt: Date(timeIntervalSinceReferenceDate: seconds)
        )
    }

    static func session(
        status: SessionStatus = .inProgress,
        phase: String = "night",
        roundId: UUID? = UUID(),
        hostUserId: UUID = UUID(),
        originalHostUserId: UUID? = nil
    ) -> GameSession {
        GameSession(
            id: UUID(), roomCode: "123456", hostUserId: hostUserId, originalHostUserId: originalHostUserId,
            status: status, createdAt: Date(),
            maxPlayers: 19, botCount: 0, currentPhase: phase, currentPhaseData: nil, dayIndex: 0,
            isGameOver: false, assignedNumbers: [], nightHistory: [], dayHistory: [],
            currentRoundId: roundId, updatedAt: Date(timeIntervalSinceReferenceDate: 0)
        )
    }

    /// `userId: nil` is what the server returns when it cannot identify the caller.
    static func view(_ session: GameSession, isMember: Bool = true, isHost: Bool = false, userId: UUID? = UUID()) -> SessionView {
        SessionView(session: session, viewer: .init(
            userId: userId, playerRecordId: nil, playerId: nil, isMember: isMember, isHost: isHost
        ))
    }

    static func round(
        _ roundId: UUID = UUID(),
        phase: String = "night",
        ready: Bool = false,
        actions: [GameAction] = [],
        tentative: [TentativeSelection] = []
    ) -> RoundState {
        RoundState(roundId: roundId, phase: phase, phaseIndex: 0, readyToAdvance: ready, actions: actions, tentative: tentative)
    }

    /// The host had been silent for `silence` seconds when the server sent this value.
    static func presence(silence: TimeInterval, staleAfter: TimeInterval = 15, host: UUID = UUID()) -> HostPresence {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        return HostPresence(hostUserId: host, hostLastHeartbeat: now - silence, serverNow: now, staleAfterSeconds: staleAfter)
    }
}

/// Lets queued main-actor work run (tasks started by the code under test).
@MainActor
func settle() async {
    for _ in 0..<20 { await Task.yield() }
}

/// Values sent through `receive(on: DispatchQueue.main)` land after this.
@MainActor
func drainMainQueue() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}

@MainActor
private final class Once {
    var done = false
}

/// Waits for `task`, but records an issue and returns nil instead of hanging the run
/// when it has not finished within `limit`. The task is not cancelled.
@MainActor
func finishes<T: Sendable>(_ task: Task<T, Error>, within limit: Duration = .seconds(5)) async -> Result<T, Error>? {
    let once = Once()
    let result: Result<T, Error>? = await withCheckedContinuation { continuation in
        Task { @MainActor in
            let value = await task.result
            guard !once.done else { return }
            once.done = true
            continuation.resume(returning: value)
        }
        Task { @MainActor in
            try? await Task.sleep(for: limit)
            guard !once.done else { return }
            once.done = true
            continuation.resume(returning: nil)
        }
    }
    if result == nil { Issue.record("Still waiting after \(limit)") }
    return result
}

/// Time only moves when a test advances it.
final class ManualClock {
    private var now: Duration = .zero
    private(set) var requested: [Duration] = []
    private var sleepers: [(deadline: Duration, continuation: UnsafeContinuation<Void, Never>)] = []

    func sleep(_ duration: Duration) async {
        requested.append(duration)
        await withUnsafeContinuation { sleepers.append((now + duration, $0)) }
    }

    /// Lets pending tasks reach their sleep, moves time forward and runs the ones that woke.
    func advance(by duration: Duration) async {
        await settle()
        now += duration
        let due = sleepers.filter { $0.deadline <= now }
        sleepers.removeAll { $0.deadline <= now }
        due.forEach { $0.continuation.resume() }
        await settle()
    }
}

/// An in-memory `SessionServicing` that records every call.
@MainActor
final class FakeSessionService: SessionServicing {
    enum Call: Equatable {
        case create, join, leave(UUID), cancel, removePlayer, claimHost, heartbeat, setReady(Bool)
        case startGame, returnToLobby, advance(String), submit(ActionType), submitBots([BotPlan])
        case tentative, finishNight(UUID), closeVoting, resolveVote
    }

    private(set) var calls: [Call] = []
    /// One subject per `watch`, keyed by query name; the latest one is live.
    private(set) var feeds: [String: [PassthroughSubject<Any, ClientError>]] = [:]
    var enterResult = EnterResult(sessionId: UUID(), roomCode: "482913", playerRecordId: UUID(), playerId: UUID(), rejoined: false)
    var heartbeatError: Error?
    var leaveError: Error?
    /// The `phase` of every setReady call.
    private(set) var readyPhases: [String?] = []
    var claimError: Error?
    /// Each bot batch takes the next message and rejects every item with it.
    var botFailures: [String] = []
    /// While set, these calls wait until `release()`.
    var holds: Set<String> = []
    private var held: [UnsafeContinuation<Void, Never>] = []

    func count(_ call: Call) -> Int { calls.filter { $0 == call }.count }

    var botBatches: [[BotPlan]] {
        calls.compactMap { call in
            guard case .submitBots(let plans) = call else { return nil }
            return plans
        }
    }

    func release() {
        let waiting = held
        held = []
        holds = []
        waiting.forEach { $0.resume() }
    }

    private func record(_ call: Call, hold name: String) async {
        calls.append(call)
        if holds.contains(name) { await withUnsafeContinuation { held.append($0) } }
    }

    /// Sends `value` on the newest subscription of `query`.
    func send<T>(_ query: String, _ value: T) {
        feeds[query]?.last?.send(value)
    }

    /// Ends the newest subscription of `query` the way ConvexMobile does on a server error.
    func fail(_ query: String) {
        feeds[query]?.last?.send(completion: .failure(.ServerError(msg: "Server down")))
    }

    var subscribeCount: Int { feeds.values.map(\.count).reduce(0, +) }

    func watch<T: Decodable>(_ query: String, sessionId: UUID, as type: T.Type) -> AnyPublisher<T, ClientError> {
        let subject = PassthroughSubject<Any, ClientError>()
        feeds[query, default: []].append(subject)
        return subject.compactMap { $0 as? T }.eraseToAnyPublisher()
    }

    func createSession(playerName: String, botCount: Int) async throws -> EnterResult {
        await record(.create, hold: "create")
        return enterResult
    }

    func joinSession(roomCode: String, playerName: String) async throws -> EnterResult {
        await record(.join, hold: "join")
        return enterResult
    }

    func leaveSession(sessionId: UUID) async throws {
        await record(.leave(sessionId), hold: "leave")
        if let leaveError { throw leaveError }
    }

    func cancelSession(sessionId: UUID) async throws { await record(.cancel, hold: "cancel") }
    func removePlayer(sessionId: UUID, playerRecordId: UUID) async throws { await record(.removePlayer, hold: "removePlayer") }

    func claimHost(sessionId: UUID) async throws {
        await record(.claimHost, hold: "claimHost")
        if let claimError { throw claimError }
    }

    func heartbeat(sessionId: UUID) async throws {
        await record(.heartbeat, hold: "heartbeat")
        if let heartbeatError { throw heartbeatError }
    }

    func setReady(sessionId: UUID, isReady: Bool, phase: String?) async throws {
        readyPhases.append(phase)
        await record(.setReady(isReady), hold: "setReady")
    }

    func startGame(sessionId: UUID, assignments: [RoleAssignment]) async throws { await record(.startGame, hold: "startGame") }
    func returnToLobby(sessionId: UUID) async throws { await record(.returnToLobby, hold: "returnToLobby") }
    func advancePhase(sessionId: UUID, to phase: PhaseTarget) async throws { await record(.advance(phase.rawValue), hold: "advance") }

    func submitAction(
        sessionId: UUID, roundId: UUID, actionType: ActionType,
        phaseIndex: Int, actorPlayerId: UUID, targetPlayerId: UUID?
    ) async throws -> ActionResponse {
        await record(.submit(actionType), hold: "submit")
        return ActionResponse(success: true, result: nil)
    }

    func submitBotActions(sessionId: UUID, roundId: UUID, phaseIndex: Int, plans: [BotPlan]) async throws -> [BotActionResult] {
        await record(.submitBots(plans), hold: "submitBots")
        let failure = botFailures.isEmpty ? nil : botFailures.removeFirst()
        return plans.map { BotActionResult(actorPlayerId: $0.botPlayerId, ok: failure == nil, error: failure, result: nil) }
    }

    func setTentativeSelection(
        sessionId: UUID, actorPlayerId: UUID, actionType: ActionType, phaseIndex: Int, targetPlayerId: UUID?
    ) async throws {
        await record(.tentative, hold: "tentative")
    }

    func finishNight(sessionId: UUID, roundId: UUID) async throws -> NightOutcome {
        await record(.finishNight(roundId), hold: "finishNight")
        return NightOutcome(nightIndex: 0, resultingDeaths: [], nextPhase: "morning", winner: nil)
    }

    func closeVoting(sessionId: UUID, roundId: UUID) async throws -> VoteClose {
        await record(.closeVoting, hold: "closeVoting")
        return VoteClose(dayIndex: 0, eliminatedPlayerId: nil)
    }

    func resolveVoteAtomic(sessionId: UUID, roundId: UUID) async throws -> VoteOutcome {
        await record(.resolveVote, hold: "resolveVote")
        return VoteOutcome(dayIndex: 0, eliminatedPlayerId: nil, nextPhase: "night", winner: nil)
    }
}
