import Foundation

/// Tracks voting for a single day phase
struct VotingSession: Codable, Sendable, Identifiable {
    var id: UUID = UUID()
    var dayIndex: Int
    /// Map of voter ID to voted player ID
    var votes: [UUID: UUID]
    /// The player who received the most votes (nil if tie or no votes)
    var eliminatedPlayerID: UUID?
    /// Vote counts per player
    var voteCounts: [UUID: Int]

    init(dayIndex: Int) {
        self.dayIndex = dayIndex
        self.votes = [:]
        self.eliminatedPlayerID = nil
        self.voteCounts = [:]
    }

    /// Records a vote from a player
    mutating func recordVote(from voterID: UUID, for targetID: UUID) {
        votes[voterID] = targetID
    }

    /// Tallies all votes and determines who should be eliminated
    mutating func tallyVotes() -> UUID? {
        // Count votes for each player
        var counts: [UUID: Int] = [:]
        for (_, targetID) in votes {
            counts[targetID, default: 0] += 1
        }

        voteCounts = counts

        // Find player with most votes
        guard let maxVotes = counts.values.max(), maxVotes > 0 else {
            return nil
        }

        // Check for ties
        let playersWithMaxVotes = counts.filter { $0.value == maxVotes }
        guard playersWithMaxVotes.count == 1 else {
            // Tie - no elimination
            return nil
        }

        eliminatedPlayerID = playersWithMaxVotes.first?.key
        return eliminatedPlayerID
    }
}
