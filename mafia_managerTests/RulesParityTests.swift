import Foundation
import Testing

@testable import mafia_manager

/// `tests/fixtures/rules-parity.json`, written from `convex/lib/rules.ts` and
/// `convex/lib/errors.ts` and checked by vitest too. Win cases are tested by the solo suite.
nonisolated struct MultiplayerRulesParity: Decodable, Sendable {
    nonisolated struct RoleCount: Decodable, Sendable, CustomTestStringConvertible {
        let players: Int
        let mafia: Int
        let doctor: Int
        let inspector: Int
        let citizen: Int

        var testDescription: String { "\(players) players" }
    }

    nonisolated struct TargetRule: Decodable, Sendable, CustomTestStringConvertible {
        let actionType: ActionType
        let actorRole: Role
        let targetRole: Role
        let targetAlive: Bool
        let targetIsActor: Bool
        let allowed: Bool

        enum CodingKeys: String, CodingKey {
            case actionType = "action_type"
            case actorRole = "actor_role"
            case targetRole = "target_role"
            case targetAlive = "target_alive"
            case targetIsActor = "target_is_actor"
            case allowed
        }

        var testDescription: String {
            "\(actorRole.rawValue) \(actionType.rawValue) \(targetIsActor ? "self" : targetRole.rawValue)"
                + "\(targetAlive ? "" : " (dead)") -> \(allowed ? "allowed" : "rejected")"
        }
    }

    let roleCounts: [RoleCount]
    let targetRules: [TargetRule]
    /// The complete `E` map: key -> message.
    let messages: [String: String]

    enum CodingKeys: String, CodingKey {
        case roleCounts = "role_counts"
        case targetRules = "target_rules"
        case messages
    }

    private final class BundleToken {}

    /// nil when the fixture is not bundled (see `fixtureIsBundled`).
    static let loaded: MultiplayerRulesParity? = {
        guard let url = Bundle(for: BundleToken.self).url(forResource: "rules-parity", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MultiplayerRulesParity.self, from: data)
    }()
}

@MainActor
struct RulesParityTests {
    @Test func fixtureIsBundled() throws {
        let parity = try #require(MultiplayerRulesParity.loaded, "rules-parity.json is missing from the test bundle or no longer decodes")
        #expect(parity.roleCounts.map(\.players) == Array(4...19))
        #expect(!parity.targetRules.isEmpty)
    }

    @Test(arguments: MultiplayerRulesParity.loaded?.roleCounts ?? [])
    func roleCountsMatchTheSoloTable(_ row: MultiplayerRulesParity.RoleCount) {
        let swift = GameStore.roleDistribution(for: row.players)
        #expect(swift.mafia == row.mafia)
        #expect(swift.doctors == row.doctor)
        #expect(swift.inspectors == row.inspector)
        #expect(row.players - swift.mafia - swift.doctors - swift.inspectors == row.citizen)
    }

    /// `canTarget` mirrors the target checks of `validateGameAction`; the role check is the
    /// server's own, so a rule with the wrong actor role must be rejected regardless.
    @Test(arguments: MultiplayerRulesParity.loaded?.targetRules ?? [])
    func botTargetsFollowTheServerRules(_ rule: MultiplayerRulesParity.TargetRule) {
        let actor = Fixture.seat(rule.actorRole)
        let target = rule.targetIsActor ? actor : Fixture.seat(rule.targetRole, alive: rule.targetAlive)
        let alive = [actor] + (target.id != actor.id && rule.targetAlive ? [target] : [])
        let roles: [ActionType: Role] = [.mafiaTarget: .mafia, .doctorProtect: .doctor, .inspectorCheck: .inspector]
        let roleMatches = roles[rule.actionType].map { $0 == rule.actorRole } ?? true
        let accepted = roleMatches
            && BotDirector.canTarget(target.playerId, actor: actor, actionType: rule.actionType, alive: alive)
        #expect(accepted == rule.allowed)
    }

    @Test func sharedServerMessagesMatchTheSwiftLiterals() throws {
        let messages = try #require(MultiplayerRulesParity.loaded?.messages)
        #expect(messages["AUTH"] == MultiplayerGameStore.signInMessage)
        #expect(messages["GUEST_NOT_FOUND"] == BackendError.guestNotFound)
        let closing = ["NIGHT_CLOSED", "MOVED_ON", "WRONG_PHASE", "NOT_ACTIVE"].compactMap { messages[$0] }
        #expect(Set(closing) == BotDirector.roundClosedMessages)
        #expect(closing.count == 4)
    }
}
