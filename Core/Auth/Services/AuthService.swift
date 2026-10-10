import Foundation
import ClerkKit
import ConvexMobile

@MainActor
protocol AuthServicing: AnyObject {
    /// The signed-in account, or nil only when Clerk definitively has no
    /// user. Throws when Clerk or Convex cannot be reached.
    var currentUser: UserProfile? { get async throws }
    /// Reinstalls the account's Clerk token in Convex.
    func refreshConvexAuth() async throws
    /// Returns nil when Clerk emailed a code that `verifySignUpEmailCode` needs.
    func startSignUp(email: String, password: String, displayName: String) async throws -> UserProfile?
    func verifySignUpEmailCode(_ code: String, displayName: String) async throws -> UserProfile
    func resendSignUpEmailCode() async throws
    func signIn(email: String, password: String) async throws -> UserProfile
    func signOut() async throws
    func startPasswordReset(email: String) async throws
    func confirmPasswordReset(code: String, newPassword: String) async throws -> UserProfile
    func updateProfile(displayName: String) async throws
    func signInAsGuest(displayName: String, guestSecretHash: String) async throws -> UserProfile
    func mergeGuestIntoAccount(guestSecretHash: String) async throws
}

@MainActor
final class AuthService {
    private let convex = ConvexService.shared

    var currentUser: UserProfile? {
        get async throws {
            if Clerk.shared.user == nil {
                _ = try await Clerk.shared.refreshClient()
            }
            guard Clerk.shared.user != nil else { return nil }
            return try await completeSession()
        }
    }

    func refreshConvexAuth() async throws {
        try await convex.refreshAuthFromClerk()
    }

    func startSignUp(email: String, password: String, displayName: String) async throws -> UserProfile? {
        let signUp: SignUp
        do {
            signUp = try await Clerk.shared.auth.signUp(
                emailAddress: email,
                password: password,
                firstName: displayName
            )
        } catch {
            throw Self.mapClerkError(error)
        }

        guard signUp.status == .complete else {
            try await signUp.sendEmailCode()
            return nil
        }
        return try await completeSession(signUp.createdSessionId, displayName: displayName)
    }

    func verifySignUpEmailCode(_ code: String, displayName: String) async throws -> UserProfile {
        guard let signUp = Clerk.shared.auth.currentSignUp else {
            throw AuthError.signUpExpired
        }

        let updated = try await signUp.verifyEmailCode(code)
        guard updated.status == .complete else {
            throw AuthError.unknown
        }
        return try await completeSession(updated.createdSessionId, displayName: displayName)
    }

    func resendSignUpEmailCode() async throws {
        guard let signUp = Clerk.shared.auth.currentSignUp else {
            throw AuthError.signUpExpired
        }
        try await signUp.sendEmailCode()
    }

    func signIn(email: String, password: String) async throws -> UserProfile {
        let signIn: SignIn
        do {
            signIn = try await Clerk.shared.auth.signInWithPassword(
                identifier: email,
                password: password
            )
        } catch {
            throw Self.mapClerkError(error)
        }

        // Without a session Clerk still needs another step (for example a
        // second factor), so waiting for an active session would only time out.
        guard let sessionId = signIn.createdSessionId else {
            throw AuthError.unknown
        }
        return try await completeSession(sessionId)
    }

    func signOut() async throws {
        do {
            try await Clerk.shared.auth.signOut()
        } catch let error as ClerkAPIError where error.code == "signed_out" {
            // The requested account state is already satisfied.
        }
        await convex.logout()
    }

    func startPasswordReset(email: String) async throws {
        do {
            _ = try await Clerk.shared.auth.signIn(email)
        } catch {
            throw Self.mapClerkError(error)
        }
        guard let signIn = Clerk.shared.auth.currentSignIn else {
            throw AuthError.unknown
        }
        _ = try await signIn.sendResetPasswordEmailCode()
    }

    func confirmPasswordReset(code: String, newPassword: String) async throws -> UserProfile {
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
        return try await completeSession(afterPassword.createdSessionId)
    }

    func updateProfile(displayName: String) async throws {
        let _: UserProfile = try await convex.mutation(
            "users:updateProfile",
            with: ["display_name": displayName]
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

    func mergeGuestIntoAccount(guestSecretHash: String) async throws {
        let _: MergeStatsResult = try await convex.mutation(
            "users:mergeGuestIntoAccount",
            with: ["guest_secret_hash": guestSecretHash]
        )
    }

    /// Finishes every account entry path: activates the Clerk session (when
    /// a flow created one), installs its token in Convex and loads the profile.
    private func completeSession(_ sessionId: String? = nil, displayName: String? = nil) async throws -> UserProfile {
        if let sessionId {
            try await Clerk.shared.auth.setActive(sessionId: sessionId)
        }
        // setActive normally applies the returned client and marks the
        // session active. Only when it has not, fetch the client: an
        // unconditional refresh can return a stale client that pushes an
        // active session out of .active again.
        if Clerk.shared.session?.status != .active {
            _ = try? await Clerk.shared.refreshClient()
        }
        // The provider's session-sync task installs the token too, but on its
        // own task; doing it here keeps ensureUser from racing it.
        try await convex.refreshAuthFromClerk()
        return try await convex.mutation(
            "users:ensureUser",
            with: ["display_name": displayName]
        )
    }

    static func mapClerkError(_ error: Error) -> Error {
        authError(forClerkCode: (error as? ClerkAPIError)?.code) ?? error
    }

    static func authError(forClerkCode code: String?) -> AuthError? {
        switch code {
        case "form_identifier_exists": .emailAlreadyInUse
        case "form_identifier_not_found": .accountNotFound
        default: nil
        }
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

// TEMP(integration): remove after merge. ConvexIntegrationTests still calls it.
extension AuthService {
    func getUserProfile(userId: UUID, guestSecretHash: String? = nil) async throws -> UserProfile {
        guard let profile = try await convex.query(
            "users:getMe",
            with: ["guest_secret_hash": guestSecretHash],
            as: UserProfile?.self
        ), profile.id == userId else {
            throw AuthError.unknown
        }
        return profile
    }
}

enum AuthError: LocalizedError {
    case emailAlreadyInUse
    case accountNotFound
    case signUpExpired
    case passwordResetExpired
    case unknown

    var errorDescription: String? {
        switch self {
        case .emailAlreadyInUse:
            return "An account with this email already exists. Sign in instead."
        case .accountNotFound:
            return "No account uses this email. If you played before the update, tap Sign Up with the same email to restore your stats."
        case .signUpExpired:
            return "Your verification expired. Please sign up again."
        case .passwordResetExpired:
            return "Your password reset expired. Please request a new code."
        case .unknown:
            return "An unknown error occurred"
        }
    }
}
