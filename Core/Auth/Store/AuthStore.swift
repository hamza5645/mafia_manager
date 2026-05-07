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
        case emailAlreadyExists(anonymousUserId: UUID)
        case failure(String)
    }

    private let authService = AuthService()
    private let keychain = KeychainHelper.shared
    private var authStateTask: Task<Void, Never>?

    private enum KeychainKeys {
        static let guestSecret = "convex_guest_secret"
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

    func signUp(email: String, password: String, displayName: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let profile = try await authService.signUp(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            applyAuthenticatedProfile(profile)
            clearGuestSecret()
            return true
        } catch {
            errorMessage = mapAuthError(error)
            return false
        }
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

    func resetPassword(email: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await authService.resetPassword(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
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

        let signedUp = await signUp(email: email, password: password, displayName: displayName)
        guard signedUp, let targetUserId = currentUserId else {
            return .failure(errorMessage ?? "Could not create account")
        }

        do {
            _ = try await authService.mergeAnonymousStats(
                anonymousUserId: anonymousUserId,
                targetUserId: targetUserId
            )
            isAnonymous = false
            userProfile?.isAnonymous = false
            guestDisplayName = nil
            clearGuestSecret()
            return .success
        } catch {
            return .failure(mapAuthError(error))
        }
    }

    func mergeIntoExistingAccount(anonymousUserId: UUID, email: String, password: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let profile = try await authService.signIn(email: email, password: password)
            _ = try await authService.mergeAnonymousStats(
                anonymousUserId: anonymousUserId,
                targetUserId: profile.id
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

