import ConvexMobile
import XCTest

@testable import mafia_manager

@MainActor
final class BackendRequestErrorTests: XCTestCase {
    func testConvexJSONStringIsMappedWithoutSDKDetails() {
        let error = BackendRequestError(ClientError.ConvexError(data: "\"Game session not found\""))
        XCTAssertEqual(error.localizedDescription, "Game session not found. It may have ended.")
    }

    func testStructuredBusinessErrorIsMapped() {
        let error = BackendRequestError(ClientError.ConvexError(data: "{\"message\":\"Stale round\"}"))
        XCTAssertEqual(error.localizedDescription, "The game has advanced. Please refresh and try again.")
    }

    func testUnknownValidationOrSDKPayloadCannotLeakIntoAlerts() {
        let errors: [Error] = [
            ClientError.ConvexError(data: "\"private-token and internal stack trace\""),
            ClientError.ServerError(msg: "Object contains secret argument private-token"),
            ClientError.InternalError(msg: "FFI private-token"),
        ]
        for error in errors {
            let message = BackendRequestError(error).localizedDescription
            XCTAssertFalse(message.contains("private-token"))
            XCTAssertFalse(message.contains("ClientError"))
            XCTAssertTrue(message.contains("Please try again"))
        }
    }

    func testNetworkErrorAndAlreadyMappedErrorRemainReadable() {
        let error = BackendRequestError(URLError(.notConnectedToInternet))
        XCTAssertEqual(error.localizedDescription, "Network error. Please check your internet connection.")
        XCTAssertEqual(BackendRequestError(error).localizedDescription, error.localizedDescription)
    }
}
