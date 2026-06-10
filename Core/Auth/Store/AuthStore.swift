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

    var guestDisplayName: String? {
        get { UserDefaults.standard.string(forKey: "guest_display_name") }
        set {
            if let name = newValue {
                UserDefaults.standard.set(name, forKey: "guest_display_name")
            } else {
                UserDefaults.standard.removeObject(forKey: "guest_display_name")
            }
        }
    }

    enum LinkResult {
        case success
        case needsEmailVerification
        case emailAlreadyExists(anonymousUserId: UUID)
        case failure(String)
    }

    enum SignUpStepResult {
        case authenticated
        case needsEmailCode
        case failure
    }

    private let authService = AuthService()
    private let keychain = KeychainHelper.shared
    private var authStateTask: Task<Void, Never>?

    private enum KeychainKeys {
        static let guestSecret = "convex_guest_secret"
    }

    private enum DefaultsKeys {
        static let pendingSignUpDisplayName = "pending_signup_display_name"
        static let pendingMergeFromAnonymousId = "pending_merge_from_anonymous_id"
    }

    init() {
        Task {
            defer { isRestoringSession = false }
            await restoreSession()
        }
    }

    deinit {
        authStateTask?.cancel()
    }

    private func restoreSession() async {
        if let user = await authService.currentUser {
            applyAuthenticatedProfile(user)
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
                clearPendingSignUpState()
                applyAuthenticatedProfile(profile)
                clearGuestSecret()
                return .authenticated
            case .needsEmailCode:
                UserDefaults.standard.set(trimmedDisplayName, forKey: DefaultsKeys.pendingSignUpDisplayName)
                return .needsEmailCode
            }
        } catch {
            clearPendingSignUpState()
            errorMessage = mapAuthError(error)
            return .failure
        }
    }

    func verifySignUpEmailCode(_ code: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let displayName = UserDefaults.standard.string(forKey: DefaultsKeys.pendingSignUpDisplayName) ?? ""
        let mergeAnonymousId = UserDefaults.standard.string(forKey: DefaultsKeys.pendingMergeFromAnonymousId)
            .flatMap(UUID.init(uuidString:))
        // Capture guest credential proof *before* clearing the keychain — the
        // server-side merge now requires the original guest's secret hash.
        let guestSecretHash = currentGuestSecretHash()

        do {
            let profile = try await authService.verifySignUpEmailCode(code, displayName: displayName)
            applyAuthenticatedProfile(profile)

            if let anonymousId = mergeAnonymousId,
               anonymousId != profile.id,
               let guestSecretHash {
                _ = try? await authService.mergeAnonymousStats(
                    anonymousUserId: anonymousId,
                    targetUserId: profile.id,
                    guestSecretHash: guestSecretHash
                )
                isAnonymous = false
                userProfile?.isAnonymous = false
                guestDisplayName = nil
            }

            clearGuestSecret()
            clearPendingSignUpState()
            return true
        } catch {
            errorMessage = mapAuthError(error)
            return false
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
        clearPendingSignUpState()
    }

    private func clearPendingSignUpState() {
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.pendingSignUpDisplayName)
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.pendingMergeFromAnonymousId)
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
            clearGuestSecret()
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
        clearGuestSecret()
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
            try await authService.updateUserProfile(userId: userId, displayName: displayName)
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

        UserDefaults.standard.set(
            anonymousUserId.uuidString,
            forKey: DefaultsKeys.pendingMergeFromAnonymousId
        )

        // Capture guest credential proof *before* startSignUp — the
        // .authenticated branch of startSignUp clears the keychain.
        guard let guestSecretHash = currentGuestSecretHash() else {
            clearPendingSignUpState()
            return .failure("Missing guest credentials for merge")
        }

        let step = await startSignUp(email: email, password: password, displayName: displayName)
        switch step {
        case .authenticated:
            guard let targetUserId = currentUserId else {
                return .failure(errorMessage ?? "Could not create account")
            }
            do {
                _ = try await authService.mergeAnonymousStats(
                    anonymousUserId: anonymousUserId,
                    targetUserId: targetUserId,
                    guestSecretHash: guestSecretHash
                )
                isAnonymous = false
                userProfile?.isAnonymous = false
                guestDisplayName = nil
                clearGuestSecret()
                clearPendingSignUpState()
                return .success
            } catch {
                clearPendingSignUpState()
                return .failure(mapAuthError(error))
            }
        case .needsEmailCode:
            return .needsEmailVerification
        case .failure:
            clearPendingSignUpState()
            return .failure(errorMessage ?? "Could not create account")
        }
    }

    func mergeIntoExistingAccount(anonymousUserId: UUID, email: String, password: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Capture guest credential proof before signing into the real account.
        guard let guestSecretHash = currentGuestSecretHash() else {
            errorMessage = "Missing guest credentials for merge"
            return false
        }

        do {
            let profile = try await authService.signIn(email: email, password: password)
            _ = try await authService.mergeAnonymousStats(
                anonymousUserId: anonymousUserId,
                targetUserId: profile.id,
                guestSecretHash: guestSecretHash
            )
            applyAuthenticatedProfile(profile)
            clearGuestSecret()
            guestDisplayName = nil
            return true
        } catch {
            errorMessage = mapAuthError(error)
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

    private func currentGuestSecretHash() -> String? {
        guard let secret = try? keychain.load(forKey: KeychainKeys.guestSecret) else {
            return nil
        }
        return hash(secret)
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

