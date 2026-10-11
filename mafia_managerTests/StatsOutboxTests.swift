import Foundation
import Testing

@testable import mafia_manager

@MainActor
struct StatsOutboxTests {
    private func entry(_ id: String = UUID().uuidString.lowercased()) -> StatsOutbox.Entry {
        StatsOutbox.Entry(gameID: id, results: [
            .init(playerName: "Alice", role: .mafia, won: true, kills: 2),
            .init(playerName: "Bob", role: .citizen, won: false, kills: 0),
        ])
    }

    @Test func encodesTheRecordGameArguments() throws {
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry("g1"))) as? [String: Any]
        #expect(json?["game_id"] as? String == "g1")
        let first = (json?["results"] as? [[String: Any]])?.first
        #expect(first?["player_name"] as? String == "Alice")
        #expect(first?["role"] as? String == "mafia")
        #expect(first?["won"] as? Bool == true)
        #expect(first?["kills"] as? Int == 2)
    }

    @Test func removesAnEntryOnlyAfterTheServerAcknowledgesIt() async {
        let environment = SoloTestEnvironment()
        defer { environment.removeFiles() }
        let outbox = environment.outbox
        outbox.canSend = { true }
        environment.sender.failure = SoloTestError.offline

        outbox.enqueue(entry("g1"))
        await outbox.flush()
        #expect(outbox.pending.map(\.gameID) == ["g1"])
        #expect(environment.sender.sent.isEmpty)

        environment.sender.failure = nil
        await outbox.flush()
        #expect(outbox.pending.isEmpty)
        #expect(environment.sender.sent.map(\.gameID) == ["g1"])
        #expect(!FileManager.default.fileExists(atPath: environment.directory.appendingPathComponent("StatsOutbox.json").path))
    }

    @Test func keepsEntriesWhileSignedOut() async {
        let environment = SoloTestEnvironment()
        defer { environment.removeFiles() }
        let outbox = environment.outbox

        outbox.enqueue(entry("g1"))
        await outbox.flush()

        #expect(environment.sender.sent.isEmpty)
        #expect(outbox.pending.map(\.gameID) == ["g1"])
    }

    @Test func anAccountsGamesAreSentOnlyForThatAccount() async {
        let environment = SoloTestEnvironment()
        defer { environment.removeFiles() }
        let outbox = environment.outbox
        var account: String? = "account-a"
        outbox.canSend = { true }
        outbox.currentAccount = { account }
        environment.sender.failure = SoloTestError.offline
        outbox.enqueue(entry("a-game")) // A finishes a game offline.
        await outbox.flush()
        environment.sender.failure = nil

        // A's session lapses and B signs in on this device: A's game is not B's.
        account = "account-b"
        outbox.enqueue(entry("b-game"))
        await outbox.flush()
        #expect(environment.sender.sent.map(\.gameID) == ["b-game"])
        #expect(outbox.pending.map(\.gameID) == ["a-game"])
        #expect(outbox.pending.first?.owner == "account-a")

        account = nil // A guest is not A either.
        await outbox.flush()
        #expect(outbox.pending.map(\.gameID) == ["a-game"])

        account = "account-a"
        await outbox.flush()
        #expect(environment.sender.sent.map(\.gameID) == ["b-game", "a-game"])
        #expect(outbox.pending.isEmpty)
    }

    @Test func aGameWithoutAnAccountGoesToTheNextIdentity() async {
        let environment = SoloTestEnvironment()
        defer { environment.removeFiles() }
        let outbox = environment.outbox
        outbox.enqueue(entry("g1")) // Played signed out (or as a guest): no owner.
        #expect(outbox.pending.first?.owner == nil)

        // Like this device's guest progress, it goes to whoever signs in here next.
        outbox.canSend = { true }
        outbox.currentAccount = { "account-b" }
        await outbox.flush()
        #expect(environment.sender.sent.map(\.gameID) == ["g1"])
    }

    @Test func persistsAcrossLaunchesAndClearEmptiesIt() {
        let environment = SoloTestEnvironment()
        defer { environment.removeFiles() }
        let url = environment.directory.appendingPathComponent("StatsOutbox.json")
        environment.outbox.currentAccount = { "account-a" }
        environment.outbox.enqueue(entry("g1"))
        environment.outbox.enqueue(entry("g2"))
        environment.outbox.enqueue(entry("g1")) // the same game again replaces it

        let relaunched = StatsOutbox(fileURL: url) { _ in }
        #expect(relaunched.pending.map(\.gameID) == ["g2", "g1"])
        #expect(relaunched.pending.map(\.owner) == ["account-a", "account-a"], "The owner is saved too")

        relaunched.clear()
        #expect(relaunched.pending.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(StatsOutbox(fileURL: url) { _ in }.pending.isEmpty)
    }

    @Test func keepsOnlyTheNewestEntries() {
        let environment = SoloTestEnvironment()
        defer { environment.removeFiles() }

        for index in 0...StatsOutbox.maxEntries {
            environment.outbox.enqueue(entry("g\(index)"))
        }

        #expect(environment.outbox.pending.count == StatsOutbox.maxEntries)
        #expect(environment.outbox.pending.first?.gameID == "g1")
    }

    @Test func gameStoreFlushesWhenTheAppBecomesActive() async {
        let environment = SoloTestEnvironment()
        defer { environment.removeFiles() }
        let store = environment.makeStore()
        environment.outbox.enqueue(entry("g1"))
        await environment.outbox.flush()
        #expect(environment.sender.sent.isEmpty)

        environment.outbox.canSend = { true }
        environment.notificationCenter.post(name: .appDidBecomeActive, object: nil)

        #expect(await SoloTestEnvironment.eventually { environment.sender.sent.count == 1 })
        #expect(environment.outbox.pending.isEmpty)
        _ = store
    }

    @Test func gameStoreFlushesWhenTheIdentityChanges() async {
        let environment = SoloTestEnvironment()
        defer { environment.removeFiles() }
        let suiteName = "StatsOutboxTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let authStore = AuthStore(
            authService: FakeAuthService(), keychain: MemoryKeychain(), defaults: defaults,
            notificationCenter: NotificationCenter(), autoRestore: false
        )
        let store = environment.makeStore()
        store.setAuthStore(authStore)
        environment.outbox.enqueue(entry("g1"))
        await environment.outbox.flush()
        #expect(environment.sender.sent.isEmpty, "Signed out: the game waits")

        #expect(await authStore.signInAsGuest(displayName: "Guest"))

        #expect(await SoloTestEnvironment.eventually { environment.sender.sent.count == 1 })
        #expect(environment.outbox.pending.isEmpty)
    }
}
