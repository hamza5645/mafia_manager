import ConvexMobile
import XCTest

@testable import mafia_manager

@MainActor
final class BackendErrorTests: XCTestCase {
    func testConvexErrorStringIsShownDirectly() {
        let error = BackendError(ClientError.ConvexError(data: "\"Game not found.\""))
        XCTAssertEqual(error.localizedDescription, "Game not found.")
        XCTAssertTrue(error.isServerMessage)
    }

    func testNonStringPayloadsAndSDKErrorsBecomeGeneric() {
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

    func testNetworkErrorIsReadable() {
        let error = BackendError(URLError(.notConnectedToInternet))
        XCTAssertEqual(error.localizedDescription, BackendError.network)
        XCTAssertFalse(error.isServerMessage)
    }

    func testExistingBackendErrorPassesThroughUnchanged() {
        let server = BackendError(ClientError.ConvexError(data: "\"Only the host can do that.\""))
        XCTAssertEqual(BackendError(server), server)
        let network = BackendError(URLError(.timedOut))
        XCTAssertEqual(BackendError(network), network)
    }
}
