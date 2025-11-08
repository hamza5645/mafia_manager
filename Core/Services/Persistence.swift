import Foundation

final class Persistence: @unchecked Sendable {
    static let shared = Persistence()

    private init() {}

    // BUG FIX: Add error callback for save failures
    var onSaveError: ((Error) -> Void)?

    // BUG FIX: Debouncing for rapid saves
    private var saveTask: Task<Void, Never>?
    private let saveDebounceDuration: TimeInterval = 0.3 // 300ms

    private var folderURL: URL {
        let fm = FileManager.default
        let appSupport = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = appSupport?.appendingPathComponent("com.example.mafia_manager", isDirectory: true)
        if let dir {
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            return dir
        }
        // Fallback to documents
        return fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var stateURL: URL { folderURL.appendingPathComponent("GameState.json") }

    // BUG FIX: Save with debouncing and error reporting
    func save(_ state: GameState) {
        // Cancel any pending save
        saveTask?.cancel()

        // Schedule new save with debounce
        saveTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(saveDebounceDuration * 1_000_000_000))
                guard !Task.isCancelled else { return }

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(state)
                try data.write(to: stateURL, options: .atomic)
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: stateURL, options: .atomic)
    }

    func load() -> GameState? {
        do {
            let data = try Data(contentsOf: stateURL)
            let decoder = JSONDecoder()
            return try decoder.decode(GameState.self, from: data)
        } catch {
            return nil
        }
    }

    func hasSavedState() -> Bool {
        FileManager.default.fileExists(atPath: stateURL.path)
    }

    func reset() {
        try? FileManager.default.removeItem(at: stateURL)
    }
}

