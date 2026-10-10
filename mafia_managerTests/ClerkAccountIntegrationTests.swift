import CryptoKit
import XCTest

@testable import mafia_manager

/// Creates an isolated Clerk development account and exercises the actual
/// ClerkKit -> ConvexMobile -> Convex account path, including a guest merge.
/// Requires both opt-in flags; every run uses a new email and guest proof.
@MainActor
final class ClerkAccountIntegrationTests: XCTestCase {
    func testVerifiedSignupMergeRestorationAndPasswordReset() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CONVEX_INTEGRATION"] == "1"
                && ProcessInfo.processInfo.environment["CLERK_ACCOUNT_E2E"] == "1",
            "Set TEST_RUNNER_CONVEX_INTEGRATION=1 and TEST_RUNNER_CLERK_ACCOUNT_E2E=1"
        )
        let service = AuthService()
        let database = DatabaseService()
        let convex = ConvexService.shared
        let email = "mafia-native-\(UUID().uuidString.lowercased())+clerk_test@example.com"
        let password = "Qa-\(UUID().uuidString)-2026!"
        let resetPassword = "Qa-\(UUID().uuidString)-Reset!"
        let guestHash = SHA256.hash(data: Data(UUID().uuidString.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let statName = "QA Native Collision"
        let appProofProvider = convex.guestProofProvider
        print("QA ACCOUNT: \(email)")
        addTeardownBlock { @MainActor in
            convex.guestProofProvider = nil
            if (try? await service.currentUser) != nil {
                for row in (try? await database.getPlayerStats()) ?? [] where row.playerName == statName {
                    try? await database.deletePlayerStat(id: row.id)
                }
            }
            try? await service.signOut()
            convex.guestProofProvider = appProofProvider
        }

        // Repeated sign-out must succeed and leave Convex unauthenticated.
        try await service.signOut()
        try await service.signOut()

        print("QA STAGE: guest stats")
        convex.guestProofProvider = { guestHash }
        _ = try await service.signInAsGuest(displayName: "QA Native Merge", guestSecretHash: guestHash)
        try await database.upsertPlayerStat(playerName: statName, role: .doctor, won: false, kills: 1)

        print("QA STAGE: native signup")
        let account: UserProfile
        if let profile = try await service.startSignUp(email: email, password: password, displayName: "QA Native Account") {
            account = profile
        } else {
            print("QA STAGE: native email verification")
            account = try await service.verifySignUpEmailCode("424242", displayName: "QA Native Account")
        }
        XCTAssertFalse(account.isAnonymous)

        print("QA STAGE: native guest stats merge")
        convex.guestProofProvider = nil
        try await database.upsertPlayerStat(playerName: statName, role: .mafia, won: true, kills: 2)
        try await service.mergeGuestIntoAccount(guestSecretHash: guestHash)
        try await service.mergeGuestIntoAccount(guestSecretHash: guestHash)
        let rows = try await database.getPlayerStats()
        XCTAssertEqual(rows.filter { $0.playerName == statName }.count, 1)
        let combined = try await database.getPlayerStat(playerName: statName)
        XCTAssertEqual(combined?.gamesPlayed, 2)
        XCTAssertEqual(combined?.gamesWon, 1)
        XCTAssertEqual(combined?.gamesLost, 1)
        XCTAssertEqual(combined?.totalKills, 3)
        for row in rows where row.playerName == statName {
            try await database.deletePlayerStat(id: row.id)
        }

        print("QA STAGE: native profile restoration and edit")
        let restored = try await service.currentUser
        XCTAssertEqual(restored?.id, account.id)
        try await service.updateProfile(displayName: "QA Edited Native")
        let edited = try await service.currentUser
        XCTAssertEqual(edited?.displayName, "QA Edited Native")

        try await service.signOut()
        print("QA STAGE: native password sign-in")
        let signedIn = try await service.signIn(email: email, password: password)
        XCTAssertEqual(signedIn.id, account.id)
        XCTAssertEqual(signedIn.displayName, "QA Edited Native")

        try await service.signOut()
        print("QA STAGE: native password reset")
        try await service.startPasswordReset(email: email)
        let reset = try await service.confirmPasswordReset(code: "424242", newPassword: resetPassword)
        XCTAssertEqual(reset.id, account.id)

        try await service.signOut()
        print("QA STAGE: reject old password")
        do {
            _ = try await service.signIn(email: email, password: password)
            XCTFail("Old password must fail after reset")
        } catch {
            // Expected authentication rejection.
        }
        print("QA STAGE: accept reset password")
        let final = try await service.signIn(email: email, password: resetPassword)
        XCTAssertEqual(final.id, account.id)

        print("QA STAGE: unknown email gets legacy guidance")
        try await service.signOut()
        do {
            try await service.startPasswordReset(email: "missing-\(UUID().uuidString.lowercased())+clerk_test@example.com")
            XCTFail("An unknown email must not start a reset")
        } catch AuthError.accountNotFound {
            // Expected: Clerk reports form_identifier_not_found.
        }
    }
}
