import Foundation
import Testing

@testable import mafia_manager

@MainActor
struct AccountRestorationTests {
    @Test func cachedIdentityAuthenticatesBeforeLoadingProfile() async throws {
        let profile = UserProfile(id: UUID(), displayName: "Restored", isAnonymous: false,
                                  createdAt: Date(), updatedAt: Date())
        var authenticated = false
        let restored = try await AuthService.restoreAccountProfile(
            hasClerkUser: true,
            refreshConvexAuth: { authenticated = true },
            loadProfile: {
                #expect(authenticated, "Profile restoration requires the cached Clerk token")
                return profile
            }
        )
        #expect(restored?.id == profile.id)
    }

    @Test func failedTokenRestorationDoesNotSendUnauthenticatedProfileMutation() async {
        var requestedProfile = false
        do {
            _ = try await AuthService.restoreAccountProfile(
                hasClerkUser: true,
                refreshConvexAuth: { throw RestorationError.unavailable },
                loadProfile: {
                    requestedProfile = true
                    throw RestorationError.unavailable
                }
            )
            Issue.record("Expected the token restoration error")
        } catch {
            #expect(error is RestorationError)
        }
        #expect(requestedProfile == false)
    }

    @Test func signedOutLaunchDoesNotAttemptAccountRestoration() async throws {
        var requestedAuth = false
        let restored = try await AuthService.restoreAccountProfile(
            hasClerkUser: false,
            refreshConvexAuth: { requestedAuth = true },
            loadProfile: { throw RestorationError.unavailable }
        )
        #expect(restored == nil)
        #expect(requestedAuth == false)
    }
}

private enum RestorationError: Error { case unavailable }
