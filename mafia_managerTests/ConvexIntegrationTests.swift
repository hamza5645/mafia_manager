import Combine
import XCTest

@testable import mafia_manager

/// Live integration tests against the Convex dev deployment configured in
/// `ConvexConfig.swift`. They exercise the real client stack (ConvexMobile FFI,
/// argument encoding, model decoding, live subscriptions) that replaced the
/// Supabase SDK in the backend migration.
///
/// These tests require network access and a reachable dev deployment, so they
/// are skipped unless the test runner environment sets `CONVEX_INTEGRATION=1`:
///
///     xcodebuild test -workspace mafia_manager.xcworkspace -scheme mafia_manager \
///       -destination 'platform=iOS Simulator,name=iPhone 17' \
///       TEST_RUNNER_CONVEX_INTEGRATION=1
@MainActor
final class ConvexIntegrationTests: XCTestCase {
    private static var enabled: Bool {
        ProcessInfo.processInfo.environment["CONVEX_INTEGRATION"] == "1"
    }

    private var sessionService: SessionService!
    private var authService: AuthService!

    override func setUp() async throws {
        try XCTSkipUnless(
            Self.enabled,
            "Set TEST_RUNNER_CONVEX_INTEGRATION=1 to run live Convex integration tests"
        )
        sessionService = SessionService()
        authService = AuthService()
    }

    // MARK: - Helpers

    private struct HealthResponse: Decodable {
        let ok: Bool
        let backend: String
        let version: String
    }

    private func makeGuest(name: String, hash: String) async throws -> UserProfile {
        try await authService.signInAsGuest(displayName: name, guestSecretHash: hash)
    }

    /// Ends a test session so no joinable `qa-swift-*` rooms linger on dev.
    private func tearDownSession(
        _ session: GameSession,
        hostUserId: UUID,
        hostHash: String,
        users: [(UUID, String)]
    ) async {
        try? await sessionService.updateSessionStatus(
            sessionId: session.id,
            status: .cancelled,
            callerUserId: hostUserId,
            guestSecretHash: hostHash
        )
        for (userId, hash) in users {
            try? await sessionService.leaveSession(
                sessionId: session.id,
                userId: userId,
                guestSecretHash: hash
            )
        }
    }

    // MARK: - Tests

    func testHealthCheckRoundTrip() async throws {
        let health: HealthResponse = try await ConvexService.shared.query("health:check")
        XCTAssertTrue(health.ok)
        XCTAssertEqual(health.backend, "convex")
    }

    func testGuestCreateAndRestoreIsIdempotent() async throws {
        let hash = "qa-swift-int-guest"
        let first = try await makeGuest(name: "QA Swift Guest", hash: hash)
        let second = try await makeGuest(name: "QA Swift Guest Renamed", hash: hash)

        XCTAssertEqual(first.id, second.id, "Same guest secret must restore the same user")
        XCTAssertTrue(second.isAnonymous)
        XCTAssertEqual(second.displayName, "QA Swift Guest Renamed")
    }

    func testMultiplayerSessionLifecycle() async throws {
        let hostHash = "qa-swift-int-host"
        let joinerHash = "qa-swift-int-joiner"
        let host = try await makeGuest(name: "QA Swift Host", hash: hostHash)
        let joiner = try await makeGuest(name: "QA Swift Joiner", hash: joinerHash)

        let session = try await sessionService.createSession(
            hostUserId: host.id,
            guestSecretHash: hostHash
        )
        var cleanupUsers = [(host.id, hostHash)]
        defer {
            let users = cleanupUsers
            Task {
                await self.tearDownSession(
                    session,
                    hostUserId: host.id,
                    hostHash: hostHash,
                    users: users
                )
            }
        }

        XCTAssertEqual(session.status, .waiting)
        XCTAssertEqual(session.currentPhase, "lobby")
        XCTAssertEqual(session.roomCode.count, 6)

        let hostPlayer = try await sessionService.addPlayer(
            sessionId: session.id,
            userId: host.id,
            playerName: "QA Swift Host",
            isBot: false,
            callerUserId: host.id,
            guestSecretHash: hostHash
        )
        let (joinedSession, joinerPlayer) = try await sessionService.joinSession(
            roomCode: session.roomCode,
            userId: joiner.id,
            playerName: "QA Swift Joiner",
            guestSecretHash: joinerHash
        )
        cleanupUsers.append((joiner.id, joinerHash))
        XCTAssertEqual(joinedSession.id, session.id)

        try await sessionService.assignRolesAndNumbers(
            sessionId: session.id,
            assignments: [
                (playerId: hostPlayer.playerId, role: .mafia, number: 1),
                (playerId: joinerPlayer.playerId, role: .citizen, number: 2),
            ],
            callerUserId: host.id,
            guestSecretHash: hostHash
        )

        // Host is the game master and must see every role; the joiner must
        // only see their own.
        let hostView = try await sessionService.getSessionPlayers(
            sessionId: session.id,
            viewerUserId: host.id,
            guestSecretHash: hostHash
        )
        XCTAssertEqual(hostView.count, 2)
        XCTAssertEqual(hostView.compactMap(\.role).count, 2)

        let joinerView = try await sessionService.getSessionPlayers(
            sessionId: session.id,
            viewerUserId: joiner.id,
            guestSecretHash: joinerHash
        )
        XCTAssertEqual(
            joinerView.first(where: { $0.playerId == joinerPlayer.playerId })?.role, .citizen
        )
        XCTAssertNil(
            joinerView.first(where: { $0.playerId == hostPlayer.playerId })?.role,
            "A citizen must not see the host's role before game over"
        )

        // Enter night: the backend must mint a fresh round id.
        try await sessionService.updateSessionStatus(
            sessionId: session.id,
            status: .inProgress,
            callerUserId: host.id,
            guestSecretHash: hostHash
        )
        try await sessionService.updateSessionPhase(
            sessionId: session.id,
            currentPhase: "night",
            phaseData: .night(nightIndex: 0, activeRole: nil),
            callerUserId: host.id,
            guestSecretHash: hostHash
        )
        let nightSession = try await sessionService.getSession(sessionId: session.id)
        let roundId = try XCTUnwrap(nightSession?.currentRoundId)

        // Submit a mafia action for the current round and read it back.
        let response = try await sessionService.submitAction(
            GameAction.mafiaAction(
                sessionId: session.id,
                roundId: roundId,
                nightIndex: 0,
                actorPlayerId: hostPlayer.playerId,
                targetPlayerId: joinerPlayer.playerId
            ),
            guestSecretHash: hostHash
        )
        XCTAssertTrue(response.success)

        let actions = try await sessionService.getActionsForPhase(
            sessionId: session.id,
            actionType: .mafiaTarget,
            phaseIndex: 0,
            roundId: roundId,
            viewerUserId: host.id,
            guestSecretHash: hostHash
        )
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.targetPlayerId, joinerPlayer.playerId)

        // A stale round id must be rejected (replay protection).
        do {
            _ = try await sessionService.submitAction(
                GameAction.mafiaAction(
                    sessionId: session.id,
                    roundId: UUID(),
                    nightIndex: 0,
                    actorPlayerId: hostPlayer.playerId,
                    targetPlayerId: joinerPlayer.playerId
                ),
                guestSecretHash: hostHash
            )
            XCTFail("Submitting against a stale round id must throw")
        } catch {
            // expected
        }

        // Two-phase night resolution: record-then-resolve via the atomic mutation.
        let record = NightActionRecord(
            nightIndex: 0,
            isResolved: true,
            mafiaTargetId: joinerPlayer.playerId,
            inspectorCheckedId: nil,
            inspectorResult: nil,
            doctorProtectedId: nil,
            targetWasSaved: false,
            resultingDeaths: [joinerPlayer.playerId],
            revealedDeathRoles: [joinerPlayer.playerId.uuidString.lowercased(): "citizen"],
            mafiaPlayerNumbers: [1],
            doctorPlayerNumbers: [],
            inspectorPlayerNumbers: [],
            timestamp: Date()
        )
        let resolved = try await sessionService.resolveNightAtomic(
            sessionId: session.id,
            nightRecord: record,
            eliminatedPlayerIds: [joinerPlayer.playerId],
            nextPhase: "game_over",
            nextPhaseData: .gameOver(winner: Role.mafia.rawValue),
            callerUserId: host.id,
            isGameOver: true,
            winner: .mafia,
            guestSecretHash: hostHash
        )
        XCTAssertTrue(resolved)

        let maybeFinalSession = try await sessionService.getSession(sessionId: session.id)
        let finalSession = try XCTUnwrap(maybeFinalSession)
        XCTAssertTrue(finalSession.isGameOver)
        XCTAssertEqual(finalSession.winner, .mafia)
        XCTAssertEqual(finalSession.status, .completed)
        XCTAssertEqual(finalSession.nightHistory.count, 1)
        XCTAssertEqual(finalSession.nightHistory.first?.resultingDeaths, [joinerPlayer.playerId])

        let finalPlayers = try await sessionService.getSessionPlayers(
            sessionId: session.id,
            viewerUserId: joiner.id,
            guestSecretHash: joinerHash
        )
        XCTAssertEqual(
            finalPlayers.first(where: { $0.playerId == joinerPlayer.playerId })?.isAlive, false
        )
        XCTAssertEqual(
            finalPlayers.compactMap(\.role).count, 2,
            "All roles must be revealed at game over"
        )
    }

    func testGuestAuthorizationAndMembershipBoundaries() async throws {
        let hostHash = "qa-security-host"
        let memberHash = "qa-security-member"
        let outsiderHash = "qa-security-outsider"
        let host = try await makeGuest(name: "QA Security Host", hash: hostHash)
        let member = try await makeGuest(name: "QA Security Member", hash: memberHash)
        let outsider = try await makeGuest(name: "QA Security Outsider", hash: outsiderHash)

        do {
            _ = try await authService.getUserProfile(userId: host.id)
            XCTFail("An asserted user id without Clerk or guest proof must fail")
        } catch {}
        do {
            _ = try await authService.getUserProfile(
                userId: host.id,
                guestSecretHash: "wrong-proof"
            )
            XCTFail("Wrong guest proof must fail")
        } catch {}
        let provenHost = try await authService.getUserProfile(
            userId: host.id,
            guestSecretHash: hostHash
        )
        XCTAssertEqual(provenHost.id, host.id)

        let session = try await sessionService.createSession(
            hostUserId: host.id,
            guestSecretHash: hostHash
        )
        defer {
            Task {
                await self.tearDownSession(
                    session,
                    hostUserId: host.id,
                    hostHash: hostHash,
                    users: [(host.id, hostHash), (member.id, memberHash)]
                )
            }
        }
        let hostPlayer = try await sessionService.addPlayer(
            sessionId: session.id,
            userId: host.id,
            playerName: "QA Security Host",
            isBot: false,
            callerUserId: host.id,
            guestSecretHash: hostHash
        )
        let (_, memberPlayer) = try await sessionService.joinSession(
            roomCode: session.roomCode,
            userId: member.id,
            playerName: "QA Security Member",
            guestSecretHash: memberHash
        )
        let bot = try await sessionService.addPlayer(
            sessionId: session.id,
            userId: nil,
            playerName: "QA Security Bot",
            isBot: true,
            callerUserId: host.id,
            guestSecretHash: hostHash
        )
        try await sessionService.assignRolesAndNumbers(
            sessionId: session.id,
            assignments: [
                (hostPlayer.playerId, .mafia, 1),
                (memberPlayer.playerId, .citizen, 2),
                (bot.playerId, .doctor, 3),
            ],
            callerUserId: host.id,
            guestSecretHash: hostHash
        )

        do {
            _ = try await sessionService.getSessionPlayers(
                sessionId: session.id,
                viewerUserId: host.id,
                guestSecretHash: memberHash
            )
            XCTFail("A spoofed host viewer must not reveal roles")
        } catch {}
        do {
            try await sessionService.updatePlayerReady(
                playerId: hostPlayer.id,
                isReady: false,
                guestSecretHash: memberHash
            )
            XCTFail("One guest must not mutate another player's row")
        } catch {}

        try await sessionService.updateSessionStatus(
            sessionId: session.id,
            status: .inProgress,
            callerUserId: host.id,
            guestSecretHash: hostHash
        )
        try await sessionService.updateSessionPhase(
            sessionId: session.id,
            currentPhase: "night",
            phaseData: .night(nightIndex: 0, activeRole: nil),
            callerUserId: host.id,
            guestSecretHash: hostHash
        )
        let updatedSession = try await sessionService.getSession(sessionId: session.id)
        let roundId = try XCTUnwrap(updatedSession?.currentRoundId)
        let hostAction = GameAction.mafiaAction(
            sessionId: session.id,
            roundId: roundId,
            nightIndex: 0,
            actorPlayerId: hostPlayer.playerId,
            targetPlayerId: memberPlayer.playerId
        )
        do {
            _ = try await sessionService.submitAction(
                hostAction,
                guestSecretHash: memberHash
            )
            XCTFail("One guest must not submit another player's action")
        } catch {}
        _ = try await sessionService.submitAction(hostAction, guestSecretHash: hostHash)

        do {
            _ = try await sessionService.getActionsForPhase(
                sessionId: session.id,
                actionType: .mafiaTarget,
                phaseIndex: 0,
                roundId: roundId,
                viewerUserId: outsider.id,
                guestSecretHash: outsiderHash
            )
            XCTFail("An outsider must not read session actions")
        } catch {}
        let memberRead = try await sessionService.getActionsForPhase(
            sessionId: session.id,
            actionType: .mafiaTarget,
            phaseIndex: 0,
            roundId: roundId,
            viewerUserId: member.id,
            guestSecretHash: memberHash
        )
        XCTAssertEqual(memberRead.count, 1)

        let botAction = GameAction.doctorAction(
            sessionId: session.id,
            roundId: roundId,
            nightIndex: 0,
            actorPlayerId: bot.playerId,
            targetPlayerId: memberPlayer.playerId
        )
        let botResponse = try await sessionService.submitAction(
            botAction,
            callerUserId: host.id,
            guestSecretHash: hostHash
        )
        XCTAssertTrue(botResponse.success)
    }

    func testLiveSubscriptionDeliversPhaseUpdates() async throws {
        let hostHash = "qa-swift-int-sub"
        let host = try await makeGuest(name: "QA Swift Sub Host", hash: hostHash)
        let session = try await sessionService.createSession(
            hostUserId: host.id,
            guestSecretHash: hostHash
        )
        defer {
            Task {
                await self.tearDownSession(
                    session,
                    hostUserId: host.id,
                    hostHash: hostHash,
                    users: [(host.id, hostHash)]
                )
            }
        }
        _ = try await sessionService.addPlayer(
            sessionId: session.id,
            userId: host.id,
            playerName: "QA Swift Sub Host",
            isBot: false,
            callerUserId: host.id,
            guestSecretHash: hostHash
        )

        let sawNightPhase = expectation(description: "subscription delivered the night phase")
        sawNightPhase.assertForOverFulfill = false
        var cancellables: Set<AnyCancellable> = []
        ConvexService.shared.subscribe(
            "sessions:getSessionById",
            with: ["session_id": session.id.uuidString.lowercased()],
            as: GameSession?.self
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { _ in },
            receiveValue: { update in
                if update?.currentPhase == "night" {
                    sawNightPhase.fulfill()
                }
            }
        )
        .store(in: &cancellables)

        // Give the subscription a moment to deliver its initial snapshot, then
        // mutate the phase and require the update to arrive reactively.
        try await Task.sleep(nanoseconds: 1_000_000_000)
        try await sessionService.updateSessionPhase(
            sessionId: session.id,
            currentPhase: "night",
            phaseData: .night(nightIndex: 0, activeRole: nil),
            callerUserId: host.id,
            guestSecretHash: hostHash
        )

        await fulfillment(of: [sawNightPhase], timeout: 15)
        cancellables.removeAll()
    }
}
