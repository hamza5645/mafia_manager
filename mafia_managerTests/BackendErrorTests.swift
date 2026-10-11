import Combine
import ConvexMobile
import XCTest

@testable import mafia_manager

// nonisolated, with main-actor members: under default MainActor isolation a main-actor
// XCTestCase subclass inherits its initializers as main-actor ones (an error in Swift 6).
nonisolated final class BackendErrorTests: XCTestCase {
    @MainActor func testConvexErrorStringIsShownDirectly() {
        let error = BackendError(ClientError.ConvexError(data: "\"Game not found.\""))
        XCTAssertEqual(error.localizedDescription, "Game not found.")
        XCTAssertTrue(error.isServerMessage)
    }

    @MainActor func testNonStringPayloadsAndSDKErrorsBecomeGeneric() {
        let errors: [Error] = [
            ClientError.ConvexError(data: "{\"message\":\"private-token\"}"),
            ClientError.ConvexError(data: "not json private-token"),
            ClientError.ServerError(msg: "Object contains secret argument private-token"),
            ClientError.InternalError(msg: "FFI private-token"),
            CocoaError(.coderReadCorrupt),
        ]
        for error in errors {
            let mapped = BackendError(error)
            XCTAssertEqual(mapped.message, BackendError.generic)
            XCTAssertFalse(mapped.isServerMessage)
        }
    }

    @MainActor func testNetworkErrorIsReadable() {
        let error = BackendError(URLError(.notConnectedToInternet))
        XCTAssertEqual(error.localizedDescription, BackendError.network)
        XCTAssertFalse(error.isServerMessage)
    }

    @MainActor func testExistingBackendErrorPassesThroughUnchanged() {
        let server = BackendError(ClientError.ConvexError(data: "\"Only the host can do that.\""))
        XCTAssertEqual(BackendError(server), server)
        let network = BackendError(URLError(.timedOut))
        XCTAssertEqual(BackendError(network), network)
    }

    // MARK: - Time limits

    @MainActor func testTimeoutErrorIsFlaggedAndSurvivesMapping() {
        let stillSending = BackendError(timedOut: BackendError.stillSending)
        XCTAssertTrue(stillSending.isTimeout)
        XCTAssertFalse(stillSending.isServerMessage)
        XCTAssertEqual(stillSending.localizedDescription, BackendError.stillSending)
        XCTAssertTrue(BackendError(stillSending).isTimeout)
        XCTAssertFalse(BackendError(URLError(.timedOut)).isTimeout, "Only the app's own time limits set it")
        XCTAssertFalse(BackendError(ClientError.ConvexError(data: "\"Game not found.\"")).isTimeout)
    }

    @MainActor func testQueryThatNeverAnswersTimesOutAndUnsubscribes() async {
        let values = PassthroughSubject<Int, ClientError>()
        let cancelled = expectation(description: "subscription cancelled")
        // @Sendable: the timeout cancels from a background task, not the main actor.
        let publisher = values.handleEvents(receiveCancel: { @Sendable in cancelled.fulfill() }).eraseToAnyPublisher()

        do {
            _ = try await ConvexService.firstValue(
                of: publisher,
                timeout: .milliseconds(50),
                timeoutError: BackendError(timedOut: BackendError.network)
            )
            XCTFail("A query with no value must time out")
        } catch let error as BackendError {
            XCTAssertTrue(error.isTimeout)
            XCTAssertEqual(error.message, BackendError.network, "Existing alerts with Reload appear")
        } catch {
            XCTFail("Unexpected \(error)")
        }
        await fulfillment(of: [cancelled], timeout: 2)
    }

    @MainActor func testQueryReturnsTheFirstValueBeforeTheTimeLimit() async throws {
        let values = CurrentValueSubject<Int, ClientError>(7)
        let value = try await ConvexService.firstValue(
            of: values.eraseToAnyPublisher(),
            timeout: .seconds(5),
            timeoutError: BackendError(timedOut: BackendError.network)
        )
        XCTAssertEqual(value, 7)
    }

    @MainActor func testQueryErrorIsPassedOn() async {
        let failing = Fail<Int, ClientError>(error: .ConvexError(data: "\"Game not found.\"")).eraseToAnyPublisher()
        do {
            _ = try await ConvexService.firstValue(
                of: failing,
                timeout: .seconds(5),
                timeoutError: BackendError(timedOut: BackendError.network)
            )
            XCTFail("Expected the server error")
        } catch {
            XCTAssertEqual(BackendError(error).message, "Game not found.")
        }
    }

    @MainActor func testCancellingAQueryTearsDownItsSubscription() async {
        let values = PassthroughSubject<Int, ClientError>()
        let cancelled = expectation(description: "subscription cancelled")
        let publisher = values.handleEvents(receiveCancel: { cancelled.fulfill() }).eraseToAnyPublisher()

        let task = Task {
            try await ConvexService.firstValue(of: publisher, timeout: nil, timeoutError: CancellationError())
        }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()

        await fulfillment(of: [cancelled], timeout: 2)
        let result = await task.result
        XCTAssertThrowsError(try result.get()) { XCTAssertTrue($0 is CancellationError) }
    }

    @MainActor func testSlowOperationTimesOutWithoutWaitingForIt() async {
        let started = ContinuousClock.now
        do {
            _ = try await ConvexService.withTimeout(
                .milliseconds(50),
                error: BackendError(timedOut: BackendError.stillSending)
            ) {
                try await Task.sleep(for: .seconds(30))
                return 1
            }
            XCTFail("Expected a timeout")
        } catch let error as BackendError {
            XCTAssertTrue(error.isTimeout)
            XCTAssertEqual(error.message, BackendError.stillSending)
        } catch {
            XCTFail("Unexpected \(error)")
        }
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(5), "The caller does not wait for the operation")
    }

    @MainActor func testFastOperationReturnsItsResultOrError() async throws {
        let value = try await ConvexService.withTimeout(.seconds(5), error: BackendError(timedOut: BackendError.stillSending)) {
            42
        }
        XCTAssertEqual(value, 42)
        do {
            _ = try await ConvexService.withTimeout(.seconds(5), error: BackendError(timedOut: BackendError.stillSending)) {
                throw URLError(.notConnectedToInternet)
            }
            XCTFail("Expected the operation's error")
        } catch {
            XCTAssertEqual(BackendError(error).message, BackendError.network)
        }
    }

    // MARK: - API contract

    @MainActor func testUpdateIsRequiredOnlyWhenTheServerNeedsANewerContract() async {
        let current = BackendCompatibility(fetchMinClientContract: { ConvexConfig.apiContractVersion })
        await current.checkOnce()
        XCTAssertFalse(current.updateRequired)

        let older = BackendCompatibility(fetchMinClientContract: { ConvexConfig.apiContractVersion - 1 })
        await older.checkOnce()
        XCTAssertFalse(older.updateRequired, "Staged rollouts: a newer client is fine")

        let newer = BackendCompatibility(fetchMinClientContract: { ConvexConfig.apiContractVersion + 1 })
        await newer.checkOnce()
        XCTAssertTrue(newer.updateRequired)
    }

    @MainActor func testFailedOrTimedOutCheckNeverBlocksAndIsRetried() async {
        var calls = 0
        var failure: Error? = BackendError(timedOut: BackendError.network)
        let compatibility = BackendCompatibility(fetchMinClientContract: {
            calls += 1
            if let failure { throw failure }
            return ConvexConfig.apiContractVersion + 1
        })

        await compatibility.checkOnce()
        XCTAssertFalse(compatibility.updateRequired)

        failure = nil
        await compatibility.checkOnce()
        XCTAssertTrue(compatibility.updateRequired)
        await compatibility.checkOnce()
        XCTAssertEqual(calls, 2, "One successful check per launch")
    }

    @MainActor func testContractVersionMatchesTheBackend() {
        XCTAssertEqual(ConvexConfig.apiContractVersion, 5)
    }

    @MainActor func testDebugBuildsTakeAFullBackendURLFromTheEnvironment() {
        let configured = ConvexConfig.deploymentURL(environment: [:])
        XCTAssertTrue(configured.hasPrefix("https://"))
        XCTAssertEqual(ConvexConfig.deploymentURL(environment: ["MAFIA_CONVEX_URL": "http://127.0.0.1:3210"]),
                       "http://127.0.0.1:3210")
        XCTAssertEqual(ConvexConfig.deploymentURL(environment: ["MAFIA_CONVEX_URL": "https://preview.convex.cloud"]),
                       "https://preview.convex.cloud")
        XCTAssertEqual(ConvexConfig.deploymentURL(environment: ["MAFIA_CONVEX_URL": "preview.convex.cloud"]), configured,
                       "Only a full http(s) URL overrides the configured host")
    }
}
