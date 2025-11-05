import Foundation
import SwiftUI
import Combine
import Auth

@MainActor
final class AuthStore: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUserId: UUID?
    @Published var userProfile: UserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?

    // WORKAROUND: Store tokens manually since SDK doesn't persist session
    @Published var accessToken: String? {
        didSet {
            if let token = accessToken {
                UserDefaults.standard.set(token, forKey: "auth_access_token")
            } else {
                UserDefaults.standard.removeObject(forKey: "auth_access_token")
            }
        }
    }
    @Published var refreshToken: String? {
        didSet {
            if let token = refreshToken {
                UserDefaults.standard.set(token, forKey: "auth_refresh_token")
            } else {
                UserDefaults.standard.removeObject(forKey: "auth_refresh_token")
            }
        }
    }

    private let authService = AuthService()
    private let databaseService = DatabaseService()
    private var authStateTask: Task<Void, Never>?

    private enum AuthOperation {
        case signIn
        case signUp
        case resetPassword
    }

    init() {
        // Restore tokens from UserDefaults
        self.accessToken = UserDefaults.standard.string(forKey: "auth_access_token")
        self.refreshToken = UserDefaults.standard.string(forKey: "auth_refresh_token")

        Task {
            // Try to restore session if we have tokens
            if let accessToken = self.accessToken,
               let refreshToken = self.refreshToken {
                do {
                    try await authService.restoreSession(accessToken: accessToken, refreshToken: refreshToken)
                } catch {
                    // If session restoration fails, clear tokens
                    self.accessToken = nil
                    self.refreshToken = nil
                }
            }

            await checkAuthState()
            setupAuthStateListener()
        }
    }

    deinit {
        authStateTask?.cancel()
    }

    // MARK: - Authentication State

    private func checkAuthState() async {
        do {
            if let user = await authService.currentUser {
                currentUserId = user.id
                isAuthenticated = true
                await loadUserProfile()
            } else {
                isAuthenticated = false
                currentUserId = nil
                userProfile = nil
            }
        }
    }

    private func setupAuthStateListener() {
        authStateTask = authService.onAuthStateChange { [weak self] event, session in
            Task { @MainActor in
                guard let self = self else { return }

                switch event {
                case .signedIn:
                    if let user = session?.user {
                        self.currentUserId = user.id
                        self.isAuthenticated = true
                        await self.loadUserProfile()
                    }
                case .signedOut:
                    self.isAuthenticated = false
                    self.currentUserId = nil
                    self.userProfile = nil
                    self.accessToken = nil
                    self.refreshToken = nil
                case .userDeleted:
                    self.isAuthenticated = false
                    self.currentUserId = nil
                    self.userProfile = nil
                    self.accessToken = nil
                    self.refreshToken = nil
                default:
                    break
                }
            }
        }
    }

    private func loadUserProfile() async {
        guard let userId = currentUserId else { return }

        do {
            userProfile = try await authService.getUserProfile(userId: userId)
        } catch {
            // Silently fail - profile will be loaded on next auth state change
            errorMessage = "Could not load user profile"
        }
    }

    // MARK: - Sign Up

    func signUp(email: String, password: String, displayName: String) async -> Bool {
        isLoading = true
        errorMessage = nil

        let sanitizedEmail = sanitizeEmail(email)
        let sanitizedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            _ = try await authService.signUp(email: sanitizedEmail, password: sanitizedPassword, displayName: trimmedDisplayName)

            // With the auto-confirm trigger, the user should be immediately signed in
            // If not, attempt sign-in
            if await authService.currentSession == nil {
                _ = try await authService.signIn(email: sanitizedEmail, password: sanitizedPassword)
            }

            // Signup + auto sign-in successful - auth state listener updates isAuthenticated
            isLoading = false
            return true
        } catch let error as NSError {
            errorMessage = mapAuthError(error, operation: .signUp)
            isLoading = false
            return false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }

    // MARK: - Sign In

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let sanitizedEmail = sanitizeEmail(email)
            let sanitizedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

            let session = try await authService.signIn(email: sanitizedEmail, password: sanitizedPassword)

            // WORKAROUND: Manually store tokens since SDK doesn't persist properly
            self.accessToken = session.accessToken
            self.refreshToken = session.refreshToken

            // Auth state listener will handle updating isAuthenticated
        } catch let error as NSError {
            errorMessage = mapAuthError(error, operation: .signIn)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Sign Out

    func signOut() async {
        isLoading = true
        errorMessage = nil

        do {
            try await authService.signOut()
            // Auth state listener will handle updating isAuthenticated
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Password Reset

    func resetPassword(email: String) async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            let sanitizedEmail = sanitizeEmail(email)
            try await authService.resetPassword(email: sanitizedEmail)
            isLoading = false
            return true
        } catch let error as NSError {
            errorMessage = mapAuthError(error, operation: .resetPassword)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        return false
    }

    // MARK: - Profile Management

    func updateProfile(displayName: String) async {
        guard let userId = currentUserId else { return }

        isLoading = true
        errorMessage = nil

        do {
            try await authService.updateUserProfile(userId: userId, displayName: displayName)
            await loadUserProfile()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Helper Methods

    func clearError() {
        errorMessage = nil
    }

    private func sanitizeEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func mapAuthError(_ error: NSError, operation: AuthOperation) -> String {
        if error.domain == NSURLErrorDomain {
            return AuthError.networkError.errorDescription ?? "Network error. Please try again."
        }

        if let message = extractSupabaseMessage(from: error) {
            let normalized = message.lowercased()

            if normalized.contains("already registered") || normalized.contains("already been registered") {
                return AuthError.emailAlreadyInUse.errorDescription ?? message
            }

            if normalized.contains("email not confirmed") || normalized.contains("verify your email") {
                return "Email confirmation is enabled in Supabase. Disable it in Authentication → Providers → Email settings."
            }

            if normalized.contains("invalid login credentials") {
                return AuthError.invalidCredentials.errorDescription ?? message
            }

            if normalized.contains("password should be at least") || normalized.contains("weak password") {
                return AuthError.weakPassword.errorDescription ?? message
            }

            if normalized.contains("user not found") {
                return AuthError.userNotFound.errorDescription ?? message
            }

            return message
        }

        if error.domain == "GoTrueClientError" && error.code == 400 {
            switch operation {
            case .signIn:
                return AuthError.invalidCredentials.errorDescription ?? error.localizedDescription
            case .signUp:
                return AuthError.unknown.errorDescription ?? error.localizedDescription
            case .resetPassword:
                return "We couldn't find an account with that email address."
            }
        }

        if operation == .signIn {
            return AuthError.invalidCredentials.errorDescription ?? error.localizedDescription
        }

        return error.localizedDescription
    }

    private func extractSupabaseMessage(from error: NSError) -> String? {
        if let message = error.userInfo["error_description"] as? String, !message.isEmpty {
            return message
        }

        if let dict = error.userInfo["com.supabase.auth"] as? [String: Any],
           let message = dict["msg"] as? String,
           !message.isEmpty {
            return message
        }

        if let message = error.userInfo[NSLocalizedDescriptionKey] as? String, !message.isEmpty {
            return message
        }

        return nil
    }
}
