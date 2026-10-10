import Foundation
import Testing

@testable import mafia_manager

/// Launch restoration and app resume must never sign anyone out just
/// because Clerk or Convex could not be reached.
@MainActor
final class AccountRestorationTests {
    private let service = FakeAuthService()
    private let keychain = MemoryKeychain()
    private let suiteName = "AccountRestorationTests.\(UUID().uuidString)"

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    private func makeStore() -> AuthStore {
        AuthStore(authService: service, keychain: keychain,
                  defaults: UserDefaults(suiteName: suiteName)!, autoRestore: false)
    }

    @Test func restoresTheSignedInAccount() async {
        service.restoredUser = service.account
        let store = makeStore()

        await store.restoreSession()

        #expect(store.authenticatedAccountId == service.account.id)
    }

    @Test func restoresTheGuestWhenClerkHasNoUser() async {
        _ = await makeStore().signInAsGuest(displayName: "Guest")

        let relaunched = makeStore()
        await relaunched.restoreSession()

        #expect(relaunched.isAnonymous)
        #expect(relaunched.currentUserId == service.guest.id)
    }

    @Test func transientRestoreErrorKeepsIdentityAndPendingMerge() async {
        let store = makeStore()
        _ = await store.signInAsGuest(displayName: "Guest")
        service.mergeError = TestError.expected
        await store.signIn(email: "qa@example.com", password: "test-password")
        service.restoreError = BackendError(URLError(.notConnectedToInternet))

        await store.restoreSession()

        #expect(store.authenticatedAccountId == service.account.id)
        #expect(store.hasPendingGuestMerge, "The guest secret survives an unknown account state")
        #expect(service.guestSignIns == 1, "An unknown account state must not fall back to the guest")
        #expect(service.mergedHashes.count == 1)
    }

    @Test func transientLaunchErrorDoesNotSignInTheStoredGuest() async {
        _ = await makeStore().signInAsGuest(displayName: "Guest")
        service.restoreError = BackendError(URLError(.timedOut))

        let relaunched = makeStore()
        await relaunched.restoreSession()

        #expect(relaunched.isAuthenticated == false)
        #expect(service.guestSignIns == 1, "Only the original guest sign-in")
        #expect(relaunched.currentGuestSecretHash != nil)
        #expect(relaunched.guestDisplayName == "Guest")
    }

    @Test func resumeRefreshFailureKeepsTheAccount() async {
        let store = makeStore()
        await store.signIn(email: "qa@example.com", password: "test-password")
        service.refreshError = BackendError(URLError(.networkConnectionLost))

        await store.ensureValidSession()

        #expect(service.refreshes == 1)
        #expect(store.authenticatedAccountId == service.account.id)
    }

    @Test func foregroundRetriesAnAccountRestoreThatFailedTransiently() async throws {
        service.restoredUser = service.account
        service.restoreError = BackendError(URLError(.notConnectedToInternet))
        let store = makeStore()
        await store.restoreSession()
        #expect(store.isAuthenticated == false)

        service.restoreError = nil
        NotificationCenter.default.post(name: .appDidBecomeActive, object: nil)
        for _ in 0..<100 where store.authenticatedAccountId == nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(store.authenticatedAccountId == service.account.id)
    }

    @Test func resumeRetriesAGuestRestoreThatFailedTransiently() async {
        _ = await makeStore().signInAsGuest(displayName: "Guest")
        service.guestSignInError = BackendError(URLError(.timedOut))
        let relaunched = makeStore()
        await relaunched.restoreSession()
        #expect(relaunched.isAuthenticated == false)
        #expect(relaunched.currentGuestSecretHash != nil)

        service.guestSignInError = nil
        await relaunched.ensureValidSession()

        #expect(relaunched.isAnonymous)
        #expect(relaunched.currentUserId == service.guest.id)
    }

    @Test func noRetryWhenClerkDefinitelyHasNoUser() async {
        let store = makeStore()
        await store.restoreSession()
        service.restoredUser = service.account

        await store.ensureValidSession()

        #expect(store.isAuthenticated == false)
    }

    @Test func resumeAsGuestDoesNotTouchClerk() async {
        let store = makeStore()
        _ = await store.signInAsGuest(displayName: "Guest")

        await store.ensureValidSession()

        #expect(service.refreshes == 0)
        #expect(store.isAnonymous)
    }
}
