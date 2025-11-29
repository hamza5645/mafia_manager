import Foundation

/// Service responsible for making strategic decisions for bot players during gameplay
@MainActor
final class BotDecisionService {

    // MARK: - Night Phase Decisions

    /// Chooses a target for bot Mafia player
    /// Strategy: Avoid recent targets, prioritize non-special roles if known
    func chooseMafiaTarget(
        botPlayer: Player,
        alivePlayers: [Player],
        nightHistory: [NightAction]
    ) -> UUID? {
        // Filter valid targets: alive, not Mafia
        let validTargets = alivePlayers.filter { player in
            player.role != .mafia && player.alive && player.id != botPlayer.id
        }

        guard !validTargets.isEmpty else { return nil }

        // Get recent targets from last 2 nights to avoid repeating
        let recentTargetIDs = Set(nightHistory.suffix(2).compactMap { $0.mafiaTargetPlayerID })

        // Prefer targets that haven't been targeted recently
        let freshTargets = validTargets.filter { !recentTargetIDs.contains($0.id) }

        if !freshTargets.isEmpty {
            return freshTargets.randomElement()?.id
        }

        // Fallback to any valid target
        return validTargets.randomElement()?.id
    }

    /// Chooses a player to investigate for bot Inspector
    /// Strategy: Check players who haven't been checked, prioritize survivors
    func chooseInspectorTarget(
        botPlayer: Player,
        alivePlayers: [Player],
        nightHistory: [NightAction]
    ) -> UUID? {
        // Filter valid targets: alive, not Inspector
        let validTargets = alivePlayers.filter { player in
            player.role != .inspector && player.alive && player.id != botPlayer.id
        }

        guard !validTargets.isEmpty else { return nil }

        // Get all previously checked player IDs
        let checkedIDs = Set(nightHistory.compactMap { $0.inspectorCheckedPlayerID })

        // Prioritize unchecked players
        let uncheckedTargets = validTargets.filter { !checkedIDs.contains($0.id) }

        if !uncheckedTargets.isEmpty {
            return uncheckedTargets.randomElement()?.id
        }

        // If everyone has been checked, check randomly
        return validTargets.randomElement()?.id
    }

    /// Chooses a player to protect for bot Doctor
    /// Strategy: 60% self-protect, 40% protect others (weighted toward vulnerable players)
    func chooseDoctorProtection(
        botPlayer: Player,
        alivePlayers: [Player],
        nightHistory: [NightAction]
    ) -> UUID? {
        let validTargets = alivePlayers.filter { $0.alive }

        guard !validTargets.isEmpty else { return nil }

        // 60% chance to protect self
        if Double.random(in: 0...1) < 0.6 {
            return botPlayer.id
        }

        // Get recent Mafia targets to identify who might be at risk
        let recentTargetIDs = Set(nightHistory.suffix(2).compactMap { $0.mafiaTargetPlayerID })

        // 40% protect others, slightly prefer players who were recently targeted
        let recentTargets = validTargets.filter { recentTargetIDs.contains($0.id) && $0.id != botPlayer.id }

        if !recentTargets.isEmpty && Double.random(in: 0...1) < 0.7 {
            return recentTargets.randomElement()?.id
        }

        // Otherwise protect random other player
        let otherPlayers = validTargets.filter { $0.id != botPlayer.id }
        return otherPlayers.randomElement()?.id ?? botPlayer.id
    }

    /// Picks a single coordinated Mafia target so all Mafia bots agree
    /// Uses the same strategy as `chooseMafiaTarget` but executes once per night for the team
    func chooseCoordinatedMafiaTarget(
        mafiaBots: [Player],
        alivePlayers: [Player],
        nightHistory: [NightAction]
    ) -> UUID? {
        guard let representative = mafiaBots.first else { return nil }
        return chooseMafiaTarget(
            botPlayer: representative,
            alivePlayers: alivePlayers,
            nightHistory: nightHistory
        )
    }

    // MARK: - Day Phase Decisions

    /// Chooses who to vote out during day phase
    /// Strategy: Mafia votes for non-Mafia, Citizens vote semi-randomly
    /// HAMZA-FIX: Returns non-optional UUID - bots MUST always vote
    func chooseVotingTarget(
        botPlayer: Player,
        alivePlayers: [Player],
        nightHistory: [NightAction],
        dayHistory: [DayAction]
    ) -> UUID {
        let validTargets = alivePlayers.filter { $0.alive && $0.id != botPlayer.id }

        // If no valid targets (only bot left), self-vote as last resort
        guard !validTargets.isEmpty else { return botPlayer.id }

        if botPlayer.role == .mafia {
            // Bot Mafia: Vote for non-Mafia players
            let nonMafiaTargets = validTargets.filter { $0.role != .mafia }

            if !nonMafiaTargets.isEmpty {
                // Slightly prefer voting for players who survived multiple nights (suspicious)
                let survivors = nonMafiaTargets.filter { player in
                    // Check if this player was targeted but survived
                    nightHistory.contains { action in
                        action.mafiaTargetPlayerID == player.id && !action.resultingDeaths.contains(player.id)
                    }
                }

                if !survivors.isEmpty && Double.random(in: 0...1) < 0.6 {
                    // Guaranteed non-nil since survivors is non-empty
                    return survivors.randomElement()!.id
                }

                // Guaranteed non-nil since nonMafiaTargets is non-empty
                return nonMafiaTargets.randomElement()!.id
            }
        } else {
            // Bot Citizen/Inspector/Doctor: Vote somewhat randomly
            // Slight bias against players who have survived many nights without being targeted
            let nightsSurvived = nightHistory.count

            if nightsSurvived >= 2 {
                // In late game, slightly prefer voting for players who haven't been targeted
                let untargetedPlayers = validTargets.filter { player in
                    !nightHistory.contains { $0.mafiaTargetPlayerID == player.id }
                }

                if untargetedPlayers.count >= 2 && Double.random(in: 0...1) < 0.5 {
                    // Guaranteed non-nil since untargetedPlayers has >= 2 elements
                    return untargetedPlayers.randomElement()!.id
                }
            }

            // Default: random vote - guaranteed non-nil since validTargets is non-empty
            return validTargets.randomElement()!.id
        }

        // Fallback - guaranteed non-nil since validTargets is non-empty (checked at top)
        return validTargets.randomElement()!.id
    }

    // MARK: - Utility

    /// Adds a small delay to simulate bot "thinking"
    func simulateThinking() async {
        // Random delay between 3.0 and 5.0 seconds for realism
        // Longer delay prevents humans from getting suspicious about short bot turns
        let delay = Double.random(in: 3.0...5.0)
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}
