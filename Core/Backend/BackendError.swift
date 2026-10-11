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
    /// A mutation that did not finish in time. It may still be applied.
    static let stillSending = "Still sending. Check your connection; it may still go through."
    /// The start of the server's MERGE_SEAT_CONFLICT message (it may name the room).
    static let mergeSeatConflictPrefix = "Leave your other seat"

    let message: String
    /// True only when `message` is a ConvexError string from the server.
    let isServerMessage: Bool
    var errorDescription: String? { message }
    /// The request ran past its time limit. A mutation that timed out may still be applied.
    private(set) var isTimeout = false

    /// A request that ran past its time limit.
    init(timedOut message: String) {
        self.message = message
        isServerMessage = false
        isTimeout = true
    }

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
            #if DEBUG
            print("⚠️ [BackendError] Replaced non-server error: \(error)")
            #endif
            message = (error as NSError).domain == NSURLErrorDomain ? Self.network : Self.generic
            isServerMessage = false
        }
    }
}
