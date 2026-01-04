import Foundation
import SwiftUI
import Combine

@MainActor
final class GameStore: ObservableObject {
    @Published private(set) var state: GameState = .empty
    @Published var isFreshSetup: Bool = true
    @Published var flowID: UUID = UUID()
    // BUG FIX: Track persistence errors to show to user
    @Published var persistenceError: String?
    // Store previous player names for "Play Again" feature
    @Published var previousPlayerNames: [String] = []
    // Track previous bot count so the bot slider can be restored accurately
    @Published var previousBotCount: Int = 0
    // Surface setup validation errors to the UI
    @Published var setupError: String?
    // Flag to return directly to solo setup (for "Play Again")
    @Published var returnToSoloSetup: Bool = false

    private let databaseService = DatabaseService()
    // BUG FIX: Use weak reference to prevent potential retain cycle
    private weak var authStore: AuthStore?

    init() {
        // BUG FIX: Set up persistence error callback
        Persistence.shared.onSaveError = { [weak self] error in
            Task { @MainActor in
                self?.persistenceError = "Failed to save game: \(error.localizedDescription)"
            }
        }

        if let saved = Persistence.shared.load() {
            self.state = saved
            self.isFreshSetup = saved.players.isEmpty
        }
    }

    func setAuthStore(_ authStore: AuthStore) {
        self.authStore = authStore
    }

    // MARK: - Setup & Persistence

    var hasSavedGame: Bool { Persistence.shared.hasSavedState() }

    func resetAll() {
        // Preserve human player names and bot count for "Play Again" feature
        var humanNames: [String] = []
        var botCount = 0
        for player in state.players {
            if player.isBot {
                botCount += 1
            } else {
                humanNames.append(player.name)
            }
        }

        previousPlayerNames = humanNames
        previousBotCount = botCount
        setupError = nil
        state = .empty
        isFreshSetup = true
        returnToSoloSetup = true
        Persistence.shared.reset()
        flowID = UUID()
    }

    func loadLastGame() {
        if let saved = Persistence.shared.load() {
            state = saved
            isFreshSetup = saved.players.isEmpty
        }
    }

    func assignNumbersAndRoles(names: [String], numberOfBots: Int = 0, customRoleConfig: CustomRoleConfig? = nil) {
        setupError = nil
        returnToSoloSetup = false
        // SECURITY FIX: Validate all player names
        var validatedNames: [String] = []
        for name in names {
            switch InputValidator.validatePlayerName(name) {
            case .success(let validName):
                if InputValidator.isReservedBotName(validName) {
                    setupError = "\"\(validName)\" is reserved for bot players. Please choose a different name."
                    return
                }

                validatedNames.append(validName)
            case .failure:
                // Skip invalid names
                continue
            }
        }

        // Add bot player names
        var allNames = validatedNames
        let botNames: [String]
        if numberOfBots > 0 {
            botNames = (1...numberOfBots).map { "Bot \($0)" }
            allNames.append(contentsOf: botNames)
        } else {
            botNames = []
        }

        guard allNames.count >= 4 && allNames.count <= 19 else {
            setupError = "Games require between 4 and 19 total players (humans + bots)."
            return
        }

        // Ensure names are unique while preserving order (case-insensitive)
        var seen = Set<String>()
        var unique: [String] = []
        let botNameSet = Set(botNames.map { $0.lowercased() })
        for name in allNames {
            let key = name.lowercased()
            if seen.insert(key).inserted {
                unique.append(name)
            } else {
                if botNameSet.contains(key) {
                    setupError = "Names like \"Bot 1\" are reserved for bot players. Please rename your human or lower the bot count."
                } else {
                    setupError = "Player names must be unique."
                }
                return
            }
        }

        // Random unique numbers from 1..(2 * playerCount)
        // Use explicit SystemRandomNumberGenerator for true randomness
        let count = unique.count
        var rng = SystemRandomNumberGenerator()
        let numberPool = Array(1...(count * 2)).shuffled(using: &rng)
        let assignedNumbers = Array(numberPool.prefix(count))

        // Roles - use custom config if provided, otherwise use default distribution
        let roleCounts: (mafia: Int, doctors: Int, inspectors: Int)

        // BUG FIX: Validate custom role distribution before using
        if let customConfig = customRoleConfig,
           customConfig.roleDistribution.totalPlayers == count {

            let totalCustomRoles = customConfig.roleDistribution.mafiaCount +
                                 customConfig.roleDistribution.doctorCount +
                                 customConfig.roleDistribution.inspectorCount

            // Validate: total roles shouldn't exceed player count
            let validTotalCount = totalCustomRoles <= count
            // Validate: must have at least one mafia
            let validMafiaCount = customConfig.roleDistribution.mafiaCount >= 1

            if validTotalCount && validMafiaCount {
                // Use valid custom role distribution
                roleCounts = (
                    mafia: customConfig.roleDistribution.mafiaCount,
                    doctors: customConfig.roleDistribution.doctorCount,
                    inspectors: customConfig.roleDistribution.inspectorCount
                )
            } else {
                // Invalid config - fall back to default
                if !validTotalCount {
                    print("⚠️ Custom config has \(totalCustomRoles) roles for \(count) players - falling back to default")
                }
                if !validMafiaCount {
                    print("⚠️ Custom config must have at least 1 mafia - falling back to default")
                }
                roleCounts = Self.roleDistribution(for: count)
            }
        } else {
            // No custom config or player count mismatch - use default distribution
            roleCounts = Self.roleDistribution(for: count)
        }

        var roles: [Role] = []
        roles += Array(repeating: .mafia, count: roleCounts.mafia)
        roles += Array(repeating: .doctor, count: roleCounts.doctors)
        roles += Array(repeating: .inspector, count: roleCounts.inspectors)
        let remaining = max(0, count - roles.count)
        roles += Array(repeating: .citizen, count: remaining)
        // Use explicit SystemRandomNumberGenerator for true randomness
        roles.shuffle(using: &rng)

        // Build players - preserve entry order of names
        var players: [Player] = []
        let humanPlayerCount = validatedNames.count
        for (idx, name) in unique.enumerated() {
            let number = assignedNumbers[idx]
            let role = roles[idx]
            // Mark as bot if index is beyond human players
            let isBot = idx >= humanPlayerCount
            players.append(Player(id: UUID(), number: number, name: name, role: role, alive: true, isBot: isBot, removalNote: nil))
        }

        state = GameState(players: players, nightHistory: [], dayHistory: [], dayIndex: 0, isGameOver: false, winner: nil, currentPhase: .roleReveal(currentPlayerIndex: 0))
        isFreshSetup = false
        // Regenerate flowID to trigger NavigationStack rebuild with transition
        flowID = UUID()
        save()
    }

    private func save() {
        Persistence.shared.save(state)
    }

    // MARK: - Phase Management

    func startRoleReveal() {
        state.currentPhase = .roleReveal(currentPlayerIndex: 0)
        save()

        // If the first player is a bot, advance to the first human
        if !state.players.isEmpty && state.players[0].isBot {
            advanceToNextPlayer()
        }
    }

    func revealRoleToPlayer(at index: Int) {
        guard index >= 0 && index < state.players.count else { return }
        state.currentPhase = .roleReveal(currentPlayerIndex: index)
        save()
    }

    func advanceToNextPlayer() {
        guard case .roleReveal(let currentIndex) = state.currentPhase else { return }
        let nextIndex = currentIndex + 1

        if nextIndex >= state.players.count {
            // All players have seen their roles - start night phase
            completeRoleReveal()
        } else {
            // Check if the next player is a bot - if so, skip them
            let nextPlayer = state.players[nextIndex]
            if nextPlayer.isBot {
                // Skip this bot player by recursively advancing
                state.currentPhase = .roleReveal(currentPlayerIndex: nextIndex)
                advanceToNextPlayer()
            } else {
                state.currentPhase = .roleReveal(currentPlayerIndex: nextIndex)
                save()
            }
        }
    }

    func completeRoleReveal() {
        // After all players see their roles, transition to first night
        state.currentPhase = .nightWakeUp(activeRole: .mafia)
        save()
    }

    func wakeUpRole(_ role: Role) {
        state.currentPhase = .nightWakeUp(activeRole: role)
        save()
    }

    func beginRoleAction(_ role: Role) {
        state.currentPhase = .nightAction(activeRole: role)
        save()
    }

    func completeRoleAction() {
        // Determine next role to wake
        guard case .nightAction(let currentRole) = state.currentPhase else { return }

        switch currentRole {
        case .mafia:
            // After mafia, check if police are alive
            if alivePlayers.contains(where: { $0.role == .inspector }) {
                state.currentPhase = .nightTransition
            } else if alivePlayers.contains(where: { $0.role == .doctor }) {
                state.currentPhase = .nightTransition
            } else {
                // No more roles - resolve night outcome (no doctor to save) and go to morning
                resolveNightOutcome(targetWasSaved: false)
                transitionToMorning()
            }
        case .inspector:
            // After police, check if doctor is alive
            if alivePlayers.contains(where: { $0.role == .doctor }) {
                state.currentPhase = .nightTransition
            } else {
                // No doctor - resolve night outcome (no doctor to save) and go to morning
                resolveNightOutcome(targetWasSaved: false)
                transitionToMorning()
            }
        case .doctor:
            // After doctor, always go to morning
            // Note: NightWakeUpView calls resolveNightOutcome before this
            transitionToMorning()
        case .citizen:
            // Citizens don't have night actions
            break
        }
        save()
    }

    func transitionToNextRole() {
        guard case .nightTransition = state.currentPhase else { return }

        // Determine which role wakes up next based on who acted last
        // Since we're in transition, we need to figure out what happened before

        // Simple approach: check night history to see what actions were recorded
        // For now, use a simple order: Mafia → Police → Doctor

        // If we have current night actions, determine next role
        let currentNight = state.nightHistory.last

        if currentNight == nil {
            // No actions yet, start with mafia
            state.currentPhase = .nightWakeUp(activeRole: .mafia)
        } else if currentNight?.inspectorCheckedPlayerID == nil && alivePlayers.contains(where: { $0.role == .inspector }) {
            // Mafia done, police not done yet
            state.currentPhase = .nightWakeUp(activeRole: .inspector)
        } else if currentNight?.doctorProtectedPlayerID == nil && alivePlayers.contains(where: { $0.role == .doctor }) {
            // Police done (or skipped), doctor not done yet
            state.currentPhase = .nightWakeUp(activeRole: .doctor)
        } else {
            // All roles done - resolve if no doctor acted
            // Check if doctor exists in game (not just alive)
            let hasDoctor = state.players.contains(where: { $0.role == .doctor })
            if !hasDoctor || currentNight?.doctorProtectedPlayerID == nil {
                // No doctor in game or doctor didn't protect - resolve outcome
                let wasSaved = currentNight?.mafiaTargetPlayerID == currentNight?.doctorProtectedPlayerID
                resolveNightOutcome(targetWasSaved: wasSaved)
            }
            transitionToMorning()
        }
        save()
    }

    func transitionToMorning() {
        // Don't overwrite gameOver phase - game may have ended during night resolution
        guard !state.isGameOver else { return }
        state.currentPhase = .morning
        save()
    }

    func transitionToDeathReveal() {
        state.currentPhase = .deathReveal
        save()
    }

    func transitionToDay() {
        // Skip the old day management view and go directly to voting
        startVoting()
    }

    func transitionToGameOver() {
        state.currentPhase = .gameOver
        save()
    }

    // MARK: - Voting Phase

    func startVoting() {
        // Create new voting session
        state.currentVotingSession = VotingSession(dayIndex: currentDayIndex)

        // Auto-cast all bot votes first
        let aliveBots = state.players.filter { $0.alive && $0.isBot }
        let botService = BotDecisionService()

        for bot in aliveBots {
            // HAMZA-FIX: chooseVotingTarget now returns non-optional UUID (always votes)
            let targetID = botService.chooseVotingTarget(
                botPlayer: bot,
                alivePlayers: alivePlayers,
                nightHistory: state.nightHistory,
                dayHistory: state.dayHistory
            )
            recordVote(from: bot.id, for: targetID)
        }

        // If there are bots, show their votes first
        if !aliveBots.isEmpty {
            state.currentPhase = .botVotingReveal
        } else {
            // No bots, go directly to first human voter
            startHumanVoting()
        }

        save()
    }

    func startHumanVoting() {
        // Find first alive human player
        if let firstHumanIndex = state.players.firstIndex(where: { $0.alive && !$0.isBot }) {
            state.currentPhase = .votingIndividual(currentPlayerIndex: firstHumanIndex)
        } else {
            // No human players alive, go directly to results
            completeVoting()
        }
        save()
    }

    func recordVote(from voterID: UUID, for targetID: UUID) {
        guard var votingSession = state.currentVotingSession else { return }
        votingSession.recordVote(from: voterID, for: targetID)
        state.currentVotingSession = votingSession
        save()
    }

    func advanceToNextVoter() {
        guard case .votingIndividual(let currentIndex) = state.currentPhase else { return }

        // Find next alive human player after current index
        let nextHumanIndex = state.players[(currentIndex + 1)...].firstIndex(where: { $0.alive && !$0.isBot })

        if let nextIndex = nextHumanIndex {
            // Found next human player
            state.currentPhase = .votingIndividual(currentPlayerIndex: nextIndex)
            save()
        } else {
            // No more human players - all voting complete
            completeVoting()
        }
    }

    func completeVoting() {
        guard var votingSession = state.currentVotingSession else { return }

        // Tally votes and determine elimination
        _ = votingSession.tallyVotes()
        state.currentVotingSession = votingSession

        // Transition to results view
        state.currentPhase = .votingResults
        save()
    }

    func applyVotingResult() {
        guard let votingSession = state.currentVotingSession,
              let eliminatedID = votingSession.eliminatedPlayerID else {
            // No elimination (tie or no votes) - move to next night
            state.currentVotingSession = nil
            wakeUpRole(.mafia)
            return
        }

        // Mark player as eliminated
        if let index = state.players.firstIndex(where: { $0.id == eliminatedID }) {
            state.players[index].alive = false
        }

        // Record in day history
        let dayAction = DayAction(dayIndex: currentDayIndex, removedPlayerIDs: [eliminatedID])
        state.dayHistory.append(dayAction)
        state.dayIndex += 1

        // Clear voting session
        state.currentVotingSession = nil

        // Check for winners
        evaluateWinners(startOfDay: false)

        // If game isn't over, start next night
        if !state.isGameOver {
            wakeUpRole(.mafia)
        }

        save()
    }

    // MARK: - Role distribution

    static func roleDistribution(for playerCount: Int) -> (mafia: Int, doctors: Int, inspectors: Int) {
        let p = min(max(playerCount, 4), 19)
        switch p {
        case 4:
            // 1 Mafia, 1 Police, 2 Citizens; no Doctor
            return (mafia: 1, doctors: 0, inspectors: 1)
        case 5:
            // 1 Mafia, 1 Police, 3 Citizens; no Doctor
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
    var botPlayers: [Player] { state.players.filter { $0.isBot } }
    var humanPlayers: [Player] { state.players.filter { !$0.isBot } }
    var aliveBots: [Player] { state.players.filter { $0.isBot && $0.alive } }
    var aliveHumans: [Player] { state.players.filter { !$0.isBot && $0.alive } }
    var currentNightIndex: Int {
        if let lastNight = state.nightHistory.last {
            // If last night is resolved, we're on the next night
            // If last night is not resolved, we're still on that night
            return lastNight.isResolved ? lastNight.nightIndex + 1 : lastNight.nightIndex
        } else {
            // No history yet, we're on night 1
            return 1
        }
    }
    var currentDayIndex: Int { state.dayIndex }

    // MARK: - Role-based queries

    func playersWithRole(_ role: Role) -> [Player] {
        state.players.filter { $0.role == role }
    }

    func alivePlayersWithRole(_ role: Role) -> [Player] {
        state.players.filter { $0.role == role && $0.alive }
    }

    func allBotsForRole(_ role: Role) -> Bool {
        let alivePlayers = alivePlayersWithRole(role)
        guard !alivePlayers.isEmpty else { return false }
        return alivePlayers.allSatisfy { $0.isBot }
    }

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
        let resulting: [UUID] = []
        var inspectorResult: Bool?
        var inspectorRole: Role?

        if let inspectID = inspectorCheckedID, let inspected = player(by: inspectID) {
            // Prevent police from identifying other police members
            if inspected.role == .inspector {
                // BUG FIX: Provide feedback that inspector was blocked
                // Set role to .inspector so UI knows what happened, but keep boolean nil
                inspectorRole = .inspector
                inspectorResult = nil
            } else {
                inspectorRole = inspected.role
                inspectorResult = (inspected.role == .mafia)
            }
        }

        // BUG FIX: Validate mafia targeting rules
        // Mafia cannot target another mafia member or dead players
        if let targetID = mafiaTargetID, let target = player(by: targetID) {
            if target.role == .mafia {
                print("⚠️ Invalid: Mafia attempted to target another mafia member (#\(target.number))")
                // Continue anyway - action will be recorded but targeting rules violated
            } else if !target.alive {
                print("⚠️ Invalid: Mafia attempted to target dead player (#\(target.number))")
                // Continue anyway - action will be recorded but targeting rules violated
            }
        }

        let mafiaNumbers = state.players.filter { $0.role == .mafia }.map { $0.number }.sorted()
        // BUG FIX: Track alive mafia IDs for accurate kill attribution
        let aliveMafiaIDs = state.players.filter { $0.role == .mafia && $0.alive }.map { $0.id }

        let action = NightAction(
            nightIndex: currentNightIndex,
            mafiaTargetPlayerID: mafiaTargetID,
            inspectorCheckedPlayerID: inspectorCheckedID,
            inspectorResultIsMafia: inspectorResult,
            inspectorResultRole: inspectorRole,
            doctorProtectedPlayerID: doctorProtectedID,
            resultingDeaths: resulting,
            mafiaNumbers: mafiaNumbers,
            aliveMafiaIDs: aliveMafiaIDs
        )

        // Update existing night action if it exists, or append new one
        if let existingIndex = state.nightHistory.lastIndex(where: { $0.nightIndex == currentNightIndex }) {
            state.nightHistory[existingIndex] = action
        } else {
            state.nightHistory.append(action)
        }

        save()
    }

    func resolveNightOutcome(targetWasSaved: Bool) {
        guard let lastIndex = state.nightHistory.indices.last else { return }
        var action = state.nightHistory[lastIndex]

        // BUG FIX: Guard against duplicate resolution using isResolved flag
        guard !action.isResolved else {
            print("⚠️ Night \(action.nightIndex) outcome already resolved")
            return
        }

        // Note: We clear and rebuild resultingDeaths to ensure clean state
        action.resultingDeaths.removeAll()

        if !targetWasSaved,
           let targetID = action.mafiaTargetPlayerID,
           let playerIndex = state.players.firstIndex(where: { $0.id == targetID }) {
            if state.players[playerIndex].alive {
                state.players[playerIndex].alive = false
            }
            action.resultingDeaths = [targetID]
        }

        // Mark this night as resolved
        action.isResolved = true

        state.nightHistory[lastIndex] = action

        // After resolving the night outcome we check if a team has already won.
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

    // MARK: - Cloud Sync

    func syncPlayerStatsToCloud() async {
        guard let userId = authStore?.currentUserId,
              authStore?.isAuthenticated == true,
              state.isGameOver,
              let winner = state.winner else { return }

        // BUG FIX: Calculate kills per player using accurate alive mafia tracking
        var killsPerPlayer: [UUID: Int] = [:]
        for night in state.nightHistory {
            if night.resultingDeaths.first != nil {
                // Use new aliveMafiaIDs field if available (post-fix), fall back to old logic
                if let aliveMafiaIDs = night.aliveMafiaIDs {
                    // New accurate method: use tracked alive mafia IDs
                    for mafiaID in aliveMafiaIDs {
                        killsPerPlayer[mafiaID, default: 0] += 1
                    }
                } else {
                    // Old fallback method (for backward compatibility with old saves)
                    let aliveMafiaInNight = state.players.filter { player in
                        player.role == .mafia &&
                        night.mafiaNumbers.contains(player.number)
                    }
                    for mafiaPlayer in aliveMafiaInNight {
                        killsPerPlayer[mafiaPlayer.id, default: 0] += 1
                    }
                }
            }
        }

        // Sync stats for each player
        for player in state.players {
            let playerWon = (winner == .mafia && player.role == .mafia) ||
                           (winner != .mafia && player.role != .mafia)
            let kills = killsPerPlayer[player.id] ?? 0

            do {
                try await databaseService.upsertPlayerStat(
                    userId: userId,
                    playerName: player.name,
                    role: player.role,
                    won: playerWon,
                    kills: kills
                )
            } catch {
                // Continue with other players even if one fails
                // In production, this should log to a proper logging system
            }
        }
    }

    // MARK: - Victory

    private func evaluateWinners(startOfDay: Bool) {
        // BUG FIX: Prevent re-evaluation if game is already over
        guard !state.isGameOver else { return }

        let mafiaCount = aliveMafia.count
        let nonMafiaCount = aliveNonMafia.count
        let totalAlive = mafiaCount + nonMafiaCount

        // Edge case: Everyone is dead - game ends with no winner
        if totalAlive == 0 {
            state.isGameOver = true
            state.winner = nil // No winner - everyone died
            state.currentPhase = .gameOver
            return
        }

        // Citizens win: All mafia eliminated
        if mafiaCount == 0 {
            state.isGameOver = true
            state.winner = .citizen // represent villagers team
            state.currentPhase = .gameOver
            return
        }

        // Mafia majority check - timing determines threshold
        // startOfDay=true (after night): Mafia needs strict majority (> non-mafia)
        //   - Tie means citizens can still vote out a Mafia member
        // startOfDay=false (after voting): Mafia needs >= non-mafia
        //   - Tie means Mafia will kill at night, guaranteeing majority
        if startOfDay {
            // After night resolution: strict majority required
            if mafiaCount > nonMafiaCount {
                state.isGameOver = true
                state.winner = .mafia
                state.currentPhase = .gameOver
                return
            }
        } else {
            // After voting (going into night): tie or majority = Mafia wins
            if mafiaCount >= nonMafiaCount {
                state.isGameOver = true
                state.winner = .mafia
                state.currentPhase = .gameOver
                return
            }
        }
    }

    func endGameEarly() {
        // End game early without determining a winner
        // Could optionally determine winner based on current state
        state.isGameOver = true
        state.winner = nil
        state.currentPhase = .gameOver
        save()
    }

    // MARK: - Testing Helpers

    #if DEBUG
    func setVotingSessionForPreview(_ session: VotingSession) {
        state.currentVotingSession = session
    }
    #endif

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
                lines.append("  Police checked: #\(n) → \(res)")
            } else {
                lines.append("  Police checked: —")
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
            lines.append("Day \(day.dayIndex + 1)")
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
            } else if state.winner == .citizen {
                winnerText = "Citizens"
            } else {
                winnerText = "No Winner (Everyone Died)"
            }
            lines.append("Winner: \(winnerText)")
        }
        return lines.joined(separator: "\n")
    }
}
