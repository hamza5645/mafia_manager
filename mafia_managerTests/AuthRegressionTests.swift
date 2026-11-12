import ConvexMobile
import XCTest

@testable import mafia_manager

// nonisolated, with main-actor members: under default MainActor isolation a main-actor
// XCTestCase subclass inherits its initializers as main-actor ones (an error in Swift 6).
nonisolated final class AuthRegressionTests: XCTestCase {
    @MainActor func testGuestToAccountTransitionChangesLoginDismissalSignal() async throws {
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

    @MainActor func testFailedAccountLoginKeepsGuestDismissalSignalEmpty() async throws {
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

    @MainActor func testClerkCodesMapToActionableErrors() {
        XCTAssertEqual(AuthService.authError(forClerkCode: "form_identifier_exists"), .emailAlreadyInUse)
        XCTAssertEqual(AuthService.authError(forClerkCode: "form_identifier_not_found"), .accountNotFound)
        XCTAssertNil(AuthService.authError(forClerkCode: "form_password_incorrect"))
        let guidance = AuthError.accountNotFound.errorDescription ?? ""
        XCTAssertTrue(guidance.contains("before the update"))
        XCTAssertTrue(guidance.contains("Sign Up with the same email"))
    }

    @MainActor func testUnknownEmailShowsLegacyGuidanceOnSignInAndReset() async {
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

    @MainActor func testPasswordsAreTrimmedTheSameWayEverywhere() async {
        let service = FakeAuthService()
        let store = makeStore(service)

        await store.signIn(email: " a@example.com ", password: "  sign-in-pass \n")
        _ = await store.startSignUp(email: "b@example.com", password: " sign-up-pass ", displayName: "B")
        await store.confirmPasswordReset(code: "123456", newPassword: "\treset-pass ")

        XCTAssertEqual(service.passwords, ["sign-in-pass", "sign-up-pass", "reset-pass"])
        XCTAssertEqual(AuthStore.minimumPasswordLength, 8)
    }

    @MainActor func testTemplatedTokenRefreshForwardsOnlySuccessfulFetch() async {
        let token = await ClerkConvexAuthProvider.refreshedConvexToken {
            "convex-template-token"
        }
        let failed = await ClerkConvexAuthProvider.refreshedConvexToken {
            throw TestError.expected
        }

        XCTAssertEqual(token, "convex-template-token")
        XCTAssertNil(failed)
    }

    @MainActor func testRefreshedTokenIsPushedOnlyWhenItChanged() {
        XCTAssertNil(ClerkConvexAuthProvider.tokenToPush("token-a", lastPushed: "token-a"),
                     "A second .tokenRefreshed with the same token must not re-authenticate Convex")
        XCTAssertEqual(ClerkConvexAuthProvider.tokenToPush("token-b", lastPushed: "token-a"), "token-b")
        XCTAssertEqual(ClerkConvexAuthProvider.tokenToPush("token-a", lastPushed: nil), "token-a")
        XCTAssertNil(ClerkConvexAuthProvider.tokenToPush(nil, lastPushed: "token-a"), "A failed fetch keeps the last token")
    }

    // MARK: - Guest merge

    @MainActor func testUpgradeMergesGuestAndForgetsIt() async {
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

    @MainActor func testPasswordResetFinishesGuestMerge() async {
        let service = FakeAuthService()
        let store = makeStore(service)
        _ = await store.signInAsGuest(displayName: service.guest.displayName)

        await store.confirmPasswordReset(code: "424242", newPassword: "new-password")

        XCTAssertEqual(store.authenticatedAccountId, service.account.id)
        XCTAssertEqual(service.mergedHashes.count, 1)
        XCTAssertNil(store.currentGuestSecretHash)
    }

    @MainActor func testFailedMergeStaysPendingAndRetriesAtNextLaunch() async {
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

    @MainActor func testSettingsRetryFinishesAPendingMerge() async {
        let service = FakeAuthService()
        let store = makeStore(service)
        _ = await store.signInAsGuest(displayName: service.guest.displayName)
        service.mergeError = TestError.expected
        await store.signIn(email: "qa@example.com", password: "test-password")
        XCTAssertTrue(store.hasPendingGuestMerge)

        let failure = await store.retryGuestMerge()
        XCTAssertTrue(store.hasPendingGuestMerge)
        XCTAssertNotNil(failure, "Settings shows why the retry failed")

        service.mergeError = nil
        let success = await store.retryGuestMerge()
        XCTAssertNil(success)
        XCTAssertFalse(store.hasPendingGuestMerge)
        XCTAssertEqual(service.mergedHashes.count, 3)
    }

    @MainActor func testMissingServerGuestIsForgottenInsteadOfRetriedForever() async {
        let service = FakeAuthService()
        let store = makeStore(service)
        _ = await store.signInAsGuest(displayName: service.guest.displayName)
        service.mergeError = BackendError(ClientError.ConvexError(data: "\"\(BackendError.guestNotFound)\""))

        await store.signIn(email: "qa@example.com", password: "test-password")

        XCTAssertNil(store.currentGuestSecretHash)
        XCTAssertFalse(store.hasPendingGuestMerge)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor func testAbandonedUpgradeLeavesAPlainGuestWithNothingPending() async {
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

    @MainActor func testClearingGuestDataRemovesSecretNameAndPendingMerge() async {
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
        XCTAssertEqual(clearedStats, 1, "Sign-out forgets the games waiting to be recorded")
    }

    @MainActor func testFailedAccountSignOutKeepsTheAccountAndItsPendingGuest() async {
        let service = FakeAuthService()
        let store = makeStore(service)
        _ = await store.signInAsGuest(displayName: service.guest.displayName)
        service.mergeError = TestError.expected
        await store.signIn(email: "qa@example.com", password: "test-password")
        service.signOutError = URLError(.notConnectedToInternet)

        await store.signOut()

        XCTAssertEqual(store.authenticatedAccountId, service.account.id, "Clerk still has the account")
        XCTAssertTrue(store.hasPendingGuestMerge)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(clearedStats, 0, "The account stays signed in, so its pending games stay")
    }

    @MainActor func testFailedGuestSignOutStillClearsGuestData() async {
        let service = FakeAuthService()
        let store = makeStore(service)
        _ = await store.signInAsGuest(displayName: service.guest.displayName)
        service.signOutError = URLError(.notConnectedToInternet)

        await store.signOut()

        XCTAssertFalse(store.isAuthenticated)
        XCTAssertNil(store.currentGuestSecretHash)
        XCTAssertNil(store.guestDisplayName)
    }

    @MainActor func testSignOutWithPendingMergeNeverMergesIntoTheNextAccount() async {
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

    // MARK: - Seat conflict

    @MainActor func testSeatConflictCanBeDiscardedFromSettings() async {
        let service = FakeAuthService()
        let store = makeStore(service)
        _ = await store.signInAsGuest(displayName: service.guest.displayName)
        service.mergeError = BackendError(ClientError.ConvexError(
            data: "\"Leave your other seat in this room before saving guest progress.\""
        ))
        await store.signIn(email: "qa@example.com", password: "test-password")
        XCTAssertTrue(store.hasPendingGuestMerge)
        XCTAssertTrue(store.guestMergeHasSeatConflict, "Settings offers Discard guest progress")

        store.discardPendingGuestProgress()

        XCTAssertFalse(store.hasPendingGuestMerge)
        XCTAssertFalse(store.guestMergeHasSeatConflict)
        XCTAssertNil(store.activeGuestProof, "Requests act as the account again")
        XCTAssertEqual(store.authenticatedAccountId, service.account.id)
    }

    @MainActor func testOtherMergeFailuresDoNotOfferDiscard() async {
        let service = FakeAuthService()
        let store = makeStore(service)
        _ = await store.signInAsGuest(displayName: service.guest.displayName)
        service.mergeError = BackendError(URLError(.notConnectedToInternet))

        await store.signIn(email: "qa@example.com", password: "test-password")

        XCTAssertTrue(store.hasPendingGuestMerge)
        XCTAssertFalse(store.guestMergeHasSeatConflict)
    }

    // MARK: - Guest proof cache and identity revision

    @MainActor func testGuestSecretHashIsReadFromTheKeychainOnce() async {
        let service = FakeAuthService()
        let keychain = MemoryKeychain()
        let store = makeStore(service, keychain: keychain)
        XCTAssertNil(store.activeGuestProof)
        _ = await store.signInAsGuest(displayName: service.guest.displayName)
        let loadsAfterSignIn = keychain.loads

        for _ in 0..<20 { _ = store.activeGuestProof }

        XCTAssertNotNil(store.activeGuestProof)
        XCTAssertEqual(keychain.loads, loadsAfterSignIn, "Every request reuses the cached hash")

        await store.signOut()
        XCTAssertNil(store.currentGuestSecretHash)
        let loadsAfterSignOut = keychain.loads
        for _ in 0..<20 { _ = store.currentGuestSecretHash }
        XCTAssertEqual(keychain.loads, loadsAfterSignOut, "A missing secret is cached too")
    }

    @MainActor func testKeychainErrorsOtherThanNotFoundAreNotCached() {
        let keychain = MemoryKeychain()
        keychain.loadError = TestError.expected
        let store = makeStore(FakeAuthService(), keychain: keychain)

        XCTAssertNil(store.currentGuestSecretHash)
        keychain.loadError = nil
        try? keychain.save("secret", forKey: "convex_guest_secret")

        XCTAssertNotNil(store.currentGuestSecretHash, "A failed read is tried again")
    }

    @MainActor func testIdentityRevisionChangesOnlyWithTheIdentity() async {
        let service = FakeAuthService()
        let keychain = MemoryKeychain()
        let store = makeStore(service, keychain: keychain)
        _ = await store.signInAsGuest(displayName: service.guest.displayName)
        let guestRevision = store.identityRevision

        await store.restoreSession()
        await store.ensureValidSession()
        XCTAssertEqual(store.identityRevision, guestRevision, "Re-applying the same guest restarts nothing")

        service.mergeError = TestError.expected
        await store.signIn(email: "qa@example.com", password: "test-password")
        let pendingRevision = store.identityRevision
        XCTAssertGreaterThan(pendingRevision, guestRevision)

        service.restoredUser = service.account
        await store.restoreSession()
        XCTAssertEqual(store.identityRevision, pendingRevision, "Same account, same pending guest proof")

        service.mergeError = nil
        _ = await store.retryGuestMerge()
        XCTAssertGreaterThan(store.identityRevision, pendingRevision, "The guest proof stopped being sent")
    }

    @MainActor private var clearedStats = 0

    @MainActor private func makeStore(_ service: FakeAuthService, keychain: MemoryKeychain? = nil) -> AuthStore {
        let suiteName = "AuthRegressionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        // A private center: the host app and parallel tests never see these stores.
        return AuthStore(
            authService: service,
            keychain: keychain ?? MemoryKeychain(),
            defaults: defaults,
            notificationCenter: NotificationCenter(),
            autoRestore: false,
            clearPendingStats: { [weak self] in self?.clearedStats += 1 }
        )
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
    var signOutError: Error?
    var signUpError: Error?
    var passwordResetError: Error?
    var mergeError: Error?
    var signUpNeedsEmailCode = false
    /// Makes `currentUser` and `refreshConvexAuth` slow, to test overlap and time limits.
    var restoreDelay: Duration?
    var refreshDelay: Duration?
    /// Keeps `signIn` running, like Clerk's setActive and ensureUser on a slow network.
    var signInDelay: Duration?
    private(set) var passwords: [String] = []
    private(set) var mergedHashes: [String?] = []
    private(set) var guestSignIns = 0
    private(set) var refreshes = 0
    private(set) var restores = 0
    private var sessionContinuations: [AsyncStream<Void>.Continuation] = []

    var currentUser: UserProfile? {
        get async throws {
            restores += 1
            if let restoreDelay { try? await Task.sleep(for: restoreDelay) }
            if let restoreError { throw restoreError }
            return restoredUser
        }
    }

    /// One stream per store, like Clerk's events.
    var accountSessionStarted: AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        sessionContinuations.append(continuation)
        return stream
    }

    /// Clerk reports a newly active session.
    func startAccountSession() {
        sessionContinuations.forEach { $0.yield() }
    }

    func refreshConvexAuth() async throws {
        refreshes += 1
        if let refreshDelay { try? await Task.sleep(for: refreshDelay) }
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
        if let signInDelay { try? await Task.sleep(for: signInDelay) }
        if let signInError { throw signInError }
        return account
    }

    func signOut() async throws {
        if let signOutError { throw signOutError }
    }

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
    private(set) var loads = 0
    /// Thrown by `load` instead of a result, e.g. a locked Keychain.
    var loadError: Error?

    func save(_ value: String, forKey key: String) throws {
        values[key] = value
    }

    func load(forKey key: String) throws -> String {
        loads += 1
        if let loadError { throw loadError }
        guard let value = values[key] else { throw KeychainHelper.KeychainError.itemNotFound }
        return value
    }

    func delete(forKey key: String) throws {
        values.removeValue(forKey: key)
    }
}
