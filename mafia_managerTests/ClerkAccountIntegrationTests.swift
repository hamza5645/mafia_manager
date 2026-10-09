import XCTest

@testable import mafia_manager

/// Creates an isolated Clerk development account and exercises the actual
/// ClerkKit -> ConvexMobile -> Convex profile path. Requires both opt-in flags.
@MainActor
final class ClerkAccountIntegrationTests: XCTestCase {
    func testVerifiedSignupSignInRestorationAndPasswordReset() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CONVEX_INTEGRATION"] == "1"
                && ProcessInfo.processInfo.environment["CLERK_ACCOUNT_E2E"] == "1",
            "Set TEST_RUNNER_CONVEX_INTEGRATION=1 and TEST_RUNNER_CLERK_ACCOUNT_E2E=1"
        )
        let service = AuthService()
        let email = "mafia-native-\(UUID().uuidString.lowercased())+clerk_test@example.com"
        let password = "Qa-\(UUID().uuidString)-2026!"
        let resetPassword = "Qa-\(UUID().uuidString)-Reset!"
        print("QA ACCOUNT: \(email)")

        try await service.signOut()
        // Cleanup and a guest-to-account flow may both request sign-out.
        try await service.signOut()
        let database = DatabaseService()
        let guestHash = "qa-native-merge-\(UUID().uuidString)"
        let guest = try await service.signInAsGuest(displayName: "QA Native Merge", guestSecretHash: guestHash)
        let sessions = SessionService()
        let guestRoom = try await sessions.createSession(hostUserId: guest.id, guestSecretHash: guestHash)
        let guestPlayer = try await sessions.addPlayer(
            sessionId: guestRoom.id, userId: guest.id, playerName: guest.displayName,
            isBot: false, callerUserId: guest.id, guestSecretHash: guestHash
        )
        let realtime = RealtimeService()
        let guestSeen = expectation(description: "Guest realtime seat is present")
        let noRemoval = expectation(description: "Upgrade does not kick the guest")
        noRemoval.isInverted = true
        var sawGuest = false
        var watchingUpgrade = true
        var subscriptionErrors: [String] = []
        try await realtime.subscribeToSession(
            sessionId: guestRoom.id, viewerUserId: guest.id, guestSecretHash: guestHash,
            onSessionUpdate: { _ in },
            onPlayerUpdate: { player in
                if player.id == guestPlayer.id && player.userId == guest.id && !sawGuest {
                    sawGuest = true
                    guestSeen.fulfill()
                }
            },
            onPlayerRemoved: { id in
                if watchingUpgrade && id == guestPlayer.id { noRemoval.fulfill() }
            },
            onActionUpdate: { _ in },
            onDecodeError: { error, _ in if watchingUpgrade { subscriptionErrors.append(error.localizedDescription) } }
        )
        await fulfillment(of: [guestSeen], timeout: 10)
        let statName = "QA Native Collision"
        try await database.upsertPlayerStat(
            userId: guest.id, playerName: statName, role: .doctor, won: false, kills: 1,
            guestSecretHash: guestHash
        )
        print("QA STAGE: native signup")
        let signup = try await service.startSignUp(
            email: email,
            password: password,
            displayName: "QA Native Account"
        )
        let account: UserProfile
        switch signup {
        case .completed(let profile):
            account = profile
        case .needsEmailCode:
            print("QA STAGE: native email verification")
            account = try await service.verifySignUpEmailCode("424242", displayName: "QA Native Account")
        }
        XCTAssertFalse(account.isAnonymous)
        print("QA STAGE: native profile restoration")
        let restored = await service.currentUser
        XCTAssertEqual(restored?.id, account.id)
        print("QA STAGE: native profile edit survives refresh")
        try await service.updateUserProfile(userId: account.id, displayName: "QA Edited Native", guestSecretHash: nil)
        let edited = await service.currentUser
        XCTAssertEqual(edited?.displayName, "QA Edited Native")

        print("QA STAGE: guest subscriptions survive new Clerk identity")
        await fulfillment(of: [noRemoval], timeout: 1)
        XCTAssertTrue(subscriptionErrors.isEmpty, "Changing auth must not terminate guest subscriptions")
        print("QA STAGE: native guest stats merge")
        try await database.upsertPlayerStat(userId: account.id, playerName: statName, role: .mafia, won: true, kills: 2)
        do {
            let merge = try await service.mergeAnonymousStats(
                anonymousUserId: guest.id, targetUserId: account.id, guestSecretHash: guestHash
            )
            XCTAssertTrue(merge.success)
            print("QA STAGE: native active room upgrade")
            let upgradedRoom = try await sessions.getSession(sessionId: guestRoom.id, viewerUserId: account.id)
            XCTAssertEqual(upgradedRoom?.hostUserId, account.id)
            let seats = try await sessions.getSessionPlayers(sessionId: guestRoom.id, viewerUserId: account.id)
            XCTAssertEqual(seats.first(where: { $0.id == guestPlayer.id })?.userId, account.id)
            XCTAssertEqual(seats.first(where: { $0.id == guestPlayer.id })?.playerId, guestPlayer.playerId)
            XCTAssertTrue(realtime.isConnected, "Merged room subscriptions must remain active")
            watchingUpgrade = false
            await realtime.unsubscribeAll()
            try await sessions.updateSessionStatus(sessionId: guestRoom.id, status: .cancelled, callerUserId: account.id)
            try await sessions.leaveSession(sessionId: guestRoom.id, userId: account.id)
            let afterLeave = try await sessions.getSessionPlayers(sessionId: guestRoom.id, viewerUserId: account.id)
            XCTAssertTrue(afterLeave.isEmpty)
            let rows = try await database.getPlayerStats(userId: account.id)
            XCTAssertEqual(rows.filter { $0.playerName == statName }.count, 1)
            let combined = try await database.getPlayerStat(userId: account.id, playerName: statName)
            XCTAssertEqual(combined?.gamesPlayed, 2)
            XCTAssertEqual(combined?.gamesWon, 1)
            XCTAssertEqual(combined?.gamesLost, 1)
            XCTAssertEqual(combined?.totalKills, 3)
            try await database.upsertPlayerStat(userId: account.id, playerName: statName, role: .citizen, won: true, kills: 0)
            let incremented = try await database.getPlayerStat(userId: account.id, playerName: statName)
            XCTAssertEqual(incremented?.gamesPlayed, 3)
        } catch {
            watchingUpgrade = false
            await realtime.unsubscribeAll()
            try? await sessions.updateSessionStatus(sessionId: guestRoom.id, status: .cancelled, callerUserId: account.id)
            try? await sessions.leaveSession(sessionId: guestRoom.id, userId: account.id)
            for row in (try? await database.getPlayerStats(userId: account.id)) ?? [] where row.playerName == statName {
                try? await database.deletePlayerStat(id: row.id)
            }
            try? await service.signOut()
            try? await sessions.updateSessionStatus(sessionId: guestRoom.id, status: .cancelled, callerUserId: guest.id, guestSecretHash: guestHash)
            try? await sessions.leaveSession(sessionId: guestRoom.id, userId: guest.id, guestSecretHash: guestHash)
            throw error
        }
        for row in try await database.getPlayerStats(userId: account.id) where row.playerName == statName {
            try await database.deletePlayerStat(id: row.id)
        }

        try await service.signOut()
        print("QA STAGE: native password sign-in")
        let signedIn = try await service.signIn(email: email, password: password)
        XCTAssertEqual(signedIn.id, account.id)
        let afterSignIn = await service.currentUser
        XCTAssertEqual(afterSignIn?.id, account.id)
        XCTAssertEqual(afterSignIn?.displayName, "QA Edited Native")

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
        XCTAssertEqual(final.displayName, "QA Edited Native")
        try await service.signOut()
    }
}
