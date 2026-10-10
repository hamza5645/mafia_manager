import Foundation

/// Host-only phase requests. The server checks each transition and computes every outcome;
/// all calls are safe to retry (api_contract 4, §8.2).
extension MultiplayerGameStore {
    func startGame() async throws {
        guard isHost, let sessionId else { throw SessionError.notHost }
        guard (4...19).contains(players.count) else { throw SessionError.invalidPhase }
        try await sessionService.startGame(sessionId: sessionId, assignments: Self.makeAssignments(for: players))
    }

    /// Shuffled seats get roles from `GameStore.roleDistribution` and numbers from a shuffle of 1...2N.
    static func makeAssignments(for players: [SessionPlayer]) -> [RoleAssignment] {
        let count = players.count
        var rng = SystemRandomNumberGenerator()
        let numbers = Array(Array(1...(count * 2)).shuffled(using: &rng).prefix(count))

        let roleCounts = GameStore.roleDistribution(for: count)
        var roles: [Role] = []
        roles += Array(repeating: .mafia, count: roleCounts.mafia)
        roles += Array(repeating: .doctor, count: roleCounts.doctors)
        roles += Array(repeating: .inspector, count: roleCounts.inspectors)
        roles += Array(repeating: .citizen, count: max(0, count - roles.count))
        roles.shuffle(using: &rng)

        // Shuffle seats too so join order never decides who gets which role.
        return players.shuffled(using: &rng).enumerated().map { index, player in
            RoleAssignment(playerId: player.playerId, role: roles[index], number: numbers[index])
        }
    }

    /// Starts the first night even if not everyone has confirmed their role.
    func forceStartNight() async throws {
        try await advance(to: .night)
    }

    /// Finish Night: record the night's actions, then apply the recorded outcome atomically.
    func completeNightPhase() async throws {
        guard isHost, !isCompletingNight, let session = currentSession,
              session.currentPhase == "night", let roundId = session.currentRoundId else { return }
        isCompletingNight = true
        defer { isCompletingNight = false }
        try await sessionService.recordNightActions(sessionId: session.id, roundId: roundId)
        try await sessionService.resolveNightAtomic(sessionId: session.id, roundId: roundId)
    }

    func revealDeaths() async throws {
        try await advance(to: .deathReveal)
    }

    func startVoting() async throws {
        try await advance(to: .voting)
    }

    func endVoting() async throws {
        guard isHost, let session = currentSession, let roundId = session.currentRoundId else { throw SessionError.notHost }
        try await sessionService.closeVoting(sessionId: session.id, roundId: roundId)
    }

    /// Continue from the voting results to the elimination reveal.
    func continueFromVotingResults() async throws {
        try await advance(to: .voteDeathReveal)
    }

    /// Continue from the elimination reveal: the server applies the vote and opens the next night.
    func continueFromVoteReveal() async throws {
        guard isHost, let session = currentSession, let roundId = session.currentRoundId else { throw SessionError.notHost }
        try await sessionService.resolveVoteAtomic(sessionId: session.id, roundId: roundId)
    }

    private func advance(to phase: PhaseTarget) async throws {
        guard isHost, let sessionId else { throw SessionError.notHost }
        try await sessionService.advancePhase(sessionId: sessionId, to: phase)
    }

    /// Runs on every snapshot: leaves role reveal once everyone is ready and drives the bots.
    func runHostAutomation() {
        guard isHost, let session = currentSession, let round = roundState else { return }
        if round.phase == "role_reveal", round.readyToAdvance, !isAdvancingFromRoleReveal {
            isAdvancingFromRoleReveal = true
            Task {
                defer { isAdvancingFromRoleReveal = false }
                do {
                    try await advance(to: .night)
                } catch {
                    print("❌ [MultiplayerGameStore] Failed to start the night: \(error.localizedDescription)")
                }
            }
        }
        botDirector.run(session: session, players: players, round: round)
    }
}
