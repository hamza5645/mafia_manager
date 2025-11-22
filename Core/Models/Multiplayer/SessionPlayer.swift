import Foundation

// Represents a player in a multiplayer session
struct SessionPlayer: Codable, Identifiable, Sendable {
    let id: UUID
    let sessionId: UUID
    let userId: UUID? // null for bots
    let playerId: UUID // Local player UUID from game logic
    var playerName: String
    var playerNumber: Int?
    var role: Role? // Only visible to that player + host + other mafia
    var isBot: Bool
    var isAlive: Bool
    var isOnline: Bool
    var isReady: Bool
    var lastHeartbeat: Date
    let joinedAt: Date
    var removalNote: String?

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case userId = "user_id"
        case playerId = "player_id"
        case playerName = "player_name"
        case playerNumber = "player_number"
        case role
        case isBot = "is_bot"
        case isAlive = "is_alive"
        case isOnline = "is_online"
        case isReady = "is_ready"
        case lastHeartbeat = "last_heartbeat"
        case joinedAt = "joined_at"
        case removalNote = "removal_note"
    }
}

// Public player info (what everyone can see)
struct PublicPlayerInfo: Identifiable, Sendable {
    let id: UUID
    let playerId: UUID
    let playerName: String
    let playerNumber: Int?
    let isBot: Bool
    let isAlive: Bool
    let isOnline: Bool
    let isReady: Bool

    init(from sessionPlayer: SessionPlayer) {
        self.id = sessionPlayer.id
        self.playerId = sessionPlayer.playerId
        self.playerName = sessionPlayer.playerName
        self.playerNumber = sessionPlayer.playerNumber
        self.isBot = sessionPlayer.isBot
        self.isAlive = sessionPlayer.isAlive
        self.isOnline = sessionPlayer.isOnline
        self.isReady = sessionPlayer.isReady
    }
}

// My player info (what I can see about myself)
struct MyPlayerInfo: Sendable {
    let sessionPlayer: SessionPlayer
    let role: Role? // My role
    let playerNumber: Int? // My number

    var isHost: Bool = false

    init(from sessionPlayer: SessionPlayer, isHost: Bool = false) {
        self.sessionPlayer = sessionPlayer
        self.role = sessionPlayer.role
        self.playerNumber = sessionPlayer.playerNumber
        self.isHost = isHost
    }
}
