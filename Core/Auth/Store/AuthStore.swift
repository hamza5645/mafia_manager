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
    /// Changes whenever the identity sent to Convex may have changed;
    /// multiplayer subscriptions restart when it does.
    @Published private(set) var identityRevision = 0

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

    private let authService: any AuthServicing
    private let keychain: any KeychainStoring
    private let defaults: UserDefaults

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
        autoRestore: Bool = true
    ) {
        self.authService = authService ?? AuthService()
        self.keychain = keychain ?? KeychainHelper.shared
        self.defaults = defaults
        // The real AuthService talks to ConvexService.shared; give it this
        // device's guest proof. Injected test services leave Convex untouched.
        if authService == nil {
            ConvexService.shared.guestProofProvider = { [weak self] in self?.activeGuestProof }
        }
        if autoRestore {
            Task {
                defer { isRestoringSession = false }
                await restoreSession()
            }
        } else {
            isRestoringSession = false
        }
    }

    func restoreSession() async {
        let account: UserProfile?
        do {
            account = try await authService.currentUser
        } catch {
            // Clerk or Convex is unreachable. Not knowing is not signed out:
            // keep the current identity and every stored credential.
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
                clearLocalAuthState()
            }
        } else {
            clearLocalAuthState()
        }
    }

    /// Called when the app resumes. Only refreshes the account's Convex token;
    /// a failure keeps the current identity, since the next token refresh or
    /// launch can still succeed.
    func ensureValidSession() async {
        guard authenticatedAccountId != nil else { return }
        try? await authService.refreshConvexAuth()
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
        }

        clearLocalAuthState()
        clearGuestData()
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
        guard let guestSecretHash = currentGuestSecretHash else { return }
        do {
            try await authService.mergeGuestIntoAccount(guestSecretHash: guestSecretHash)
            clearGuestData()
        } catch let error as BackendError where error.message == "Guest progress could not be found." {
            // The guest was never created on the server; nothing is left to merge.
            clearGuestData()
        } catch {
            errorMessage = "Guest progress was not saved to your account yet and will retry next launch. \(mapAuthError(error))"
        }
    }

    private func applyAuthenticatedProfile(_ profile: UserProfile) {
        currentUserId = profile.id
        userProfile = profile
        isAuthenticated = true
        isAnonymous = profile.isAnonymous
        identityRevision += 1
    }

    private func clearLocalAuthState() {
        isAuthenticated = false
        currentUserId = nil
        userProfile = nil
        isAnonymous = false
        identityRevision += 1
    }

    private func loadOrCreateGuestSecret() throws -> String {
        if let existing = try? keychain.load(forKey: KeychainKeys.guestSecret) {
            return existing
        }
        let secret = UUID().uuidString + "-" + UUID().uuidString
        try keychain.save(secret, forKey: KeychainKeys.guestSecret)
        return secret
    }

    var currentGuestSecretHash: String? {
        guard let secret = try? keychain.load(forKey: KeychainKeys.guestSecret) else {
            return nil
        }
        return hash(secret)
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
        guestDisplayName = nil
        identityRevision += 1
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
