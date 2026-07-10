import Foundation
import ClerkKit
import ConvexMobile

@MainActor
protocol AuthServicing: AnyObject {
    var currentUser: UserProfile? { get async }
    func startSignUp(email: String, password: String, displayName: String) async throws -> AuthService.SignUpStartResult
    func verifySignUpEmailCode(_ code: String, displayName: String) async throws -> UserProfile
    func resendSignUpEmailCode() async throws
    func signIn(email: String, password: String) async throws -> UserProfile
    func signOut() async throws
    func startPasswordReset(email: String) async throws
    func confirmPasswordReset(code: String, newPassword: String) async throws -> UserProfile
    func updateUserProfile(userId: UUID, displayName: String, guestSecretHash: String?) async throws
    func signInAsGuest(displayName: String, guestSecretHash: String) async throws -> UserProfile
    func mergeAnonymousStats(anonymousUserId: UUID, targetUserId: UUID, guestSecretHash: String) async throws -> MergeStatsResult
}

@MainActor
final class AuthService {
    private let convex = ConvexService.shared

    var currentUser: UserProfile? {
        get async {
            if ConvexConfig.hasConfiguredClerkKey, Clerk.shared.user != nil {
                return try? await ensureClerkUser()
            }
            if ConvexConfig.hasConfiguredClerkKey {
                _ = try? await Clerk.shared.refreshClient()
                if Clerk.shared.user != nil {
                    return try? await ensureClerkUser()
                }
            }
            return nil
        }
    }

    enum SignUpStartResult {
        case completed(UserProfile)
        case needsEmailCode
    }

    func startSignUp(email: String, password: String, displayName: String) async throws -> SignUpStartResult {
        guard ConvexConfig.hasConfiguredClerkKey else {
            throw AuthError.providerNotConfigured
        }

        let signUp: SignUp
        do {
            signUp = try await Clerk.shared.auth.signUp(
                emailAddress: email,
                password: password,
                firstName: displayName
            )
        } catch {
            throw Self.mapSignUpError(error)
        }

        if signUp.status == .complete {
            if let sessionId = signUp.createdSessionId {
                try await Clerk.shared.auth.setActive(sessionId: sessionId)
            }
            try await Self.synchronizeCompletedSignUp(
                refreshClient: { _ = try? await Clerk.shared.refreshClient() },
                refreshConvexAuth: { try await self.convex.refreshAuthFromClerk() }
            )
            return .completed(try await ensureClerkUser(displayName: displayName))
        }

        try await signUp.sendEmailCode()
        return .needsEmailCode
    }

    func verifySignUpEmailCode(_ code: String, displayName: String) async throws -> UserProfile {
        guard ConvexConfig.hasConfiguredClerkKey else {
            throw AuthError.providerNotConfigured
        }
        guard let signUp = Clerk.shared.auth.currentSignUp else {
            throw AuthError.signUpExpired
        }

        let updated = try await signUp.verifyEmailCode(code)
        guard updated.status == .complete else {
            throw AuthError.unknown
        }

        if let sessionId = updated.createdSessionId {
            try await Clerk.shared.auth.setActive(sessionId: sessionId)
            // setActive() doesn't synchronously flip Clerk.session.status to
            // .active; refreshClient() does. Best-effort because the dev
            // instance can be flaky and the bounded poll in
            // refreshAuthFromClerk is the safety net that actually waits.
            _ = try? await Clerk.shared.refreshClient()
        }

        // Force the Convex FFI auth callback install on this task before the
        // next mutation. The patched ClerkConvexAuthProvider handles
        // `.signUpCompleted` on its own session-sync Task, but we can't
        // await that task from here, so the mutation would race it.
        try await convex.refreshAuthFromClerk()
        return try await ensureClerkUser(displayName: displayName)
    }

    func resendSignUpEmailCode() async throws {
        guard ConvexConfig.hasConfiguredClerkKey else {
            throw AuthError.providerNotConfigured
        }
        guard let signUp = Clerk.shared.auth.currentSignUp else {
            throw AuthError.signUpExpired
        }
        try await signUp.sendEmailCode()
    }

    func signIn(email: String, password: String) async throws -> UserProfile {
        guard ConvexConfig.hasConfiguredClerkKey else {
            throw AuthError.providerNotConfigured
        }

        let signIn = try await Clerk.shared.auth.signInWithPassword(
            identifier: email,
            password: password
        )

        // Clerk returns a SignIn object describing what (if anything) is
        // still required to complete the sign-in. If MFA is enforced
        // (app-level or per-user), .createdSessionId is nil and status
        // is one of .needsSecondFactor / .needsNewPassword / etc. We
        // surface that as a clear error rather than silently falling
        // through to refreshAuthFromClerk, which would just time out
        // polling for a session that will never exist.
        guard let sessionId = signIn.createdSessionId else {
            throw AuthError.unknown
        }

        try await Clerk.shared.auth.setActive(sessionId: sessionId)

        // signInWithPassword's response middleware already applied the
        // fresh Client and flipped Clerk.shared.session.status to .active
        // (Clerk.client.didSet emits .sessionChanged). We do NOT call
        // refreshClient() here — a stale GET /v1/client can clear
        // lastActiveSessionId and push session out of .active longer
        // than refreshAuthFromClerk's 5s poll. We still need the
        // refreshAuthFromClerk call though: the SDK's session-sync Task
        // handles .sessionChanged on its own queue, so ensureClerkUser
        // can race past the FFI auth-callback install. This forces the
        // install on the call-site Task.
        try await convex.refreshAuthFromClerk()
        return try await ensureClerkUser()
    }

    func signOut() async throws {
        if ConvexConfig.hasConfiguredClerkKey {
            try await Clerk.shared.auth.signOut()
        }
        await convex.logout()
    }

    func startPasswordReset(email: String) async throws {
        guard ConvexConfig.hasConfiguredClerkKey else {
            throw AuthError.providerNotConfigured
        }

        _ = try await Clerk.shared.auth.signIn(email)
        guard let signIn = Clerk.shared.auth.currentSignIn else {
            throw AuthError.unknown
        }
        _ = try await signIn.sendResetPasswordEmailCode()
    }

    func confirmPasswordReset(code: String, newPassword: String) async throws -> UserProfile {
        guard ConvexConfig.hasConfiguredClerkKey else {
            throw AuthError.providerNotConfigured
        }
        guard let signIn = Clerk.shared.auth.currentSignIn else {
            throw AuthError.passwordResetExpired
        }

        let afterCode = try await signIn.verifyCode(code)
        guard afterCode.status == .needsNewPassword else {
            throw AuthError.unknown
        }

        let afterPassword = try await afterCode.resetPassword(
            newPassword: newPassword,
            signOutOfOtherSessions: false
        )
        guard afterPassword.status == .complete else {
            throw AuthError.unknown
        }
        if let sessionId = afterPassword.createdSessionId {
            try await Clerk.shared.auth.setActive(sessionId: sessionId)
            _ = try? await Clerk.shared.refreshClient()
        }
        // Same race as verifySignUpEmailCode — see comment there. The
        // password-reset SignIn emits `.signInCompleted`, which the SDK
        // currently does NOT route through syncCompletedSignUp, so we
        // *must* install the FFI auth callback ourselves before the next
        // mutation.
        try await convex.refreshAuthFromClerk()
        return try await ensureClerkUser()
    }

    func getUserProfile(userId: UUID, guestSecretHash: String? = nil) async throws -> UserProfile {
        let profile: UserProfile? = try await convex.query(
            "users:getUserProfile",
            with: [
                "user_id": userId.uuidString.lowercased(),
                "guest_secret_hash": guestSecretHash,
            ],
            as: UserProfile?.self
        )

        guard let profile else {
            throw AuthError.userNotFound
        }

        return profile
    }

    func updateUserProfile(
        userId: UUID,
        displayName: String,
        guestSecretHash: String? = nil
    ) async throws {
        let _: UserProfile = try await convex.mutation(
            "users:updateProfile",
            with: [
                "user_id": userId.uuidString.lowercased(),
                "display_name": displayName,
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    func updateGuestProfile(
        userId: UUID,
        displayName: String,
        isAnonymous: Bool,
        guestSecretHash: String
    ) async throws {
        let _: UserProfile = try await convex.mutation(
            "users:updateProfile",
            with: [
                "user_id": userId.uuidString.lowercased(),
                "display_name": displayName,
                "is_anonymous": isAnonymous,
                "guest_secret_hash": guestSecretHash,
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

    func mergeAnonymousStats(
        anonymousUserId: UUID,
        targetUserId: UUID,
        guestSecretHash: String
    ) async throws -> MergeStatsResult {
        try await convex.mutation(
            "users:mergeGuestIntoAccount",
            with: [
                "guest_user_id": anonymousUserId.uuidString.lowercased(),
                "target_user_id": targetUserId.uuidString.lowercased(),
                "guest_secret_hash": guestSecretHash,
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

    static func mapSignUpError(_ error: Error) -> Error {
        if let clerkError = error as? ClerkAPIError,
           let mapped = signUpError(forClerkCode: clerkError.code) {
            return mapped
        }
        return error
    }

    static func signUpError(forClerkCode code: String) -> AuthError? {
        code == "form_identifier_exists" ? .emailAlreadyInUse : nil
    }

    static func synchronizeCompletedSignUp(
        refreshClient: () async -> Void,
        refreshConvexAuth: () async throws -> Void
    ) async throws {
        await refreshClient()
        try await refreshConvexAuth()
    }

}

extension AuthService: AuthServicing {}

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
    case signUpExpired
    case passwordResetExpired
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
        case .signUpExpired:
            return "Your verification expired. Please sign up again."
        case .passwordResetExpired:
            return "Your password reset expired. Please request a new code."
        case .unknown:
            return "An unknown error occurred"
        }
    }
}
