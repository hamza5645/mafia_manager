import Combine
import ConvexMobile
import Foundation

/// Keeps one Convex query subscription alive (api_contract 5, §8.3).
///
/// ConvexMobile 0.8.1 ends the publisher with `.failure` on any query error
/// (`ConvexError` / `ServerError`) and never recovers by itself; it never sends
/// `.finished`. A value this build cannot decode ends it with
/// `ConvexService.undecodableValue`. Transport drops are handled inside the Rust
/// client and only pause values. It attaches its subject only after the FFI call
/// returns, so a value the Rust client already holds can be dropped; a subscription
/// with no first value in time is therefore retried like a failure.
@MainActor
final class SubscriptionSupervisor {
    enum Status: Equatable {
        case idle
        case connecting
        case live
        /// Waiting to resubscribe after a transient failure.
        case retrying(attempt: Int)
        /// A ConvexError, or a value this build cannot decode. Retried only on identity
        /// change, foreground or user Retry.
        case failed(String)
    }

    private(set) var status: Status = .idle {
        didSet { if status != oldValue { onStatusChange?() } }
    }
    var onStatusChange: (() -> Void)?

    static let firstValueTimeout: Duration = .seconds(15)
    /// Shown for the one room whose value this build cannot decode.
    nonisolated static let unreadableMessage = "This version of Mafia can't read this room's data. Try again, or update the app."

    /// Names the query in logs and test messages.
    let label: String
    private let open: (SubscriptionSupervisor) -> AnyCancellable
    /// Waits for backoff delays and the first-value timeout (a fake clock in tests).
    private let sleep: (Duration) async -> Void
    /// Called once a decode failure is confirmed.
    private let onUnreadable: () -> Void
    private var subscription: AnyCancellable?
    private var retryTask: Task<Void, Never>?
    private var attempt = 0
    /// Decode failures since the last value; the second one is final.
    private var decodeFailures = 0

    init<Value>(
        _ subscribe: @escaping () -> AnyPublisher<Value, ClientError>,
        label: String = "",
        sleep: @escaping (Duration) async -> Void = { duration in _ = try? await Task.sleep(for: duration) },
        onUnreadable: @escaping () -> Void = { Task { await BackendCompatibility.shared.recheck() } },
        onValue: @escaping (Value) -> Void
    ) {
        self.label = label
        self.sleep = sleep
        self.onUnreadable = onUnreadable
        open = { supervisor in
            subscribe()
                // FFI callbacks arrive on arbitrary threads; the main queue keeps them in order.
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { [weak supervisor] completion in
                        supervisor?.handle(completion)
                    },
                    receiveValue: { [weak supervisor] value in
                        guard let supervisor else { return }
                        supervisor.attempt = 0
                        supervisor.decodeFailures = 0
                        supervisor.status = .live
                        onValue(value)
                    }
                )
        }
    }

    /// Cancels any current subscription and subscribes again from attempt 0.
    func start() {
        attempt = 0
        decodeFailures = 0
        connect()
    }

    /// Foreground and Retry: restart a failed or waiting subscription; leave healthy ones alone.
    func restartIfNeeded() {
        switch status {
        case .connecting, .live:
            return
        case .idle, .retrying, .failed:
            start()
        }
    }

    func stop() {
        retryTask?.cancel()
        retryTask = nil
        subscription?.cancel()
        subscription = nil
        status = .idle
    }

    private func connect() {
        retryTask?.cancel()
        subscription?.cancel()
        status = .connecting
        subscription = open(self)
        retryTask = Task { [weak self, sleep] in
            await sleep(Self.firstValueTimeout)
            guard !Task.isCancelled, let self, self.status == .connecting else { return }
            print("⚠️ [SubscriptionSupervisor] \(self.label): no first value; resubscribing")
            self.subscription?.cancel()
            self.scheduleRetry()
        }
    }

    private func handle(_ completion: Subscribers.Completion<ClientError>) {
        retryTask?.cancel()
        guard case .failure(let error) = completion else {
            scheduleRetry()
            return
        }
        if let message = Self.deterministicMessage(for: error) {
            // views:* never throw ConvexError, so this is a contract bug: surface it, don't loop.
            print("❌ [SubscriptionSupervisor] \(label): ConvexError: \(message)")
            status = .failed(message)
            return
        }
        if Self.isDecodeFailure(error) {
            decodeFailures += 1
            // One retry confirms it. Only this subscription stops: one bad row must not close
            // online play everywhere, so whether the app is too old is left to `health:check`.
            if decodeFailures >= 2 {
                print("❌ [SubscriptionSupervisor] \(label): cannot decode the server's value")
                status = .failed(Self.unreadableMessage)
                onUnreadable()
                return
            }
        }
        print("⚠️ [SubscriptionSupervisor] \(label): subscription failed: \(error)")
        scheduleRetry()
    }

    private func scheduleRetry() {
        let delay = Self.backoffDelay(attempt: attempt, jitter: .random(in: 0.8...1.2))
        attempt += 1
        status = .retrying(attempt: attempt)
        retryTask = Task { [weak self, sleep] in
            await sleep(.seconds(delay))
            guard !Task.isCancelled else { return }
            self?.connect()
        }
    }

    /// The server message for a ConvexError (a plain JSON string); nil for failures worth retrying.
    nonisolated static func deterministicMessage(for error: ClientError) -> String? {
        guard case .ConvexError(let data) = error else { return nil }
        return (try? JSONDecoder().decode(String.self, from: Data(data.utf8)))
            ?? "Something went wrong. Please try again."
    }

    /// The value arrived but this build's models cannot decode it (see `ConvexService.Decoded`).
    nonisolated static func isDecodeFailure(_ error: ClientError) -> Bool {
        guard case .InternalError(let message) = error else { return false }
        return message == ConvexService.undecodableValue
    }

    /// `min(30, 2^attempt)` seconds, scaled by a 0.8...1.2 jitter factor.
    nonisolated static func backoffDelay(attempt: Int, jitter: Double) -> TimeInterval {
        min(30, pow(2, Double(attempt))) * jitter
    }
}
