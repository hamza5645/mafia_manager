# AGENTS.md

This file provides guidance to Codex when working in this repository.

## Project Overview

**Mafia Manager** is an iOS game assistant for the party game Mafia.

Modes:
- **Solo mode**: pass-and-play on one device, fully offline.
- **Multiplayer mode**: multi-device gameplay with room codes, Convex realtime/database, and Clerk account auth.

Tech stack:
- SwiftUI + MVVM
- iOS 18+
- Tuist-managed Xcode project
- Convex backend functions and database
- Clerk auth for account users
- Convex guest profiles for quick-play guests

## Required Project Rules

1. **Always use Tuist for project changes.**
   - Edit `Project.swift` and `Tuist/Package.swift`.
   - Run `tuist install` after dependency changes.
   - Run `tuist generate` after project manifest changes.
   - Never modify `.pbxproj` directly.

2. **Do not resurrect removed legacy backend code.**
   - Active backend code should use Convex + Clerk.
   - Historical migration/audit docs may mention the previous backend, but app code should not.

3. **Preserve the two-phase (record, then resolve) pattern.**
   - Solo: `endNight()` records actions; `resolveNightOutcome()` applies outcomes.
   - Multiplayer: Convex computes every outcome. Night: the host calls `night:finishNight`, which runs the record step (`night:recordNightActions`) and then the resolve step (`night:resolveNightAtomic`) in one transaction; both steps stay callable on their own. Voting: `voting:closeVoting` → `voting:resolveVoteAtomic`. The host client only requests transitions (`phases:advancePhase`) and drives bots (`play:submitBotActions`, one call per pass).

4. **Keep solo and multiplayer state paths separate.**
   - Solo: `GameStore` + local JSON persistence.
   - Multiplayer: `MultiplayerGameStore` + Convex services.

5. **When finishing major changes, document what changed.**
   - Use or update `docs/SESSION_CHANGES.md`.
   - Include rollback notes and known gotchas.

6. **Linear issues are not marked done.**
   - If Linear is used, move completed work to in review.

## Build & Test Commands

```bash
tuist install
tuist generate
tuist build mafia_manager
tuist test mafia_manager --no-selective-testing
```

Backend (Convex functions run in-process with convex-test; nothing talks to a deployment):
```bash
npm ci
npm run test:backend        # tsc -p tests --noEmit (tests and scripts/e2e/*.mjs), then vitest
npx tsc --noEmit -p convex/tsconfig.json
```

Convex:
```bash
npx convex dev
npx convex dev --once
npm run convex:deploy                          # test:backend, then convex deploy, then the --prod contract check
node scripts/e2e/verify-deployment.mjs [--prod] # read-only: prints the URL it checks
```

`npx convex codegen` contacts the configured dev deployment (it downloads state and uploads function bundles for analysis). When you must not touch a deployment, hand-edit `convex/_generated/api.d.ts` instead.

Generated fixtures (a normal `vitest run` fails on drift; regenerate only for a deliberate change, then update the Swift side in the same change):
```bash
npx vitest run tests/convex/contract.test.ts -u      # tests/fixtures/contract/*.json → ContractFixtureDecodingTests
npx vitest run tests/convex/rules-parity.test.ts -u  # tests/fixtures/rules-parity.json → RulesParityTests, SoloRulesParityTests
```

Simulator helper (runs `tuist install` and `tuist generate`, builds the workspace with normal signing, boots the simulator if needed, installs and launches; prints the build log path on failure). Without a name it uses the first available iPhone simulator:
```bash
./scripts/run_ios_sim.sh ["iPhone 18 Pro"]
```

Tool versions: `mise.toml` pins Tuist 4.198.1 and Node 22.12 (`mise trust && mise install`). `Tuist.swift` accepts Xcode 27.x only. Swift packages are pinned exactly in `Tuist/Package.swift`; bump them deliberately and record the bump in `docs/SESSION_CHANGES.md`.

CI (`.github/workflows/ci.yml`):
- every pull request: `npm ci`, the Convex typecheck and `npm run test:backend` on Ubuntu;
- pull requests into `main` and manual runs: `tuist install`, `tuist generate` and `tuist test mafia_manager --no-selective-testing` on macOS.

Local maintenance:
- Keep clones and worktrees outside iCloud-synced folders such as `~/Documents` and `~/Desktop`. iCloud keeps conflict copies (`Foo 2.swift`) after large git operations or dependency re-checkouts, and Tuist's globs compile them, which breaks the build. If copies appear, delete them; do not add exclusion globs.
- If `tuist generate` fails with "Package.swift not found at path …/Vendor/clerk-convex-swift", the dependency cache predates the vendored bridge moving into the app target: run `rm -rf Tuist/.build && tuist install && tuist generate`.
- `buildServer.json` is machine-specific and untracked: `xcode-build-server config -workspace mafia_manager.xcworkspace -scheme mafia_manager`.
- `node scripts/clerk_cleanup_test_users.mjs` lists the Clerk dev users left by `ClerkAccountIntegrationTests` (`mafia-native-*+clerk_test@example.com`); `--delete` removes them. It reads `CLERK_SECRET_KEY` from the environment and refuses `sk_live_` keys.
- The Convex side of QA cleanup is the internal `testing:purgeQa` mutation. It deletes QA guests (names starting with `QA `) and `mafia-native-<uuid>+clerk_test@example.com` accounts with their seats, cancelled rooms, presence rows and stats. It runs only on a deployment with `MAFIA_ALLOW_QA_PURGE=1` (`npx convex env set MAFIA_ALLOW_QA_PURGE 1`, dev only, never production): run `npx convex run testing:purgeQa '{}'`, then repeat with the returned `cursor` until it is `null`.

## Architecture

### Solo Mode

`GameStore` is the single source of truth. Views call store methods and never mutate the solo state directly.

Critical files:
- `Core/Gameplay/Store/GameStore.swift`
- `Core/Gameplay/Models/GameState.swift`
- `Core/Gameplay/Models/NightAction.swift`
- `Core/Gameplay/Services/Persistence.swift`
- `Core/Gameplay/Services/StatsOutbox.swift`
- `Features/Night/NightWakeUpView.swift`
- `App/mafia_managerApp.swift`

Solo notes:
- Saves decode leniently (missing fields with defaults get the default). A save that still cannot be decoded is moved to `GameState.corrupt-<unix time>.json` and reported through `GameStore.persistenceError`, which `RootView` shows once. Saves are compact JSON, an unchanged state is not rewritten, and `Persistence.reset()` cancels the pending debounced save.
- At game end `GameStore` queues one entry per game (humans only; bots are left out) in `StatsOutbox` (`Application Support/.../StatsOutbox.json`, separate from the save, so Play Again cannot drop it). The outbox sends `stats:recordGame` on enqueue, on an identity change and on `.appDidBecomeActive`, removes an entry only after the server acknowledges it, and is cleared on sign-out. An entry queued while an account is signed in is sent only for that account; a game that ended as a guest or signed out goes to the next identity on the device, like the guest merge.
- The night's timed steps (Start Night, end of turn, bot wake-up and bot turns) are `.task(id:)` work owned by `NightWakeUpView`, so End Game cancels them. Bot and human turns share `finishTurn(_:)`, which keeps `endNight()` → `resolveNightOutcome()`. An all-bot Mafia waits for "Everyone Ready - Start Night". `endNight` and `resolveNightOutcome` do nothing once the game is over.
- `SoundManager.warmUp()` runs from the Start Night tap (not at launch); `play()` still warms up lazily, and an `AVAudioSession` interruption observer re-activates the session. Sounds are `.m4a`.

### Multiplayer Mode

`MultiplayerGameStore` holds four Convex snapshot subscriptions (`views:getSessionView`, `views:getPlayers`, `views:getRoundState`, `views:getHostPresence`) and assigns each value to store state; everything else is derived. The snapshot models are `Equatable`, and a value equal to the current one is not assigned, so an unchanged snapshot publishes nothing. Each subscription is supervised and resubscribed with backoff; a decode failure confirmed by one retry stops it and calls `BackendCompatibility.shared.markUpdateRequired()`. Mutations go through `SessionService` (behind the `SessionServicing` protocol).

Presence: `sessions:heartbeat` writes only the caller's `session_presence` row, never `session_players`, so a heartbeat does not re-run the roster and round queries. When the host heartbeats, the server also updates each seat's `is_online` (heartbeat within 20 s), writing only seats that changed. `views:getHostPresence` reads only the host's presence row; any member may call `sessions:claimHost` once the host is stale (90 s in the lobby, 15 s in a game), and the server installs the successor.

Client side of presence and host automation:
- A 5 s ticker heartbeats, checks the host and re-runs host automation, so bot and role-reveal retries do not depend on new snapshots.
- The host counts as offline when the server's age at receipt (`server_now - host_last_heartbeat`) plus local monotonic time since then passes `stale_after_seconds`. A missing host presence row counts as stale. Nothing is concluded while the socket is reconnecting or the server cannot identify me, and no device clock is compared with server times. After a resume, a reconnect or a sign-in recovery the local time counts from that moment, so time away is never read as host silence.
- On resume, an original host who is no longer host takes the lobby back with `sessions:returnToLobby` after the first successful heartbeat. On background the store sends one last heartbeat inside a background task. The screen stays awake only while a game is in progress.
- Bots: the host sends every pending bot action of a pass in one `play:submitBotActions` call. Item errors that mean the round closed (`NIGHT_CLOSED`, `MOVED_ON`, `WRONG_PHASE`, `NOT_ACTIVE`) end the round; other item errors retry on a later pass. Mafia bots wait for every living human Mafia, then back the human plurality (ties go to the leader named first). A rejected bot vote is planned again with the role rules; there is no random fallback.
- Timeouts: user taps wait `ConvexService.interactiveMutationTimeout` (12 s). Heartbeats and `claimHost` have the same limit, so a call that never returns cannot block the next; the store sends one heartbeat and one claim at a time without the tick waiting, so an outage queues one per limit, not one per tick. Create and join send with no limit, but the store stops the user's wait after 12 s ("Network error") and gives back a room or new seat that arrives after that or after a Cancel (a re-entered seat stays); a retry waits for that give-back and is dropped if it also runs out of time. Bot batches have no limit (a second batch could change a bot's target). Other timeouts read "Still sending", never "failed"; a Leave or End Game that times out still leaves (the Convex client sends it on reconnect). "Reconnecting…" shows after 3 failed retries, 2.5 s of socket reconnecting, or a tap sending for more than 5 s.

Server rules worth knowing:
- Mafia target: once a living human Mafia has named a target, only human rows decide; bot rows only break a tie among the human leaders, then the earliest human row wins. Without a human pick every row counts.
- At resolution, night picks and votes on a seat that is no longer alive (left or kicked) are ignored. A lone Mafia whose only target left kills nobody. A leave after the vote reveal still removes nobody.
- `submitAction`, `setTentativeSelection` and `submitBotActions` items with the same target as the stored row write nothing.

Data lifecycle: `convex/crons.ts` runs `cleanup:sweep` hourly (minute 17 UTC), 20 rooms per transaction. Lobbies and games with no presence heartbeat for 6 h are cancelled (rooms from before `session_presence` fall back to the seats' `last_heartbeat` or `joined_at`; `updated_at` is never used). Finished games lose seats, presence, actions and drafts 24 h after `completed_at`. Cancelled and finished rooms are deleted after 30 days, which frees their room codes. Guest user rows are not deleted.

Guest merge (`users:mergeGuestIntoAccount`): a seat conflict refuses the merge only for an `in_progress` room, and the message names the room code ("Leave your other seat in room … before saving guest progress."; Settings then offers Discard Guest Progress). In other rooms the seat used last (presence heartbeat) is kept and the other is deleted. Only waiting, in-progress, and finished-with-a-guest-seat rooms change host fields. The guest's `recorded_games` move to the account. `merged_guest_digests` keeps the last 20.

Multiplayer UI:
- The router passes phase payloads as `let` values and gives each round's screen `.id(nightIndex)` / `.id(dayIndex)`. Night and Voting treat a missing `myPlayer` as loading, never as eliminated.
- Night and voting no longer call `setReady`; readiness comes from action rows. Only role reveal uses `is_ready`. `setReady` carries the phase it was tapped in, and the server drops it in any other phase (a resend after a reconnect can arrive late); it writes only a change.
- The host sees a "Waiting for …" list with Remove on role reveal, night and voting, can start the night early after a confirmation, and has the room code in the in-game toolbar. Night finishes on its own for citizen and eliminated hosts; an alive Inspector host still taps Finish Night.
- Host phase buttons use `HostTransitionButton` / `HostTransition.errorMessage`: `MOVED_ON`, `NOT_ACTIVE` and `HOST_ONLY` count as success.
- Create and Join call `cancelPendingEntry()` on Cancel and on disappear; a create or join that returns after a cancel leaves the seat it created. A re-entry (`joinSession` returns `rejoined: true`) keeps its seat, and the next create or join waits until a cancelled entry's leave was sent.
- Online entry points are disabled while `BackendCompatibility.shared.updateRequired` is true.
- `GameModeSelectionView` has no `NavigationStack` of its own; it lives in `RootView`'s stack. Its auto-pushes use `navigationDestination(isPresented:)`, and it clears `GameStore.returnToSoloSetup` once used.

Critical files:
- `Core/Multiplayer/Store/MultiplayerGameStore.swift` - snapshot state, player actions
- `Core/Multiplayer/Store/MultiplayerGameStore+Connection.swift` - subscriptions, heartbeat, host-offline claim
- `Core/Multiplayer/Store/MultiplayerGameStore+HostPhases.swift` - host transition requests
- `Core/Multiplayer/Store/BotDirector.swift` - host-driven bot actions and votes
- `Core/Multiplayer/Services/SessionService.swift` - Convex mutations
- `Core/Multiplayer/Services/SubscriptionSupervisor.swift` - keeps one subscription alive
- `Core/Multiplayer/Models/` - `GameSession`, `SessionPlayer`, `GameAction`, `SessionSnapshots`
- `convex/schema.ts`, `convex/sessions.ts` (lobby, membership, host), `convex/phases.ts`, `convex/play.ts` (actions, bot batches, tentative selections), `convex/night.ts`, `convex/voting.ts`, `convex/views.ts` (subscription queries, with exact `returns` validators)
- `convex/cleanup.ts` + `convex/crons.ts` (room cleanup), `convex/testing.ts` (env-gated QA purge)
- `convex/lib/` - identity, guards, rules, transitions, presence, privacy projections, errors

Indexes: query actions and drafts with `by_unique_action` and `by_actor`, and library rows with `by_user_player`, `by_user_config_name` and `by_user_group_name` using an `eq` prefix. Removed in contract 5: `game_actions.by_session`, `by_session_round_type_phase` and `by_app_id`; `tentative_selections.by_session_phase_type` and `by_app_id`; `by_user` on `player_stats`, `custom_roles_configs` and `player_groups`; `users.by_app_id`; `session_players.by_app_id`. `game_sessions.by_status` is read by the cleanup cron and `session_players.by_session_player` by `guards.seatByPlayer`.

### Auth and Cloud Data

Auth/account state:
- `Core/Auth/Store/AuthStore.swift`
- `Core/Auth/Services/AuthService.swift`
- `Core/Auth/Models/UserProfile.swift`

Backend wiring:
- `Core/Backend/ConvexConfig.swift`
- `Core/Backend/ConvexService.swift`
- `Core/Backend/BackendError.swift`
- `Core/Backend/DatabaseService.swift`

Convex backend:
- `convex/auth.config.ts`
- `convex/users.ts`
- `convex/stats.ts`
- `convex/health.ts`

Backend client behaviour:
- `ConvexService.query` has a default 15 s limit (`timeout: nil` means none) and throws a network `BackendError` with `isTimeout` on timeout; cancelling the calling task ends the subscription. Mutations have no limit by default; interactive callers pass `ConvexService.interactiveMutationTimeout` (12 s). A timed-out mutation throws `BackendError.stillSending` with `isTimeout`, because it may still apply: never report it as failed or retry it blindly. `ConvexService.connectionState` comes from ConvexMobile's `watchWebSocketState()`.
- Mutation results cross the FFI boundary as JSON and are decoded on the main actor, because the app's `Decodable` conformances are main-actor-isolated (`SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`).
- API contract 5: `BackendCompatibility.checkOnce()` calls `health:check` once per launch, off the critical path, and blocks only online features, only when `ConvexConfig.apiContractVersion < min_client_contract`, never on an error or timeout. Keep the exact spelling `apiContractVersion = N`; `scripts/e2e/verify-deployment.mjs` reads it with a regex.
- Game stats go through `stats:recordGame` (idempotent per caller and `game_id`, `recorded_games` table). `stats:upsertPlayerStat` is kept for old builds only.

Auth notes:
- `AuthService.currentUser` does not refresh the Clerk client. A session Clerk finds later is adopted through `.sessionChanged` (`AuthServicing.accountSessionStarted`), merging a pending guest.
- `ensureValidSession` is single-flight. The launch restore and the resume token refresh are bounded by `AuthStore.restoreTimeout` (15 s); running out of time counts as a transient failure, retried on the next resume.
- The guest proof hash is cached after the first Keychain read. `identityRevision` changes only when the user id, anonymity or guest proof changes.
- Sign-out calls `StatsOutbox.shared.clear()`. A merge that fails on a seat conflict offers Discard Guest Progress in Settings (matched on `BackendError.mergeSeatConflictPrefix`).
- The vendored `ClerkConvexAuthProvider` pushes a refreshed token only when it changed (see `Vendor/clerk-convex-swift/VENDORED.md`).

App lifecycle: `.appWillEnterBackground` is posted only on `.background`, and `.appDidBecomeActive` only when returning from a real background. `.inactive` only saves. The audio-session reset runs on `.background`.

## Testing Notes

- Unit tests run in a bare host: `AppLauncher` (keyed only on `XCTestConfigurationFilePath`) launches an empty app, so no Clerk, Convex or solo save is touched at launch. Live suites create `ConvexService` and configure Clerk lazily.
- Seams: `MultiplayerGameStore(service:sleep:connectionState:)` with `FakeSessionService` and `ManualClock` (`mafia_managerTests/Multiplayer/MultiplayerFixtures.swift`); `GameStore(persistence:statsOutbox:notificationCenter:)` with `SoloTestEnvironment` (temporary directories, never the simulator's real save); `AuthStore` with `FakeAuthService` and `MemoryKeychain` (`AuthRegressionTests.swift`, also used by the multiplayer and outbox tests).
- Shared fixtures: `ContractFixtureDecodingTests` decodes every `tests/fixtures/contract/contract_*.json`; `RulesParityTests` and `SoloRulesParityTests` check `tests/fixtures/rules-parity.json` (role table, 144 target rules, 78 win cases, shared error strings).
- Live suites (opt-in, they talk to a deployment): `TEST_RUNNER_CONVEX_INTEGRATION=1` for `ConvexIntegrationTests`, plus `TEST_RUNNER_CLERK_ACCOUNT_E2E=1` for `ClerkAccountIntegrationTests`. In Debug builds `TEST_RUNNER_MAFIA_CONVEX_URL=<full http(s) URL>` points them at another backend (`ConvexConfig` reads `MAFIA_CONVEX_URL`; Release ignores it). They name every guest `QA …` so `testing:purgeQa` can clean up.
- UI automation uses explicit `automationID`s (`solo.setup.*`, `solo.roleReveal.*`, `intro_*_button`, `multiplayer.*`). The label-derived `ui.*` identifiers are gone.

## Backend Setup Notes

`Configuration/Debug.xcconfig` (Debug) and `Configuration/Production.xcconfig` (Release) must contain:
- Convex deployment host (`MAFIA_CONVEX_HOST`).
- Clerk publishable key (`MAFIA_CLERK_PUBLISHABLE_KEY`) and frontend host (`MAFIA_CLERK_FRONTEND_HOST`).

`Core/Backend/ConvexConfig.swift` reads them from Info.plist and stops the app if one is missing; Release also requires a `pk_live_` key.

The "Verify backend config" pre-build phase in `Project.swift` fails the build when a `MAFIA_*` value is empty. In Release it also requires a `pk_live_` Clerk key, a `.convex.cloud` host other than the Debug one, and a Clerk frontend host outside `.accounts.dev`. Local profiling builds that point Release at the dev backend pass `MAFIA_ALLOW_NONPROD_RELEASE=YES` to xcodebuild, for example `xcodebuild -configuration Release MAFIA_CONVEX_HOST=<dev host> MAFIA_ALLOW_NONPROD_RELEASE=YES …`. Never ship such a build. The launch-time check still requires a `pk_live_` key in Release, so these builds keep the production Clerk key and are used signed out.

`convex/auth.config.ts` reads the Clerk issuer/frontend API URL from the Convex `CLERK_FRONTEND_API_URL` environment variable.

Identity is derived on the server; no Convex function accepts a user id. A valid guest proof makes the caller that guest, otherwise the caller is the Clerk user (`identity.subject` → `users.auth_subject`). The guest proof is the sha256 hex of a Keychain secret, sent as `guest_secret_hash`, which `ConvexService` injects into every call. The server stores only `users.guest_secret_digest`, a sha256 of that value.

## Common Gotchas

- Convex Swift `ConvexEncodable` arguments must encode to raw JSON strings.
- Swift dates are encoded as seconds since Apple reference date; Convex timestamp helpers should match that for direct `Date` decoding.
- Role privacy must be enforced in Convex query results, not just hidden in SwiftUI.
- The server issues a new `current_round_id` for each night/voting phase; actions and the record/resolve mutations must carry the current one.
- Subscriptions emit full snapshots; a value equal to the current one is skipped, and everything else is assigned as-is. There is no polling.
- `views:*` declare exact `returns` validators, so a projection that drifts from them is a query error. Unknown keys and nulls in stored `v.any()` history rows are dropped.
- Every `ConvexError` is a short user-facing string; Swift shows it through `BackendError`.
- Host players can also have active roles and must still submit their night actions.
- Win rule (parity, the same in solo and multiplayer): Mafia win when living Mafia are at least the living non-Mafia, checked after every night and every vote; Citizens win when no Mafia are alive. A game where only bots are alive also ends (Citizens if no Mafia remain, else Mafia). `tests/fixtures/rules-parity.json` pins the role table, target rules, win cases and shared error strings for vitest and the Swift tests.
- Contract fixtures in `tests/fixtures/contract/` are real `views:*` and mutation results from convex-test; the test target bundles every `tests/fixtures/**/*.json` flat, so fixture file names must be unique.

## Documentation Index

- `docs/CLAUDE_PRIMER.md` - quick project overview.
- `docs/ARCHITECTURE_NOTES.md` - deeper architecture notes.
- `docs/MULTIPLAYER_GUIDE.md` - multiplayer backend and test guide.
- `docs/CLERK_SETUP.md` - required Clerk dashboard and config values.
- `docs/BACKEND_DECISIONS.md` - why Convex + Clerk, guest proof, legacy-account claiming.
