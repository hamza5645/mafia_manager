import ConvexMobile
import Foundation
import Testing

@testable import mafia_manager

@MainActor
struct MultiplayerStoreTests {
    // MARK: - Derived values

    @Test func myPlayerAndTeammatesComeFromTheServerIsMeFlag() {
        let store = MultiplayerGameStore()
        let me = Fixture.seat(.mafia, bot: false, isMe: true)
        let teammate = Fixture.seat(.mafia)
        let citizen = Fixture.seat(.citizen, bot: false)
        store.players = [teammate, me, citizen]

        #expect(store.myPlayer?.id == me.id)
        #expect(store.myRole == .mafia)
        #expect(store.mafiaTeammatePlayerIds == [teammate.playerId])
        #expect(store.visiblePlayers.map(\.id) == [teammate.id, me.id, citizen.id])

        store.players = [teammate, citizen]
        #expect(store.myPlayer == nil)
        #expect(store.mafiaTeammates.isEmpty)
    }

    @Test func playersInLobbyCountCountsReadySeats() {
        let store = MultiplayerGameStore()
        store.players = [Fixture.seat(.citizen, ready: true), Fixture.seat(nil, bot: false, ready: false),
                         Fixture.seat(nil, bot: false, ready: true)]
        #expect(store.playersInLobbyCount == 2)
    }

    @Test func phaseReadinessComesOnlyFromTheServer() {
        let store = MultiplayerGameStore()
        #expect(!store.isPhaseReadyToAdvance)
        store.roundState = Fixture.round(ready: true)
        #expect(store.isPhaseReadyToAdvance)
        store.roundState = Fixture.round(ready: false)
        #expect(!store.isPhaseReadyToAdvance)
    }

    @Test func tentativeCountsUseTheCurrentRoundStateOnly() {
        let store = MultiplayerGameStore()
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
        let store = MultiplayerGameStore()
        let me = Fixture.seat(.inspector, bot: false, isMe: true)
        let suspect = Fixture.seat(.mafia)
        var check = Fixture.action(me, .inspectorCheck, target: suspect)
        check.actionData = ActionData(inspectorResult: "mafia")
        store.players = [me, suspect]
        store.roundState = Fixture.round(actions: [Fixture.action(suspect, .mafiaTarget, target: me), check])
        #expect(store.myNightAction?.actionData?.inspectorResult == "mafia")
    }

    // MARK: - Membership

    @Test func losingMembershipEndsTheSessionAsAKick() {
        let store = MultiplayerGameStore()
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
            let store = MultiplayerGameStore()
            store.sessionId = UUID()
            store.apply(sessionView: snapshot)
            #expect(store.wasKicked)
            #expect(!store.isInSession)
        }
    }

    @Test func anUnidentifiedViewerKeepsTheGameAndAsksToSignIn() {
        let store = MultiplayerGameStore()
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
        let store = MultiplayerGameStore()
        store.sessionId = UUID()
        store.apply(sessionView: Fixture.view(Fixture.session(roundId: nil)))
        let waiting = Task { try await store.currentRoundId() }
        for _ in 0..<10 { await Task.yield() }

        let round = UUID()
        store.apply(sessionView: Fixture.view(Fixture.session(roundId: round)))
        #expect(try await waiting.value == round)
    }

    @Test func leavingStopsWaitingForARound() async {
        let store = MultiplayerGameStore()
        store.sessionId = UUID()
        store.apply(sessionView: Fixture.view(Fixture.session(roundId: nil)))
        let waiting = Task { try await store.currentRoundId() }
        for _ in 0..<10 { await Task.yield() }

        store.clearLocalSession()
        await #expect(throws: SessionError.self) { try await waiting.value }
    }

    @Test func voluntaryLeaveIsNotAKick() {
        let store = MultiplayerGameStore()
        store.sessionId = UUID()
        store.isLeaving = true
        store.apply(sessionView: Fixture.view(Fixture.session(), isMember: false))
        #expect(!store.wasKicked)
    }

    @Test func snapshotsAfterLeavingAreIgnored() {
        let store = MultiplayerGameStore()
        store.apply(players: [Fixture.seat(.citizen)])
        store.apply(sessionView: Fixture.view(Fixture.session()))
        #expect(store.players.isEmpty)
        #expect(store.currentSession == nil)
        #expect(!store.wasKicked)
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

    @Test func nextHostIsTheEarliestLivingHumanWithAFreshHeartbeat() {
        let now = Date()
        let host = Fixture.seat(.citizen, bot: false, joinedAt: now - 100, lastHeartbeat: now - 60)
        let stale = Fixture.seat(.citizen, bot: false, joinedAt: now - 90, lastHeartbeat: now - 30)
        let dead = Fixture.seat(.citizen, bot: false, alive: false, joinedAt: now - 80)
        let bot = Fixture.seat(.citizen, joinedAt: now - 70)
        let fresh = Fixture.seat(.citizen, bot: false, joinedAt: now - 60, lastHeartbeat: now - 5)
        let later = Fixture.seat(.citizen, bot: false, joinedAt: now - 50, lastHeartbeat: now)
        let players = [later, host, stale, dead, bot, fresh]
        let next = MultiplayerGameStore.nextHost(in: players, excluding: host.userId!, now: now)
        #expect(next?.id == fresh.id)
    }
}
