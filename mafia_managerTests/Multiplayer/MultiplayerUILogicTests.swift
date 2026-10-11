import ConvexMobile
import Foundation
import Testing

@testable import mafia_manager

/// The pure helpers behind the multiplayer screens: tally order, host-button errors and the
/// host's "Waiting for" summary.
@MainActor
struct MultiplayerUILogicTests {
    private func player(_ name: String, number: Int?, id: UUID = UUID()) -> PublicPlayerInfo {
        PublicPlayerInfo(
            id: id, playerId: id, playerName: name, playerNumber: number,
            isBot: false, isAlive: true, isOnline: true, isReady: false
        )
    }

    private func serverError(_ message: String) -> BackendError {
        BackendError(ClientError.ConvexError(data: "\"\(message)\""))
    }

    @Test func talliesPutMostVotesFirstAndBreakTiesTheSameWayOnEveryDevice() {
        let one = player("One", number: 1)
        let three = player("Three", number: 3)
        let seven = player("Seven", number: 7)
        let lookup = Dictionary(uniqueKeysWithValues: [one, three, seven].map { ($0.playerId, $0) })
        let counts = [seven.playerId: 2, one.playerId: 1, three.playerId: 2]

        let sorted = MultiplayerVotingResultsView.sortedTallies(counts, lookup: lookup)

        #expect(sorted.map(\.player.playerName) == ["Three", "Seven", "One"])
        #expect(sorted.map(\.votes) == [2, 2, 1])
    }

    @Test func playersMissingFromTheRosterAreKeptAndTieLast() {
        let known = player("Known", number: 4)
        let missing = [UUID(), UUID()].sorted { $0.uuidString < $1.uuidString }
        let counts = [missing[1]: 1, known.playerId: 1, missing[0]: 1]

        let sorted = MultiplayerVotingResultsView.sortedTallies(counts, lookup: [known.playerId: known])

        #expect(sorted.map(\.player.playerId) == [known.playerId, missing[0], missing[1]])
        #expect(sorted.dropFirst().allSatisfy { $0.player.playerName == "Unknown Player" })
    }

    @Test func aRequestThatIsNoLongerNeededIsNotAnError() {
        for message in HostTransition.silentMessages {
            #expect(HostTransition.errorMessage(for: serverError(message)) == nil)
        }
        #expect(HostTransition.errorMessage(for: SessionError.notHost) == nil)
        #expect(HostTransition.errorMessage(for: SessionError.noActiveSession) == nil)
    }

    @Test func aTimeoutSaysStillSendingAndOtherErrorsSayFailed() {
        let timeout = BackendError(timedOut: BackendError.stillSending)
        #expect(HostTransition.errorMessage(for: timeout) == BackendError.stillSending)
        #expect(HostTransition.errorMessage(for: serverError("Game not found."))
            == "Failed to continue: Game not found.")
        #expect(HostTransition.errorMessage(for: SessionError.invalidPhase)
            == "Failed to continue: Cannot perform this action in the current phase")
    }

    /// The literals must be the server's MOVED_ON, NOT_ACTIVE and HOST_ONLY messages.
    @Test func silentMessagesAreTheServerStrings() throws {
        let messages = try #require(MultiplayerRulesParity.loaded?.messages)
        let server = ["MOVED_ON", "NOT_ACTIVE", "HOST_ONLY"].compactMap { messages[$0] }
        #expect(server.count == 3)
        #expect(Set(server) == HostTransition.silentMessages)
        // Settings offers Discard Guest Progress on this prefix, with or without a room code.
        let seatConflict = try #require(messages["MERGE_SEAT_CONFLICT"])
        #expect(seatConflict.hasPrefix(BackendError.mergeSeatConflictPrefix))
    }

    @Test func theWaitingSummaryNamesTwoPlayersAndCountsTheRest() {
        let me = Fixture.seat(.citizen, bot: false, isMe: true)
        let others = (1...4).map { index in
            var seat = Fixture.seat(.citizen, bot: false)
            seat.playerName = "P\(index)"
            return seat
        }

        #expect(WaitingForPlayersSection.summary([me]) == "Waiting for you")
        #expect(WaitingForPlayersSection.summary(Array(others.prefix(2))) == "Waiting for P1, P2")
        #expect(WaitingForPlayersSection.summary(others) == "Waiting for P1, P2 and 2 more")
        #expect(WaitingForPlayersSection.summary([me] + others.prefix(1)) == "Waiting for you, P1")
    }
}
