import XCTest

@testable import mafia_manager

@MainActor
final class AuthRegressionTests: XCTestCase {
    func testTypedExistingEmailErrorMapsToAuthError() {
        guard case AuthError.emailAlreadyInUse? = AuthService.signUpError(
            forClerkCode: "form_identifier_exists"
        ) else {
            return XCTFail("Expected emailAlreadyInUse")
        }
    }

    func testVerificationFreeSignupSynchronizesClerkBeforeConvex() async throws {
        var events: [String] = []

        try await AuthService.synchronizeCompletedSignUp(
            refreshClient: { events.append("clerk") },
            refreshConvexAuth: { events.append("convex") }
        )

        XCTAssertEqual(events, ["clerk", "convex"])
    }

    func testTemplatedTokenRefreshForwardsOnlySuccessfulFetch() async {
        let token = await ClerkConvexAuthProvider.refreshedConvexToken {
            "convex-template-token"
        }
        let failed = await ClerkConvexAuthProvider.refreshedConvexToken {
            throw TestError.expected
        }

        XCTAssertEqual(token, "convex-template-token")
        XCTAssertNil(failed)
    }

    func testMergeFailurePersistsAndRetrySuccessClearsCredentials() async throws {
        let guest = profile(isAnonymous: true)
        let account = profile(isAnonymous: false)
        let service = MockAuthService(guest: guest, account: account)
        let keychain = MemoryKeychain()
        let suiteName = "AuthRegressionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AuthStore(
            authService: service,
            keychain: keychain,
            defaults: defaults,
            autoRestore: false
        )

        let signedInAsGuest = await store.signInAsGuest(displayName: guest.displayName)
        XCTAssertTrue(signedInAsGuest)
        service.mergeError = TestError.expected

        let result = await store.linkEmailPassword(
            email: "guest@example.com",
            password: "password123",
            displayName: account.displayName
        )

        guard case .retryableMergeFailure = result else {
            return XCTFail("Expected retryable merge failure")
        }
        XCTAssertTrue(store.hasPendingGuestMerge)
        XCTAssertNotNil(store.currentGuestSecretHash)

        service.mergeError = nil
        let retrySucceeded = await store.retryPendingGuestMerge()
        XCTAssertTrue(retrySucceeded)
        XCTAssertFalse(store.hasPendingGuestMerge)
        XCTAssertNil(store.currentGuestSecretHash)
        XCTAssertFalse(store.isAnonymous)
        XCTAssertEqual(service.mergeAttempts, 2)
    }

    func testSessionRestorationRetriesPendingMergeAutomatically() async throws {
        let guest = profile(isAnonymous: true)
        let account = profile(isAnonymous: false)
        let service = MockAuthService(guest: guest, account: account)
        service.restoredUser = account
        let keychain = MemoryKeychain()
        try keychain.save("guest-secret", forKey: "convex_guest_secret")
        let suiteName = "AuthRestoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(guest.id.uuidString, forKey: "pending_merge_from_anonymous_id")
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AuthStore(
            authService: service,
            keychain: keychain,
            defaults: defaults,
            autoRestore: false
        )

        await store.ensureValidSession()

        XCTAssertEqual(service.mergeAttempts, 1)
        XCTAssertFalse(store.hasPendingGuestMerge)
        XCTAssertNil(store.currentGuestSecretHash)
        XCTAssertEqual(store.currentUserId, account.id)
    }

    private func profile(isAnonymous: Bool) -> UserProfile {
        UserProfile(
            id: UUID(),
            displayName: isAnonymous ? "Guest" : "Account",
            isAnonymous: isAnonymous,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

private enum TestError: Error {
    case expected
}

@MainActor
private final class MockAuthService: AuthServicing {
    let guest: UserProfile
    let account: UserProfile
    var restoredUser: UserProfile?
    var mergeError: Error?
    var mergeAttempts = 0

    init(guest: UserProfile, account: UserProfile) {
        self.guest = guest
        self.account = account
    }

    var currentUser: UserProfile? {
        get async { restoredUser }
    }

    func startSignUp(email: String, password: String, displayName: String) async throws -> AuthService.SignUpStartResult {
        .completed(account)
    }

    func verifySignUpEmailCode(_ code: String, displayName: String) async throws -> UserProfile {
        account
    }

    func resendSignUpEmailCode() async throws {}

    func signIn(email: String, password: String) async throws -> UserProfile {
        account
    }

    func signOut() async throws {}
    func startPasswordReset(email: String) async throws {}

    func confirmPasswordReset(code: String, newPassword: String) async throws -> UserProfile {
        account
    }

    func updateUserProfile(userId: UUID, displayName: String, guestSecretHash: String?) async throws {}

    func signInAsGuest(displayName: String, guestSecretHash: String) async throws -> UserProfile {
        guest
    }

    func mergeAnonymousStats(
        anonymousUserId: UUID,
        targetUserId: UUID,
        guestSecretHash: String
    ) async throws -> MergeStatsResult {
        mergeAttempts += 1
        if let mergeError { throw mergeError }
        return MergeStatsResult(success: true, error: nil, mergedCount: 0, transferredCount: 0)
    }
}

private final class MemoryKeychain: KeychainStoring {
    private var values: [String: String] = [:]

    func save(_ value: String, forKey key: String) throws {
        values[key] = value
    }

    func load(forKey key: String) throws -> String {
        guard let value = values[key] else { throw TestError.expected }
        return value
    }

    func delete(forKey key: String) throws {
        values.removeValue(forKey: key)
    }
}
