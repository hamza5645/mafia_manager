# Session Changes

## Authentication, realtime, and migration regression fixes

### What Changed

- Protected Convex profile, stats, setup-data, player, session, action, and
  tentative-selection APIs now require either a matching Clerk identity or the
  anonymous row's `guest_secret_hash`. Human actions require player ownership;
  bot actions require the proven session host. Sensitive action/readiness data
  requires proven session membership, while room-code discovery stays public.
- Clerk token refresh events now fetch the `convex` JWT template and retain the
  last valid Convex token if refresh fails. Verification-free signup performs
  the same Clerk/Convex synchronization as verified signup, and Clerk's typed
  existing-email error routes into the existing-account merge flow.
- Guest upgrades persist pending merge work and Keychain proof until the merge
  succeeds. Failed merges expose Retry saving progress and Finish later, and an
  active account retries pending work during session restoration.
- Realtime player snapshots emit removals before replacing their cache. Other
  players disappear immediately; local removal clears player/role/number state,
  stops the session connection, sets `isInSession = false`, and marks the kick.
- Migration parity now counts every row with `legacy_supabase_user_id`, including
  Clerk-claimed rows. `listLegacyOrphans` remains the unclaimed-user report only.

### Validation

- Added XCTest coverage for Clerk error/token handling, verification-free auth
  synchronization, pending merge persistence/retry/cleanup, snapshot insertion,
  update and one-shot deletion, and local/remote player removal behavior.
- `node --check scripts/migration/verify.mjs` passed.
- `npx convex codegen --dry-run --typecheck enable` passed after adding the
  standard Convex TypeScript configuration and development compiler dependency.
- `tuist generate` and `tuist build mafia_manager` passed.
- `tuist test mafia_manager` passed 30 local tests; 5 live Convex security and
  integration scenarios were skipped behind `CONVEX_INTEGRATION=1` as intended.

### Rollback

- Roll back the fixed app and Convex functions together. Revert the guest-proof
  arguments and strict guards only with the matching Swift service/realtime
  changes; reverting one side alone breaks guest multiplayer and cloud data.
- Pending merge state is backward-compatible local data. A rollback may leave
  the Keychain secret and pending anonymous ID in place; do not delete them
  unless guest data has been merged or intentionally abandoned.

### Guest API Compatibility

- Existing account clients remain compatible because Clerk calls omit the
  optional guest hash. Older guest clients do not send proof and cannot use the
  newly protected endpoints. Production Convex and the fixed app must therefore
  ship as a coordinated rollout; do not deploy this backend ahead of the app.

## Final pre-App-Store revision: auth-config hardening, build bump, ETL verification

### What Changed

- `convex/auth.config.ts` now throws at deploy time when `CLERK_FRONTEND_API_URL`
  is unset instead of silently degrading to `providers: []`. Previously a prod
  deploy without the env var would ship a backend where Clerk sign-in silently
  authenticates nobody; now `npx convex deploy` fails with instructions.
- Bumped `CURRENT_PROJECT_VERSION` 10 → 11 in `Project.swift`. Both branches sat
  at 5.0 (10); App Store Connect rejects an upload reusing the live build number.
  Bumping `MARKETING_VERSION` (5.0 → 5.1?) is a product call left to the owner.

### Validation

- `npx convex dev --once` green after the auth.config change (dev has the var set).
- Post-regenerate: 26 unit tests (4 gated skips) 0 failures; live integration
  tests 4/4 against dev; Release **device** build (`-destination generic/platform=iOS`,
  the archive path) succeeds.
- Release build for `generic/platform=iOS Simulator` fails to link **x86_64**:
  upstream `convex-swift` ships `libconvexmobile.a` with an arm64-only simulator
  slice. Irrelevant to App Store archives (device arm64) and Apple-Silicon
  simulators; only Release-config runs on Intel-Mac simulators are affected.
- ETL verified complete against the live legacy database: restored the paused
  Supabase project `mafia-manager` (it was INACTIVE — the shipped app's backend
  was down) and compared counts: 86 auth users / 48 player_stats / 6
  custom_roles_configs / 2 player_groups exactly match the
  `legacy_supabase_user_id`-tagged rows already ingested in the dev deployment;
  row-level spot check of the heaviest user matched field-for-field. The
  Supabase project was left ACTIVE so the legacy app keeps working during rollout.

### Known Gotchas

- `tuist test` uses selective testing: with unchanged inputs it regenerates a
  pruned "for testing" project whose scheme has **no test action**, breaking
  subsequent `xcodebuild test` until `tuist generate` runs again. Drive tests via
  `xcodebuild test` after a plain `tuist generate` when you need a real run.

## Migration production-readiness review: build fix, backend fixes, live integration tests

### What Changed

- Fixed the broken build under Xcode 27 beta: Tuist maps the `convex-swift` package's
  `ConvexMobile` target to a product named `ConvexMobileWrapper.framework` while the
  module inside stays `ConvexMobile`, so `import ConvexMobile` failed module resolution.
  Added a `PackageSettings.targetSettings` override in `Tuist/Package.swift` forcing
  `PRODUCT_NAME=ConvexMobile`.
- Restored host role visibility in `convex/lib.ts` (`visiblePlayerForViewer`). The
  prior authorization-hardening pass hid all roles from the host, but the host client
  is the authoritative game master: it drives bot actions (`processBotActions`),
  evaluates win conditions (`evaluateWinners` counts alive mafia), and records
  revealed death roles. With roles hidden, a non-mafia host ended every game as
  "citizens win" after the first night and role-holding bots never acted. This
  matches the Supabase `get_visible_role` contract on main.
- `sessions:returnToLobby` now deletes the previous game's `game_actions` and
  `tentative_selections` (parity with Supabase `reset_session_to_lobby`). Without
  this, a Play Again game shared `phase_index` values with stale rows, which leak
  into `checkNightPhaseReadiness` (loads actions without `round_id`) and bot
  coordination.
- `migration:countByTable` and `migration:listLegacyOrphans` are now
  `internalQuery`. `listLegacyOrphans` returned legacy users' emails to any
  unauthenticated client. The migration scripts use `setAdminAuth`, so they can
  still call internal functions.
- Added `mafia_managerTests/ConvexIntegrationTests.swift`: live integration tests
  against the dev deployment through the real client stack (ConvexMobile FFI,
  arg encoding, model/date decoding, reactive subscriptions). Skipped unless the
  runner env sets `CONVEX_INTEGRATION=1`
  (`TEST_RUNNER_CONVEX_INTEGRATION=1 xcodebuild test ...`).

### Validation

- `tuist build mafia_manager` succeeded (Xcode 27 beta).
- `tuist test mafia_manager`: 22 unit tests passed, 4 integration tests skipped by default.
- `TEST_RUNNER_CONVEX_INTEGRATION=1 xcodebuild test -only-testing:mafia_managerTests/ConvexIntegrationTests`:
  4/4 passed against dev (health, guest restore idempotency, full multiplayer
  lifecycle incl. stale-round rejection and `resolveNightAtomic`, live subscription
  delivering phase updates).
- Backend functional campaign over `mcp__convex__run` (15 scenario groups): role
  privacy per viewer, save-beats-kill, inspector mafia/not_mafia/blocked, stale
  round rejection, non-host resolve/kick/life-status rejections, host transfer on
  leave + heartbeat-guarded host claim, voting upsert + game over, returnToLobby
  reset with action cleanup, executeRematch, stats upsert increments, health checks.
- `npx convex dev --once` pushed all changes to the dev deployment.

### Rollback

- Revert `Tuist/Package.swift` (build fix), `convex/lib.ts`, `convex/sessions.ts`,
  `convex/migration.ts`, and delete `mafia_managerTests/ConvexIntegrationTests.swift`.

### Known Gotchas

- Xcode 27 beta replaced Simulator.app with DeviceHub and moved SimulatorKit to
  `Contents/SharedFrameworks`; simulator HID automation (idb/XcodeBuildMCP/Xcode
  device interaction) is currently broken, so UI-level E2E remains manual. A
  symlink was added at
  `Xcode-beta.app/Contents/Developer/Library/PrivateFrameworks/SimulatorKit.framework`
  to restore idb screenshots/accessibility (taps still no-op on this beta).
- The prod Convex deployment (`handsome-tiger-460`) has never been pushed and the
  app still hardcodes the dev URL + `pk_test_` Clerk key in `ConvexConfig.swift`.

## Multiplayer Convex authorization hardening

### What Changed

- Restricted exported Convex player insertion so direct human adds require the session host to add only themselves while the session is waiting, with duplicate and capacity checks preserved.
- Routed host kicks through the host-only `sessions:removePlayer` mutation for both human players and bots.
- Tightened lobby reset so `sessions:returnToLobby` verifies the caller owns the player record in the session and only resets after game over.
- Removed host status as a role/action visibility override so active host players do not receive secret roles or other inspectors' results before game over.

### Validation

- `tuist build mafia_manager` succeeded after the security fixes.
- `tuist test mafia_manager` succeeded with 22 tests and 0 failures.
- `npx convex dev --once` and local `convex codegen --dry-run --typecheck enable` could not run here because the Convex CLI attempted external network authorization/telemetry and network access was blocked.

### Rollback

- Revert the `convex/sessions.ts`, `convex/lib.ts`, and `Core/Multiplayer/Store/MultiplayerGameStore.swift` changes if this hardening must be backed out.

### Known Gotchas

- Guest quick-play still uses the existing asserted app user ID model; these fixes prevent the reviewed regressions without replacing guest identity verification.

## Backend migration: Convex + Clerk

### What Changed

- Replaced the active backend dependency and service layer with Convex + Clerk.
- Added Convex schema/functions for users, stats, saved setup data, multiplayer sessions, players, actions, tentative selections, and atomic night resolution.
- Replaced account auth with Clerk-backed `AuthService` while preserving guest quick-play through Convex guest profiles.
- Replaced multiplayer realtime with Convex reactive query subscriptions.
- Removed legacy backend setup SQL, obsolete auth workaround docs, and old Xcode mutation scripts.
- Updated active docs and privacy copy to describe Convex + Clerk.
- Configured Clerk with the real publishable key and Convex Frontend API URL for the dev deployment.

### Validation

- `npx convex env list` shows `CLERK_FRONTEND_API_URL=https://striking-elf-22.clerk.accounts.dev` on the dev deployment.
- `npx convex dev --once` succeeded with Clerk auth config.
- Convex MCP `health.js:check` returned `{ ok: true, backend: "convex", version: "convex-clerk-v1" }`.
- `tuist generate` succeeded after the Tuist dependency/project changes.
- `tuist build mafia_manager` succeeded.
- `tuist xcodebuild test -workspace mafia_manager.xcworkspace -scheme mafia_manager -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` succeeded with 22 tests and 0 failures.

### Rollback

- Reverting this migration requires restoring the deleted legacy backend files, the previous Swift service implementations, and the previous Tuist dependency graph.
- Do not attempt rollback by hand-editing `.pbxproj`; use Tuist manifests and regenerate.

### Known Gotchas

- Account auth now initializes against Clerk project `striking-elf-22`.
- Guest multiplayer role visibility depends on passing the current Convex app user ID to `sessions:getSessionPlayers`.

## MM-17: Solo vote elimination reveal

### What Changed

- Added a new solo `voteDeathReveal` phase so daytime eliminations pause on a reveal screen instead of jumping straight from vote results into the next night.
- Updated `GameStore.applyVotingResult()` to route actual vote eliminations through that reveal phase while keeping tie/no-elimination days on the existing direct-to-night path.
- Reused `DeathRevealView` for both night kills and vote eliminations with context-specific copy and continue behavior.
- Updated `VoteResultsView` so the primary button reflects the new reveal step when a player was actually eliminated.
- Added `GameStore` regression tests for:
  - vote elimination entering the reveal phase,
  - continuing from that reveal into the next night,
  - continuing from that reveal into game over when the final mafia is voted out.

### Validation

- Xcode project build succeeded after the phase-routing and UI changes.
- CLI `xcodebuild test` and Xcode-hosted targeted test execution both stalled in this session before producing a usable XCTest summary, so the new tests were added but not fully observed completing here.

### Rollback

- Revert the `voteDeathReveal` phase and restore the old `applyVotingResult()` behavior if you want vote results to advance directly into the next night again.

### Known Gotchas

- `DeathRevealView` now serves two solo contexts. If you change its copy or continue action later, verify both night deaths and vote eliminations still route correctly.

## MM-02: Persist multiplayer doctor saves across two-phase resolution

### What Changed

- Added `target_was_saved` to multiplayer `night_history` records so phase 1 persists the authoritative doctor-save verdict.
- Updated `MultiplayerGameStore.recordNightActions()` to store that verdict and bias `doctorProtectedId` toward the mafia target whenever any doctor actually saved them.
- Updated `MultiplayerGameStore.resolveNightOutcome()` so phase 2 resolves from the stored verdict instead of recomputing from `doctorProtectedId`.
- Added a compatibility fallback for unresolved legacy records: if `target_was_saved` is missing and the session is still on that active night, the host re-reads doctor actions for the current round before falling back to `doctorProtectedId == mafiaTargetId`.
- Updated multiplayer summaries to use `target_was_saved` when available so saved nights are reported consistently.

### Validation

- Built the multiplayer resolution path around the persisted phase-1 verdict to remove the split-doctor mismatch identified in MM-02.
- Planned manual verification for split protections, no-save nights, unanimous-save nights, and unresolved legacy records that predate `target_was_saved`.

### Rollback

- Revert the `NightActionRecord` schema addition and restore the old `resolveNightOutcome(nightIndex:targetWasSaved:)` call path if you intentionally want phase 2 to recompute saves from the summarized doctor target again.

### Known Gotchas

- This is fix-forward for new records plus unresolved legacy nights. Already-resolved historical rows that only stored a non-saving `doctorProtectedId` cannot be reconstructed after the fact.

## MM-01: `resolve_night_atomic()` snake_case fix

### What Changed

- Patched `public.resolve_night_atomic()` in `supabase/multiplayer_schema.sql` to read `night_index` first and tolerate legacy `nightIndex` only as a fallback.
- Added migration `supabase/migrations/20260321110000_fix_resolve_night_atomic_json_keys.sql` so existing Supabase projects can deploy the RPC fix without re-running the full schema.
- Hardened the RPC so malformed night payloads raise an error instead of silently nulling `night_index` and collapsing `night_history`.

### Validation

- Confirmed the Swift multiplayer payload already encodes snake_case keys, so no app-facing contract changes were required.
- Verified against the connected Supabase project that the pre-fix live RPC still used camelCase lookups and matched the audit's live data anomaly counts.
- Planned SQL verification after migration application to confirm prior `night_history` rows are preserved and `removal_note` receives a real night number.

### Rollback

- Re-apply the previous function body if you intentionally need the old behavior, though it will reintroduce history corruption for snake_case payloads.

### Known Gotchas

- MM-01 is fix-forward only. Sessions whose `night_history` was already collapsed before this patch are not reconstructed by this change.

## What Changed

- Reorganized the app entry point into `App/mafia_managerApp.swift`.
- Reworked `Core/` into domain folders:
  - `Core/Auth/`
  - `Core/Backend/`
  - `Core/Gameplay/`
  - `Core/Multiplayer/`
  - `Core/Stats/`
  - `Core/Support/`
- Split multiplayer views into clearer flow buckets:
  - `Features/Multiplayer/Entry/`
  - `Features/Multiplayer/Flow/`
- Moved the non-project `SupabaseConfig.swift.template` into `Core/Backend/`.
- Updated `AGENTS.md`, `docs/CLAUDE_PRIMER.md`, and `docs/ARCHITECTURE_NOTES.md` to match the new paths.

## Why

- The previous layout mixed technical buckets (`Models`, `Services`, `Store`) with feature-specific code, which made multiplayer/auth/stats ownership harder to follow.
- Several Xcode navigator entries were effectively stale or duplicated after earlier iterations. Moving files through Xcode-safe project operations normalized the navigator and kept the project buildable.
- Multiplayer screens were all flat in one folder; splitting entry vs in-game flow makes future changes less error-prone.

## Validation

- Rebuilt the project through Xcode after the moves.
- Result: successful build with the reorganized structure.

## Rollback

- To revert the structure, move files back to their previous paths using Xcode project moves, not raw `.pbxproj` edits.
- If you want a full rollback with Git, revert this changeset rather than manually dragging files around in Finder.
- If a future move affects target membership or file references, validate with an Xcode build immediately after the move batch.

## Known Gotchas

- This project’s Xcode navigator had path drift before the cleanup. Use Xcode-aware moves for source files so the project file stays consistent.
- The repo still contains a duplicate on-disk `mafia_manager/Assets.xcassets` folder that was not touched in this session because the active target is already building successfully and that asset cleanup should be done as a separate verification pass.

## Audio preloading via SoundManager

### What Changed

- Created `Core/Gameplay/Services/SoundManager.swift` — a `@MainActor` singleton that preloads all 4 `.wav` sound files (`mafia_gunshot`, `police_siren`, `doctor_ecg`, `wakeup_rooster`) at startup via an explicit `warmUp()` call.
- `warmUp()` is called from `App/mafia_managerApp.swift` `.onAppear`, well before any sound is needed. Guarded by `hasWarmedUp` flag so repeat calls are free.
- Audio session is re-configured defensively before each playback (`ensureAudioSession()`), with a cheap early-return when already active. Handles session deactivation after backgrounding.
- Each sound file is preloaded independently — one missing/corrupt file does not break the others.
- Removed all inline audio code from `NightWakeUpView.swift` (~45 lines) and `MorningSummaryView.swift` (~30 lines). Both now delegate to `SoundManager.shared`.
- Removed duplicate `configureAudioSessionIfNeeded()` implementations from both views.
- Added `SoundManager.shared.handleBackgrounding()` to the app's background lifecycle handler.

### Why

- Instruments Time Profiler showed `AVAudioPlayer.__allocating_init(contentsOf:)` costing 84ms+ on the main thread at each play site. Preloading eliminates this hitch entirely.
- Audio code was duplicated across two views with no shared service.

### Validation

- Build succeeds (`Cmd+B`).
- Solo night flow: mafia gunshot plays after 2s "Start Night" delay, inspector siren on inspector wake, doctor ECG on doctor wake — no perceptible delay.
- Morning summary: rooster plays on appear.
- Background/foreground: sounds still play after returning from background.

### Rollback

- Delete `Core/Gameplay/Services/SoundManager.swift`, revert `NightWakeUpView.swift`, `MorningSummaryView.swift`, and `App/mafia_managerApp.swift` to restore inline audio code.

### Known Gotchas

- `SoundManager.swift` must be added to the Xcode project manually (not auto-added via .pbxproj edit).
- `MultiplayerVoteDeathRevealView.swift` uses `AudioServicesPlaySystemSound(1057)` — different mechanism, intentionally not touched.
- Persistence main-thread work (`GameStore` → `Persistence.save`) is a separate perf concern for a future pass.

## MM-04 through MM-16 remediation pass

### What Changed

- Fixed solo rules regressions:
  - Mafia now wins at parity after night resolution.
  - Tied day votes now record a no-elimination day, increment `dayIndex`, and re-run winner evaluation.
  - Solo inspector-on-inspector checks no longer leak a role through the UI.
  - Morning summary no longer labels the first night as “Night 2”.
- Fixed multiplayer app-side issues:
  - Voting readiness now keys off actual submitted votes instead of `isReady`.
  - Night death reveal now stores explicit revealed death roles instead of inferring from who submitted actions.
  - Game-over UI now falls back to `currentPhaseData` for winner rendering.
  - Entering `game_over` now forces a player snapshot refresh so newly visible roles can appear once the backend allows them.
  - Inspector UI now only shows `mafia`, `not_mafia`, or `blocked`.
- Fixed schema/migration drift in repo:
  - Added checked-in definitions/migrations for `add_session_player` and `reset_players_ready`.
  - Normalized `submit_game_action` inspector results.
  - Extended `resolve_night_atomic` so game-over winner fields are written atomically with the phase transition.
  - Fixed optional performance RPCs so `batch_assign_roles` accepts real JSONB payloads and no longer writes a nonexistent `updated_at` column.
- Re-enabled the automated test path:
  - Added a real `mafia_managerTests` target to the Xcode project.
  - Added the test target to the shared scheme.
  - Added a regression test covering tied-vote day advancement.
- Updated docs:
  - Multiplayer guide no longer claims `phase_timers` exists.
  - Architecture notes now describe the corrected inspector behavior.
  - Audit statuses now distinguish repo fixes from still-pending live Supabase deployment.

### Validation

- Xcode build succeeded after the changes.
- `xcodebuild -project mafia_manager.xcodeproj -scheme mafia_manager -destination "platform=iOS Simulator,name=iPhone 17 Pro" test` now succeeds with 17 passing tests.
- Live Supabase inspection confirmed the deployed DB is still on the old function bodies for `get_visible_role`, round-aware `submit_game_action`, `resolve_night_atomic`, and `batch_assign_roles`.
- Attempting to apply the new DB migrations through the Supabase MCP failed because the connected project is exposed in read-only mode in this session.

### Rollback

- Revert the app/code changes if you want to restore the audited behavior, though that will reintroduce the bugs documented in `docs/AUDIT_2026-03-20.md`.
- Revert the Xcode project changes if you intentionally want to disable the test target again.
- Revert the new Supabase migration files if you do not want the backend contract upgrades queued for deployment.

### Known Gotchas

- The repo is fixed; the deployed Supabase project is not fully fixed until the new migrations are applied with write access.
- `submit_game_action` is overloaded in the live DB, and the round-aware overload used by the app is still the old leaking version until deployment happens.
