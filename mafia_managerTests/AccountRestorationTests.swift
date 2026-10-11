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
    /// Private, so parallel tests and the host app never see these posts.
    private let notifications = NotificationCenter()

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    private func makeStore(restoreTimeout: Duration = AuthStore.restoreTimeout) -> AuthStore {
        AuthStore(authService: service, keychain: keychain, defaults: UserDefaults(suiteName: suiteName)!,
                  notificationCenter: notifications, autoRestore: false, restoreTimeout: restoreTimeout,
                  clearPendingStats: {})
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

    @Test func resumeOnABadNetworkKeepsTheAccount() async {
        let store = makeStore()
        await store.signIn(email: "qa@example.com", password: "test-password")
        service.refreshError = BackendError(URLError(.networkConnectionLost))
        service.restoreError = BackendError(URLError(.networkConnectionLost))

        await store.ensureValidSession()

        #expect(service.refreshes == 1)
        #expect(store.authenticatedAccountId == service.account.id)
    }

    @Test func resumeDetectsARevokedSession() async {
        let store = makeStore()
        await store.signIn(email: "qa@example.com", password: "test-password")
        service.refreshError = ClerkConvexAuthError.noActiveSession
        service.restoredUser = nil

        await store.ensureValidSession()

        #expect(store.isAuthenticated == false)
    }

    @Test func foregroundRetriesAnAccountRestoreThatFailedTransiently() async throws {
        service.restoredUser = service.account
        service.restoreError = BackendError(URLError(.notConnectedToInternet))
        let store = makeStore()
        await store.restoreSession()
        #expect(store.isAuthenticated == false)

        service.restoreError = nil
        notifications.post(name: .appDidBecomeActive, object: nil)
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

    @Test func concurrentResumesShareOneTokenRefresh() async {
        let store = makeStore()
        await store.signIn(email: "qa@example.com", password: "test-password")
        service.refreshDelay = .milliseconds(50)

        async let first: Void = store.ensureValidSession()
        async let second: Void = store.ensureValidSession()
        _ = await (first, second)

        #expect(service.refreshes == 1, "AuthStore's observer and the multiplayer resume share one refresh")
        await store.ensureValidSession()
        #expect(service.refreshes == 2, "A later resume refreshes again")
    }

    @Test(.timeLimit(.minutes(1))) func slowRestoreCountsAsTransientAndResumeRetries() async {
        service.restoredUser = service.account
        service.restoreDelay = .seconds(30)
        let store = makeStore(restoreTimeout: .milliseconds(100))

        await store.restoreSession()

        #expect(store.isAuthenticated == false, "A restore that runs out of time keeps waiting off the critical path")
        service.restoreDelay = nil
        await store.ensureValidSession()
        #expect(store.authenticatedAccountId == service.account.id)
    }

    @Test(.timeLimit(.minutes(1))) func aSlowRestoreIsAdoptedWhenItArrives() async throws {
        service.restoredUser = service.account
        service.restoreDelay = .milliseconds(300)
        let store = makeStore(restoreTimeout: .milliseconds(50))

        await store.restoreSession()
        #expect(store.isAuthenticated == false, "The launch does not wait past the time limit")

        // No resume and no new Clerk event: the lookup that timed out lands on its own.
        for _ in 0..<200 where store.authenticatedAccountId == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.authenticatedAccountId == service.account.id)
        #expect(service.restores == 1, "The late result is used, not a second lookup")
    }

    @Test(.timeLimit(.minutes(1))) func aSlowRestoreFindingTheAccountAfterAGuestSignInMergesTheGuest() async throws {
        service.restoredUser = service.account
        service.restoreDelay = .milliseconds(300)
        let store = makeStore(restoreTimeout: .milliseconds(50))
        await store.restoreSession()
        // The app looked signed out, so the user played on as a guest.
        _ = await store.signInAsGuest(displayName: "Guest")
        #expect(store.isAnonymous)

        for _ in 0..<200 where store.authenticatedAccountId == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.authenticatedAccountId == service.account.id, "As when Clerk reports the account later")
        #expect(service.mergedHashes.count == 1)
    }

    @Test(.timeLimit(.minutes(1))) func accountSessionFoundAfterLaunchReplacesTheGuest() async throws {
        let store = makeStore()
        _ = await store.signInAsGuest(displayName: "Guest")
        await store.restoreSession()
        #expect(store.isAnonymous, "Clerk held no user at launch, so the guest was restored at once")

        service.restoredUser = service.account
        service.startAccountSession()
        for _ in 0..<200 where store.authenticatedAccountId == nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(store.authenticatedAccountId == service.account.id)
        #expect(service.mergedHashes.count == 1, "The guest's progress merges into the account")
    }

    @Test(.timeLimit(.minutes(1))) func accountSessionDuringInteractiveSignInIsLeftToTheFlow() async throws {
        let store = makeStore()
        _ = await store.signInAsGuest(displayName: "Guest")
        service.restoredUser = service.account
        service.signInDelay = .milliseconds(300)
        let restores = service.restores

        let signIn = Task { await store.signIn(email: "qa@example.com", password: "test-password") }
        for _ in 0..<100 where !store.isLoading {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(store.isLoading)
        #expect(store.authenticatedAccountId == nil, "Still the guest while the flow runs")
        // Clerk reports the session from inside setActive, while the sign-in flow is still running.
        service.startAccountSession()
        try await Task.sleep(for: .milliseconds(50))
        await signIn.value
        try await Task.sleep(for: .milliseconds(50))

        #expect(store.authenticatedAccountId == service.account.id)
        #expect(service.restores == restores, "The flow finishes its own sign-in; no restore runs alongside it")
        #expect(service.mergedHashes.count == 1, "One guest merge, by the flow")
    }
}
