import Foundation
import SwiftUI
import Combine

@MainActor
final class GameStore: ObservableObject {
    @Published private(set) var state: GameState = .empty
    @Published var isFreshSetup: Bool = true

    init() {
        if let saved = Persistence.shared.load() {
            self.state = saved
            self.isFreshSetup = saved.players.isEmpty
        }
    }

    // MARK: - Setup & Persistence

    var hasSavedGame: Bool { Persistence.shared.hasSavedState() }

    func resetAll() {
        state = .empty
        isFreshSetup = true
        Persistence.shared.reset()
    }

    func loadLastGame() {
        if let saved = Persistence.shared.load() {
            state = saved
            isFreshSetup = saved.players.isEmpty
        }
    }

    func assignNumbersAndRoles(names: [String]) {
        let clean = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard clean.count >= 5 && clean.count <= 19 else { return }
        let unique = Array(NSOrderedSet(array: clean)) as! [String]
        guard unique.count == clean.count else { return }

        // Random unique numbers 1..99
        let count = unique.count
        var numbers = Set<Int>()
        while numbers.count < count {
            numbers.insert(Int.random(in: 1...99))
        }
        var assignedNumbers = Array(numbers)
        assignedNumbers.shuffle()

        // Shuffle names independently for random pairing with roles
        var shuffledNames = unique
        shuffledNames.shuffle()

        // Roles
        let roleCounts = Self.roleDistribution(for: count)
        var roles: [Role] = []
        roles += Array(repeating: .mafia, count: roleCounts.mafia)
        roles += Array(repeating: .doctor, count: roleCounts.doctors)
        roles += Array(repeating: .inspector, count: roleCounts.inspectors)
        let remaining = max(0, count - roles.count)
        roles += Array(repeating: .citizen, count: remaining)
        roles.shuffle()

        // Build players
        var players: [Player] = []
        for (idx, name) in shuffledNames.enumerated() {
            let number = assignedNumbers[idx]
            let role = roles[idx]
            players.append(Player(id: UUID(), number: number, name: name, role: role, alive: true, removalNote: nil))
        }

        state = GameState(players: players, nightHistory: [], dayHistory: [], dayIndex: 0, isGameOver: false, winner: nil)
        isFreshSetup = false
        save()
    }

    private func save() {
        Persistence.shared.save(state)
    }

    // MARK: - Role distribution

    private static func roleDistribution(for playerCount: Int) -> (mafia: Int, doctors: Int, inspectors: Int) {
        let p = min(max(playerCount, 5), 19)
        switch p {
        case 5:
            // 1 Mafia, 1 Inspector (police), 3 Citizens; no Doctor
            return (mafia: 1, doctors: 0, inspectors: 1)
        case 6...8:
            return (mafia: 2, doctors: 1, inspectors: 1)
        case 9...14:
            return (mafia: 4, doctors: 1, inspectors: 2)
        default: // 15...19
            return (mafia: 5, doctors: 2, inspectors: 2)
        }
    }

    // MARK: - Queries

    var alivePlayers: [Player] { state.players.filter { $0.alive } }
    var mafiaPlayers: [Player] { state.players.filter { $0.role == .mafia } }
    var aliveMafia: [Player] { state.players.filter { $0.role == .mafia && $0.alive } }
    var aliveNonMafia: [Player] { state.players.filter { $0.role != .mafia && $0.alive } }
    var currentNightIndex: Int { state.nightHistory.count + 1 }
    var currentDayIndex: Int { state.dayIndex }

    func player(by id: UUID?) -> Player? {
        guard let id else { return nil }
        return state.players.first(where: { $0.id == id })
    }

    func number(for id: UUID?) -> Int? {
        guard let id, let p = player(by: id) else { return nil }
        return p.number
    }

    // MARK: - Night phase

    func endNight(mafiaTargetID: UUID?, inspectorCheckedID: UUID?, doctorProtectedID: UUID?) {
        var resulting: [UUID] = []
        var inspectorResult: Bool?
        var inspectorRole: Role?

        if let inspectID = inspectorCheckedID, let inspected = player(by: inspectID) {
            // Prevent identifying inspectors (police cannot identify police)
            if inspected.role != .inspector {
                inspectorRole = inspected.role
                inspectorResult = (inspected.role == .mafia)
            }
        }

        // Do not auto-remove the mafia target at night.
        // We only log the target; actual removals are handled manually during the Day phase.
        // Still enforce that mafia cannot target mafia; doctor protection is logged but has no removal effect here.
        if let targetID = mafiaTargetID,
           let target = player(by: targetID),
           target.role != .mafia,
           target.alive {
            // Intentionally no state.players[..].alive = false and no resulting death.
        }

        let mafiaNumbers = state.players.filter { $0.role == .mafia }.map { $0.number }.sorted()
        let action = NightAction(
            nightIndex: currentNightIndex,
            mafiaTargetPlayerID: mafiaTargetID,
            inspectorCheckedPlayerID: inspectorCheckedID,
            inspectorResultIsMafia: inspectorResult,
            inspectorResultRole: inspectorRole,
            doctorProtectedPlayerID: doctorProtectedID,
            resultingDeaths: resulting,
            mafiaNumbers: mafiaNumbers
        )
        state.nightHistory.append(action)

        // After night ends, check win condition at start of day
        evaluateWinners(startOfDay: true)

        save()
    }

    // MARK: - Day management

    func applyDayRemovals(removed: [UUID: Bool], notes: [UUID: String]) {
        var removedIDs: [UUID] = []
        for idx in state.players.indices {
            let pid = state.players[idx].id
            if removed[pid] == true, state.players[idx].alive {
                state.players[idx].alive = false
                removedIDs.append(pid)
            }
            if let note = notes[pid], !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.players[idx].removalNote = note
            }
        }
        let dayAction = DayAction(dayIndex: currentDayIndex, removedPlayerIDs: removedIDs)
        state.dayHistory.append(dayAction)
        state.dayIndex += 1

        evaluateWinners(startOfDay: false)

        save()
    }

    // MARK: - Victory

    private func evaluateWinners(startOfDay: Bool) {
        let mafiaCount = aliveMafia.count
        let nonMafiaCount = aliveNonMafia.count

        if mafiaCount == 0 {
            state.isGameOver = true
            state.winner = .citizen // represent villagers team
            return
        }
        if startOfDay && mafiaCount >= nonMafiaCount {
            state.isGameOver = true
            state.winner = .mafia
            return
        }
        // Optional: also end immediately after day if mafia outnumber
        if !startOfDay && mafiaCount >= nonMafiaCount {
            state.isGameOver = true
            state.winner = .mafia
            return
        }
    }

    // MARK: - Export

    func exportLogText(includeNames: Bool) -> String {
        var lines: [String] = []
        lines.append("Mafia Manager Log")
        lines.append("Players: \(state.players.count)")
        let roster = state.players.sorted { $0.number < $1.number }
        for p in roster {
            let base = "#\(p.number)"
            let namePart = includeNames ? " \(p.name)" : ""
            lines.append("  \(base)\(namePart) – \(p.role.displayName)\(p.alive ? " (alive)" : " (removed)")")
        }
        lines.append("")
        for night in state.nightHistory.sorted(by: { $0.nightIndex < $1.nightIndex }) {
            lines.append("Night \(night.nightIndex)")
            lines.append("  Mafia: \(night.mafiaNumbers.map { "#\($0)" }.joined(separator: ", "))")
            if let n = number(for: night.mafiaTargetPlayerID) {
                lines.append("  Mafia targeted: #\(n)")
            } else {
                lines.append("  Mafia targeted: —")
            }
            if let n = number(for: night.inspectorCheckedPlayerID) {
                let res = night.inspectorResultRole?.displayName ?? (night.inspectorResultIsMafia == true ? "Mafia" : (night.inspectorResultIsMafia == false ? "Not Mafia" : "—"))
                lines.append("  Inspector checked: #\(n) → \(res)")
            } else {
                lines.append("  Inspector checked: —")
            }
            if let n = number(for: night.doctorProtectedPlayerID) {
                lines.append("  Doctor protected: #\(n)")
            } else {
                lines.append("  Doctor protected: —")
            }
            if night.resultingDeaths.isEmpty {
                lines.append("  Result: no deaths")
            } else {
                let nums = night.resultingDeaths.compactMap { number(for: $0) }.sorted()
                lines.append("  Result: killed → \(nums.map { "#\($0)" }.joined(separator: ", "))")
            }
            lines.append("")
        }
        for day in state.dayHistory.sorted(by: { $0.dayIndex < $1.dayIndex }) {
            lines.append("Day \(day.dayIndex)")
            if day.removedPlayerIDs.isEmpty {
                lines.append("  Removals: none")
            } else {
                let nums = day.removedPlayerIDs.compactMap { number(for: $0) }.sorted()
                lines.append("  Removals: \(nums.map { "#\($0)" }.joined(separator: ", "))")
            }
            lines.append("")
        }
        if state.isGameOver {
            let winnerText: String
            if state.winner == .mafia {
                winnerText = "Mafia"
            } else {
                winnerText = "Citizens"
            }
            lines.append("Winner: \(winnerText)")
        }
        return lines.joined(separator: "\n")
    }
}
