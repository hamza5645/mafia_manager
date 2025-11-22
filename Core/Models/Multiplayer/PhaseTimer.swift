import Foundation

// Represents a phase timer for multiplayer games
struct PhaseTimer: Codable, Identifiable, Sendable {
    let id: UUID
    let sessionId: UUID
    let phaseName: String
    let startedAt: Date
    let expiresAt: Date
    var isExpired: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case phaseName = "phase_name"
        case startedAt = "started_at"
        case expiresAt = "expires_at"
        case isExpired = "is_expired"
    }

    // Time remaining in seconds
    var timeRemaining: TimeInterval {
        let remaining = expiresAt.timeIntervalSince(Date())
        return max(0, remaining)
    }

    var hasExpired: Bool {
        Date() >= expiresAt
    }
}

// Helper to create timers
extension PhaseTimer {
    static func create(
        sessionId: UUID,
        phaseName: String,
        durationSeconds: Int
    ) -> PhaseTimer {
        let now = Date()
        let expiresAt = now.addingTimeInterval(TimeInterval(durationSeconds))

        return PhaseTimer(
            id: UUID(),
            sessionId: sessionId,
            phaseName: phaseName,
            startedAt: now,
            expiresAt: expiresAt,
            isExpired: false
        )
    }
}
