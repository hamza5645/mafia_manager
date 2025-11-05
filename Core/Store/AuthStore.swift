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

    private let authService = AuthService()
    private let databaseService = DatabaseService()
    private var authStateTask: Task<Void, Never>?

    init() {
        Task {
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
                case .userDeleted:
                    self.isAuthenticated = false
                    self.currentUserId = nil
                    self.userProfile = nil
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
            print("Error loading user profile: \(error)")
        }
    }

    // MARK: - Sign Up

    func signUp(email: String, password: String, displayName: String) async {
        isLoading = true
        errorMessage = nil

        do {
            _ = try await authService.signUp(email: email, password: password, displayName: displayName)
            // Auth state listener will handle updating isAuthenticated
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Sign In

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil

        do {
            _ = try await authService.signIn(email: email, password: password)
            // Auth state listener will handle updating isAuthenticated
        } catch {
            errorMessage = "Invalid email or password"
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

    func resetPassword(email: String) async {
        isLoading = true
        errorMessage = nil

        do {
            try await authService.resetPassword(email: email)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
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
}
