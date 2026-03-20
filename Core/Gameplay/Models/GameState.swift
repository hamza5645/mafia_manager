import Foundation

enum GamePhase: Codable, Sendable, Equatable {
    case roleReveal(currentPlayerIndex: Int)
    case nightWakeUp(activeRole: Role)
    case nightAction(activeRole: Role)
    case nightTransition
    case morning
    case deathReveal
    case botVotingReveal
    case votingIndividual(currentPlayerIndex: Int)
    case votingResults
    case gameOver
}

struct GameState: Codable, Sendable {
    var players: [Player]
    var nightHistory: [NightAction]
    var dayHistory: [DayAction]
    var dayIndex: Int
    var isGameOver: Bool
    var winner: Role?
    var currentPhase: GamePhase = .roleReveal(currentPlayerIndex: 0)
    var currentVotingSession: VotingSession?
}

extension GameState {
    static var empty: GameState {
        GameState(players: [], nightHistory: [], dayHistory: [], dayIndex: 0, isGameOver: false, winner: nil, currentPhase: .roleReveal(currentPlayerIndex: 0), currentVotingSession: nil)
    }
}

