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

    private let feed = Feed()
    private let clock = ManualClock()

    /// `onUnreadable` defaults to nothing, so no test reaches the shared `BackendCompatibility`.
    private func makeSupervisor(
        onUnreadable: @escaping () -> Void = {},
        onValue: @escaping (Int) -> Void = { _ in }
    ) -> SubscriptionSupervisor {
        SubscriptionSupervisor(feed.subscribe, sleep: clock.sleep, onUnreadable: onUnreadable, onValue: onValue)
    }

    // MARK: - Classification and backoff

    @Test func convexErrorsAreDeterministicAndCarryTheServerMessage() {
        #expect(SubscriptionSupervisor.deterministicMessage(for: .ConvexError(data: "\"Game not found.\"")) == "Game not found.")
        #expect(SubscriptionSupervisor.deterministicMessage(for: .ConvexError(data: "{\"code\":1}"))
                == "Something went wrong. Please try again.")
        #expect(SubscriptionSupervisor.deterministicMessage(for: .ServerError(msg: "Server down")) == nil)
        #expect(SubscriptionSupervisor.deterministicMessage(for: .InternalError(msg: decodeFailure)) == nil)
    }

    /// What `ConvexService.subscribe` ends a subscription with when a value cannot be decoded.
    private let decodeFailure = ConvexService.undecodableValue

    @Test func onlyTheAppsOwnMarkerCountsAsADecodeFailure() {
        #expect(SubscriptionSupervisor.isDecodeFailure(.InternalError(msg: decodeFailure)))
        // A failed subscribe call is an InternalError too, carrying a UniFFI error's description.
        #expect(!SubscriptionSupervisor.isDecodeFailure(.InternalError(msg: "The operation couldn’t be completed. (UniFFI.ClientError error 0.)")))
        // Foundation's text for a decoding error, which convex-swift would have passed on.
        #expect(!SubscriptionSupervisor.isDecodeFailure(.InternalError(msg: "The data couldn’t be read because it is missing.")))
        #expect(!SubscriptionSupervisor.isDecodeFailure(.ServerError(msg: decodeFailure)))
        #expect(!SubscriptionSupervisor.isDecodeFailure(.ConvexError(data: "\"\(decodeFailure)\"")))
    }

    /// Decodes like ConvexMobile does: its `JSONDecoder` on the server's JSON.
    private func received<T: Decodable>(_ json: String, as type: T.Type) throws -> ConvexService.Decoded<T> {
        try JSONDecoder().decode(ConvexService.Decoded<T>.self, from: Data(json.utf8))
    }

    private func isRejected<T: Decodable>(_ json: String, as type: T.Type) throws -> Bool {
        if case .failure = try received(json, as: type).result { return true }
        return false
    }

    @Test func aValueTheModelsRejectEndsTheSubscriptionWithTheMarker() throws {
        let subject = PassthroughSubject<ConvexService.Decoded<[Int]?>, ClientError>()
        var values: [[Int]?] = []
        var failure: ClientError?
        let subscription = ConvexService.unwrapping(subject.eraseToAnyPublisher(), query: "test").sink(
            receiveCompletion: { if case .failure(let error) = $0 { failure = error } },
            receiveValue: { values.append($0) }
        )
        subject.send(try received("[1,2]", as: [Int]?.self))
        subject.send(try received("null", as: [Int]?.self))
        #expect(values == [[1, 2], nil], "null is a value of an optional query, not a failure")
        #expect(failure == nil)

        // A missing key, a wrong type and a null where a value is required are outcomes, not thrown errors.
        #expect(try isRejected("{}", as: SessionView.self))
        #expect(try isRejected("\"x\"", as: Int.self))
        #expect(try isRejected("{\"id\":null}", as: GameAction.self))
        #expect(try !isRejected("7", as: Int.self))

        subject.send(try received("{\"a\":1}", as: [Int]?.self))
        #expect(failure.map(SubscriptionSupervisor.isDecodeFailure) == true)
        #expect(values.count == 2)
        subscription.cancel()
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
        feed.latest.send(completion: .failure(.InternalError(msg: "The operation couldn’t be completed.")))
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

    // MARK: - Decode failures (the server's shape moved past this build)

    @Test func aConfirmedDecodeFailureStopsOnlyThisSubscriptionAndRechecksTheContract() async {
        var rechecks = 0
        let supervisor = makeSupervisor(onUnreadable: { rechecks += 1 })
        supervisor.start()
        feed.latest.send(completion: .failure(.InternalError(msg: decodeFailure)))
        await drainMainQueue()
        #expect(supervisor.status == .retrying(attempt: 1), "The first decode failure gets one confirming retry")
        #expect(rechecks == 0)

        await clock.advance(by: .milliseconds(1_200))
        #expect(feed.subjects.count == 2)
        feed.latest.send(completion: .failure(.InternalError(msg: decodeFailure)))
        await drainMainQueue()
        #expect(supervisor.status == .failed(SubscriptionSupervisor.unreadableMessage))
        #expect(rechecks == 1, "Whether the app is too old is health:check's call, asked once")
        await clock.advance(by: .seconds(60))
        #expect(feed.subjects.count == 2, "A confirmed decode failure is not retried automatically")

        supervisor.restartIfNeeded() // The user's Retry still works.
        #expect(feed.subjects.count == 3)
    }

    @Test func aValueBetweenDecodeFailuresResetsTheConfirmation() async {
        let supervisor = makeSupervisor()
        supervisor.start()
        feed.latest.send(completion: .failure(.InternalError(msg: decodeFailure)))
        await drainMainQueue()
        await clock.advance(by: .milliseconds(1_200))
        feed.latest.send(1)
        await drainMainQueue()
        feed.latest.send(completion: .failure(.InternalError(msg: decodeFailure)))
        await drainMainQueue()
        #expect(supervisor.status == .retrying(attempt: 1))
    }
}
