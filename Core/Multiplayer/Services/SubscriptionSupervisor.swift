import Combine
import ConvexMobile
import Foundation

/// Keeps one Convex query subscription alive (api_contract 4, §8.3).
///
/// ConvexMobile 0.8.1 ends the publisher with `.failure` on any query error
/// (`ConvexError` / `ServerError`) or decode failure (`InternalError`) and never
/// recovers by itself; it never sends `.finished`. Transport drops are handled
/// inside the Rust client and only pause values. It attaches its subject only after
/// the FFI call returns, so a value the Rust client already holds can be dropped;
/// a subscription with no first value in time is therefore retried like a failure.
@MainActor
final class SubscriptionSupervisor {
    enum Status: Equatable {
        case idle
        case connecting
        case live
        /// Waiting to resubscribe after a transient failure.
        case retrying(attempt: Int)
        /// A ConvexError. Retried only on identity change, foreground or user Retry.
        case failed(String)
    }

    private(set) var status: Status = .idle {
        didSet { if status != oldValue { onStatusChange?() } }
    }
    var onStatusChange: (() -> Void)?

    private let open: (SubscriptionSupervisor) -> AnyCancellable
    private let firstValueTimeout: Duration
    private var subscription: AnyCancellable?
    private var retryTask: Task<Void, Never>?
    private var attempt = 0

    init<Value>(
        _ subscribe: @escaping () -> AnyPublisher<Value, ClientError>,
        firstValueTimeout: Duration = .seconds(15),
        onValue: @escaping (Value) -> Void
    ) {
        self.firstValueTimeout = firstValueTimeout
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
                        supervisor.status = .live
                        onValue(value)
                    }
                )
        }
    }

    /// Cancels any current subscription and subscribes again from attempt 0.
    func start() {
        attempt = 0
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
        retryTask = Task { [weak self, firstValueTimeout] in
            try? await Task.sleep(for: firstValueTimeout)
            guard !Task.isCancelled, let self, self.status == .connecting else { return }
            print("⚠️ [SubscriptionSupervisor] No first value; resubscribing")
            self.subscription?.cancel()
            self.scheduleRetry()
        }
    }

    private func handle(_ completion: Subscribers.Completion<ClientError>) {
        retryTask?.cancel()
        if case .failure(let error) = completion, let message = Self.deterministicMessage(for: error) {
            // views:* never throw ConvexError, so this is a contract bug: surface it, don't loop.
            print("❌ [SubscriptionSupervisor] ConvexError: \(message)")
            status = .failed(message)
            return
        }
        if case .failure(let error) = completion {
            print("⚠️ [SubscriptionSupervisor] Subscription failed: \(error)")
        }
        scheduleRetry()
    }

    private func scheduleRetry() {
        let delay = Self.backoffDelay(attempt: attempt, jitter: .random(in: 0.8...1.2))
        attempt += 1
        status = .retrying(attempt: attempt)
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
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

    /// `min(30, 2^attempt)` seconds, scaled by a 0.8...1.2 jitter factor.
    nonisolated static func backoffDelay(attempt: Int, jitter: Double) -> TimeInterval {
        min(30, pow(2, Double(attempt))) * jitter
    }
}
