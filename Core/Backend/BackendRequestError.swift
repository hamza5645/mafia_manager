import ConvexMobile
import Foundation

/// Converts transport/SDK failures into messages safe to show in app alerts.
struct BackendRequestError: LocalizedError {
    let message: String
    var errorDescription: String? { message }

    init(_ error: Error) {
        if let mapped = error as? BackendRequestError {
            message = mapped.message
            return
        }
        if (error as NSError).domain == NSURLErrorDomain {
            message = "Network error. Please check your internet connection."
            return
        }
        guard let clientError = error as? ClientError else {
            message = "Could not complete the request. Please try again."
            return
        }
        guard case .ConvexError(let data) = clientError else {
            message = "Unable to connect to the game server. Please try again."
            return
        }
        let payload = data.data(using: .utf8).flatMap {
            try? JSONSerialization.jsonObject(with: $0, options: .fragmentsAllowed)
        }
        let serverMessage = (payload as? String) ?? ((payload as? [String: Any])?["message"] as? String)
        let knownMessages: [String: String] = [
            "Game session not found": "Game session not found. It may have ended.",
            "Game session is full": "This game is full.",
            "You are already in this session": "You are already in this game.",
            "Authentication required": "Please sign in again.",
            "Invalid guest credentials": "Your guest session could not be restored. Please try signing in again.",
            "Only the host can perform this action": "Only the host can perform this action.",
            "Caller is not in this session": "You are no longer in this game.",
            "Stale round": "The game has advanced. Please refresh and try again.",
            "Stale phase index": "The game has advanced. Please refresh and try again.",
            "Stale night resolution": "The game has advanced. Please refresh and try again.",
            "Night already resolved or phase has advanced": "The game has advanced. Please refresh and try again.",
            "Game is not active": "This game is no longer active.",
            "Action is not allowed in this phase": "This action is not available in the current phase.",
            "Action is not allowed for this role": "This action is not available for your role.",
            "Actor is not alive in this session": "Eliminated players cannot submit actions.",
            "Target is not alive in this session": "Choose a player who is still alive.",
            "Mafia cannot target a teammate": "Mafia cannot target a teammate.",
            "Inspector cannot inspect themselves": "Inspectors cannot inspect themselves.",
            "Cannot return to lobby before game over": "Wait until the game ends before playing again.",
            "Rematch requires a completed game": "Wait until the game ends before starting a rematch.",
            "Leave the account's existing seat in this room before upgrading the guest": "Leave your existing seat in this room before saving guest progress.",
        ]
        message = serverMessage.flatMap { knownMessages[$0] }
            ?? "Could not complete the request. Please try again."
    }
}
