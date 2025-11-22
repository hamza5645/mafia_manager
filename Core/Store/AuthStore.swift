import Foundation
import SwiftUI
import Auth

@MainActor
final class AuthStore: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUserId: UUID?
    @Published var userProfile: UserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isRestoringSession = true

    // SECURITY FIX: Tokens now stored securely in Keychain instead of UserDefaults
    @Published var accessToken: String?
    @Published var refreshToken: String?

    private let authService = AuthService()
    private let databaseService = DatabaseService()
    private let keychain = KeychainHelper.shared
    private var authStateTask: Task<Void, Never>?

    // SECURITY FIX: Rate limiting to prevent brute force attacks
    private struct RateLimitEntry {
        var attempts: Int
        var lastAttempt: Date
    }
    private var rateLimits: [String: RateLimitEntry] = [:]
    private let maxAttempts = 5
    private let cooldownSeconds: TimeInterval = 30

    private enum KeychainKeys {
        static let accessToken = "auth_access_token"
        static let refreshToken = "auth_refresh_token"
    }

    private enum AuthOperation {
        case signIn
        case signUp
        case resetPassword
    }

    init() {
        // SECURITY FIX: Migrate from UserDefaults to Keychain if needed
        migrateTokensFromUserDefaultsIfNeeded()

        // Restore tokens from Keychain
        self.accessToken = loadAccessToken()
        self.refreshToken = loadRefreshToken()

        Task {
            defer { isRestoringSession = false }

            // Try to restore session if we have tokens
            if let accessToken = self.accessToken,
               let refreshToken = self.refreshToken {
                do {
                    try await authService.restoreSession(accessToken: accessToken, refreshToken: refreshToken)
                } catch {
                    // If session restoration fails, clear tokens
                    clearTokens()
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
                    self.clearTokens()
                case .userDeleted:
                    self.isAuthenticated = false
                    self.currentUserId = nil
                    self.userProfile = nil
                    self.clearTokens()
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

    // MARK: - Secure Token Management

    private func saveAccessToken(_ token: String) {
        try? keychain.save(token, forKey: KeychainKeys.accessToken)
        self.accessToken = token
    }

    private func saveRefreshToken(_ token: String) {
        try? keychain.save(token, forKey: KeychainKeys.refreshToken)
        self.refreshToken = token
    }

    private func loadAccessToken() -> String? {
        try? keychain.load(forKey: KeychainKeys.accessToken)
    }

    private func loadRefreshToken() -> String? {
        try? keychain.load(forKey: KeychainKeys.refreshToken)
    }

    private func clearTokens() {
        try? keychain.delete(forKey: KeychainKeys.accessToken)
        try? keychain.delete(forKey: KeychainKeys.refreshToken)
        self.accessToken = nil
        self.refreshToken = nil
    }

    /// Migrate tokens from UserDefaults to Keychain for existing users
    private func migrateTokensFromUserDefaultsIfNeeded() {
        let defaults = UserDefaults.standard

        // Check if tokens exist in UserDefaults
        if let accessToken = defaults.string(forKey: KeychainKeys.accessToken),
           !keychain.exists(forKey: KeychainKeys.accessToken) {
            try? keychain.save(accessToken, forKey: KeychainKeys.accessToken)
            defaults.removeObject(forKey: KeychainKeys.accessToken)
        }

        if let refreshToken = defaults.string(forKey: KeychainKeys.refreshToken),
           !keychain.exists(forKey: KeychainKeys.refreshToken) {
            try? keychain.save(refreshToken, forKey: KeychainKeys.refreshToken)
            defaults.removeObject(forKey: KeychainKeys.refreshToken)
        }
    }

    // MARK: - Rate Limiting

    /// Check if email is rate limited
    private func isRateLimited(email: String) -> Bool {
        guard let entry = rateLimits[email.lowercased()] else {
            return false
        }

        let timeSinceLastAttempt = Date().timeIntervalSince(entry.lastAttempt)

        // If cooldown has passed, reset the entry
        if timeSinceLastAttempt >= cooldownSeconds {
            rateLimits.removeValue(forKey: email.lowercased())
            return false
        }

        // Check if max attempts reached
        return entry.attempts >= maxAttempts
    }

    /// Record a failed authentication attempt
    private func recordFailedAttempt(email: String) {
        let key = email.lowercased()
        if var entry = rateLimits[key] {
            entry.attempts += 1
            entry.lastAttempt = Date()
            rateLimits[key] = entry
        } else {
            rateLimits[key] = RateLimitEntry(attempts: 1, lastAttempt: Date())
        }
    }

    /// Reset rate limit for successful authentication
    private func resetRateLimit(email: String) {
        rateLimits.removeValue(forKey: email.lowercased())
    }

    // MARK: - Sign Up

    func signUp(email: String, password: String, displayName: String) async -> Bool {
        isLoading = true
        errorMessage = nil

        // SECURITY FIX: Check rate limiting
        if isRateLimited(email: email) {
            errorMessage = "Too many attempts. Please wait 30 seconds before trying again."
            isLoading = false
            return false
        }

        // SECURITY FIX: Validate inputs
        let validEmail: String
        switch InputValidator.validateEmail(email) {
        case .success(let email):
            validEmail = email
        case .failure(let error):
            errorMessage = "Invalid email: \(error.localizedDescription)"
            isLoading = false
            return false
        }

        let validPassword: String
        switch InputValidator.validatePassword(password) {
        case .success(let pwd):
            validPassword = pwd
        case .failure(let error):
            errorMessage = "Invalid password: \(error.localizedDescription)"
            isLoading = false
            return false
        }

        let validDisplayName: String
        switch InputValidator.validateDisplayName(displayName) {
        case .success(let name):
            validDisplayName = name
        case .failure(let error):
            errorMessage = "Invalid display name: \(error.localizedDescription)"
            isLoading = false
            return false
        }

        do {
            _ = try await authService.signUp(email: validEmail, password: validPassword, displayName: validDisplayName)

            // With the auto-confirm trigger, the user should be immediately signed in
            // If not, attempt sign-in
            if await authService.currentSession == nil {
                _ = try await authService.signIn(email: validEmail, password: validPassword)
            }

            // Signup + auto sign-in successful - auth state listener updates isAuthenticated
            resetRateLimit(email: validEmail)
            isLoading = false
            return true
        } catch let error as NSError {
            recordFailedAttempt(email: email)
            errorMessage = mapAuthError(error, operation: .signUp)
            isLoading = false
            return false
        } catch {
            recordFailedAttempt(email: email)
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }

    // MARK: - Sign In

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil

        // SECURITY FIX: Check rate limiting
        if isRateLimited(email: email) {
            errorMessage = "Too many attempts. Please wait 30 seconds before trying again."
            isLoading = false
            return
        }

        // SECURITY FIX: Validate inputs
        let validEmail: String
        switch InputValidator.validateEmail(email) {
        case .success(let email):
            validEmail = email
        case .failure(let error):
            errorMessage = "Invalid email: \(error.localizedDescription)"
            isLoading = false
            return
        }

        let validPassword: String
        switch InputValidator.validatePassword(password) {
        case .success(let pwd):
            validPassword = pwd
        case .failure(let error):
            errorMessage = "Invalid password: \(error.localizedDescription)"
            isLoading = false
            return
        }

        do {
            let session = try await authService.signIn(email: validEmail, password: validPassword)

            // SECURITY FIX: Store tokens securely in Keychain
            saveAccessToken(session.accessToken)
            saveRefreshToken(session.refreshToken)

            // Auth successful - reset rate limit
            resetRateLimit(email: validEmail)

            // Auth state listener will handle updating isAuthenticated
        } catch let error as NSError {
            recordFailedAttempt(email: email)
            errorMessage = mapAuthError(error, operation: .signIn)
        } catch {
            recordFailedAttempt(email: email)
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
