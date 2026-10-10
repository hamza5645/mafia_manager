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

    /// Time only moves when a test advances it.
    private final class ManualClock {
        private var now: Duration = .zero
        private(set) var requested: [Duration] = []
        private var sleepers: [(deadline: Duration, continuation: UnsafeContinuation<Void, Never>)] = []

        func sleep(_ duration: Duration) async {
            requested.append(duration)
            await withUnsafeContinuation { sleepers.append((now + duration, $0)) }
        }

        /// Lets pending tasks reach their sleep, moves time forward and runs the ones that woke.
        func advance(by duration: Duration) async {
            await settle()
            now += duration
            let due = sleepers.filter { $0.deadline <= now }
            sleepers.removeAll { $0.deadline <= now }
            due.forEach { $0.continuation.resume() }
            await settle()
        }

        private func settle() async {
            for _ in 0..<10 { await Task.yield() }
        }
    }

    private let feed = Feed()
    private let clock = ManualClock()

    private func makeSupervisor(onValue: @escaping (Int) -> Void = { _ in }) -> SubscriptionSupervisor {
        SubscriptionSupervisor(feed.subscribe, sleep: clock.sleep, onValue: onValue)
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
        var values: [Int] = []
        let supervisor = makeSupervisor { values.append($0) }
        supervisor.start()
        #expect(supervisor.status == .connecting)
        feed.latest.send(1)
        feed.latest.send(2)
        await drainMainQueue()
        #expect(values == [1, 2])
        #expect(supervisor.status == .live)
    }

    @Test func convexErrorStopsUntilTheUserRetries() async {
        let supervisor = makeSupervisor()
        supervisor.start()
        feed.latest.send(completion: .failure(.ConvexError(data: "\"You are no longer in this game.\"")))
        await drainMainQueue()
        #expect(supervisor.status == .failed("You are no longer in this game."))
        await clock.advance(by: .seconds(60))
        #expect(feed.subjects.count == 1, "A ConvexError must not be retried automatically")

        supervisor.restartIfNeeded()
        #expect(feed.subjects.count == 2)
        #expect(supervisor.status == .connecting)
    }

    @Test func transientFailureWaitsAndForegroundRestartsImmediately() async {
        let supervisor = makeSupervisor()
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
        let supervisor = makeSupervisor()
        supervisor.start()
        feed.latest.send(1)
        await drainMainQueue()
        supervisor.restartIfNeeded()
        #expect(feed.subjects.count == 1)
    }

    @Test func backoffResubscribesAndAValueResetsTheAttemptCounter() async {
        let supervisor = makeSupervisor()
        supervisor.start()
        feed.latest.send(completion: .failure(.InternalError(msg: "Decoding failed")))
        await drainMainQueue()
        #expect(supervisor.status == .retrying(attempt: 1))

        await clock.advance(by: .milliseconds(1_200)) // The first retry waits 0.8...1.2 s.
        #expect(clock.requested.contains { $0 >= .milliseconds(800) && $0 <= .milliseconds(1_200) })
        #expect(feed.subjects.count == 2)
        feed.latest.send(1)
        await drainMainQueue()
        feed.latest.send(completion: .failure(.ServerError(msg: "Server down")))
        await drainMainQueue()
        #expect(supervisor.status == .retrying(attempt: 1))
    }

    @Test func aSubscriptionWithoutAFirstValueIsRetried() async {
        let supervisor = makeSupervisor()
        supervisor.start()
        await clock.advance(by: SubscriptionSupervisor.firstValueTimeout)
        #expect(supervisor.status == .retrying(attempt: 1), "A value dropped by ConvexMobile must not hang the screen")
        await clock.advance(by: .seconds(2))
        #expect(feed.subjects.count == 2)
    }

    @Test func aFirstValueCancelsTheTimeout() async {
        let supervisor = makeSupervisor()
        supervisor.start()
        feed.latest.send(1)
        await drainMainQueue()
        await clock.advance(by: .seconds(60))
        #expect(supervisor.status == .live)
        #expect(feed.subjects.count == 1)
    }

    @Test func stopCancelsAPendingRetry() async {
        let supervisor = makeSupervisor()
        supervisor.start()
        feed.latest.send(completion: .failure(.ServerError(msg: "Server down")))
        await drainMainQueue()
        supervisor.stop()
        await clock.advance(by: .seconds(60))
        #expect(feed.subjects.count == 1)
        #expect(supervisor.status == .idle)
    }
}
