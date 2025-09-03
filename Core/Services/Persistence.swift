import Foundation

final class Persistence: @unchecked Sendable {
    static let shared = Persistence()

    private init() {}

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

    func save(_ state: GameState) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            print("[Persistence] Save error: \(error)")
        }
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

