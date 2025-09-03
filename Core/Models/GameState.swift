import Foundation

struct GameState: Codable, Sendable {
    var players: [Player]
    var nightHistory: [NightAction]
    var dayHistory: [DayAction]
    var dayIndex: Int
    var isGameOver: Bool
    var winner: Role?
}

extension GameState {
    static var empty: GameState {
        GameState(players: [], nightHistory: [], dayHistory: [], dayIndex: 0, isGameOver: false, winner: nil)
    }
}

