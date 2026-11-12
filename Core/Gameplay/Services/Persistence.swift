import Foundation

final class Persistence: @unchecked Sendable {
    static let shared = Persistence(directory: Persistence.defaultDirectory)

    /// Application Support/com.example.mafia_manager, or Documents if that cannot be created.
    static var defaultDirectory: URL {
        let fm = FileManager.default
        if let appSupport = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            return appSupport.appendingPathComponent("com.example.mafia_manager", isDirectory: true)
        }
        return fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Tests pass a temporary directory so they never touch the real save.
    init(directory: URL) {
        self.directory = directory
    }

    // BUG FIX: Add error callback for save failures
    var onSaveError: ((Error) -> Void)?

    // BUG FIX: Debouncing for rapid saves
    private var saveTask: Task<Void, Never>?
    private let saveDebounceDuration: TimeInterval = 0.3 // 300ms
    private let directory: URL
    /// The state last written or loaded; saving an equal state is skipped.
    /// (Compared as values: JSONEncoder's key order is not stable between runs.)
    private var lastWritten: GameState?

    private var stateURL: URL { directory.appendingPathComponent("GameState.json") }

    // BUG FIX: Save with debouncing and error reporting
    func save(_ state: GameState) {
        // Cancel any pending save
        saveTask?.cancel()

        // Schedule new save with debounce
        saveTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(saveDebounceDuration * 1_000_000_000))
                guard !Task.isCancelled else { return }
                try write(state)
            } catch is CancellationError {
                // Ignore cancellation
            } catch {
                // Report error via callback
                onSaveError?(error)
                print("❌ Failed to save game state: \(error.localizedDescription)")
            }
        }
    }

    // BUG FIX: Immediate save without debouncing (for critical operations)
    func saveImmediately(_ state: GameState) throws {
        cancelPendingSave()
        try write(state)
    }

    /// Returns the saved game, or nil when there is none. A file that cannot be
    /// decoded is first moved aside (GameState.corrupt-<timestamp>.json), so no
    /// later save can overwrite it, and the decoding error is rethrown.
    func load() throws -> GameState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        do {
            let state = try JSONDecoder().decode(GameState.self, from: data)
            lastWritten = state
            return state
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = directory.appendingPathComponent("GameState.corrupt-\(stamp).json")
            try? FileManager.default.moveItem(at: stateURL, to: aside)
            lastWritten = nil
            throw error
        }
    }

    func reset() {
        cancelPendingSave()
        lastWritten = nil
        try? FileManager.default.removeItem(at: stateURL)
    }

    private func cancelPendingSave() {
        saveTask?.cancel()
        saveTask = nil
    }

    // PERF: Compact JSON; an unchanged state is not written again.
    private func write(_ state: GameState) throws {
        guard state != lastWritten else { return }
        let data = try JSONEncoder().encode(state)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: stateURL, options: .atomic)
        lastWritten = state
    }
}
