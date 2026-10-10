import Foundation
import Testing

@testable import mafia_manager

@MainActor
struct SoloVoteValidationTests {
    @Test func rejectsSelfAndUnknownVotesAndPreservesLockedVote() throws {
        let store = GameStore()
        store.resetAll()
        defer { store.resetAll() }
        store.assignNumbersAndRoles(names: ["QA One", "QA Two", "QA Three", "QA Four"])
        store.startVoting()
        let voter = try #require(store.state.players.first)
        let target = store.state.players[1]
        let other = store.state.players[2]

        #expect(store.recordVote(from: voter.id, for: voter.id) == false)
        #expect(store.recordVote(from: UUID(), for: target.id) == false)
        #expect(store.recordVote(from: voter.id, for: UUID()) == false)
        #expect(store.state.currentVotingSession?.votes.isEmpty == true)
        #expect(store.recordVote(from: voter.id, for: target.id))
        #expect(store.recordVote(from: voter.id, for: other.id) == false)
        #expect(store.state.currentVotingSession?.votes[voter.id] == target.id)
    }

    @Test func rejectsDeadVotersAndTargets() throws {
        let store = GameStore()
        store.resetAll()
        defer { store.resetAll() }
        store.assignNumbersAndRoles(names: ["QA One", "QA Two", "QA Three", "QA Four"])
        let dead = try #require(store.state.players.first)
        let alive = store.state.players[1]
        store.applyDayRemovals(removed: [dead.id: true], notes: [:])
        store.startVoting()

        #expect(store.recordVote(from: dead.id, for: alive.id) == false)
        #expect(store.recordVote(from: alive.id, for: dead.id) == false)
        #expect(store.state.currentVotingSession?.votes.isEmpty == true)
    }
}
