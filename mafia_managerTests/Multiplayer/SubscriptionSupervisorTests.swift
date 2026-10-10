import Combine
import ConvexMobile
import Foundation
import Testing

@testable import mafia_manager

@MainActor
struct SubscriptionSupervisorTests {
    /// Hands out a fresh subject per (re)subscription, like the Convex client does.
    private final class Feed {
        var subjects: [PassthroughSubject<Int, ClientError>] = []
        var latest: PassthroughSubject<Int, ClientError> { subjects[subjects.count - 1] }

        func subscribe() -> AnyPublisher<Int, ClientError> {
            subjects.append(PassthroughSubject())
            return latest.eraseToAnyPublisher()
        }
    }

    /// Values are delivered with `receive(on: DispatchQueue.main)`; let them land.
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    // MARK: - Classification and backoff

    @Test func convexErrorsAreDeterministicAndCarryTheServerMessage() {
        #expect(SubscriptionSupervisor.deterministicMessage(for: .ConvexError(data: "\"Game not found.\"")) == "Game not found.")
        #expect(SubscriptionSupervisor.deterministicMessage(for: .ConvexError(data: "{\"code\":1}"))
                == "Something went wrong. Please try again.")
        #expect(SubscriptionSupervisor.deterministicMessage(for: .ServerError(msg: "Server down")) == nil)
        #expect(SubscriptionSupervisor.deterministicMessage(for: .InternalError(msg: "Decoding failed")) == nil)
    }

    @Test func backoffDoublesUpToThirtySecondsAndAppliesJitter() {
        let delays = (0...6).map { SubscriptionSupervisor.backoffDelay(attempt: $0, jitter: 1) }
        #expect(delays == [1, 2, 4, 8, 16, 30, 30])
        #expect(abs(SubscriptionSupervisor.backoffDelay(attempt: 3, jitter: 0.8) - 6.4) < 1e-9)
        #expect(abs(SubscriptionSupervisor.backoffDelay(attempt: 9, jitter: 1.2) - 36) < 1e-9)
    }

    // MARK: - Supervision

    @Test func valuesAreDeliveredAndMarkTheSubscriptionLive() async {
        let feed = Feed()
        var values: [Int] = []
        let supervisor = SubscriptionSupervisor(feed.subscribe, onValue: { values.append($0) })
        supervisor.start()
        #expect(supervisor.status == .connecting)
        feed.latest.send(1)
        feed.latest.send(2)
        await drainMainQueue()
        #expect(values == [1, 2])
        #expect(supervisor.status == .live)
    }

    @Test func convexErrorStopsUntilTheUserRetries() async {
        let feed = Feed()
        let supervisor = SubscriptionSupervisor(feed.subscribe, onValue: { _ in })
        supervisor.start()
        feed.latest.send(completion: .failure(.ConvexError(data: "\"You are no longer in this game.\"")))
        await drainMainQueue()
        #expect(supervisor.status == .failed("You are no longer in this game."))
        #expect(feed.subjects.count == 1, "A ConvexError must not be retried automatically")

        supervisor.restartIfNeeded()
        #expect(feed.subjects.count == 2)
        #expect(supervisor.status == .connecting)
    }

    @Test func transientFailureWaitsAndForegroundRestartsImmediately() async {
        let feed = Feed()
        let supervisor = SubscriptionSupervisor(feed.subscribe, onValue: { _ in })
        supervisor.start()
        feed.latest.send(completion: .failure(.ServerError(msg: "Server down")))
        await drainMainQueue()
        #expect(supervisor.status == .retrying(attempt: 1))
        #expect(feed.subjects.count == 1)

        supervisor.restartIfNeeded()
        #expect(feed.subjects.count == 2)
        feed.latest.send(7)
        await drainMainQueue()
        #expect(supervisor.status == .live)
    }

    @Test func healthySubscriptionIsLeftAloneOnForeground() async {
        let feed = Feed()
        let supervisor = SubscriptionSupervisor(feed.subscribe, onValue: { _ in })
        supervisor.start()
        feed.latest.send(1)
        await drainMainQueue()
        supervisor.restartIfNeeded()
        #expect(feed.subjects.count == 1)
    }

    @Test func backoffResubscribesAndAValueResetsTheAttemptCounter() async throws {
        let feed = Feed()
        let supervisor = SubscriptionSupervisor(feed.subscribe, onValue: { _ in })
        supervisor.start()
        feed.latest.send(completion: .failure(.InternalError(msg: "Decoding failed")))
        await drainMainQueue()
        #expect(supervisor.status == .retrying(attempt: 1))

        try await Task.sleep(for: .milliseconds(1_500)) // First retry waits 0.8...1.2 s.
        #expect(feed.subjects.count == 2)
        feed.latest.send(1)
        await drainMainQueue()
        feed.latest.send(completion: .failure(.ServerError(msg: "Server down")))
        await drainMainQueue()
        #expect(supervisor.status == .retrying(attempt: 1))
    }

    @Test func aSubscriptionWithoutAFirstValueIsRetried() async throws {
        let feed = Feed()
        let supervisor = SubscriptionSupervisor(feed.subscribe, firstValueTimeout: .milliseconds(100), onValue: { _ in })
        supervisor.start()
        try await Task.sleep(for: .milliseconds(300))
        #expect(supervisor.status == .retrying(attempt: 1), "A value dropped by ConvexMobile must not hang the screen")
    }

    @Test func stopCancelsAPendingRetry() async throws {
        let feed = Feed()
        let supervisor = SubscriptionSupervisor(feed.subscribe, onValue: { _ in })
        supervisor.start()
        feed.latest.send(completion: .failure(.ServerError(msg: "Server down")))
        await drainMainQueue()
        supervisor.stop()
        try await Task.sleep(for: .milliseconds(1_500))
        #expect(feed.subjects.count == 1)
        #expect(supervisor.status == .idle)
    }
}
