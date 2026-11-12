import Foundation

@testable import mafia_manager

/// Solo stores that save into their own temporary directory, so tests never
/// read, overwrite or delete the simulator's real `GameState.json` or stats outbox.
@MainActor
final class SoloTestEnvironment {
    let directory: URL
    let persistence: Persistence
    let sender: StatsSender
    let outbox: StatsOutbox
    let notificationCenter = NotificationCenter()

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SoloTests-\(UUID().uuidString)", isDirectory: true)
        persistence = Persistence(directory: directory)
        let sender = StatsSender()
        self.sender = sender
        outbox = StatsOutbox(fileURL: directory.appendingPathComponent("StatsOutbox.json")) { entry in
            try await sender.send(entry)
        }
    }

    var stateURL: URL { directory.appendingPathComponent("GameState.json") }

    func makeStore() -> GameStore {
        GameStore(persistence: persistence, statsOutbox: outbox, notificationCenter: notificationCenter)
    }

    /// Saves `state` and opens a store on it, the way a relaunch would.
    func makeStore(loading state: GameState) throws -> GameStore {
        try persistence.saveImmediately(state)
        return makeStore()
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Polls `condition` on the main actor for up to about a second.
    static func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

/// Stands in for `stats:recordGame`.
@MainActor
final class StatsSender {
    private(set) var sent: [StatsOutbox.Entry] = []
    var failure: Error?

    func send(_ entry: StatsOutbox.Entry) async throws {
        if let failure { throw failure }
        sent.append(entry)
    }
}

enum SoloTestError: Error {
    case offline
}

/// Builds solo states directly, for rules that need exact role counts.
enum SoloStateBuilder {
    static func player(_ role: Role, bot: Bool = false, alive: Bool = true, number: Int) -> Player {
        Player(id: UUID(), number: number, name: bot ? "Bot \(number)" : "Player \(number)", role: role, alive: alive, isBot: bot)
    }

    static func state(_ players: [Player], phase: GamePhase = .nightAction(activeRole: .mafia)) -> GameState {
        GameState(
            players: players, nightHistory: [], dayHistory: [], dayIndex: 0,
            isGameOver: false, winner: nil, currentPhase: phase, gameID: UUID()
        )
    }
}
