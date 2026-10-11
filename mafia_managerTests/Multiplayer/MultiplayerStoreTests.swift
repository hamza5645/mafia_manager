import Combine
import ConvexMobile
import Foundation
import Testing
import UIKit

@testable import mafia_manager

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct MultiplayerStoreTests {
    private let service = FakeSessionService()
    private let clock = ManualClock()
    private let socket = CurrentValueSubject<ConvexConnectionState, Never>(.connected)

    private func makeStore() -> MultiplayerGameStore {
        MultiplayerGameStore(service: service, sleep: clock.sleep, connectionState: socket.eraseToAnyPublisher())
    }

    /// A store inside a running game, seen by a non-host member unless `isHost`.
    private func joinedStore(_ session: GameSession? = nil, isHost: Bool = false, userId: UUID = UUID()) -> MultiplayerGameStore {
        let store = makeStore()
        store.sessionId = UUID()
        store.apply(sessionView: Fixture.view(session ?? Fixture.session(), isHost: isHost, userId: userId))
        return store
    }

    // MARK: - Derived values

    @Test func myPlayerAndTeammatesComeFromTheServerIsMeFlag() {
        let store = makeStore()
        let me = Fixture.seat(.mafia, bot: false, isMe: true)
        let teammate = Fixture.seat(.mafia)
        let citizen = Fixture.seat(.citizen, bot: false)
        store.players = [teammate, me, citizen]

        #expect(store.myPlayer?.id == me.id)
        #expect(store.myRole == .mafia)
        #expect(store.mafiaTeammatePlayerIds == [teammate.playerId])
        #expect(store.mafiaTeammates.map(\.id) == [teammate.id])
        #expect(store.visiblePlayers.map(\.id) == [teammate.id, me.id, citizen.id])
        #expect(store.playersById[citizen.playerId]?.id == citizen.id)

        store.players = [teammate, citizen]
        #expect(store.myPlayer == nil)
        #expect(store.mafiaTeammates.isEmpty)
        #expect(store.playersById[me.playerId] == nil)
    }

    @Test func playersInLobbyCountCountsReadySeats() {
        let store = makeStore()
        store.players = [Fixture.seat(.citizen, ready: true), Fixture.seat(nil, bot: false, ready: false),
                         Fixture.seat(nil, bot: false, ready: true)]
        #expect(store.playersInLobbyCount == 2)
    }

    @Test func phaseReadinessComesOnlyFromTheServer() {
        let store = makeStore()
        #expect(!store.isPhaseReadyToAdvance)
        store.roundState = Fixture.round(ready: true)
        #expect(store.isPhaseReadyToAdvance)
        store.roundState = Fixture.round(ready: false)
        #expect(!store.isPhaseReadyToAdvance)
    }

    @Test func tentativeCountsUseTheCurrentRoundStateOnly() {
        let store = makeStore()
        let target = UUID()
        let drafts = [
            TentativeSelection(actorPlayerId: UUID(), targetPlayerId: target, actionType: .mafiaTarget, phaseIndex: 0),
            TentativeSelection(actorPlayerId: UUID(), targetPlayerId: target, actionType: .mafiaTarget, phaseIndex: 0),
            TentativeSelection(actorPlayerId: UUID(), targetPlayerId: nil, actionType: .mafiaTarget, phaseIndex: 0),
            TentativeSelection(actorPlayerId: UUID(), targetPlayerId: target, actionType: .doctorProtect, phaseIndex: 0),
        ]
        store.roundState = Fixture.round(tentative: drafts)
        #expect(store.tentativeVoteCounts == [.mafiaTarget: [target: 2], .doctorProtect: [target: 1]])
        store.roundState = Fixture.round()
        #expect(store.tentativeVoteCounts.isEmpty, "Drafts from an earlier phase must not linger")
    }

    @Test func myNightActionRestoresTheInspectorResult() {
        let store = makeStore()
        let me = Fixture.seat(.inspector, bot: false, isMe: true)
        let suspect = Fixture.seat(.mafia)
        var check = Fixture.action(me, .inspectorCheck, target: suspect)
        check.actionData = ActionData(inspectorResult: "mafia")
        store.players = [me, suspect]
        store.roundState = Fixture.round(actions: [Fixture.action(suspect, .mafiaTarget, target: me), check])
        #expect(store.myNightAction?.actionData?.inspectorResult == "mafia")
    }

    @Test func myVoteRestoresASubmittedVote() {
        let store = makeStore()
        let me = Fixture.seat(.citizen, bot: false, isMe: true)
        let suspect = Fixture.seat(.mafia, bot: false)
        store.players = [me, suspect]
        store.roundState = Fixture.round(phase: "voting", actions: [Fixture.action(suspect, .vote, target: me)])
        #expect(store.myVote == nil)
        let vote = Fixture.action(me, .vote, target: suspect)
        store.roundState = Fixture.round(phase: "voting", actions: [Fixture.action(suspect, .vote, target: me), vote])
        #expect(store.myVote?.id == vote.id)
        #expect(store.myVote?.targetPlayerId == suspect.playerId)
    }

    @Test func waitingForPlayersListsTheHumansThePhaseStillNeeds() {
        let round = UUID()
        let host = joinedStore(Fixture.session(phase: "night", roundId: round), isHost: true)
        let mafia = Fixture.seat(.mafia, bot: false)
        let doctor = Fixture.seat(.doctor, bot: false)
        let citizen = Fixture.seat(.citizen, bot: false, ready: false)
        let dead = Fixture.seat(.inspector, bot: false, alive: false)
        let bot = Fixture.seat(.inspector)
        host.apply(players: [mafia, doctor, citizen, dead, bot])

        host.apply(roundState: Fixture.round(round, phase: "role_reveal"))
        #expect(host.waitingForPlayers.map(\.id) == [citizen.id])

        host.apply(roundState: Fixture.round(round, actions: [Fixture.action(mafia, .mafiaTarget, target: citizen, round: round)]))
        #expect(host.waitingForPlayers.map(\.id) == [doctor.id], "Citizens, the dead and bots never hold the night up")

        host.apply(roundState: Fixture.round(round, phase: "voting", actions: [Fixture.action(doctor, .vote, target: mafia, round: round)]))
        #expect(host.waitingForPlayers.map(\.id) == [mafia.id, citizen.id])

        let member = joinedStore(Fixture.session(phase: "night", roundId: round))
        member.apply(players: [mafia, doctor])
        member.apply(roundState: Fixture.round(round, phase: "voting"))
        #expect(member.waitingForPlayers.isEmpty, "Host only")
    }

    // MARK: - Snapshots (PA-10, PA-34)

    @Test func identicalSnapshotsPublishNothing() {
        let store = makeStore()
        store.sessionId = UUID()
        let view = Fixture.view(Fixture.session())
        let players = [Fixture.seat(.citizen, bot: false, isMe: true), Fixture.seat(.mafia)]
        let round = Fixture.round()
        let presence = Fixture.presence(silence: 1)
        store.apply(sessionView: view)
        store.apply(players: players)
        store.apply(roundState: round)
        store.apply(hostPresence: presence)

        var changes = 0
        let watcher = store.objectWillChange.sink { changes += 1 }
        for _ in 0..<10 {
            store.apply(sessionView: view)
            store.apply(players: players)
            store.apply(roundState: round)
            store.apply(hostPresence: presence)
        }
        #expect(changes == 0, "Audit baseline: 10 identical player snapshots fired 10 objectWillChange")

        store.apply(players: players + [Fixture.seat(.doctor)])
        #expect(changes == 1)
        withExtendedLifetime(watcher) {}
    }

    // MARK: - Membership

    @Test func losingMembershipEndsTheSessionAsAKick() {
        let store = makeStore()
        store.sessionId = UUID()
        store.apply(sessionView: Fixture.view(Fixture.session()))
        #expect(store.currentSession != nil)

        store.apply(sessionView: Fixture.view(Fixture.session(), isMember: false))
        #expect(store.wasKicked)
        #expect(!store.isInSession)
        #expect(store.currentSession == nil)
    }

    @Test func cancelledOrMissingSessionIsTreatedAsHostEndedGame() {
        for snapshot in [Fixture.view(Fixture.session(status: .cancelled)), nil] {
            let store = makeStore()
            store.sessionId = UUID()
            store.apply(sessionView: snapshot)
            #expect(store.wasKicked)
            #expect(!store.isInSession)
        }
    }

    @Test func anUnidentifiedViewerKeepsTheGameAndAsksToSignIn() {
        let store = makeStore()
        store.sessionId = UUID()
        let session = Fixture.session()
        let me = Fixture.seat(.citizen, bot: false, isMe: true)
        store.apply(sessionView: Fixture.view(session))
        store.apply(players: [me])
        store.apply(roundState: Fixture.round())

        // A lapsed Clerk token: the server sees no caller at all.
        store.apply(sessionView: Fixture.view(session, isMember: false, userId: nil))
        store.apply(players: [])
        store.apply(roundState: nil)
        #expect(!store.wasKicked)
        #expect(store.isInSession)
        #expect(store.currentSession?.id == session.id)
        #expect(store.myPlayer?.id == me.id)
        #expect(store.roundState != nil)
        #expect(store.connectionProblem == "Please sign in to continue.")

        store.apply(sessionView: Fixture.view(session))
        #expect(!store.needsSignIn)
        #expect(store.connectionProblem == nil)
    }

    @Test func onlyTheServerAuthMessageMeansSignInIsRequired() {
        let auth = BackendError(ClientError.ConvexError(data: "\"Please sign in to continue.\""))
        let other = BackendError(ClientError.ConvexError(data: "\"Game not found.\""))
        #expect(MultiplayerGameStore.isSignInRequired(auth))
        #expect(!MultiplayerGameStore.isSignInRequired(other))
        #expect(!MultiplayerGameStore.isSignInRequired(URLError(.notConnectedToInternet)))
    }

    @Test func actionsWaitForTheSnapshotThatCarriesTheRound() async throws {
        let store = makeStore()
        store.sessionId = UUID()
        store.apply(sessionView: Fixture.view(Fixture.session(roundId: nil)))
        let waiting = Task { try await store.currentRoundId() }
        await settle()

        let round = UUID()
        store.apply(sessionView: Fixture.view(Fixture.session(roundId: round)))
        guard let result = await finishes(waiting) else { return }
        #expect(try result.get() == round)
    }

    @Test func leavingStopsWaitingForARound() async {
        let store = makeStore()
        store.sessionId = UUID()
        store.apply(sessionView: Fixture.view(Fixture.session(roundId: nil)))
        let waiting = Task { try await store.currentRoundId() }
        await settle()

        store.clearLocalSession()
        guard let result = await finishes(waiting) else { return }
        #expect(throws: SessionError.self) { try result.get() }
    }

    @Test func voluntaryLeaveIsNotAKick() {
        let store = makeStore()
        store.sessionId = UUID()
        store.isLeaving = true
        store.apply(sessionView: Fixture.view(Fixture.session(), isMember: false))
        #expect(!store.wasKicked)
    }

    @Test func aLeaveThatRunsOutOfTimeStillLeaves() async throws {
        // Still queued in the Convex client, so it is not a failure; the room is left here.
        service.leaveError = BackendError(timedOut: BackendError.stillSending)
        let store = joinedStore()
        try await store.leaveSession()
        #expect(store.sessionId == nil)
        #expect(!store.wasKicked)

        service.leaveError = BackendError(URLError(.badServerResponse))
        let other = joinedStore()
        await #expect(throws: BackendError.self) { try await other.leaveSession() }
        #expect(other.sessionId != nil, "A real failure keeps the room so the user can retry")
        #expect(!other.isLeaving)
        other.clearLocalSession()
    }

    @Test func readinessIsSentWithThePhaseItWasGivenIn() async throws {
        let store = joinedStore(Fixture.session(phase: "role_reveal", roundId: nil))
        try await store.markRoleAsSeen()
        #expect(service.calls == [.setReady(true)])
        #expect(service.readyPhases == ["role_reveal"])
    }

    @Test func snapshotsAfterLeavingAreIgnored() {
        let store = makeStore()
        store.apply(players: [Fixture.seat(.citizen)])
        store.apply(sessionView: Fixture.view(Fixture.session()))
        #expect(store.players.isEmpty)
        #expect(store.currentSession == nil)
        #expect(!store.wasKicked)
    }

    // MARK: - Entering a room (PA-09, PA-49)

    @Test func createKeepsTheRoomCodeAndStartsFourSubscriptions() async throws {
        let store = makeStore()
        try await store.createSession(playerName: "Host")
        #expect(store.sessionId == service.enterResult.sessionId)
        #expect(store.roomCode == service.enterResult.roomCode)
        #expect(Set(service.feeds.keys) == ["views:getSessionView", "views:getPlayers", "views:getRoundState", "views:getHostPresence"])

        store.clearLocalSession()
        #expect(store.roomCode == nil)
    }

    @Test func cancellingAnInFlightJoinGivesTheSeatBack() async {
        let store = makeStore()
        service.holds = ["join"]
        let joining = Task { try await store.joinSession(roomCode: "482913", playerName: "Late") }
        await settle()
        store.cancelPendingEntry()
        service.release()

        guard let result = await finishes(joining) else { return }
        #expect(throws: CancellationError.self) { try result.get() }
        await settle()
        #expect(service.calls.contains(.leave(service.enterResult.sessionId)))
        #expect(store.sessionId == nil)
        #expect(store.roomCode == nil)
        #expect(service.feeds.isEmpty, "No subscriptions for a cancelled entry")
        #expect(store.tickTask == nil)
        #expect(service.count(.heartbeat) == 0)
    }

    @Test func cancelBeforeAnEntryDoesNotAffectTheNextOne() async throws {
        let store = makeStore()
        store.cancelPendingEntry()
        try await store.createSession(playerName: "Host")
        #expect(store.sessionId == service.enterResult.sessionId)
        #expect(!service.calls.contains(.leave(service.enterResult.sessionId)))
        store.clearLocalSession()
    }

    @Test func aCreateThatReturnsLongAfterCancelLeavesItsRoomOnce() async {
        let store = makeStore()
        service.holds = ["create"]
        let creating = Task { try await store.createSession(playerName: "Host") }
        await settle()
        store.cancelPendingEntry()
        await clock.advance(by: .seconds(60)) // Offline: the request itself has no time limit.
        service.release()

        guard let result = await finishes(creating) else { return }
        #expect(throws: CancellationError.self) { try result.get() }
        await settle()
        #expect(service.count(.leave(service.enterResult.sessionId)) == 1)
        #expect(store.sessionId == nil)
    }

    @Test func anEntryThatRunsOutOfTimeStopsWaitingAndGivesALateRoomBack() async {
        let store = makeStore()
        service.holds = ["create"] // Offline: the create does not return.
        let creating = Task { try await store.createSession(playerName: "Host") }
        await clock.advance(by: ConvexService.interactiveMutationTimeout)
        guard let result = await finishes(creating) else { return }
        #expect(throws: BackendError(timedOut: BackendError.network)) { try result.get() }

        // A retry while still offline waits for the first create, and is never sent.
        let retrying = Task { try await store.createSession(playerName: "Host") }
        await clock.advance(by: ConvexService.interactiveMutationTimeout)
        guard let retried = await finishes(retrying) else { return }
        #expect(throws: BackendError(timedOut: BackendError.network)) { try retried.get() }

        service.release()
        await settle()
        let room = service.enterResult.sessionId
        #expect(service.calls == [.create, .leave(room)], "The late room is given back; the retry was dropped")
        #expect(store.sessionId == nil)
        #expect(service.feeds.isEmpty, "No subscriptions for an entry that ran out of time")
        #expect(store.tickTask == nil)
    }

    @Test func cancellingAReEntryKeepsTheSeat() async {
        // Re-entering a running game through Join returns the seat I already had.
        service.enterResult = EnterResult(
            sessionId: UUID(), roomCode: "482913", playerRecordId: UUID(), playerId: UUID(), rejoined: true
        )
        let store = makeStore()
        service.holds = ["join"]
        let joining = Task { try await store.joinSession(roomCode: "482913", playerName: "Back") }
        await settle()
        store.cancelPendingEntry()
        service.release()

        guard let result = await finishes(joining) else { return }
        #expect(throws: CancellationError.self) { try result.get() }
        await settle()
        #expect(service.count(.leave(service.enterResult.sessionId)) == 0, "A seat this entry did not create stays")
        #expect(store.sessionId == nil)
    }

    @Test func aNewEntryWaitsUntilTheCancelledOneGaveItsSeatBack() async throws {
        let store = makeStore()
        service.holds = ["join"]
        let first = Task { try await store.joinSession(roomCode: "482913", playerName: "A") }
        await settle()
        store.cancelPendingEntry()
        let second = Task { try await store.joinSession(roomCode: "482913", playerName: "B") }
        await settle()
        #expect(service.count(.join) == 1, "The second join waits for the first one")

        service.release()
        _ = await finishes(first)
        guard let result = await finishes(second) else { return }
        try result.get()
        let room = service.enterResult.sessionId
        #expect(Array(service.calls.prefix(3)) == [.join, .leave(room), .join], "The leave reaches the server before the new join")
        #expect(store.sessionId == room)
        store.clearLocalSession()
    }

    // MARK: - Host phases (PA-31)

    @Test func concurrentFinishNightTapsSendOneFinishNight() async {
        let round = UUID()
        let store = joinedStore(Fixture.session(phase: "night", roundId: round), isHost: true)
        service.holds = ["finishNight"]
        let first = Task { try await store.completeNightPhase() }
        let second = Task { try await store.completeNightPhase() }
        await settle()
        #expect(service.count(.finishNight(round)) == 1)

        service.release()
        _ = await finishes(first)
        _ = await finishes(second)
        #expect(service.calls == [.finishNight(round)], "One round trip: no separate record and resolve calls")
    }

    // MARK: - Heartbeat and host presence (PA-01, PA-40, PA-93)

    @Test func aStaleHostGetsOneClaimPerTick() async {
        let store = joinedStore()
        store.apply(hostPresence: Fixture.presence(silence: 20))
        #expect(store.isHostOffline)

        store.startTicking()
        await settle()
        #expect(service.count(.heartbeat) == 1)
        #expect(service.count(.claimHost) == 1)

        await clock.advance(by: MultiplayerGameStore.tickInterval)
        #expect(service.count(.claimHost) == 2, "The server rejects or installs; the next tick asks again")
        store.clearLocalSession()
    }

    @Test func aFreshHostIsLeftAlone() async {
        let store = joinedStore()
        store.apply(hostPresence: Fixture.presence(silence: 3))
        store.startTicking()
        await settle()
        #expect(!store.isHostOffline)
        #expect(service.count(.claimHost) == 0)
        store.clearLocalSession()
    }

    @Test func theHostNeverClaimsAndALobbyWaitsLonger() {
        let host = joinedStore(isHost: true)
        host.apply(hostPresence: Fixture.presence(silence: 500))
        #expect(!host.isHostOffline)

        let lobby = joinedStore(Fixture.session(status: .waiting, phase: "lobby", roundId: nil))
        lobby.apply(hostPresence: Fixture.presence(silence: 60, staleAfter: 90))
        #expect(!lobby.isHostOffline)
    }

    @Test func hostSilenceIsServerAgeAtReceiptPlusLocalTime() throws {
        let store = joinedStore()
        let presence = Fixture.presence(silence: 10)
        store.apply(hostPresence: presence)
        let receivedAt = try #require(store.hostPresenceReceivedAt)
        #expect(!store.hostLooksOffline(now: receivedAt + .seconds(4)))
        #expect(store.hostLooksOffline(now: receivedAt + .seconds(6)))

        store.apply(hostPresence: presence) // Re-delivered unchanged: the clock keeps running.
        #expect(store.hostPresenceReceivedAt == receivedAt)
        store.apply(hostPresence: Fixture.presence(silence: 0)) // A new value restarts it.
        #expect(!store.hostLooksOffline(now: receivedAt + .seconds(6)))
    }

    @Test func nothingIsConcludedWhileTheSocketReconnects() async {
        let store = joinedStore()
        socket.send(.connecting)
        await drainMainQueue()
        store.apply(hostPresence: Fixture.presence(silence: 60))
        #expect(!store.isHostOffline, "I may be the one offline")
        store.startTicking()
        await settle()
        #expect(service.count(.claimHost) == 0)

        socket.send(.connected)
        await drainMainQueue()
        #expect(store.isHostOffline)
        store.clearLocalSession()
    }

    @Test func timeAwayIsNotCountedAsHostSilence() async throws {
        // Resume: the first tick runs at once, with the value from before the app was suspended.
        let resumed = joinedStore()
        resumed.apply(hostPresence: Fixture.presence(silence: 3))
        resumed.hostPresenceReceivedAt = .now - .seconds(60)
        #expect(resumed.hostLooksOffline())
        resumed.isInBackground = true
        await resumed.handleAppResume()
        await settle()
        #expect(!resumed.isHostOffline)
        #expect(service.count(.claimHost) == 0)
        // A host that really went quiet is still found once its silence passes the limit.
        let restartedAt = try #require(resumed.hostPresenceReceivedAt)
        #expect(resumed.hostLooksOffline(now: restartedAt + .seconds(13)))
        resumed.clearLocalSession()

        // The socket comes back.
        let reconnected = joinedStore()
        reconnected.apply(hostPresence: Fixture.presence(silence: 3))
        socket.send(.connecting)
        await drainMainQueue()
        reconnected.hostPresenceReceivedAt = .now - .seconds(60)
        socket.send(.connected)
        await drainMainQueue()
        #expect(!reconnected.isHostOffline)

        // Unidentified: no new value can arrive, so nothing is concluded.
        let unidentified = joinedStore()
        unidentified.apply(hostPresence: Fixture.presence(silence: 60))
        #expect(unidentified.isHostOffline)
        unidentified.apply(sessionView: Fixture.view(Fixture.session(), userId: nil))
        #expect(unidentified.needsSignIn)
        #expect(!unidentified.isHostOffline)
    }

    @Test func aFailingHeartbeatDoesNotStallTheTick() async {
        service.heartbeatError = BackendError(URLError(.timedOut))
        let store = joinedStore()
        store.apply(hostPresence: Fixture.presence(silence: 20))
        store.startTicking()
        await settle()
        #expect(service.count(.heartbeat) == 1)
        #expect(service.count(.claimHost) == 1, "The host check still runs")

        await clock.advance(by: MultiplayerGameStore.tickInterval)
        #expect(service.count(.heartbeat) == 2)
        #expect(clock.requested.filter { $0 == MultiplayerGameStore.tickInterval }.count == 2)
        store.clearLocalSession()
    }

    @Test func aHeartbeatOrClaimStillWaitingIsNotSentAgain() async {
        let store = joinedStore()
        store.apply(hostPresence: Fixture.presence(silence: 20))
        service.holds = ["heartbeat", "claimHost"] // An outage: neither call has returned yet.
        store.startTicking()
        await settle()
        for _ in 0..<3 { await clock.advance(by: MultiplayerGameStore.tickInterval) }
        #expect(clock.requested.filter { $0 == MultiplayerGameStore.tickInterval }.count == 4, "The tick keeps running")
        #expect(service.count(.heartbeat) == 1, "One heartbeat waits instead of one per tick")
        #expect(service.count(.claimHost) == 1)

        // Their time limit: both throw a timeout, which frees the slot for the next tick.
        service.heartbeatError = BackendError(timedOut: BackendError.stillSending)
        service.claimError = BackendError(timedOut: BackendError.stillSending)
        service.release()
        await settle()
        await clock.advance(by: MultiplayerGameStore.tickInterval)
        #expect(service.count(.heartbeat) == 2)
        #expect(service.count(.claimHost) == 2)
        store.clearLocalSession()
    }

    @Test func ticksRetryAFailedBotSubmissionWithoutANewSnapshot() async {
        let round = UUID()
        let store = joinedStore(Fixture.session(phase: "night", roundId: round), isHost: true)
        let doctor = Fixture.seat(.doctor)
        store.apply(players: [doctor, Fixture.seat(.citizen, bot: false, isMe: true), Fixture.seat(.mafia, bot: false)])
        service.botFailures = ["Choose a player who is still alive."]
        store.apply(roundState: Fixture.round(round))
        await settle()
        #expect(service.botBatches.count == 1)

        store.startTicking()
        await settle()
        #expect(service.botBatches.count == 2)
        #expect(service.botBatches.last?.map(\.botPlayerId) == [doctor.playerId])
        store.clearLocalSession()
    }

    // MARK: - Resume and background (PA-05, PA-06)

    @Test func anOriginalHostTakesTheLobbyBackAfterTheFirstHeartbeatOnResume() async {
        let me = UUID()
        let lobby = Fixture.session(status: .waiting, phase: "lobby", roundId: nil, originalHostUserId: me)
        let store = joinedStore(lobby, userId: me)
        store.isInBackground = true

        await store.handleAppResume()
        await settle()
        #expect(service.calls.prefix(2) == [.heartbeat, .returnToLobby])

        await clock.advance(by: MultiplayerGameStore.tickInterval)
        #expect(service.count(.returnToLobby) == 1, "Only once per resume")
        store.clearLocalSession()
    }

    @Test func noReclaimMidGameOrForOthersOrBeforeAHeartbeatSucceeds() async {
        let me = UUID()
        let running = joinedStore(Fixture.session(originalHostUserId: me), userId: me)
        await running.handleAppResume()
        await settle()
        let someoneElse = joinedStore(Fixture.session(status: .waiting, phase: "lobby", roundId: nil, originalHostUserId: UUID()))
        await someoneElse.handleAppResume()
        await settle()
        #expect(service.count(.returnToLobby) == 0)
        running.clearLocalSession()
        someoneElse.clearLocalSession()

        service.heartbeatError = BackendError(URLError(.timedOut))
        let offline = joinedStore(Fixture.session(status: .waiting, phase: "lobby", roundId: nil, originalHostUserId: me), userId: me)
        await offline.handleAppResume()
        await settle()
        #expect(service.count(.returnToLobby) == 0)
        service.heartbeatError = nil
        await clock.advance(by: MultiplayerGameStore.tickInterval)
        #expect(service.count(.returnToLobby) == 1, "The first heartbeat that succeeds")
        offline.clearLocalSession()
    }

    @Test func backgroundSendsOneLastHeartbeatAndStopsTicking() async {
        let store = joinedStore()
        store.startTicking()
        await settle()
        #expect(service.count(.heartbeat) == 1)

        store.prepareForBackground()
        await settle()
        #expect(store.tickTask == nil)
        #expect(service.count(.heartbeat) == 2)
        #expect(store.finalHeartbeatTask == .invalid, "The background task ends with the heartbeat")
        await clock.advance(by: .seconds(30))
        #expect(service.count(.heartbeat) == 2)
    }

    @Test func theScreenStaysAwakeOnlyWhileAGameRuns() {
        UIApplication.shared.isIdleTimerDisabled = false // Other stores in this run may have set it.
        let store = joinedStore(Fixture.session(status: .waiting, phase: "lobby", roundId: nil))
        #expect(!UIApplication.shared.isIdleTimerDisabled)
        store.apply(sessionView: Fixture.view(Fixture.session(status: .inProgress)))
        #expect(UIApplication.shared.isIdleTimerDisabled)
        store.clearLocalSession()
        #expect(!UIApplication.shared.isIdleTimerDisabled)
    }

    // MARK: - Reconnect banner (PA-07)

    @Test func theBannerShowsAfterTheSocketReconnectsForAWhile() async {
        let store = joinedStore()
        socket.send(.connecting)
        await drainMainQueue()
        #expect(!store.showsReconnectBanner, "A short blip stays quiet")
        await clock.advance(by: MultiplayerGameStore.slowConnectionDelay)
        #expect(store.showsReconnectBanner)

        socket.send(.connected)
        await drainMainQueue()
        #expect(!store.showsReconnectBanner)
    }

    @Test func theBannerShowsWhileATapHasBeenSendingForAWhile() async {
        let store = joinedStore()
        service.holds = ["setReady"]
        let ready = Task { try await store.setReadyStatus(true) }
        await clock.advance(by: .seconds(4))
        #expect(!store.showsReconnectBanner)
        await clock.advance(by: .seconds(1))
        #expect(store.showsReconnectBanner)

        service.release()
        _ = await finishes(ready)
        #expect(!store.showsReconnectBanner)
    }

    @Test func theBannerShowsOnTheThirdFailedRetry() async {
        let store = makeStore()
        store.sessionId = UUID()
        store.startSubscriptions(sessionId: store.sessionId!)
        for attempt in 1...3 {
            service.fail("views:getPlayers")
            await drainMainQueue()
            #expect(store.showsReconnectBanner == (attempt >= 3))
            await clock.advance(by: .seconds(Double(1 << attempt) * 1.2))
        }
        store.clearLocalSession()
    }

    // MARK: - Identity (PA-42)

    @Test func subscriptionsRestartOnlyWhenTheGuestProofChanges() async {
        let suite = "MultiplayerStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let authService = FakeAuthService()
        let auth = AuthStore(authService: authService, keychain: MemoryKeychain(), defaults: defaults, autoRestore: false)
        let store = makeStore()
        store.setAuthStore(auth)
        store.sessionId = UUID()
        store.startSubscriptions(sessionId: store.sessionId!)
        #expect(service.subscribeCount == 4)

        _ = await auth.signInAsGuest(displayName: "Guest") // nil -> this device's proof
        await drainMainQueue()
        #expect(service.subscribeCount == 8)

        // A new identity with the same proof: an account signs in while the guest's merge is
        // still pending, so requests keep carrying the guest proof.
        authService.mergeError = BackendError(URLError(.timedOut))
        let proof = auth.activeGuestProof
        let revision = auth.identityRevision
        await auth.signIn(email: "qa@example.com", password: "test-password")
        await drainMainQueue()
        #expect(auth.identityRevision > revision)
        #expect(auth.activeGuestProof == proof)
        #expect(service.subscribeCount == 8)
        store.clearLocalSession()
    }

    // MARK: - Host helpers

    @Test func assignmentsCoverEverySeatWithServerRoleCounts() {
        for count in 4...19 {
            let players = (0..<count).map { _ in Fixture.seat(nil) }
            let assignments = MultiplayerGameStore.makeAssignments(for: players)
            #expect(Set(assignments.map(\.playerId)) == Set(players.map(\.playerId)))
            #expect(assignments.count == count)
            #expect(Set(assignments.map(\.number)).count == count)
            #expect(assignments.allSatisfy { (1...(count * 2)).contains($0.number) })
            let expected = GameStore.roleDistribution(for: count)
            #expect(assignments.filter { $0.role == .mafia }.count == expected.mafia)
            #expect(assignments.filter { $0.role == .doctor }.count == expected.doctors)
            #expect(assignments.filter { $0.role == .inspector }.count == expected.inspectors)
        }
    }
}
