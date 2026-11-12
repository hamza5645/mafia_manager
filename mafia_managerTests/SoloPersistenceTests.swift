import Foundation
import Testing

@testable import mafia_manager

@MainActor
struct SoloPersistenceTests {
    @Test func resetCancelsThePendingSave() async throws {
        let environment = SoloTestEnvironment()
        defer { environment.removeFiles() }
        let store = environment.makeStore()
        store.assignNumbersAndRoles(names: ["A", "B", "C", "D"])

        // Play Again inside the 300 ms debounce.
        store.resetAll()
        try await Task.sleep(for: .milliseconds(500))

        #expect(!FileManager.default.fileExists(atPath: environment.stateURL.path))
    }

    @Test func saveImmediatelyCancelsThePendingSaveAndWritesCompactJSON() async throws {
        let environment = SoloTestEnvironment()
        defer { environment.removeFiles() }
        let store = environment.makeStore()
        // Schedules a debounced save of the new game.
        store.assignNumbersAndRoles(names: ["A", "B", "C", "D"])

        try environment.persistence.saveImmediately(.empty)
        let written = try Data(contentsOf: environment.stateURL)
        try await Task.sleep(for: .milliseconds(500))

        // The debounced save of the new game did not run afterwards.
        #expect(try Data(contentsOf: environment.stateURL) == written)
        #expect(try JSONDecoder().decode(GameState.self, from: written).players.isEmpty)
        #expect(!String(decoding: written, as: UTF8.self).contains("\n"))
    }

    @Test func skipsWritingAnUnchangedState() throws {
        let environment = SoloTestEnvironment()
        defer { environment.removeFiles() }
        let store = environment.makeStore()
        store.assignNumbersAndRoles(names: ["A", "B", "C", "D"])
        try environment.persistence.saveImmediately(store.state)

        // A file changed behind the store's back shows whether a write happened.
        try Data("marker".utf8).write(to: environment.stateURL)
        try environment.persistence.saveImmediately(store.state)

        #expect(try Data(contentsOf: environment.stateURL) == Data("marker".utf8))
    }

    @Test func setsAnUnreadableSaveAsideAndReportsIt() throws {
        let environment = SoloTestEnvironment()
        defer { environment.removeFiles() }
        try FileManager.default.createDirectory(at: environment.directory, withIntermediateDirectories: true)
        let unreadable = Data(#"{"players": "not a list"}"#.utf8)
        try unreadable.write(to: environment.stateURL)

        let store = environment.makeStore()

        #expect(store.persistenceError == "Your saved game could not be loaded and was set aside.")
        #expect(store.state.players.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: environment.stateURL.path))
        let files = try FileManager.default.contentsOfDirectory(atPath: environment.directory.path)
        let aside = try #require(files.first { $0.hasPrefix("GameState.corrupt-") && $0.hasSuffix(".json") })
        #expect(try Data(contentsOf: environment.directory.appendingPathComponent(aside)) == unreadable)

        // Saving the empty state afterwards leaves the set-aside file alone.
        try environment.persistence.saveImmediately(store.state)
        #expect(try Data(contentsOf: environment.directory.appendingPathComponent(aside)) == unreadable)
    }

    @Test func loadsASaveInTheVersion5Format() throws {
        let environment = SoloTestEnvironment()
        defer { environment.removeFiles() }
        try FileManager.default.createDirectory(at: environment.directory, withIntermediateDirectories: true)
        try Data(Self.version5Save.utf8).write(to: environment.stateURL)

        let store = environment.makeStore()

        #expect(store.persistenceError == nil)
        #expect(store.isFreshSetup == false)
        #expect(store.state.players.map(\.name) == ["Alice", "Bob", "Cara", "Dan", "Bot 1", "Bot 2"])
        #expect(store.state.players.map(\.isBot) == [false, false, false, false, true, true])
        #expect(store.state.currentPhase == .votingIndividual(currentPlayerIndex: 2))
        #expect(store.state.gameID == nil)
        let night = try #require(store.state.nightHistory.first)
        #expect(night.isResolved)
        #expect(night.inspectorResultRole == .mafia)
        #expect(night.aliveMafiaIDs?.count == 2)
        #expect(store.state.currentVotingSession?.votes.count == 2)
        #expect(store.state.dayHistory.count == 1)
    }

    @Test func defaultsFieldsMissingFromOlderSaves() throws {
        var json = try #require(JSONSerialization.jsonObject(with: Data(Self.version5Save.utf8)) as? [String: Any])
        json.removeValue(forKey: "currentPhase")
        json["players"] = (json["players"] as? [[String: Any]])?.map { player in
            player.filter { $0.key != "isBot" }
        }
        json["nightHistory"] = (json["nightHistory"] as? [[String: Any]])?.map { night in
            night.filter { !["id", "isResolved", "mafiaPhaseCompleted"].contains($0.key) }
        }
        json["dayHistory"] = (json["dayHistory"] as? [[String: Any]])?.map { day in
            day.filter { $0.key != "id" }
        }

        let state = try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: json))

        #expect(state.currentPhase == .roleReveal(currentPlayerIndex: 0))
        #expect(state.players.allSatisfy { !$0.isBot })
        #expect(state.nightHistory.first?.isResolved == false)
        #expect(state.dayHistory.count == 1)
    }

    /// A save written by version 5.0 (build 11) through `saveImmediately`,
    /// including the `*PhaseCompleted` keys the model no longer has.
    static let version5Save = """
    {
      "currentPhase" : {
        "votingIndividual" : {
          "currentPlayerIndex" : 2
        }
      },
      "currentVotingSession" : {
        "dayIndex" : 0,
        "id" : "00000000-0000-4000-8000-000000000020",
        "voteCounts" : [

        ],
        "votes" : [
          "00000000-0000-4000-8000-000000000006",
          "00000000-0000-4000-8000-000000000005",
          "00000000-0000-4000-8000-000000000001",
          "00000000-0000-4000-8000-000000000005"
        ]
      },
      "dayHistory" : [
        {
          "dayIndex" : 0,
          "id" : "00000000-0000-4000-8000-000000000030",
          "removedPlayerIDs" : [

          ]
        }
      ],
      "dayIndex" : 1,
      "isGameOver" : false,
      "nightHistory" : [
        {
          "aliveMafiaIDs" : [
            "00000000-0000-4000-8000-000000000001",
            "00000000-0000-4000-8000-000000000006"
          ],
          "doctorNumbers" : [
            7
          ],
          "doctorPhaseCompleted" : false,
          "doctorProtectedPlayerID" : "00000000-0000-4000-8000-000000000002",
          "id" : "00000000-0000-4000-8000-000000000010",
          "inspectorCheckedPlayerID" : "00000000-0000-4000-8000-000000000006",
          "inspectorNumbers" : [
            1
          ],
          "inspectorPhaseCompleted" : false,
          "inspectorResultIsMafia" : true,
          "inspectorResultRole" : "mafia",
          "isResolved" : true,
          "mafiaNumbers" : [
            3,
            11
          ],
          "mafiaPhaseCompleted" : false,
          "mafiaTargetPlayerID" : "00000000-0000-4000-8000-000000000004",
          "nightIndex" : 1,
          "resultingDeaths" : [
            "00000000-0000-4000-8000-000000000004"
          ]
        }
      ],
      "players" : [
        {
          "alive" : true,
          "id" : "00000000-0000-4000-8000-000000000001",
          "isBot" : false,
          "name" : "Alice",
          "number" : 3,
          "role" : "mafia"
        },
        {
          "alive" : true,
          "id" : "00000000-0000-4000-8000-000000000002",
          "isBot" : false,
          "name" : "Bob",
          "number" : 7,
          "role" : "doctor"
        },
        {
          "alive" : true,
          "id" : "00000000-0000-4000-8000-000000000003",
          "isBot" : false,
          "name" : "Cara",
          "number" : 1,
          "role" : "inspector"
        },
        {
          "alive" : false,
          "id" : "00000000-0000-4000-8000-000000000004",
          "isBot" : false,
          "name" : "Dan",
          "number" : 9,
          "role" : "citizen"
        },
        {
          "alive" : true,
          "id" : "00000000-0000-4000-8000-000000000005",
          "isBot" : true,
          "name" : "Bot 1",
          "number" : 5,
          "role" : "citizen"
        },
        {
          "alive" : true,
          "id" : "00000000-0000-4000-8000-000000000006",
          "isBot" : true,
          "name" : "Bot 2",
          "number" : 11,
          "role" : "mafia"
        }
      ]
    }
    """
}
