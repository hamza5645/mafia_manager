import Foundation
import Testing

@testable import mafia_manager

/// Solo must end games exactly as the server does (convex/lib/rules.ts). The
/// shared table is `tests/fixtures/rules-parity.json`, which vitest checks too.
@MainActor
struct SoloRulesParityTests {
    private struct Fixture: Decodable {
        let roleCounts: [RoleCount]
        let winCases: [WinCase]

        enum CodingKeys: String, CodingKey {
            case roleCounts = "role_counts"
            case winCases = "win_cases"
        }
    }

    private struct RoleCount: Decodable {
        let players: Int
        let mafia: Int
        let doctor: Int
        let inspector: Int
    }

    private struct WinCase: Decodable, CustomStringConvertible {
        let mafia: Int
        let nonMafia: Int
        let allBots: Bool
        let after: String
        let over: Bool
        let winner: String?

        enum CodingKeys: String, CodingKey {
            case mafia, after, over, winner
            case nonMafia = "non_mafia"
            case allBots = "all_bots"
        }

        var description: String {
            "\(mafia) mafia vs \(nonMafia), all bots: \(allBots), after a \(after)"
        }
    }

    private func loadFixture() throws -> Fixture {
        // Project.swift copies tests/fixtures/**/*.json flat into the test bundle.
        let url = try #require(
            Bundle(for: BundleToken.self).url(forResource: "rules-parity", withExtension: "json"),
            "rules-parity.json is missing from the test bundle"
        )
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test func endsGamesLikeTheServer() throws {
        let fixture = try loadFixture()
        #expect(!fixture.winCases.isEmpty)

        for winCase in fixture.winCases {
            let environment = SoloTestEnvironment()
            defer { environment.removeFiles() }
            let (state, victim) = Self.state(before: winCase)
            let store = try environment.makeStore(loading: state)

            switch winCase.after {
            case "night":
                store.endNight(mafiaTargetID: victim.id, inspectorCheckedID: nil, doctorProtectedID: nil)
                store.resolveNightOutcome(targetWasSaved: false)
            case "vote":
                var session = VotingSession(dayIndex: store.currentDayIndex)
                session.recordVote(from: UUID(), for: victim.id)
                _ = session.tallyVotes()
                store.setVotingSessionForPreview(session)
                store.applyVotingResult()
            default:
                Issue.record("Unknown resolution point \(winCase.after)")
            }

            #expect(store.state.isGameOver == winCase.over, "\(winCase)")
            #expect(store.state.winner?.rawValue == winCase.winner, "\(winCase)")
        }
    }

    @Test func dealsTheSameRolesAsTheServer() throws {
        let fixture = try loadFixture()
        #expect(fixture.roleCounts.map(\.players) == Array(4...19))

        for count in fixture.roleCounts {
            let solo = GameStore.roleDistribution(for: count.players)
            #expect(solo.mafia == count.mafia, "\(count.players) players")
            #expect(solo.doctors == count.doctor, "\(count.players) players")
            #expect(solo.inspectors == count.inspector, "\(count.players) players")
        }
    }

    /// The survivors the case describes, plus one human citizen whom the night
    /// kills or the vote removes, so the rule runs on exactly those survivors.
    private static func state(before winCase: WinCase) -> (GameState, Player) {
        var number = 0
        func next() -> Int { number += 1; return number }

        let victim = SoloStateBuilder.player(.citizen, number: next())
        var survivors: [Player] = []
        for _ in 0..<winCase.mafia {
            survivors.append(SoloStateBuilder.player(.mafia, bot: true, number: next()))
        }
        for _ in 0..<winCase.nonMafia {
            survivors.append(SoloStateBuilder.player(.citizen, bot: true, number: next()))
        }
        if !winCase.allBots, !survivors.isEmpty {
            survivors[0].isBot = false
        }
        let phase: GamePhase = winCase.after == "vote" ? .votingResults : .nightAction(activeRole: .mafia)
        return (SoloStateBuilder.state([victim] + survivors, phase: phase), victim)
    }
}

private final class BundleToken {}
