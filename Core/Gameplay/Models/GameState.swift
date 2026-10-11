import Foundation

enum GamePhase: Codable, Sendable, Equatable {
    case roleReveal(currentPlayerIndex: Int)
    case nightWakeUp(activeRole: Role)
    case nightAction(activeRole: Role)
    case nightTransition
    case morning
    case deathReveal
    case voteDeathReveal
    case botVotingReveal
    case votingIndividual(currentPlayerIndex: Int)
    case votingResults
    case gameOver
}

struct GameState: Codable, Sendable, Equatable {
    var players: [Player]
    var nightHistory: [NightAction]
    var dayHistory: [DayAction]
    var dayIndex: Int
    var isGameOver: Bool
    var winner: Role?
    var currentPhase: GamePhase = .roleReveal(currentPlayerIndex: 0)
    var currentVotingSession: VotingSession?
    /// Identifies this game to `stats:recordGame`. Nil in saves made before it existed.
    var gameID: UUID?
}

extension GameState {
    static var empty: GameState {
        GameState(players: [], nightHistory: [], dayHistory: [], dayIndex: 0, isGameOver: false, winner: nil, currentPhase: .roleReveal(currentPlayerIndex: 0), currentVotingSession: nil)
    }

    /// Fields with a default fall back to it when an older save lacks them.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        players = try c.decode([Player].self, forKey: .players)
        nightHistory = try c.decode([NightAction].self, forKey: .nightHistory)
        dayHistory = try c.decode([DayAction].self, forKey: .dayHistory)
        dayIndex = try c.decode(Int.self, forKey: .dayIndex)
        isGameOver = try c.decode(Bool.self, forKey: .isGameOver)
        winner = try c.decodeIfPresent(Role.self, forKey: .winner)
        currentPhase = try c.decodeIfPresent(GamePhase.self, forKey: .currentPhase) ?? .roleReveal(currentPlayerIndex: 0)
        currentVotingSession = try c.decodeIfPresent(VotingSession.self, forKey: .currentVotingSession)
        gameID = try c.decodeIfPresent(UUID.self, forKey: .gameID)
    }
}
