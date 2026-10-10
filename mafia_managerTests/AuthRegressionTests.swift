import ConvexMobile
import XCTest

@testable import mafia_manager

@MainActor
final class AuthRegressionTests: XCTestCase {
    func testGuestToAccountTransitionChangesLoginDismissalSignal() async throws {
        let service = FakeAuthService()
        let store = makeStore(service)
        XCTAssertNil(store.authenticatedAccountId)
        let guestSignedIn = await store.signInAsGuest(displayName: service.guest.displayName)
        XCTAssertTrue(guestSignedIn)
        XCTAssertTrue(store.isAuthenticated)
        XCTAssertNil(store.authenticatedAccountId, "Guest auth must not dismiss account forms")
        await store.signIn(email: "qa@example.com", password: "test-password")
        XCTAssertTrue(store.isAuthenticated, "This Boolean stays true across the transition")
        XCTAssertEqual(store.authenticatedAccountId, service.account.id, "Account identity must trigger form dismissal")
    }

    func testFailedAccountLoginKeepsGuestDismissalSignalEmpty() async throws {
        let service = FakeAuthService()
        service.signInError = TestError.expected
        let store = makeStore(service)
        _ = await store.signInAsGuest(displayName: service.guest.displayName)
        await store.signIn(email: "qa@example.com", password: "wrong-password")
        XCTAssertTrue(store.isAuthenticated)
        XCTAssertEqual(store.currentUserId, service.guest.id)
        XCTAssertNil(store.authenticatedAccountId)
        XCTAssertNotNil(store.errorMessage)
    }

    func testClerkCodesMapToActionableErrors() {
        XCTAssertEqual(AuthService.authError(forClerkCode: "form_identifier_exists"), .emailAlreadyInUse)
        XCTAssertEqual(AuthService.authError(forClerkCode: "form_identifier_not_found"), .accountNotFound)
        XCTAssertNil(AuthService.authError(forClerkCode: "form_password_incorrect"))
        let guidance = AuthError.accountNotFound.errorDescription ?? ""
        XCTAssertTrue(guidance.contains("before the update"))
        XCTAssertTrue(guidance.contains("Sign Up with the same email"))
    }

    func testUnknownEmailShowsLegacyGuidanceOnSignInAndReset() async {
        let service = FakeAuthService()
        service.signInError = AuthError.accountNotFound
        service.passwordResetError = AuthError.accountNotFound
        let store = makeStore(service)

        await store.signIn(email: "legacy@example.com", password: "legacy-password")
        XCTAssertEqual(store.errorMessage, AuthError.accountNotFound.errorDescription)
        let resetStarted = await store.startPasswordReset(email: "legacy@example.com")
        XCTAssertFalse(resetStarted)
        XCTAssertEqual(store.errorMessage, AuthError.accountNotFound.errorDescription)
    }

    func testPasswordsAreTrimmedTheSameWayEverywhere() async {
        let service = FakeAuthService()
        let store = makeStore(service)

        await store.signIn(email: " a@example.com ", password: "  sign-in-pass \n")
        _ = await store.startSignUp(email: "b@example.com", password: " sign-up-pass ", displayName: "B")
        await store.confirmPasswordReset(code: "123456", newPassword: "\treset-pass ")

        XCTAssertEqual(service.passwords, ["sign-in-pass", "sign-up-pass", "reset-pass"])
        XCTAssertEqual(AuthStore.minimumPasswordLength, 8)
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

    // MARK: - Guest merge

    func testUpgradeMergesGuestAndForgetsIt() async {
        let service = FakeAuthService()
        let store = makeStore(service)
        _ = await store.signInAsGuest(displayName: service.guest.displayName)
        let guestProof = store.currentGuestSecretHash

        let needsCode = await store.startSignUp(email: "guest@example.com", password: "password123", displayName: "Account")

        XCTAssertFalse(needsCode)
        XCTAssertEqual(service.mergedHashes, [guestProof])
        XCTAssertEqual(store.authenticatedAccountId, service.account.id)
        XCTAssertFalse(store.hasPendingGuestMerge)
        XCTAssertNil(store.currentGuestSecretHash)
        XCTAssertNil(store.guestDisplayName)
        XCTAssertNil(store.activeGuestProof)
    }

    func testPasswordResetFinishesGuestMerge() async {
        let service = FakeAuthService()
        let store = makeStore(service)
        _ = await store.signInAsGuest(displayName: service.guest.displayName)

        await store.confirmPasswordReset(code: "424242", newPassword: "new-password")

        XCTAssertEqual(store.authenticatedAccountId, service.account.id)
        XCTAssertEqual(service.mergedHashes.count, 1)
        XCTAssertNil(store.currentGuestSecretHash)
    }

    func testFailedMergeStaysPendingAndRetriesAtNextLaunch() async {
        let service = FakeAuthService()
        let keychain = MemoryKeychain()
        let store = makeStore(service, keychain: keychain)
        _ = await store.signInAsGuest(displayName: service.guest.displayName)
        let guestProof = store.currentGuestSecretHash
        service.signUpNeedsEmailCode = true
        service.mergeError = BackendError(ClientError.ConvexError(
            data: "\"Leave your other seat in this room before saving guest progress.\""
        ))

        let needsCode = await store.startSignUp(email: "guest@example.com", password: "password123", displayName: "Account")
        XCTAssertTrue(needsCode)
        await store.verifySignUpEmailCode("424242")

        XCTAssertEqual(store.authenticatedAccountId, service.account.id, "The account is usable while the merge waits")
        XCTAssertTrue(store.hasPendingGuestMerge)
        XCTAssertEqual(store.activeGuestProof, guestProof, "Requests act as the guest until the merge succeeds")
        XCTAssertTrue(store.errorMessage?.contains("Leave your other seat") == true)

        service.mergeError = nil
        service.restoredUser = service.account
        let relaunched = makeStore(service, keychain: keychain)
        await relaunched.restoreSession()

        XCTAssertEqual(service.mergedHashes, [guestProof, guestProof])
        XCTAssertFalse(relaunched.hasPendingGuestMerge)
        XCTAssertNil(relaunched.currentGuestSecretHash)
        XCTAssertNil(relaunched.errorMessage)
    }

    func testSettingsRetryFinishesAPendingMerge() async {
        let service = FakeAuthService()
        let store = makeStore(service)
        _ = await store.signInAsGuest(displayName: service.guest.displayName)
        service.mergeError = TestError.expected
        await store.signIn(email: "qa@example.com", password: "test-password")
        XCTAssertTrue(store.hasPendingGuestMerge)

        await store.retryGuestMerge()
        XCTAssertTrue(store.hasPendingGuestMerge)
        XCTAssertNotNil(store.errorMessage, "Settings shows why the retry failed")

        service.mergeError = nil
        await store.retryGuestMerge()
        XCTAssertFalse(store.hasPendingGuestMerge)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(service.mergedHashes.count, 3)
    }

    func testMissingServerGuestIsForgottenInsteadOfRetriedForever() async {
        let service = FakeAuthService()
        let store = makeStore(service)
        _ = await store.signInAsGuest(displayName: service.guest.displayName)
        service.mergeError = BackendError(ClientError.ConvexError(data: "\"Guest progress could not be found.\""))

        await store.signIn(email: "qa@example.com", password: "test-password")

        XCTAssertNil(store.currentGuestSecretHash)
        XCTAssertFalse(store.hasPendingGuestMerge)
        XCTAssertNil(store.errorMessage)
    }

    func testAbandonedUpgradeLeavesAPlainGuestWithNothingPending() async {
        let service = FakeAuthService()
        let store = makeStore(service)
        _ = await store.signInAsGuest(displayName: service.guest.displayName)

        service.signUpError = AuthError.emailAlreadyInUse
        let failed = await store.startSignUp(email: "taken@example.com", password: "password123", displayName: "Account")
        XCTAssertFalse(failed)
        XCTAssertEqual(store.errorMessage, AuthError.emailAlreadyInUse.errorDescription)

        service.signUpError = nil
        service.signUpNeedsEmailCode = true
        let needsCode = await store.startSignUp(email: "new@example.com", password: "password123", displayName: "Account")
        XCTAssertTrue(needsCode)
        store.cancelPendingSignUp()

        XCTAssertTrue(store.isAnonymous)
        XCTAssertFalse(store.hasPendingGuestMerge)
        XCTAssertTrue(service.mergedHashes.isEmpty)
    }

    // MARK: - Sign-out

    func testClearingGuestDataRemovesSecretNameAndPendingMerge() async {
        let service = FakeAuthService()
        let store = makeStore(service)
        _ = await store.signInAsGuest(displayName: service.guest.displayName)
        XCTAssertNotNil(store.currentGuestSecretHash)
        XCTAssertNotNil(store.guestDisplayName)

        await store.signOut()

        XCTAssertFalse(store.isAuthenticated)
        XCTAssertNil(store.currentGuestSecretHash)
        XCTAssertNil(store.guestDisplayName)
        XCTAssertFalse(store.hasPendingGuestMerge)
        XCTAssertNil(store.activeGuestProof)
    }

    func testSignOutWithPendingMergeNeverMergesIntoTheNextAccount() async {
        let service = FakeAuthService()
        let store = makeStore(service)
        _ = await store.signInAsGuest(displayName: service.guest.displayName)
        service.mergeError = TestError.expected
        await store.signIn(email: "first@example.com", password: "test-password")
        XCTAssertTrue(store.hasPendingGuestMerge)

        await store.signOut()
        service.mergeError = nil
        await store.signIn(email: "second@example.com", password: "test-password")

        XCTAssertEqual(service.mergedHashes.count, 1, "Only the failed attempt for the first account")
        XCTAssertFalse(store.hasPendingGuestMerge)
    }

    private func makeStore(_ service: FakeAuthService, keychain: MemoryKeychain? = nil) -> AuthStore {
        let suiteName = "AuthRegressionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return AuthStore(authService: service, keychain: keychain ?? MemoryKeychain(), defaults: defaults, autoRestore: false)
    }
}

enum TestError: Error {
    case expected
}

/// In-memory `AuthServicing` that records what the store sends.
@MainActor
final class FakeAuthService: AuthServicing {
    let guest = UserProfile(id: UUID(), displayName: "Guest", isAnonymous: true, createdAt: Date(), updatedAt: Date())
    let account = UserProfile(id: UUID(), displayName: "Account", isAnonymous: false, createdAt: Date(), updatedAt: Date())
    var restoredUser: UserProfile?
    var restoreError: Error?
    var refreshError: Error?
    var signInError: Error?
    var guestSignInError: Error?
    var signUpError: Error?
    var passwordResetError: Error?
    var mergeError: Error?
    var signUpNeedsEmailCode = false
    private(set) var passwords: [String] = []
    private(set) var mergedHashes: [String?] = []
    private(set) var guestSignIns = 0
    private(set) var refreshes = 0

    var currentUser: UserProfile? {
        get async throws {
            if let restoreError { throw restoreError }
            return restoredUser
        }
    }

    func refreshConvexAuth() async throws {
        refreshes += 1
        if let refreshError { throw refreshError }
    }

    func startSignUp(email: String, password: String, displayName: String) async throws -> UserProfile? {
        passwords.append(password)
        if let signUpError { throw signUpError }
        return signUpNeedsEmailCode ? nil : account
    }

    func verifySignUpEmailCode(_ code: String, displayName: String) async throws -> UserProfile {
        account
    }

    func resendSignUpEmailCode() async throws {}

    func signIn(email: String, password: String) async throws -> UserProfile {
        passwords.append(password)
        if let signInError { throw signInError }
        return account
    }

    func signOut() async throws {}

    func startPasswordReset(email: String) async throws {
        if let passwordResetError { throw passwordResetError }
    }

    func confirmPasswordReset(code: String, newPassword: String) async throws -> UserProfile {
        passwords.append(newPassword)
        return account
    }

    func updateProfile(displayName: String) async throws {}

    func signInAsGuest(displayName: String, guestSecretHash: String) async throws -> UserProfile {
        guestSignIns += 1
        if let guestSignInError { throw guestSignInError }
        return guest
    }

    func mergeGuestIntoAccount(guestSecretHash: String) async throws {
        mergedHashes.append(guestSecretHash)
        if let mergeError { throw mergeError }
    }
}

final class MemoryKeychain: KeychainStoring {
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
