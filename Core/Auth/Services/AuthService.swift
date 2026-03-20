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
        // The database trigger will automatically create the profile and confirm email
        let response = try await supabase.auth.signUp(
            email: email,
            password: password,
            data: ["display_name": .string(displayName)]
        )

        return response.user
    }

    // MARK: - Anonymous Sign In

    func signInAnonymously() async throws -> Session {
        let session = try await supabase.auth.signInAnonymously()

        // WORKAROUND: Manually set the session to ensure persistence
        try await supabase.auth.setSession(accessToken: session.accessToken, refreshToken: session.refreshToken)

        return session
    }

    // MARK: - Link Identity (Upgrade Anonymous to Permanent)

    func linkEmailIdentity(email: String, password: String, displayName: String) async throws {
        // Update the anonymous user with email and password
        // This preserves the user_id (UUID stays the same)
        try await supabase.auth.update(
            user: UserAttributes(
                email: email,
                password: password,
                data: ["display_name": .string(displayName)]
            )
        )
    }

    // MARK: - Sign In

    func signIn(email: String, password: String) async throws -> Session {
        let session = try await supabase.auth.signIn(
            email: email,
            password: password
        )

        // WORKAROUND: Manually set the session to ensure persistence
        // The Supabase Swift SDK has a known issue where sessions aren't persisted automatically
        try await supabase.auth.setSession(accessToken: session.accessToken, refreshToken: session.refreshToken)

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

    func restoreSession(accessToken: String, refreshToken: String) async throws {
        try await supabase.auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
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

    /// HAMZA-FIX: Added retry logic to handle Supabase session propagation timing issues
    /// After login/signup, REST API calls may fail with 406 if the session isn't fully propagated
    func getUserProfile(userId: UUID) async throws -> UserProfile {
        let maxRetries = 3
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                // Small delay before retry to allow session propagation
                if attempt > 0 {
                    try await Task.sleep(nanoseconds: UInt64(300_000_000 * attempt)) // 300ms * attempt
                }

                let response: UserProfile = try await supabase
                    .from("profiles")
                    .select()
                    .eq("id", value: userId.uuidString.lowercased())
                    .single()
                    .execute()
                    .value

                return response
            } catch {
                lastError = error
                // Continue to next retry
            }
        }

        // All retries failed, throw the last error
        throw lastError ?? NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch profile after \(maxRetries) attempts"])
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

        try await supabase
            .from("profiles")
            .update(updateData)
            .eq("id", value: userId.uuidString.lowercased())
            .execute()
    }

    func updateGuestProfile(userId: UUID, displayName: String, isAnonymous: Bool) async throws {
        struct UpdateData: Encodable {
            let displayName: String
            let isAnonymous: Bool
            let updatedAt: Date

            enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
                case isAnonymous = "is_anonymous"
                case updatedAt = "updated_at"
            }
        }

        let updateData = UpdateData(displayName: displayName, isAnonymous: isAnonymous, updatedAt: Date())

        try await supabase
            .from("profiles")
            .update(updateData)
            .eq("id", value: userId.uuidString.lowercased())
            .execute()
    }

    // MARK: - Merge Anonymous Stats

    struct MergeStatsResult: Decodable {
        let success: Bool
        let error: String?
        let mergedCount: Int?
        let transferredCount: Int?

        enum CodingKeys: String, CodingKey {
            case success
            case error
            case mergedCount = "merged_count"
            case transferredCount = "transferred_count"
        }
    }

    func mergeAnonymousStats(anonymousUserId: UUID, targetUserId: UUID) async throws -> MergeStatsResult {
        let result: MergeStatsResult = try await supabase
            .rpc("merge_anonymous_stats", params: [
                "p_anonymous_user_id": anonymousUserId.uuidString.lowercased(),
                "p_target_user_id": targetUserId.uuidString.lowercased()
            ])
            .execute()
            .value

        return result
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
