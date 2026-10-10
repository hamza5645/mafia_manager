import ConvexMobile
import Foundation

/// A failed Convex request with a message that is safe to show in alerts.
/// The server only throws short, user-facing ConvexError strings; anything
/// else may contain SDK or transport details and is replaced.
struct BackendError: LocalizedError, Equatable {
    static let generic = "Something went wrong. Please try again."
    static let network = "Network error. Please check your connection."
    /// The server's GUEST_NOT_FOUND message: there is no guest left to merge.
    static let guestNotFound = "Guest progress could not be found."

    let message: String
    /// True only when `message` is a ConvexError string from the server.
    let isServerMessage: Bool
    var errorDescription: String? { message }

    init(_ error: Error) {
        if let error = error as? BackendError {
            self = error
        } else if case ClientError.ConvexError(let data)? = error as? ClientError,
                  let message = data.data(using: .utf8).flatMap({
                      try? JSONSerialization.jsonObject(with: $0, options: .fragmentsAllowed)
                  }) as? String {
            self.message = message
            isServerMessage = true
        } else {
            message = (error as NSError).domain == NSURLErrorDomain ? Self.network : Self.generic
            isServerMessage = false
        }
    }
}
