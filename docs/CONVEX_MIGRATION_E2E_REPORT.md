# Convex migration E2E report — 2026-10-08

The branch is **not ready for release**. The existing Swift tests pass after synchronizing the development backend, but broader testing reproduced gameplay, privacy, authorization, and account-data failures.

Tested branch: `AWS`, starting commit `0d75931fd4df47899e75a31f981006abf95fe2f6`. No app or backend fixes were made. This session adds test tooling, evidence, and this report. Findings describe this branch; whether each issue existed before the migration has not been established.

## Results and coverage

| Check | Result | Scope |
| --- | --- | --- |
| Tuist generation and signed Debug simulator build | Passed | Xcode 27 beta; iOS 27.0 simulators |
| Existing Swift suite before backend synchronization | 35 tests, 4 assertion failures across 3 live test cases | Development deployment rejected this branch's guest-proof arguments |
| Existing Swift suite after synchronization | **35/35 passed** | 30 local tests and 5 real Convex integration tests; no skips |
| New native Clerk account integration test | **1/1 passed** | Actual ClerkKit → ConvexMobile → Convex signup, email verification, sign-in, profile restoration, reset, old-password rejection, new-password sign-in |
| Expanded guest/multiplayer/cloud API audit | **35 passed, 14 failed** | 49 assertions, including fixture cleanup; failed assertions group into several distinct issues below |
| Clerk/account/merge API audit | **15 passed, 5 failed** | 20 assertions, including stats cleanup |
| Clerk password-reset API audit | **5/5 passed** | Invalid code, new-password requirement, same profile, old-password rejection, new-password success |
| Saved legacy export → current Convex comparison | **Passed** | All 86 legacy users, 48 stats, 6 role configs, and 2 groups; no missing rows, duplicate legacy IDs, field mismatches, or broken owner mappings |
| Live Supabase → Convex parity | **Blocked** | Configured Supabase hostname returned `ENOTFOUND`; current source parity is unverified |
| Two-device guest UI | Mixed | Create, join, live host roster update, kick, bot room, role reveal, night, morning, death reveal, voting; kick and voting failures reproduced |
| Solo UI | Passed | Complete four-player game with one human and three bots, Mafia action, bot inspector action, morning/death, bot and human voting, winner, persisted game restoration, Play Again, cloud stats showing one game |
| Guest saved-group UI | Passed | Created a four-player group; it remained saved after app relaunch before account testing |

The two devices were `iphone` (`AFB5AEA8-6976-44A7-8BA8-5681602C2CEA`) and the newly created `Mafia QA Guest` (`91E45D7E-49E2-456B-BD1F-82EAD71CBDDF`). Tests used the configured development deployment, `energized-herring-345`, and Clerk's development instance.

Public-client API tests used real network requests and isolated QA identities, without admin auth or forged Clerk identities. Admin access was used only for read-only legacy snapshots and cleanup of this run's own QA fixtures. The native integration test exercises the real Swift SDKs. Backend checks alone do not establish that every UI journey works.

Evidence is in [e2e-evidence/2026-10-08](e2e-evidence/2026-10-08). Private raw logs and `.xcresult` bundles are under `/tmp/mafia-e2e-20261008`; credentials, JWTs, guest proofs, and legacy personal data are excluded from committed evidence.

## Confirmed issues

### E2E-01 — P1: Configured backend was incompatible with this branch

**Status: corrected in the development deployment during testing; rollout coordination remains required.**

The app supplied `guest_secret_hash` to `sessions:createSession` and `users:getUserProfile`, but the deployed validators did not accept it. Guest room creation and the live integration tests failed. A profile query without proof was also accepted by the old deployment.

Reproduce against the original deployed state: run the branch's live Swift suite or create a guest room. The server reports `Object contains extra field guest_secret_hash that is not in the validator`.

Running `npx convex dev --once --typecheck enable` deployed the existing branch code and removed this mismatch. No backend source fix was made. Before-sync evidence: [backend-before-sync.json](e2e-evidence/2026-10-08/backend-before-sync.json). All subsequent findings were reproduced after synchronization.

### E2E-02 — P1: Multiplayer cannot finish voting

Affected: `Core/Multiplayer/Store/MultiplayerGameStore.swift:2599`, `Core/Multiplayer/Services/SessionService.swift:360`, `convex/sessions.ts:737`, `Features/Multiplayer/Flow/MultiplayerVotingView.swift:224`.

`showVotingResults` calls `getActionsForPhase` without `viewerUserId` or guest proof. The Convex query requires `viewer_user_id` for every caller. Clerk authentication does not remove that validator requirement.

Reproduction:

1. Create a guest room with three bots; start the game.
2. Reveal the host role, start and finish the night, reveal deaths, then start voting.
3. Select a target and tap **End Voting**.

The UI remains in voting and displays **“Bot voting failed. Please try again.”** The exact API request fails with `Object is missing the required field viewer_user_id`. Repeating the request does not advance the game. This blocks the normal results/game-over/rematch journey. The UI's message also misidentifies the failure as bot voting.

Evidence: [voting-blocked.png](e2e-evidence/2026-10-08/voting-blocked.png), check **Host voting-results request with app arguments succeeds** in [backend-results.json](e2e-evidence/2026-10-08/backend-results.json).

Suggested correction: propagate viewer identity and guest proof at this call, and surface the actual mapped error.

### E2E-03 — P1: A kicked player stays in a stale lobby

Affected: `convex/sessions.ts:425`, `convex/lib.ts:113`, `Core/Multiplayer/Services/RealtimeService.swift:59`, `Features/Multiplayer/Flow/MultiplayerLobbyView.swift:97`.

Reproduction: join a room from a second device, then remove that human from the host device. The host immediately shows four players instead of five. The removed device continues showing itself and five players, does not dismiss, and later marks the host offline. This persisted for more than 30 seconds.

The player subscription requires current membership. After deletion, the query throws **Caller is not in this session** instead of delivering the snapshot without the local player. The client's removal-diff callback therefore cannot set `wasKicked`; generic reconnect/resync attempts hit the same authorization error.

The existing unit removal tests feed synthetic snapshots and therefore miss this backend/subscription interaction.

Evidence: [kicked-player-stale-lobby.png](e2e-evidence/2026-10-08/kicked-player-stale-lobby.png). Suggested correction: provide a safe membership-status signal or handle a definitive membership rejection by clearing local membership and dismissing the session.

### E2E-04 — P1: Members can recover hidden roles through actions and tentative selections

Affected: `convex/lib.ts:268`, `convex/sessions.ts:741`, `convex/sessions.ts:796`, `convex/sessions.ts:965`, `convex/sessions.ts:992`.

Using a valid citizen's credentials, query `getAllActions` or `getActionsForPhase` during an active game. Responses include other players' `action_type`, `actor_player_id`, and `target_player_id`. A `mafia_target`, `doctor_protect`, or `inspector_check` identifies its actor's secret role. Both tentative-selection queries expose equivalent information.

The current filter removes only `inspector_result`; it leaves the identifying action and target fields intact. Player-role redaction is consequently bypassed through another API. Inspector-result redaction itself passed.

Evidence: checks **Citizen cannot infer secret role actors/targets from actions** and **Citizen cannot read Mafia tentative targets** in [backend-results.json](e2e-evidence/2026-10-08/backend-results.json).

Suggested correction: separate private actionable data from safe readiness summaries, with role-appropriate filters. Update the existing integration assertion that currently expects a citizen to receive a Mafia action.

### E2E-05 — P1: Public room queries expose private night history

Affected: `convex/sessions.ts:177`, `convex/sessions.ts:182`, `Core/Multiplayer/Store/MultiplayerGameStore.swift:2151`.

After recording a night, call `getSessionByRoomCode` with only the room code and no authentication. It returns the full session, including `night_history.mafia_target_id` and `doctor_protected_id`. The same unfiltered session shape can contain Mafia/inspector/doctor player numbers and inspection information recorded by the Swift host.

`getSessionById` also returns the raw document. Public room discovery needs a restricted projection; it must not expose the host's complete game record.

Evidence: **Public discovery does not expose secret night targets** in [backend-results.json](e2e-evidence/2026-10-08/backend-results.json). Suggested correction: expose minimal discovery metadata and authorize/filter full session history by viewer.

### E2E-06 — P1: Action submission validates ownership and round, but not game rules

Affected: `convex/sessions.ts:658`.

All these requests were accepted using the submitting player's own valid credentials and the current round:

- A citizen submits `inspector_check` against Mafia and receives an inspector result.
- A citizen submits a vote during night.
- An inspector submits an inspection during voting.
- A dead player submits a vote.
- A Mafia actor submits a nonexistent target UUID.
- An action uses `phase_index: 99` instead of the active index.

Ownership and stale-round rejection passed, but those checks do not prevent an authorized player from inventing an action they should not have. Wrong-role inspection is also a direct role-discovery bypass.

Evidence: corresponding rejection checks in [backend-results.json](e2e-evidence/2026-10-08/backend-results.json). Suggested correction: enforce session status, phase/index, actor life status, allowed role/action, and target eligibility server-side before computing a result or writing a row.

### E2E-07 — P1: A stale atomic night resolution can rewind the game

Affected: `convex/sessions.ts:364`.

Resolve night 0, advance the session to voting, then resend a night-0 `resolveNightAtomic` request with `next_phase: morning`. The mutation succeeds and changes the session back to morning.

The mutation is transactional, but has no expected round/phase/sequence guard. A delayed or retried host request can overwrite a later phase; a different stale elimination list can also apply more deaths.

Evidence: **Reject stale atomic night resolution after voting starts** in [backend-results.json](e2e-evidence/2026-10-08/backend-results.json). Suggested correction: make resolution conditional on the expected active round/phase and recognize an already resolved night idempotently.

### E2E-08 — P1: A lobby member can steal host ownership

Affected: `convex/sessions.ts:901`.

After a room returns to the lobby, a nonhost member calls `returnToLobby` with their own valid player/user IDs and sets `original_host_user_id` to their own user ID. The server accepts the request and assigns them host ownership, even while the genuine host remains in the room.

The purported original host is supplied by the caller and is not checked against trusted session state. The normal `updateSessionHost` endpoint correctly rejects takeover from a fresh host, but this path bypasses it.

Evidence: **Return-to-lobby cannot spoof original host to steal room** in [backend-results.json](e2e-evidence/2026-10-08/backend-results.json). Suggested correction: persist and check the original host server-side or use the guarded host-transfer policy.

### E2E-09 — P1: Rematch can erase an active game

Affected: `convex/sessions.ts:1049`.

With four ready players in a live night, the host calls `executeRematch`. It succeeds, returns the session to the lobby, clears roles/numbers/actions/history, and resets life/readiness state. No game-over check protects the operation.

Evidence: **Rematch cannot reset an active game** in [backend-results.json](e2e-evidence/2026-10-08/backend-results.json). Suggested correction: require the proper completed-game/rematch phase before any destructive reset.

### E2E-10 — P1: Guest merge creates duplicate stats and breaks future reads/writes

Affected: `convex/users.ts:219`, `convex/stats.ts:47`, `convex/stats.ts:160`.

Reproduction:

1. Record one game for player `QA Merge Collision` in an account.
2. Record another game under the same player name in a guest profile.
3. Merge that guest into the account with valid proof.
4. Read or upsert that player's stats.

Merge reports success but merely changes each guest row's `user_id`. The account now has two rows for the same `(user_id, player_name)`. The subsequent `.unique()` query throws **unique() query returned more than one result**. Counts were not combined into the expected two-game record.

Evidence: **Merge combines same-name player stats into one row** and **Merged stats remain readable and incrementable** in [account-results.json](e2e-evidence/2026-10-08/account-results.json). Suggested correction: merge counters transactionally by the account/player key and remove the duplicate source row.

### E2E-11 — P1: Guest upgrade strands active room ownership and membership

Affected: `convex/users.ts:220`, `convex/users.ts:234`, `convex/sessions.ts:129`.

Create a room as a guest, add that guest as its host player, then upgrade/merge into a Clerk account. The guest user is deleted, but `game_sessions.host_user_id` and `session_players.user_id` still reference the deleted guest UUID.

The account is not recognized as a member or host. Calling `leaveSession` as the upgraded account misleadingly succeeds without removing the old membership. Guest operations also cannot authenticate against the deleted user. A host upgrade can leave an unusable room.

Evidence: membership/owner IDs and **Merged room has no orphaned membership** in [account-results.json](e2e-evidence/2026-10-08/account-results.json). Suggested correction: transfer active room references in the merge transaction or explicitly disallow upgrade until the guest has safely left every room.

### E2E-12 — P2: Refresh/sign-in overwrites an edited display name

Affected: `convex/users.ts:30`, `convex/users.ts:39`, `Core/Auth/Services/AuthService.swift:27`, `Core/Auth/Services/AuthService.swift:279`.

Update the Convex profile display name to `QA Edited Account`, verify it was saved, then call `ensureUser` without `display_name` as restoration/sign-in does. The name reverts to the Clerk identity name.

`updateProfile` edits Convex, but `ensureUser` replaces an existing profile's name with the identity-derived default on each call. The app does not update Clerk's name alongside its Convex edit.

Evidence: **Account profile update persists** passed; **Account refresh preserves edited profile name** failed in [account-results.json](e2e-evidence/2026-10-08/account-results.json). Suggested correction: retain the existing saved name unless an explicit edit is supplied, or synchronize the two stores consistently.

### E2E-13 — P2: Invalid room codes expose SDK error text

Affected: `Features/Multiplayer/Entry/JoinGameView.swift`, `Core/Multiplayer/Store/MultiplayerGameStore.swift:3520`.

Enter `000000` and join. Instead of a friendly “Room not found” message, the UI displays `UniFFI.ClientError.ConvexError(data: "\"Game session not found\"")`.

Evidence: [invalid-room-error.png](e2e-evidence/2026-10-08/invalid-room-error.png). Suggested correction: map Convex's typed application errors instead of exposing `localizedDescription`/SDK debug representations.

### E2E-14 — P1: “End Game” leaves abandoned rooms active

Affected: `Features/Multiplayer/Flow/MultiplayerLobbyView.swift:330`, `convex/sessions.ts:129`, `convex/lib.ts:199`.

The UI confirmation says the game will end without a winner, but calls only `leaveSession`. When the last human leaves a bot room, there is no eligible host to transfer to and the server leaves the old host ID/status/phase intact.

After ending the tested bot game, room `521622` remained `in_progress` in `voting` with three bots, zero humans, and no host member. The earlier empty room remained `waiting` with zero players. The scripted last-human-departure test reproduced the same behavior.

Evidence: [abandoned-ui-rooms.json](e2e-evidence/2026-10-08/abandoned-ui-rooms.json), **Last human departure cancels bot-only room** in [backend-results.json](e2e-evidence/2026-10-08/backend-results.json). The two UI rooms were subsequently cancelled and their bots removed; see [ui-room-cleanup.json](e2e-evidence/2026-10-08/ui-room-cleanup.json).

Suggested correction: cancel the session when its last human leaves, and align the host's End Game action with the confirmation's promised behavior.

## Additional source-review findings

These are concrete code/configuration problems, but are distinguished from the runtime reproductions above.

### REVIEW-01 — P1: Release configuration points at development services

`Core/Backend/ConvexConfig.swift:4` hardcodes the development Convex URL; line 6 hardcodes a Clerk `pk_test_` key. No Release configuration selects production values. A release built from this branch therefore targets the development environment. Production deployment readiness was not tested or changed.

### REVIEW-02 — P2: Migration verification can both miss corruption and flag normal new data

`scripts/migration/verify.mjs:92` fetches sampled Supabase stats counts but does not compare them with Convex stats. It only logs whether a legacy user is unclaimed. The advertised child-row orphan check also never checks stats/config/group owner references. Equal global counts can therefore pass despite rows being assigned to the wrong users.

Conversely, `convex/migration.ts:220` counts all child rows, and `verify.mjs:76` compares those totals with the old database. Legitimate new Convex-only stats/groups make verification fail even if every legacy row is intact. This run's private snapshot contained 58 total stats but exactly 48 correct legacy stats, and 3 total groups but exactly 2 correct legacy groups.

The new read-only export comparison verifies every exported child's content and owner mapping and filters by legacy IDs. It passed. The original live verifier was blocked by source DNS, so its blind spots were established by source inspection, not by a successful live run.

### REVIEW-03 — P2: Guest → account login does not trigger the login sheet's dismissal condition

`Features/Auth/LoginView.swift:137` dismisses only when `authStore.isAuthenticated` changes to true. A guest is already authenticated, and `AuthStore.signIn` changes guest → account while that Boolean stays true. The success path should dismiss based on account identity/anonymous-state change or an explicit sign-in result. The UI attempt was obscured by iOS beta password prompts, so a clean visual reproduction of this specific dismissal issue remains outstanding.

## Limits and unresolved verification

- The migration's current live Supabase source could not be reached. Saved-export parity is proven; parity with today's source and an actual legacy user's Clerk claim/password transition are not.
- Normal multiplayer voting is blocked by E2E-02. Full UI game-over, stats, and rematch journeys could not be completed. Backend completed-state role reveal and lobby reset/action cleanup passed.
- Signup/password-reset were verified through the actual Swift service integration test and independently through native Clerk API requests. Fully automated completion of their visible forms was interrupted by iOS 27 beta AutoFill/password system sheets; this is not counted as an app bug.
- No physical-device, iPad, iOS 26 runtime, production deployment, prolonged flaky-network, deliberate offline-network, or multi-human (>2 devices) stress campaign was performed. Solo game restoration passed; this does not establish every offline or retry scenario.
- No issue was inferred solely from expected Clerk errors logged during sign-out/invalid-password tests. The unsigned-build Keychain failure (`-34018`) was a test setup issue and was resolved by a normal signed simulator build.
- Solo cloud stats displayed one game after completing one game and relaunching. Reopening the winner screen did not reproduce a duplicate-stat issue in this run; see [solo-stats.png](e2e-evidence/2026-10-08/solo-stats.png).

## Test data and cleanup

Scripted multiplayer rooms were cancelled and their human memberships removed; their saved stats/groups/config fixtures were deleted. UI-created rooms `521622` and `987744` were cancelled, and the three abandoned UI bots were removed. No legacy data was changed; the saved-export comparison found every legacy row intact.

QA guest profiles remain because there is no public guest-delete endpoint. Two isolated Clerk development accounts were created: `mafia-qa-1791472654898+clerk_test@example.com` and `mafia-native-100f44d5-a97d-4576-bb9f-d250cfd5aad5+clerk_test@example.com`. The native test signed out at completion; the API test session was revoked and its temporary credential/token files deleted. The accounts may be retained for follow-up or deleted from the development dashboard.

The merge test intentionally reproduced an orphaned guest-room membership (E2E-11). Its room/guest/account IDs are recorded in `account-results.json`; public cleanup cannot prove ownership after the guest was deleted. A temporary internal mutation restricted to that exact room, missing guest, and QA player removed the fixture successfully; see [orphan-fixture-cleanup.json](e2e-evidence/2026-10-08/orphan-fixture-cleanup.json). The cleanup function was then removed from both source and deployment. The saved UI QA group and solo QA stats were retained as UI evidence.

## Reproduction tooling

See [scripts/e2e/README.md](../scripts/e2e/README.md) for commands. Added [ClerkAccountIntegrationTests.swift](../mafia_managerTests/ClerkAccountIntegrationTests.swift) is opt-in to avoid creating accounts during ordinary test runs. Tuist regenerated the project to include it; `.pbxproj` was not edited manually.

Fix the voting, privacy/action-validation, membership, and merge problems before release. Retest the full multi-device game-over/rematch journey after those fixes, then repeat live source parity and production configuration checks.
