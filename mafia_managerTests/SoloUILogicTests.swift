import Foundation
import Testing

@testable import mafia_manager

/// Logic seams of the solo screens (NightWakeUpView, VoteResultsView, SetupView).
@MainActor
struct SoloUILogicTests {
    // MARK: - Night bot automation (PA-14)

    @Test func allBotMafiaWaitsForStartNight() {
        let allBots: (Role) -> Bool = { _ in true }

        #expect(NightWakeUpView.botAction(for: .nightWakeUp(activeRole: .mafia), sleepGateUp: true, allBots: allBots) == nil)
        #expect(NightWakeUpView.botAction(for: .nightWakeUp(activeRole: .mafia), sleepGateUp: false, allBots: allBots) == .autoContinue(.mafia))
    }

    @Test func otherAllBotRolesAreNotGated() {
        // The gate state starts out true after a relaunch mid-night; only the Mafia wake-up uses it.
        let allBots: (Role) -> Bool = { _ in true }

        #expect(NightWakeUpView.botAction(for: .nightWakeUp(activeRole: .inspector), sleepGateUp: true, allBots: allBots) == .autoContinue(.inspector))
        #expect(NightWakeUpView.botAction(for: .nightWakeUp(activeRole: .doctor), sleepGateUp: true, allBots: allBots) == .autoContinue(.doctor))
        #expect(NightWakeUpView.botAction(for: .nightAction(activeRole: .mafia), sleepGateUp: true, allBots: allBots) == .takeTurn(.mafia))
        #expect(NightWakeUpView.botAction(for: .nightAction(activeRole: .inspector), sleepGateUp: false, allBots: allBots) == .takeTurn(.inspector))
        #expect(NightWakeUpView.botAction(for: .nightAction(activeRole: .doctor), sleepGateUp: false, allBots: allBots) == .takeTurn(.doctor))
    }

    @Test func rolesWithAHumanAreLeftToTheHumans() {
        let onlyDoctorBots: (Role) -> Bool = { $0 == .doctor }

        #expect(NightWakeUpView.botAction(for: .nightWakeUp(activeRole: .mafia), sleepGateUp: false, allBots: onlyDoctorBots) == nil)
        #expect(NightWakeUpView.botAction(for: .nightWakeUp(activeRole: .inspector), sleepGateUp: false, allBots: onlyDoctorBots) == nil)
        #expect(NightWakeUpView.botAction(for: .nightAction(activeRole: .mafia), sleepGateUp: false, allBots: onlyDoctorBots) == nil)
        #expect(NightWakeUpView.botAction(for: .nightAction(activeRole: .doctor), sleepGateUp: false, allBots: onlyDoctorBots) == .takeTurn(.doctor))
    }

    @Test func botsDoNothingOutsideTheRoleSteps() {
        let allBots: (Role) -> Bool = { _ in true }

        for phase in [GamePhase.nightTransition, .morning, .votingResults, .gameOver, .roleReveal(currentPlayerIndex: 0)] {
            #expect(NightWakeUpView.botAction(for: phase, sleepGateUp: false, allBots: allBots) == nil)
        }
    }

    // MARK: - Vote results order (PA-45)

    @Test func voteResultsBreakTiesByPlayerNumber() {
        let players = [4, 2, 7, 1, 3].map { number in
            Player(id: UUID(), number: number, name: "P\(number)", role: .citizen, alive: true)
        }
        let byNumber = Dictionary(uniqueKeysWithValues: players.map { ($0.number, $0) })
        let counts: [UUID: Int] = [
            byNumber[4]!.id: 2,
            byNumber[2]!.id: 0,
            byNumber[7]!.id: 2,
            byNumber[1]!.id: 0,
            byNumber[3]!.id: 1,
        ]

        let expected = [4, 7, 3, 1, 2]
        // Dictionary order differs per instance; the result must not.
        for _ in 0..<20 {
            let shuffled = Dictionary(uniqueKeysWithValues: counts.shuffled())
            let sorted = VoteResultsView.sortedVoteCounts(shuffled, players: players.shuffled())
            #expect(sorted.map { $0.player.number } == expected)
            #expect(sorted.map { $0.votes } == [2, 2, 1, 0, 0])
        }
    }

    @Test func voteResultsSkipUnknownPlayers() {
        let player = Player(id: UUID(), number: 1, name: "Known", role: .citizen, alive: true)
        let sorted = VoteResultsView.sortedVoteCounts([player.id: 1, UUID(): 3], players: [player])

        #expect(sorted.map { $0.player.id } == [player.id])
    }

    // MARK: - Setup rows (PA-59, PA-66)

    @Test func setupRowsKeepTheirIdentityWhenAnotherRowIsRemoved() {
        var entries = ["Ann", "Ben", "Cat"].map { PlayerEntry(name: $0) }
        let ids = entries.map(\.id)
        #expect(Set(ids).count == 3)

        entries.removeAll { $0.id == ids[1] }

        #expect(entries.map(\.name) == ["Ann", "Cat"])
        #expect(entries.map(\.id) == [ids[0], ids[2]])
    }
}
