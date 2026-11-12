import Foundation

/// Finished solo games waiting to be recorded with `stats:recordGame`.
///
/// The file sits next to the solo save but apart from it, so Play Again
/// (`Persistence.reset()`) cannot drop a game that has not been sent. An entry
/// leaves only after the server acknowledges it; `stats:recordGame` is
/// idempotent per game id, so a retry after a lost response is safe.
@MainActor
final class StatsOutbox {
    static let shared = StatsOutbox(
        fileURL: Persistence.defaultDirectory.appendingPathComponent("StatsOutbox.json")
    )

    struct Entry: Codable, Equatable, Sendable {
        let gameID: String
        /// The account signed in when the game was queued; nil for a guest or nobody.
        var owner: String?
        let results: [Result]

        enum CodingKeys: String, CodingKey {
            case gameID = "game_id"
            case owner
            case results
        }
    }

    struct Result: Codable, Equatable, Sendable {
        let playerName: String
        let role: Role
        let won: Bool
        let kills: Int

        enum CodingKeys: String, CodingKey {
            case playerName = "player_name"
            case role, won, kills
        }
    }

    /// Bounds the file for someone who never signs in; the oldest game goes first.
    static let maxEntries = 50

    /// Whether there is an identity to record games for. GameStore points it at
    /// its AuthStore; until then, and while signed out, entries wait.
    var canSend: () -> Bool = { false }
    /// The signed-in account's id, or nil for a guest or nobody (see `sendPending`).
    var currentAccount: () -> String? = { nil }

    private let fileURL: URL
    private let send: (Entry) async throws -> Void
    private lazy var entries: [Entry] = Self.read(fileURL)
    private var flushTask: Task<Void, Never>?
    private var flushRequestedAgain = false

    init(fileURL: URL, send: @escaping (Entry) async throws -> Void = StatsOutbox.recordGame) {
        self.fileURL = fileURL
        self.send = send
    }

    var pending: [Entry] { entries }

    /// Stores the game for the account signed in now (replacing an entry with the
    /// same id) and starts a flush.
    func enqueue(_ entry: Entry) {
        var entry = entry
        entry.owner = currentAccount()
        entries.removeAll { $0.gameID == entry.gameID }
        entries.append(entry)
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
        persist()
        Task { await flush() }
    }

    /// Sends the pending games in order and stops at the first failure. A call
    /// made while a flush is running makes that flush run once more.
    func flush() async {
        if let flushTask {
            flushRequestedAgain = true
            await flushTask.value
            return
        }
        let task = Task {
            repeat {
                flushRequestedAgain = false
                await sendPending()
            } while flushRequestedAgain
            flushTask = nil
        }
        flushTask = task
        await task.value
    }

    /// Sign-out forgets the pending games.
    func clear() {
        entries = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// An account's games are sent only while that account is signed in, so they never
    /// land in another account that signs in on this device. A game that ended as a guest
    /// or signed out has no owner and goes to the next identity here, the rule the guest
    /// merge already follows (this device's guest merges into whichever account signs in).
    /// Sign-out clears the outbox.
    private func sendPending() async {
        var attempted = Set<String>()
        func sendable(_ entry: Entry) -> Bool {
            !attempted.contains(entry.gameID) && (entry.owner == nil || entry.owner == currentAccount())
        }
        while canSend(), let entry = entries.first(where: sendable) {
            attempted.insert(entry.gameID)
            do {
                try await send(entry)
            } catch {
                return // Kept for the next flush.
            }
            entries.removeAll { $0.gameID == entry.gameID }
            persist()
        }
    }

    private func persist() {
        do {
            if entries.isEmpty {
                try? FileManager.default.removeItem(at: fileURL)
                return
            }
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            print("❌ [StatsOutbox] Failed to save pending games: \(error.localizedDescription)")
        }
    }

    private static func read(_ url: URL) -> [Entry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    /// A timed-out call may still apply; the retry is safe because the server
    /// records each game id once per caller.
    static func recordGame(_ entry: Entry) async throws {
        try await ConvexService.shared.mutation(
            "stats:recordGame",
            with: ["game_id": entry.gameID, "results": try ConvexJSON(entry.results)],
            timeout: .seconds(30)
        )
    }
}
