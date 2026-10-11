import Foundation
import SwiftUI
import Combine
import CryptoKit

@MainActor
final class AuthStore: ObservableObject {
    /// Clerk's default minimum password length.
    static let minimumPasswordLength = 8

    @Published var isAuthenticated = false
    @Published var currentUserId: UUID?
    @Published var userProfile: UserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isRestoringSession = true
    @Published var isAnonymous = false
    /// Changes whenever the identity sent to Convex (user, anonymity, guest
    /// proof) changes; multiplayer subscriptions restart when it does.
    @Published private(set) var identityRevision = 0
    /// The last guest merge failed because both identities hold a seat in
    /// one room. Settings then offers to discard the guest progress.
    @Published private(set) var guestMergeHasSeatConflict = false

    /// Guests are authenticated too; account identity is the completion signal
    /// for sign-in/signup/reset presentation, including guest upgrades.
    var authenticatedAccountId: UUID? {
        isAuthenticated && userProfile?.isAnonymous == false ? userProfile?.id : nil
    }

    /// An account is signed in but this device's guest progress has not been
    /// merged into it yet. Every account sign-in retries the merge.
    var hasPendingGuestMerge: Bool {
        authenticatedAccountId != nil && currentGuestSecretHash != nil
    }

    var guestDisplayName: String? {
        get { defaults.string(forKey: "guest_display_name") }
        set {
            if let name = newValue {
                defaults.set(name, forKey: "guest_display_name")
            } else {
                defaults.removeObject(forKey: "guest_display_name")
            }
        }
    }

    /// How long a restore may wait for Clerk and Convex before it counts as
    /// a transient failure (the next resume retries it).
    nonisolated static let restoreTimeout: Duration = .seconds(15)

    private let authService: any AuthServicing
    private let keychain: any KeychainStoring
    private let defaults: UserDefaults
    private let restoreTimeout: Duration
    private let clearPendingStats: @MainActor () -> Void
    /// The last restore could not reach Clerk or Convex; resuming retries it.
    private var restoreFailedTransiently = false
    private var foregroundObserver: AnyCancellable?
    private var launchRestore: Task<Void, Never>?
    private var accountSessionObserver: Task<Void, Never>?
    /// The running `ensureValidSession`; later callers wait for it.
    private var ensureTask: Task<Void, Never>?
    /// nil: not read yet. `.some(nil)`: the Keychain holds no guest secret.
    private var cachedGuestSecretHash: String??
    private var lastIdentity = Identity(userId: nil, isAnonymous: false, guestProof: nil)

    private struct Identity: Equatable {
        let userId: UUID?
        let isAnonymous: Bool
        let guestProof: String?
    }

    private enum KeychainKeys {
        static let guestSecret = "convex_guest_secret"
    }

    private enum DefaultsKeys {
        static let pendingSignUpDisplayName = "pending_signup_display_name"
    }

    init(
        authService: (any AuthServicing)? = nil,
        keychain: (any KeychainStoring)? = nil,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        autoRestore: Bool = true,
        restoreTimeout: Duration = AuthStore.restoreTimeout,
        clearPendingStats: @escaping @MainActor () -> Void = { StatsOutbox.shared.clear() }
    ) {
        self.authService = authService ?? AuthService()
        self.keychain = keychain ?? KeychainHelper.shared
        self.defaults = defaults
        self.restoreTimeout = restoreTimeout
        self.clearPendingStats = clearPendingStats
        // The real AuthService talks to ConvexService.shared; give it this
        // device's guest proof. Injected test services leave Convex untouched.
        if authService == nil {
            ConvexService.shared.guestProofProvider = { [weak self] in self?.activeGuestProof }
        }
        foregroundObserver = notificationCenter.publisher(for: .appDidBecomeActive)
            .sink { [weak self] _ in
                Task { @MainActor in await self?.ensureValidSession() }
            }
        if autoRestore {
            launchRestore = Task {
                defer { isRestoringSession = false }
                await restoreSession()
            }
        } else {
            isRestoringSession = false
        }
        let sessions = self.authService.accountSessionStarted
        accountSessionObserver = Task { [weak self] in
            for await _ in sessions {
                await self?.adoptAccountSessionFoundLater()
            }
        }
    }

    deinit {
        accountSessionObserver?.cancel()
    }

    func restoreSession() async {
        restoreFailedTransiently = false
        let account: UserProfile?
        let authService = authService
        let lookup = Task { try await authService.currentUser }
        do {
            account = try await ConvexService.withTimeout(
                restoreTimeout,
                error: BackendError(timedOut: BackendError.network)
            ) {
                try await lookup.value
            }
        } catch {
            // Clerk or Convex is unreachable or too slow. Not knowing is not
            // signed out: keep the current identity and every stored credential.
            restoreFailedTransiently = true
            if (error as? BackendError)?.isTimeout == true { adoptAccountWhenItArrives(lookup) }
            return
        }
        if let account {
            await finishAccountAuth(account)
            return
        }

        if let guestName = guestDisplayName, let guestSecretHash = currentGuestSecretHash {
            do {
                let profile = try await authService.signInAsGuest(
                    displayName: guestName,
                    guestSecretHash: guestSecretHash
                )
                applyAuthenticatedProfile(profile)
            } catch {
                restoreFailedTransiently = true
            }
        } else {
            clearLocalAuthState()
        }
    }

    /// A restore that ran out of time keeps looking. An account it finds is
    /// applied when it arrives, unless the store moved on meanwhile (a later
    /// restore, or an interactive flow); otherwise the next resume retries.
    private func adoptAccountWhenItArrives(_ lookup: Task<UserProfile?, Error>) {
        Task { [weak self] in
            guard case .success(let account?) = await lookup.result, let self, self.restoreFailedTransiently,
                  self.authenticatedAccountId == nil, !self.isLoading, self.ensureTask == nil else { return }
            self.restoreFailedTransiently = false
            await self.finishAccountAuth(account)
        }
    }

    /// Called when the app resumes. Retries a restore that could not reach
    /// the server; otherwise refreshes the account's Convex token. If that
    /// fails, a full restore tells a revoked session (signed out) from an
    /// unreachable server (identity kept). Concurrent callers share one run.
    func ensureValidSession() async {
        if let ensureTask {
            return await ensureTask.value
        }
        let task = Task {
            await validateSession()
            ensureTask = nil
        }
        ensureTask = task
        await task.value
    }

    private func validateSession() async {
        if restoreFailedTransiently {
            await restoreSession()
            return
        }
        guard authenticatedAccountId != nil else { return }
        do {
            let authService = authService
            try await ConvexService.withTimeout(restoreTimeout, error: BackendError(timedOut: BackendError.network)) {
                try await authService.refreshConvexAuth()
            }
        } catch {
            await restoreSession()
        }
    }

    /// Clerk reported an active session after launch restore went on without
    /// one (its own client refresh finished late). Interactive flows finish
    /// their own sign-in, so only an idle store without an account restores.
    private func adoptAccountSessionFoundLater() async {
        if let launchRestore { await launchRestore.value }
        guard authenticatedAccountId == nil, !isLoading else { return }
        await restoreSession()
    }

    /// Returns true when Clerk emailed a code that `verifySignUpEmailCode` needs.
    func startSignUp(email: String, password: String, displayName: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let trimmedDisplayName = trimmed(displayName)

        do {
            guard let profile = try await authService.startSignUp(
                email: trimmed(email),
                password: trimmed(password),
                displayName: trimmedDisplayName
            ) else {
                defaults.set(trimmedDisplayName, forKey: DefaultsKeys.pendingSignUpDisplayName)
                return true
            }
            clearPendingVerificationState()
            await finishAccountAuth(profile)
        } catch {
            clearPendingVerificationState()
            errorMessage = mapAuthError(error)
        }
        return false
    }

    func verifySignUpEmailCode(_ code: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let displayName = defaults.string(forKey: DefaultsKeys.pendingSignUpDisplayName) ?? ""
        do {
            let profile = try await authService.verifySignUpEmailCode(code, displayName: displayName)
            clearPendingVerificationState()
            await finishAccountAuth(profile)
        } catch {
            errorMessage = mapAuthError(error)
        }
    }

    func resendSignUpEmailCode() async -> Bool {
        errorMessage = nil
        do {
            try await authService.resendSignUpEmailCode()
            return true
        } catch {
            errorMessage = mapAuthError(error)
            return false
        }
    }

    func cancelPendingSignUp() {
        clearPendingVerificationState()
    }

    private func clearPendingVerificationState() {
        defaults.removeObject(forKey: DefaultsKeys.pendingSignUpDisplayName)
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let profile = try await authService.signIn(email: trimmed(email), password: trimmed(password))
            await finishAccountAuth(profile)
        } catch {
            errorMessage = mapAuthError(error)
        }
    }

    /// Signs out of the account or guest session and forgets this device's
    /// guest, so its progress can never merge into a later sign-in.
    func signOut() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await authService.signOut()
        } catch {
            errorMessage = mapAuthError(error)
            // Clerk still holds the account and would restore it at the next
            // launch, merging whatever guest plays here meanwhile. Stay signed in.
            if authenticatedAccountId != nil { return }
        }

        clearLocalAuthState()
        clearGuestData()
        clearPendingStats()
    }

    func startPasswordReset(email: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await authService.startPasswordReset(email: trimmed(email))
            return true
        } catch {
            errorMessage = mapAuthError(error)
            return false
        }
    }

    func confirmPasswordReset(code: String, newPassword: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let profile = try await authService.confirmPasswordReset(code: code, newPassword: trimmed(newPassword))
            await finishAccountAuth(profile)
        } catch {
            errorMessage = mapAuthError(error)
        }
    }

    func updateProfile(displayName: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await authService.updateProfile(displayName: displayName)
            userProfile?.displayName = displayName
            userProfile?.updatedAt = Date()
        } catch {
            errorMessage = mapAuthError(error)
        }
    }

    func signInAsGuest(displayName: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let secret = try loadOrCreateGuestSecret()
            let profile = try await authService.signInAsGuest(
                displayName: displayName,
                guestSecretHash: hash(secret)
            )
            guestDisplayName = displayName
            applyAuthenticatedProfile(profile)
            return true
        } catch {
            errorMessage = mapAuthError(error)
            return false
        }
    }

    func clearError() {
        errorMessage = nil
    }

    /// Every account entry path (restore, sign-up, sign-in, password reset)
    /// ends here. Guest progress on this device merges into the account; if
    /// that fails the guest secret stays, so the next launch or sign-in
    /// retries, and requests keep acting as the guest until then.
    private func finishAccountAuth(_ profile: UserProfile) async {
        applyAuthenticatedProfile(profile)
        if let failure = await retryGuestMerge() {
            errorMessage = failure
        }
    }

    /// Merges this device's guest into the signed-in account, if one is left.
    /// Returns why the merge failed, or nil.
    @discardableResult
    func retryGuestMerge() async -> String? {
        guard hasPendingGuestMerge, let guestSecretHash = currentGuestSecretHash else { return nil }
        do {
            try await authService.mergeGuestIntoAccount(guestSecretHash: guestSecretHash)
            clearGuestData()
        } catch let error as BackendError where error.isServerMessage && error.message == BackendError.guestNotFound {
            // The guest was never created on the server; nothing is left to merge.
            clearGuestData()
        } catch {
            guestMergeHasSeatConflict = (error as? BackendError).map {
                $0.isServerMessage && $0.message.hasPrefix(BackendError.mergeSeatConflictPrefix)
            } ?? false
            return "Guest progress was not saved to your account yet and will retry next launch. \(mapAuthError(error))"
        }
        return nil
    }

    /// Gives up a pending merge that keeps failing: forgets this device's
    /// guest so requests act as the account. The server keeps the guest row.
    func discardPendingGuestProgress() {
        guard hasPendingGuestMerge else { return }
        clearGuestData()
    }

    private func applyAuthenticatedProfile(_ profile: UserProfile) {
        currentUserId = profile.id
        userProfile = profile
        isAuthenticated = true
        isAnonymous = profile.isAnonymous
        noteIdentityChange()
    }

    private func clearLocalAuthState() {
        isAuthenticated = false
        currentUserId = nil
        userProfile = nil
        isAnonymous = false
        noteIdentityChange()
    }

    /// Bumps `identityRevision` only when what Convex sees really changed.
    private func noteIdentityChange() {
        let identity = Identity(userId: currentUserId, isAnonymous: isAnonymous, guestProof: activeGuestProof)
        guard identity != lastIdentity else { return }
        lastIdentity = identity
        identityRevision += 1
    }

    private func loadOrCreateGuestSecret() throws -> String {
        let secret: String
        if let existing = try? keychain.load(forKey: KeychainKeys.guestSecret) {
            secret = existing
        } else {
            secret = UUID().uuidString + "-" + UUID().uuidString
            try keychain.save(secret, forKey: KeychainKeys.guestSecret)
        }
        cachedGuestSecretHash = .some(hash(secret))
        return secret
    }

    /// Read on every Convex request, so the Keychain is read once and the
    /// hash cached. Only a successful read or a missing item is cached.
    var currentGuestSecretHash: String? {
        if let cachedGuestSecretHash {
            return cachedGuestSecretHash
        }
        do {
            let digest = hash(try keychain.load(forKey: KeychainKeys.guestSecret))
            cachedGuestSecretHash = .some(digest)
            return digest
        } catch KeychainHelper.KeychainError.itemNotFound {
            cachedGuestSecretHash = .some(nil)
            return nil
        } catch {
            return nil
        }
    }

    /// Guest proof sent with every Convex request: only while playing as a
    /// guest or while guest progress still waits to merge into an account.
    var activeGuestProof: String? {
        (isAnonymous || hasPendingGuestMerge) ? currentGuestSecretHash : nil
    }

    /// Forgets this device's guest: its secret (which also ends a pending
    /// merge) and its name. The server keeps the guest row.
    private func clearGuestData() {
        try? keychain.delete(forKey: KeychainKeys.guestSecret)
        cachedGuestSecretHash = nil
        guestDisplayName = nil
        guestMergeHasSeatConflict = false
        noteIdentityChange()
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func hash(_ secret: String) -> String {
        let digest = SHA256.hash(data: Data(secret.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func mapAuthError(_ error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription {
            return localized
        }
        return error.localizedDescription
    }
}
