import Foundation
import Supabase
import Auth

@MainActor
final class AuthService {
    private let supabase = SupabaseService.shared.client

    // MARK: - Authentication State

    var currentUser: User? {
        get async {
            try? await supabase.auth.session.user
        }
    }

    var currentSession: Session? {
        get async {
            try? await supabase.auth.session
        }
    }

    // MARK: - Sign Up

    func signUp(email: String, password: String, displayName: String) async throws -> User {
        // Pass display_name in user metadata
        // The database trigger will automatically create the profile
        let response = try await supabase.auth.signUp(
            email: email,
            password: password,
            data: ["display_name": .string(displayName)]
        )

        let user = response.user

        // Wait a brief moment for the trigger to complete
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        return user
    }

    // MARK: - Sign In

    func signIn(email: String, password: String) async throws -> Session {
        let session = try await supabase.auth.signIn(
            email: email,
            password: password
        )

        return session
    }

    // MARK: - Sign Out

    func signOut() async throws {
        try await supabase.auth.signOut()
    }

    // MARK: - Password Reset

    func resetPassword(email: String) async throws {
        try await supabase.auth.resetPasswordForEmail(email)
    }

    // MARK: - Session Management

    func getSession() async throws -> Session {
        try await supabase.auth.session
    }

    // Listen to auth state changes
    func onAuthStateChange(_ handler: @escaping (AuthChangeEvent, Session?) -> Void) -> Task<Void, Never> {
        Task {
            for await state in supabase.auth.authStateChanges {
                handler(state.event, state.session)
            }
        }
    }

    // MARK: - Profile Management

    // Note: Profile creation is now handled by a database trigger
    // when a new user signs up. See supabase/alternative_trigger_approach.sql

    func getUserProfile(userId: UUID) async throws -> UserProfile {
        let response: UserProfile = try await supabase.database
            .from("profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .single()
            .execute()
            .value

        return response
    }

    func updateUserProfile(userId: UUID, displayName: String) async throws {
        struct UpdateData: Encodable {
            let displayName: String
            let updatedAt: Date

            enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
                case updatedAt = "updated_at"
            }
        }

        let updateData = UpdateData(displayName: displayName, updatedAt: Date())

        try await supabase.database
            .from("profiles")
            .update(updateData)
            .eq("id", value: userId.uuidString)
            .execute()
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case userNotFound
    case invalidCredentials
    case emailAlreadyInUse
    case weakPassword
    case networkError
    case unknown

    var errorDescription: String? {
        switch self {
        case .userNotFound:
            return "User not found"
        case .invalidCredentials:
            return "Invalid email or password"
        case .emailAlreadyInUse:
            return "Email already in use"
        case .weakPassword:
            return "Password is too weak. Must be at least 6 characters"
        case .networkError:
            return "Network error. Please check your connection"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}
