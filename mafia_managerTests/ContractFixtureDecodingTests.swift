import Foundation
import Testing

@testable import mafia_manager

/// Decodes the exact JSON the Convex functions returned in convex-test
/// (`tests/fixtures/contract/contract_<function>_<viewer>.json`, bundled flat into this
/// target) into the app's models, so a server shape change fails here first (api_contract 5).
struct ContractFixtureDecodingTests {
    private final class BundleToken {}

    nonisolated static let bundle = Bundle(for: BundleToken.self)

    /// Nonisolated because `@Test(arguments:)` reads it outside the main actor.
    nonisolated static let fixtureNames: [String] = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
        .map { $0.deletingPathExtension().lastPathComponent }
        .filter { $0.hasPrefix("contract_") }
        .sorted()

    /// Every function whose result the app decodes. `health_check` and `recordGame` are read
    /// by Platform and Solo code through private types; the mirrors below hold the fields they read.
    static let functions = [
        "getSessionView", "getPlayers", "getRoundState", "getHostPresence",
        "finishNight", "submitBotActions", "health_check", "recordGame",
        "createSession", "joinSession",
    ]

    private func json(_ name: String) throws -> Data {
        let url = try #require(Self.bundle.url(forResource: name, withExtension: "json"), "\(name).json is not bundled")
        return try Data(contentsOf: url)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(type, from: try json(name))
    }

    @Test func everyContractFunctionHasABundledFixture() {
        for function in Self.functions {
            #expect(Self.fixtureNames.contains { $0.hasPrefix("contract_\(function)") },
                    "No contract_\(function)_*.json in the test bundle (tests/fixtures/contract)")
        }
    }

    @Test(arguments: fixtureNames)
    func fixtureDecodesIntoTheAppModel(name: String) throws {
        guard let function = Self.functions.first(where: { name.hasPrefix("contract_\($0)") }) else {
            Issue.record("\(name) has no Swift model mapped here; add it")
            return
        }
        switch function {
        case "getSessionView": _ = try decode(SessionView?.self, name)
        case "getPlayers": _ = try decode([SessionPlayer].self, name)
        case "getRoundState": _ = try decode(RoundState?.self, name)
        case "getHostPresence": _ = try decode(HostPresence?.self, name)
        case "finishNight": _ = try decode(NightOutcome.self, name)
        case "submitBotActions": _ = try decode(BotActionResults.self, name)
        case "health_check": _ = try decode(HealthCheck.self, name)
        case "recordGame": _ = try decode(RecordGameResult.self, name)
        case "createSession", "joinSession": _ = try decode(EnterResult.self, name)
        default: Issue.record("Unhandled function \(function)")
        }
    }

    // MARK: - What the store relies on

    @Test func sessionViewsCarryTheViewer() throws {
        let host = try #require(try decode(SessionView?.self, "contract_getSessionView_host"))
        #expect(host.viewer.isHost && host.viewer.isMember && host.viewer.userId == host.session.hostUserId)
        let member = try #require(try decode(SessionView?.self, "contract_getSessionView_member"))
        #expect(member.viewer.isMember && !member.viewer.isHost)
        let outsider = try decode(SessionView?.self, "contract_getSessionView_outsider")
        #expect(outsider?.viewer.isMember != true)
    }

    @Test(arguments: ["contract_getPlayers_host", "contract_getPlayers_mafia", "contract_getPlayers_citizen"])
    func playerListsHaveOneMeAndNoHeartbeat(name: String) throws {
        let players = try decode([SessionPlayer].self, name)
        #expect(players.filter(\.isMe).count == 1)
        let raw = try #require(try JSONSerialization.jsonObject(with: try json(name)) as? [[String: Any]])
        #expect(raw.allSatisfy { $0["last_heartbeat"] == nil }, "Presence moved to views:getHostPresence")
    }

    @Test func rolesAreProjectedPerViewer() throws {
        let citizen = try decode([SessionPlayer].self, "contract_getPlayers_citizen")
        #expect(citizen.filter { $0.role != nil }.map(\.isMe) == [true], "A citizen sees only their own role")
        let mafia = try decode([SessionPlayer].self, "contract_getPlayers_mafia")
        #expect(mafia.compactMap(\.role).allSatisfy { $0 == .mafia }, "Mafia see only the Mafia")
        #expect(mafia.filter { $0.role == .mafia }.count >= 2)
        let host = try decode([SessionPlayer].self, "contract_getPlayers_host")
        #expect(host.allSatisfy { $0.role != nil }, "The host sees every role")
    }

    @Test func hostPresenceIsMeasuredOnTheServerClock() throws {
        let presence = try #require(try decode(HostPresence?.self, "contract_getHostPresence_member"))
        #expect(presence.silenceAtReceipt >= 0)
        #expect([15, 90].contains(presence.staleAfterSeconds))
    }

    @Test func entryResultsSayWhetherTheSeatExistedBefore() throws {
        #expect(try !decode(EnterResult.self, "contract_createSession_host").rejoined)
        #expect(try decode(EnterResult.self, "contract_joinSession_rejoin").rejoined, "A cancelled re-entry keeps this seat")
    }

    @Test func thisBuildMeetsTheServersMinimumContract() throws {
        let health = try decode(HealthCheck.self, "contract_health_check")
        #expect(health.apiContract == ConvexConfig.apiContractVersion)
        #expect(ConvexConfig.apiContractVersion >= health.minClientContract)
    }

    /// `health:check`, as `BackendCompatibility` reads it.
    private struct HealthCheck: Decodable {
        let apiContract: Int
        let minClientContract: Int

        enum CodingKeys: String, CodingKey {
            case apiContract = "api_contract"
            case minClientContract = "min_client_contract"
        }
    }

    /// `stats:recordGame` (`StatsOutbox` ignores the body; the contract still fixes it).
    private struct RecordGameResult: Decodable {
        let recorded: Bool
        let skipped: Int
    }
}
