import Foundation
import SwiftUI
import Combine
import CryptoKit

@MainActor
final class AuthStore: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUserId: UUID?
    @Published var userProfile: UserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isRestoringSession = true
    @Published var isAnonymous = false
    @Published private(set) var hasPendingGuestMerge = false

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

    enum LinkResult {
        case success
        case needsEmailVerification
        case retryableMergeFailure
        case emailAlreadyExists(anonymousUserId: UUID)
        case failure(String)
    }

    enum SignUpStepResult {
        case authenticated
        case needsEmailCode
        case emailAlreadyExists
        case failure
    }

    enum VerificationResult {
        case success
        case verificationFailed
        case retryableMergeFailure
    }

    private let authService: any AuthServicing
    private let keychain: any KeychainStoring
    private let defaults: UserDefaults
    private var authStateTask: Task<Void, Never>?

    private enum KeychainKeys {
        static let guestSecret = "convex_guest_secret"
    }

    private enum DefaultsKeys {
        static let pendingSignUpDisplayName = "pending_signup_display_name"
        static let pendingMergeFromAnonymousId = "pending_merge_from_anonymous_id"
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
        hasPendingGuestMerge = pendingMergeAnonymousUserId != nil
        if autoRestore {
            Task {
                defer { isRestoringSession = false }
                await restoreSession()
            }
        } else {
            isRestoringSession = false
        }
    }

    deinit {
        authStateTask?.cancel()
    }

    private func restoreSession() async {
        if let user = await authService.currentUser {
            applyAuthenticatedProfile(user)
            if hasPendingGuestMerge {
                _ = await retryPendingGuestMerge()
            }
            return
        }

        if let guestName = guestDisplayName,
           let secret = try? keychain.load(forKey: KeychainKeys.guestSecret) {
            do {
                let profile = try await authService.signInAsGuest(
                    displayName: guestName,
                    guestSecretHash: hash(secret)
                )
                applyAuthenticatedProfile(profile)
            } catch {
                clearLocalAuthState()
            }
        } else {
            clearLocalAuthState()
        }
    }

    func ensureValidSession() async {
        await restoreSession()
    }

    func startSignUp(email: String, password: String, displayName: String) async -> SignUpStepResult {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let result = try await authService.startSignUp(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                displayName: trimmedDisplayName
            )
            switch result {
            case .completed(let profile):
                clearPendingVerificationState()
                applyAuthenticatedProfile(profile)
                if !hasPendingGuestMerge {
                    clearGuestSecret()
                }
                return .authenticated
            case .needsEmailCode:
                defaults.set(trimmedDisplayName, forKey: DefaultsKeys.pendingSignUpDisplayName)
                return .needsEmailCode
            }
        } catch AuthError.emailAlreadyInUse {
            clearPendingVerificationState()
            errorMessage = AuthError.emailAlreadyInUse.errorDescription
            return .emailAlreadyExists
        } catch {
            clearPendingVerificationState()
            errorMessage = mapAuthError(error)
            return .failure
        }
    }

    func verifySignUpEmailCode(_ code: String) async -> VerificationResult {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let displayName = defaults.string(forKey: DefaultsKeys.pendingSignUpDisplayName) ?? ""
        do {
            let profile = try await authService.verifySignUpEmailCode(code, displayName: displayName)
            applyAuthenticatedProfile(profile)
            clearPendingVerificationState()

            if hasPendingGuestMerge {
                let merged = await retryPendingGuestMerge()
                if !merged {
                    return .retryableMergeFailure
                }
            }

            clearGuestSecret()
            return .success
        } catch {
            errorMessage = mapAuthError(error)
            return .verificationFailed
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

    private func clearPendingMergeState() {
        defaults.removeObject(forKey: DefaultsKeys.pendingMergeFromAnonymousId)
        hasPendingGuestMerge = false
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let profile = try await authService.signIn(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            applyAuthenticatedProfile(profile)
            if hasPendingGuestMerge {
                _ = await retryPendingGuestMerge()
            } else {
                clearGuestSecret()
            }
        } catch {
            errorMessage = mapAuthError(error)
        }
    }

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
        if !hasPendingGuestMerge {
            clearGuestSecret()
        }
    }

    func startPasswordReset(email: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await authService.startPasswordReset(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
            return true
        } catch {
            errorMessage = mapAuthError(error)
            return false
        }
    }

    func confirmPasswordReset(code: String, newPassword: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let profile = try await authService.confirmPasswordReset(code: code, newPassword: newPassword)
            applyAuthenticatedProfile(profile)
            clearGuestSecret()
            return true
        } catch {
            errorMessage = mapAuthError(error)
            return false
        }
    }

    func updateProfile(displayName: String) async {
        guard let userId = currentUserId else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await authService.updateUserProfile(
                userId: userId,
                displayName: displayName,
                guestSecretHash: isAnonymous ? currentGuestSecretHash : nil
            )
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

    func linkEmailPassword(email: String, password: String, displayName: String) async -> LinkResult {
        guard let anonymousUserId = currentUserId, isAnonymous else {
            return .failure("No guest account to link")
        }

        defaults.set(
            anonymousUserId.uuidString,
            forKey: DefaultsKeys.pendingMergeFromAnonymousId
        )
        hasPendingGuestMerge = true

        // Capture guest credential proof *before* startSignUp — the
        // .authenticated branch of startSignUp clears the keychain.
        guard currentGuestSecretHash != nil else {
            clearPendingMergeState()
            return .failure("Missing guest credentials for merge")
        }

        let step = await startSignUp(email: email, password: password, displayName: displayName)
        switch step {
        case .authenticated:
            if await retryPendingGuestMerge() {
                return .success
            }
            return .retryableMergeFailure
        case .needsEmailCode:
            return .needsEmailVerification
        case .emailAlreadyExists:
            return .emailAlreadyExists(anonymousUserId: anonymousUserId)
        case .failure:
            return .failure(errorMessage ?? "Could not create account")
        }
    }

    func mergeIntoExistingAccount(anonymousUserId: UUID, email: String, password: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Capture guest credential proof before signing into the real account.
        guard let guestSecretHash = currentGuestSecretHash else {
            errorMessage = "Missing guest credentials for merge"
            return false
        }

        defaults.set(
            anonymousUserId.uuidString,
            forKey: DefaultsKeys.pendingMergeFromAnonymousId
        )
        hasPendingGuestMerge = true

        do {
            let profile = try await authService.signIn(email: email, password: password)
            applyAuthenticatedProfile(profile)
            _ = try await authService.mergeAnonymousStats(
                anonymousUserId: anonymousUserId,
                targetUserId: profile.id,
                guestSecretHash: guestSecretHash
            )
            completePendingGuestMerge()
            return true
        } catch {
            errorMessage = mapAuthError(error)
            return false
        }
    }

    @discardableResult
    func retryPendingGuestMerge() async -> Bool {
        guard let anonymousUserId = pendingMergeAnonymousUserId else {
            hasPendingGuestMerge = false
            return true
        }
        guard let targetUserId = currentUserId,
              userProfile?.isAnonymous == false else {
            errorMessage = "Sign in to finish saving guest progress"
            return false
        }
        guard let guestSecretHash = currentGuestSecretHash else {
            errorMessage = "Missing guest credentials for merge"
            return false
        }

        do {
            _ = try await authService.mergeAnonymousStats(
                anonymousUserId: anonymousUserId,
                targetUserId: targetUserId,
                guestSecretHash: guestSecretHash
            )
            completePendingGuestMerge()
            return true
        } catch {
            errorMessage = mapAuthError(error)
            hasPendingGuestMerge = true
            return false
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func applyAuthenticatedProfile(_ profile: UserProfile) {
        currentUserId = profile.id
        userProfile = profile
        isAuthenticated = true
        isAnonymous = profile.isAnonymous
    }

    private func clearLocalAuthState() {
        isAuthenticated = false
        currentUserId = nil
        userProfile = nil
        isAnonymous = false
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

    private var pendingMergeAnonymousUserId: UUID? {
        defaults.string(forKey: DefaultsKeys.pendingMergeFromAnonymousId)
            .flatMap(UUID.init(uuidString:))
    }

    private func completePendingGuestMerge() {
        isAnonymous = false
        userProfile?.isAnonymous = false
        guestDisplayName = nil
        clearGuestSecret()
        clearPendingMergeState()
    }

    private func clearGuestSecret() {
        try? keychain.delete(forKey: KeychainKeys.guestSecret)
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
