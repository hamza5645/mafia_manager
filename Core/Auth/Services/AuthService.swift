import Foundation
import ClerkKit
import ConvexMobile

@MainActor
final class AuthService {
    private let convex = ConvexService.shared

    var currentUser: UserProfile? {
        get async {
            if ConvexConfig.hasConfiguredClerkKey, Clerk.shared.user != nil {
                return try? await ensureClerkUser()
            }
            if ConvexConfig.hasConfiguredClerkKey {
                try? await Clerk.shared.refreshClient()
                if Clerk.shared.user != nil {
                    return try? await ensureClerkUser()
                }
            }
            return nil
        }
    }

    func signUp(email: String, password: String, displayName: String) async throws -> UserProfile {
        guard ConvexConfig.hasConfiguredClerkKey else {
            throw AuthError.providerNotConfigured
        }

        let signUp = try await Clerk.shared.auth.signUp(
            emailAddress: email,
            password: password,
            firstName: displayName
        )

        if let sessionId = signUp.createdSessionId {
            try await Clerk.shared.auth.setActive(sessionId: sessionId)
            return try await ensureClerkUser(displayName: displayName)
        }

        throw AuthError.verificationRequired
    }

    func signIn(email: String, password: String) async throws -> UserProfile {
        guard ConvexConfig.hasConfiguredClerkKey else {
            throw AuthError.providerNotConfigured
        }

        let signIn = try await Clerk.shared.auth.signInWithPassword(
            identifier: email,
            password: password
        )

        if let sessionId = signIn.createdSessionId {
            try await Clerk.shared.auth.setActive(sessionId: sessionId)
        }

        return try await ensureClerkUser()
    }

    func signOut() async throws {
        if ConvexConfig.hasConfiguredClerkKey {
            try await Clerk.shared.auth.signOut()
        }
        await convex.logout()
    }

    func resetPassword(email: String) async throws {
        guard ConvexConfig.hasConfiguredClerkKey else {
            throw AuthError.providerNotConfigured
        }

        _ = try await Clerk.shared.auth.signIn(email)
        guard let signIn = Clerk.shared.auth.currentSignIn else {
            throw AuthError.unknown
        }
        _ = try await signIn.sendResetPasswordEmailCode()
    }

    func getUserProfile(userId: UUID) async throws -> UserProfile {
        let profile: UserProfile? = try await convex.query(
            "users:getUserProfile",
            with: ["user_id": userId.uuidString.lowercased()],
            as: UserProfile?.self
        )

        guard let profile else {
            throw AuthError.userNotFound
        }

        return profile
    }

    func updateUserProfile(userId: UUID, displayName: String) async throws {
        let _: UserProfile = try await convex.mutation(
            "users:updateProfile",
            with: [
                "user_id": userId.uuidString.lowercased(),
                "display_name": displayName,
            ]
        )
    }

    func updateGuestProfile(userId: UUID, displayName: String, isAnonymous: Bool) async throws {
        let _: UserProfile = try await convex.mutation(
            "users:updateProfile",
            with: [
                "user_id": userId.uuidString.lowercased(),
                "display_name": displayName,
                "is_anonymous": isAnonymous,
            ]
        )
    }

    func signInAsGuest(displayName: String, guestSecretHash: String) async throws -> UserProfile {
        try await convex.mutation(
            "users:createOrRestoreGuest",
            with: [
                "display_name": displayName,
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    func mergeAnonymousStats(anonymousUserId: UUID, targetUserId: UUID) async throws -> MergeStatsResult {
        try await convex.mutation(
            "users:mergeGuestIntoAccount",
            with: [
                "guest_user_id": anonymousUserId.uuidString.lowercased(),
                "target_user_id": targetUserId.uuidString.lowercased(),
            ]
        )
    }

    @discardableResult
    func ensureClerkUser(displayName: String? = nil) async throws -> UserProfile {
        try await convex.mutation(
            "users:ensureUser",
            with: [
                "display_name": displayName,
            ]
        )
    }
}

struct MergeStatsResult: Decodable, Sendable {
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

enum AuthError: LocalizedError {
    case userNotFound
    case invalidCredentials
    case emailAlreadyInUse
    case weakPassword
    case networkError
    case providerNotConfigured
    case verificationRequired
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
            return "Password is too weak"
        case .networkError:
            return "Network error. Please check your connection"
        case .providerNotConfigured:
            return "Clerk is not configured yet. Add your Clerk publishable key in ConvexConfig.swift."
        case .verificationRequired:
            return "Check your email to finish account verification."
        case .unknown:
            return "An unknown error occurred"
        }
    }
}
