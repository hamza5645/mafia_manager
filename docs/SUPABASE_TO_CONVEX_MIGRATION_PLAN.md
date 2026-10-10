# Supabase to Convex Migration Plan

Date: 2026-05-06 (last reconciled 2026-05-07)

This document is the working plan for moving Mafia Manager's entire backend surface off Supabase and onto Convex. It is based on a codebase audit, local Supabase SQL files, live Supabase MCP metadata, live Convex MCP metadata, and current Convex documentation.

## Current Implementation Status (2026-05-07)

Most of this plan has shipped on the `AWS` branch as uncommitted working-tree changes. Where the plan and reality diverge, **reality is authoritative**. Specifically:

- **Schema**: Implemented with snake_case fields (`auth_subject`, `user_id`, `room_code`) and app-generated UUID `id: v.string()` keys, NOT camelCase or Convex `Id<"users">`. See `convex/schema.ts`.
- **Auth provider**: Clerk, wired through `clerk-convex-swift` 0.1.0. `convex/auth.config.ts` is env-driven (reads `CLERK_FRONTEND_API_URL`) — silently degrades to `providers: []` if unset.
- **Timestamps**: server-side helper is `nowAppleEpochSeconds()` in `convex/lib.ts`, returning seconds-since-2001-01-01 (Apple/NSDate epoch). Swift decodes via `Date(timeIntervalSinceReferenceDate:)`.
- **Auth identity checks**: tolerant pattern. Mutations call `requireSessionHostIfAuthenticated` / `requirePlayerOwnerIfAuthenticated` / `requireActionActorIfAuthenticated` — strict for Clerk-authenticated callers, no-op for guest callers (since guests have no Clerk identity). Strictly improves on the prior "no checks at all" state without breaking guest multiplayer.
- **Data migration**: ETL implemented in `convex/migration.ts` and `scripts/migration/{export,ingest,verify}.mjs`. Adds `legacy_supabase_user_id` and `email` to `users`, plus `legacy_supabase_id`/`legacy_supabase_user_id` to child tables, all with backing indexes. `users.ensureUser` claims an unclaimed legacy row by email on first Clerk sign-in.
- **Phase status**: Phases 0, 1, 2, 3, 4, 5 are essentially complete in the working tree. Phase 6 (data migration) requires running the ETL scripts with a Supabase service-role key. Phase 7 (Supabase removal) is complete (zero `Supabase` references in `*.swift`).

The remaining phases below are kept as historical context. Use the current state of `convex/`, `Core/Backend/`, `Core/Auth/`, and `Core/Multiplayer/` as the authoritative description of the system.

## Executive Summary

The migration should be treated as a backend replacement, not a database rename.

Supabase currently provides all of these backend capabilities:

- Auth: email/password, anonymous guest sign-in, session restore, password reset, anonymous-to-permanent account upgrade, profile creation trigger.
- Database CRUD: profiles, player stats, saved custom role configs, saved player groups.
- Multiplayer database state: sessions, players, actions, history, room codes, phase data, heartbeats.
- Realtime: Postgres change feeds for `game_sessions`, `session_players`, and `game_actions`, plus broadcast events for tentative selections.
- Server-side authority: Postgres RPCs for room codes, adding players, role visibility, action submission, batch role assignment, ready resets, host transfer, play-again reset, and atomic night resolution.
- Security model: RLS policies, helper functions, a role-filtered view, and `SECURITY DEFINER` RPCs.

Convex is a good technical fit for the game-state and realtime portions because:

- Convex queries are reactive and can replace Supabase table subscriptions with client subscriptions to query results.
- Convex mutations are server-side transactional functions, which maps well to host-authoritative phase changes and the current `resolve_night_atomic` RPC.
- Convex can consolidate scattered SQL RPCs into TypeScript mutations with explicit validators and shared game rules.

**Auth provider: Clerk.** Clerk has an official Convex Swift bridge (`clerk-convex-swift`), prebuilt SwiftUI sign-in views, native Sign in with Apple via ID token, email/password with password reset, and a free tier (10K MAU) that covers all foreseeable usage. See "Auth: Clerk + Convex" below for the full setup. Alternatives considered (Auth0, Sign in with Apple alone, Convex guest-only) are documented but not chosen.

Migration phasing:

- **Phase 1: Ship Clerk + Convex foundation.** All later phases need a stable user ID. Server-side identity (`ctx.auth.getUserIdentity()`) is required before any user-scoped writes can be authorized; without it, stats, configs, and groups cannot be written. Auth-first avoids that block.
- **Phase 2: Replace stats/custom-role/player-group storage.** Low-risk CRUD, validates Swift-to-Convex plumbing on real user-scoped data.
- **Phase 3: Replace Supabase multiplayer** (read model first, then mutations).
- **Phase 4: Remove Supabase dependency, config files, SQL docs, and Supabase-specific workarounds.**

Do not start by deleting Supabase. Build Convex in parallel behind a backend abstraction and a feature flag, then flip features to Convex after simulator/device testing with multiple clients.

For an even leaner path that drops data migration entirely, see "Alternative: Minimal Scope Path" below.

## Sources Checked

Local repo:

- `Project.swift`
- `Tuist/Package.swift`
- `Core/Backend/SupabaseService.swift`
- `Core/Backend/SupabaseConfig.swift`
- `Core/Backend/DatabaseService.swift`
- `Core/Auth/Services/AuthService.swift`
- `Core/Auth/Store/AuthStore.swift`
- `Core/Auth/Models/UserProfile.swift`
- `Core/Stats/Models/PlayerStats.swift`
- `Core/Stats/Models/CustomRoleConfig.swift`
- `Core/Stats/Models/PlayerGroup.swift`
- `Core/Gameplay/Store/GameStore.swift`
- `Core/Multiplayer/Models/GameSession.swift`
- `Core/Multiplayer/Models/SessionPlayer.swift`
- `Core/Multiplayer/Models/GameAction.swift`
- `Core/Multiplayer/Services/SessionService.swift`
- `Core/Multiplayer/Services/RealtimeService.swift`
- `Core/Multiplayer/Services/RealtimeEventProcessor.swift`
- `Core/Multiplayer/Store/MultiplayerGameStore.swift`
- `supabase/setup.sql`
- `supabase/multiplayer_schema.sql`
- `supabase/migrations/*.sql`
- `supabase/performance_migrations.sql`
- `convex/schema.ts`
- `.mcp.json`
- `package.json`

MCP:

- Supabase MCP `list_edge_functions`
- Supabase MCP `list_tables`
- Supabase MCP `execute_sql` for policies, functions, triggers, views, and Realtime publication membership
- Convex MCP `status`
- Convex MCP `tables`
- Convex MCP `functionSpec`

Official docs:

- Convex Swift client docs: https://docs.convex.dev/client/swift
- Convex auth docs: https://docs.convex.dev/auth
- Convex functions docs: https://docs.convex.dev/functions
- Convex database schemas/docs: https://docs.convex.dev/database/schemas
- Convex indexes docs: https://docs.convex.dev/database/reading-data/indexes
- Convex mutations docs: https://docs.convex.dev/functions/mutation-functions
- Convex scheduling docs: https://docs.convex.dev/scheduling
- Convex MCP docs: https://docs.convex.dev/ai/convex-mcp-server

## Current Backend Inventory

### Project and Dependency Setup

The iOS project is Tuist-managed.

- Supabase is declared in `Tuist/Package.swift`:
  - `.package(url: "https://github.com/supabase/supabase-swift", from: "2.5.1")`
- The app target depends on `.external(name: "Supabase")` in `Project.swift`.
- Do not edit `.pbxproj` directly. Any dependency changes must go through Tuist manifests, followed by Tuist generation.

The Convex backend scaffold exists:

- `package.json` includes `convex` and scripts:
  - `npm run convex:dev`
  - `npm run convex:deploy`
- `convex/schema.ts` is currently empty:
  - `export default defineSchema({});`
- Convex generated files exist under `convex/_generated/`.
- `.env.local` was created by `npx convex dev` and must remain uncommitted.

MCP state:

- Supabase MCP is connected.
- Supabase Edge Functions list is empty.
- Convex MCP is connected.
- Convex dev deployment:
  - URL: `https://energized-herring-345.eu-west-1.convex.cloud`
  - Dashboard: `https://dashboard.convex.dev/d/energized-herring-345`
- Convex prod deployment exists and is read-only through MCP:
  - URL: `https://handsome-tiger-460.eu-west-1.convex.cloud`
  - Dashboard: `https://dashboard.convex.dev/d/handsome-tiger-460`
- Convex currently has no tables and no public functions.

### Supabase Config

Files:

- `Core/Backend/SupabaseService.swift`
- `Core/Backend/SupabaseConfig.swift`
- `Core/Backend/SupabaseConfig.swift.template`

Current behavior:

- `SupabaseService` is a `@MainActor` singleton.
- It creates a `SupabaseClient` from `SupabaseConfig.supabaseURL` and `SupabaseConfig.supabaseAnonKey`.
- `SupabaseConfig.swift` currently contains a project URL and anon key but is in `.gitignore`.
- Many services directly reference `SupabaseService.shared.client`.

Migration implication:

- Replace `SupabaseService` with `ConvexService` or a protocol-backed backend provider.
- Avoid rewriting every call site in one pass. Add service protocols first, then replace implementations one capability at a time.
- Eventually delete `SupabaseConfig.swift.template` or replace it with a Convex/Auth config template.

### Auth Surface

Files:

- `Core/Auth/Services/AuthService.swift`
- `Core/Auth/Store/AuthStore.swift`
- `Core/Auth/Models/UserProfile.swift`
- `Features/Auth/LoginView.swift`
- `Features/Auth/SignupView.swift`
- `Features/Auth/ProfileView.swift`
- `Features/Auth/GuestNameInputView.swift`
- `Features/Auth/QuickStartSheet.swift`
- `Features/Multiplayer/Entry/CreateGameView.swift`
- `Features/Multiplayer/Entry/JoinGameView.swift`
- `Features/Multiplayer/Entry/GameModeSelectionView.swift`
- `Features/Settings/SettingsView.swift`

Current auth features:

- Email/password sign up.
- Email/password sign in.
- Password reset.
- Anonymous guest sign-in.
- Link email/password to an anonymous account.
- Merge anonymous stats into an existing account.
- Auth state listener via Supabase `authStateChanges`.
- Session restore using saved access and refresh tokens.
- Tokens stored in Keychain.
- Guest display name stored in UserDefaults.
- Profile rows are created by a Supabase trigger.
- `AuthStore` exposes:
  - `isAuthenticated`
  - `currentUserId`
  - `userProfile`
  - `isLoading`
  - `errorMessage`
  - `isRestoringSession`
  - `accessToken`
  - `refreshToken`
  - `isAnonymous`
  - `guestDisplayName`

Supabase-specific auth workarounds:

- Manual `setSession` after sign-in and anonymous sign-in.
- Keychain migration from previous UserDefaults token storage.
- Supabase-specific error parsing in `extractSupabaseMessage`.
- Supabase email-confirmation-specific user messages.
- Manual `Authorization` header workaround in some `DatabaseService` calls.

Migration implication:

- `AuthStore` can remain the UI-facing facade, but `AuthService` must be replaced.
- The app needs a new stable identity source before multiplayer can be secure.
- Current user IDs are Supabase Auth UUIDs. Convex document IDs are different. Preserve old UUIDs as `legacy_supabase_user_id` during migration if user data is imported.

### Stats and Saved Setup Data

Files:

- `Core/Backend/DatabaseService.swift`
- `Core/Stats/Models/PlayerStats.swift`
- `Core/Stats/Models/CustomRoleConfig.swift`
- `Core/Stats/Models/PlayerGroup.swift`
- `Features/Stats/PlayerStatsView.swift`
- `Features/Stats/CustomRolesView.swift`
- `Features/Stats/PlayerGroupsView.swift`
- `Features/Setup/SetupView.swift`
- `Core/Gameplay/Store/GameStore.swift`

Supabase tables:

- `profiles`
- `player_stats`
- `custom_roles_configs`
- `player_groups`

Live Supabase row counts from MCP:

- `profiles`: 85 rows
- `player_stats`: 48 rows
- `custom_roles_configs`: 6 rows
- `player_groups`: 2 rows

Current CRUD:

- `DatabaseService.getPlayerStats(userId:)`
- `DatabaseService.getPlayerStat(userId:playerName:)`
- `DatabaseService.createPlayerStat(_:)`
- `DatabaseService.updatePlayerStat(_:)`
- `DatabaseService.deletePlayerStat(id:)`
- `DatabaseService.upsertPlayerStat(userId:playerName:role:won:kills:)`
- `DatabaseService.getCustomRoleConfigs(userId:)`
- `DatabaseService.getCustomRoleConfig(id:)`
- `DatabaseService.createCustomRoleConfig(_:)`
- `DatabaseService.updateCustomRoleConfig(_:)`
- `DatabaseService.deleteCustomRoleConfig(id:)`
- `DatabaseService.getPlayerGroups(userId:)`
- `DatabaseService.getPlayerGroup(id:)`
- `DatabaseService.createPlayerGroup(_:)`
- `DatabaseService.updatePlayerGroup(_:)`
- `DatabaseService.deletePlayerGroup(id:)`

Cloud stats sync:

- `GameOverView.task` calls `GameStore.syncPlayerStatsToCloud()`.
- `syncPlayerStatsToCloud()` only runs when:
  - user is authenticated,
  - game is over,
  - a winner exists.
- Kills are credited by scanning resolved night history and alive mafia IDs.
- Stats are upserted per player name.

Migration implication:

- This is the easiest backend slice to move after auth identity is available.
- Convex should implement this as user-scoped tables plus mutations that enforce identity server-side.
- `upsertPlayerStat` should become a Convex mutation to avoid a client-side read-then-write race.

### Multiplayer Backend Surface

Files:

- `Core/Multiplayer/Models/GameSession.swift`
- `Core/Multiplayer/Models/SessionPlayer.swift`
- `Core/Multiplayer/Models/GameAction.swift`
- `Core/Multiplayer/Services/SessionService.swift`
- `Core/Multiplayer/Services/RealtimeService.swift`
- `Core/Multiplayer/Services/RealtimeEventProcessor.swift`
- `Core/Multiplayer/Store/MultiplayerGameStore.swift`
- `Features/Multiplayer/Entry/*`
- `Features/Multiplayer/Flow/*`

Supabase tables:

- `game_sessions`
- `session_players`
- `game_actions`

Live Supabase row counts from MCP:

- `game_sessions`: 259 rows
- `session_players`: 1539 rows
- `game_actions`: 1523 rows

Supabase Realtime publication:

- `game_sessions`
- `session_players`
- `game_actions`

No `phase_timers` table currently exists in the live schema or active code. Older docs mention it, but current multiplayer flow is driven by host logic, readiness, action submissions, heartbeats, reconnect checks, and manual phase advancement.

Current multiplayer model:

- `GameSession`
  - `roomCode`
  - `hostUserId`
  - `status`
  - `maxPlayers`
  - `botCount`
  - `currentPhase`
  - `currentPhaseData`
  - `dayIndex`
  - `isGameOver`
  - `winner`
  - `assignedNumbers`
  - `nightHistory`
  - `dayHistory`
  - `currentRoundId`
  - `rematchDeadline`
  - `phaseSequence`
  - timestamps
- `SessionPlayer`
  - `sessionId`
  - `userId`
  - `playerId`
  - `playerName`
  - `playerNumber`
  - `role`
  - `isBot`
  - `isAlive`
  - `isOnline`
  - `isReady`
  - `lastHeartbeat`
  - `joinedAt`
  - `removalNote`
- `GameAction`
  - `sessionId`
  - `roundId`
  - `actionType`
  - `phaseIndex`
  - `actorPlayerId`
  - `targetPlayerId`
  - `actionData`
  - `createdAt`

Current multiplayer flow:

1. Create session:
   - Host must have an auth session.
   - Supabase RPC `generate_room_code` creates a 6-digit room code.
   - Client inserts a `game_sessions` row.
   - Client adds host as `session_players` row through `add_session_player`.
   - Host adds bots through the same RPC.
2. Join session:
   - Client queries `game_sessions` by room code and `status = waiting`.
   - Client checks capacity and duplicates.
   - Client calls `add_session_player`.
3. Subscribe:
   - `RealtimeService.subscribeToSession` creates channel `session:<sessionId>`.
   - It subscribes to Postgres changes on `game_sessions`, `session_players`, `game_actions`.
   - It subscribes to broadcasts for `tentative_selection`.
   - It runs events through `RealtimeEventProcessor` to preserve FIFO event handling.
4. Heartbeat:
   - Every 5 seconds, player updates `session_players.last_heartbeat` and `is_online`.
   - Non-hosts monitor host heartbeat.
   - If host is stale for about 15 seconds, a client can call host transfer.
5. Start game:
   - Host validates 4-19 players.
   - Roles and numbers are generated client-side by host.
   - `batch_assign_roles` writes all assignments.
   - Session moves to `role_reveal`.
6. Role reveal:
   - Humans mark ready after seeing role.
   - Host advances to first night after all humans are ready.
7. Night:
   - Active roles submit actions through `submit_game_action`.
   - Bots either act independently or follow human role votes.
   - Host checks readiness.
   - Two-phase pattern:
     - `recordNightActions(nightIndex:)` records night history without deaths.
     - `resolveNightOutcome(nightIndex:)` applies deaths and advances phase atomically.
8. Morning/death reveal:
   - Host manually advances.
9. Voting:
   - Humans vote through `submit_game_action`.
   - Bots always submit non-nil votes.
   - Host computes vote results.
   - Vote result reveal happens before elimination is applied.
   - `completeVoteDeathReveal` applies elimination, records day history, checks win conditions, and advances.
10. Game over/rematch:
   - `returnToLobby` can reset session and transfer host.
   - `reset_session_to_lobby` handles concurrent play-again clicks.

Critical behavior to preserve:

- Host authority.
- Two-phase night resolution.
- Round isolation with `currentRoundId`.
- One action per actor per round/phase/action type.
- Role privacy:
  - own role visible to self,
  - mafia roles visible to mafia teammates,
  - all roles visible to host,
  - final roles visible at game over.
- Inspector privacy:
  - server returns only `mafia`, `not_mafia`, or `blocked`.
- Host can also be an active role and must be able to submit actions.
- Bot behavior:
  - bots can be added by host,
  - bots are controlled by host,
  - bots follow humans with same role when applicable,
  - bots must vote during day.
- Reconnect recovery:
  - snapshot refresh,
  - phase sequence drift detection,
  - app resume force reconnect,
  - fallback polling only when realtime appears disconnected.

### Supabase RPCs and Functions

Live Supabase functions found through MCP:

- `add_session_player(p_session_id, p_user_id, p_player_id, p_player_name, p_is_bot)`
- `all_role_actions_submitted(p_session_id, p_role, p_phase_index, p_action_type)`
- `batch_assign_roles(p_session_id, p_assignments)`
- `execute_rematch(p_session_id)`
- `fetch_actions_by_types(p_session_id, p_round_id, p_action_types)`
- `generate_room_code()`
- `get_visible_role(p_session_id, p_player_id, p_viewing_user_id)`
- `handle_new_user()`
- `increment_phase_sequence()`
- `log_insert_attempt()`
- `merge_anonymous_stats(p_anonymous_user_id, p_target_user_id)`
- `remove_player_by_id(p_player_id)`
- `reset_players_ready(p_session_id)`
- `reset_session_to_lobby(p_session_id, p_caller_user_id, p_new_host_user_id)`
- `resolve_night_atomic(...)`
  - live project has both a legacy 5-argument overload and the newer 7-argument overload.
- `session_is_joinable(p_session_id)`
- `submit_game_action(...)`
  - live project has both a legacy no-round overload and the newer round-aware overload.
- `transfer_host_on_leave()`
- `transfer_session_host(p_session_id, p_new_host_user_id)`
- `update_updated_at_column()`
- `user_is_in_session(p_session_id, p_user_id)`
- `user_is_player_in_session(p_session_id, p_user_id, p_player_id)`

Migration implication:

- Each RPC needs a Convex equivalent, but not necessarily one function per RPC.
- Convex mutations should combine related logic where it improves authority and clarity.
- Legacy Supabase overloads do not need to be preserved in Convex unless old app versions must stay compatible.

## Target Convex Architecture

### Recommended Directory Structure

Add Convex backend modules:

```text
convex/
  schema.ts
  auth.config.ts                 # only if using Convex auth config/OIDC provider
  users.ts                       # profiles and identity helpers
  stats.ts                       # player stats, custom roles, player groups
  sessions.ts                    # create/join/leave session lifecycle
  players.ts                     # player readiness, heartbeat, host transfer
  actions.ts                     # submit/fetch actions, tentative selection state
  gameFlow.ts                    # start game, phase changes, night/day resolution
  rules.ts                       # shared role distribution, targeting, win logic
  roomCodes.ts                   # room code generation
  validators.ts                  # shared Convex validators
  migrations.ts                  # one-off data import helpers, internal only
```

Add Swift client modules:

```text
Core/Backend/
  BackendProvider.swift          # protocol facade used by stores
  ConvexService.swift            # Convex client singleton/config
  ConvexConfig.swift.template    # generated from environment or copied locally

Core/Auth/Services/
  ClerkAuthService.swift         # wraps Clerk.shared, exposes auth state
  ConvexUserSync.swift           # calls users.ensureUser after Clerk auth state changes

Core/Stats/Services/
  StatsService.swift             # protocol
  ConvexStatsService.swift

Core/Multiplayer/Services/
  MultiplayerSessionServicing.swift
  ConvexSessionService.swift
  ConvexRealtimeService.swift    # likely thin query subscription wrapper, not raw WS
```

Keep `AuthStore`, `GameStore`, and `MultiplayerGameStore` as UI-facing state owners initially. Replace their service dependencies underneath.

### Convex Schema (as shipped)

The authoritative source is `convex/schema.ts`. Key facts that diverge from the original draft:

- **Field names are snake_case throughout** (`auth_subject`, `user_id`, `room_code`, `current_round_id`, `phase_sequence`, `created_at`, etc.). Swift's `JSONDecoder` is configured to decode them.
- **All keys use app-generated UUID strings** (`id: v.string()`), NOT Convex `Id<"users">` typed references. Foreign keys are plain `v.string()` — `user_id`, `session_id`, `host_user_id` — indexed via `by_app_id` on each table. This was chosen to keep Swift models using `UUID` natively without Convex-ID-aware adapters.
- **Tables are also snake_case**: `players_stats` and `custom_roles_configs` and `player_groups` (not `playerStats`/`customRoleConfigs`/`playerGroups`), and `game_sessions`/`session_players`/`game_actions`/`tentative_selections`.
- **ETL fields**: `users` has `email` and `legacy_supabase_user_id`. Child tables have `legacy_supabase_id` and `legacy_supabase_user_id`. Indexes: `by_email_unclaimed` (`email`, `auth_subject`), `by_legacy_supabase_user_id` on users; `by_legacy_supabase_id` on each child table.

Important Convex modeling notes:

- Game-level `playerId` is kept as a string (separate from `users.id`) to minimize Swift model churn.
- `night_history`, `day_history`, and `current_phase_data` use `v.any()` JSON-compatible values.
- All indexes are added before queries that need them — see `convex/schema.ts` for the full list.
- **Timestamps**: `convex/lib.ts` exports `nowAppleEpochSeconds()` — seconds since 2001-01-01. Swift decodes via `Date(timeIntervalSinceReferenceDate:)`. Do not use `Date.now()` directly; the helper subtracts the offset.

### Convex Function Map

Supabase capability to Convex function mapping:

| Supabase call/table | Convex replacement | Notes |
|---|---|---|
| `profiles` | `users.ts:getMe`, `users.ts:updateProfile`, `users.ts:ensureUser` | Auth provider subject or guest identity maps to `users` doc. |
| `handle_new_user` trigger | `users.ensureUser` mutation | Called after sign-in or guest creation. |
| `merge_anonymous_stats` | `users.mergeGuestIntoAccount` mutation | Must handle stats, custom role configs, and groups transactionally. |
| `player_stats` CRUD | `stats.ts` queries/mutations | Make `upsertPlayerStat` server-side. |
| `custom_roles_configs` CRUD | `stats.ts` queries/mutations | User-scoped. |
| `player_groups` CRUD | `stats.ts` queries/mutations | User-scoped. |
| `generate_room_code` | `roomCodes.generateUniqueRoomCode` internal helper | Loop until no `gameSessions.by_room_code` match. |
| `game_sessions` insert/update/select | `sessions.ts` and `gameFlow.ts` | Mutations own phase changes. |
| `session_players` insert/update/delete | `players.ts` | Validate caller is self or host. |
| `game_session_players` view | `players.listVisiblePlayers` query | Apply role visibility in query return shape. |
| `get_visible_role` | `rules.visibleRoleForViewer` helper | Pure TypeScript helper. |
| `add_session_player` | `sessions.joinSession`, `sessions.addBot` | Separate human join and bot add for simpler validation. |
| `batch_assign_roles` | `gameFlow.startGame` mutation | Generate roles/numbers on server, not in Swift. |
| `reset_players_ready` | `players.resetHumanReady` internal mutation/helper | Called by phase transitions. |
| `submit_game_action` | `actions.submitAction` mutation | Upsert by unique action index; return inspector result. |
| `resolve_night_atomic` | `gameFlow.resolveNightOutcome` mutation | Single Convex mutation handles history, deaths, phase, winner. |
| `transfer_session_host` | `players.transferHost` mutation | Validate candidate is alive, human, in session. |
| `transfer_host_on_leave` trigger | delete/leave mutation logic | No DB trigger needed. |
| `reset_session_to_lobby` | `gameFlow.returnToLobby` mutation | Row-lock behavior becomes mutation transaction. |
| Realtime table subscriptions | Swift subscriptions to Convex queries | Query results update automatically. |
| Broadcast tentative selection | `tentativeSelections` table + subscription query | Prefer durable ephemeral table over broadcast-only messages. |

### Convex Query Subscription Strategy

Replace `RealtimeService.subscribeToSession` with query subscriptions:

- `sessions.getSession(sessionId)`
  - replaces `game_sessions` Postgres subscription.
- `players.listVisiblePlayers(sessionId)`
  - replaces `game_session_players` select plus `session_players` subscription.
  - server applies role visibility for the current user.
- `actions.listCurrentPhaseActions(sessionId, roundId, actionTypes)`
  - used by host readiness and UI progress.
- `actions.listTentativeSelections(sessionId, phaseIndex, actionType)`
  - replaces Supabase broadcast for tentative vote preview.

The Swift store should receive snapshots instead of raw table events. This simplifies `RealtimeEventProcessor`; Convex's model is "subscribe to derived state" rather than "consume event stream."

### What To Move Server-Side

Move these out of Swift and into Convex mutations:

- Room code generation.
- Role and number assignment.
- Permission checks:
  - host-only mutations,
  - player self mutations,
  - bot mutations only by host.
- Role visibility.
- Inspector result computation.
- Action upsert.
- Night action recording.
- Night outcome resolution.
- Voting tally.
- Vote elimination application.
- Win condition checks.
- Host transfer.
- Play-again reset.
- Stats upsert and guest merge.

Keep these in Swift:

- UI state and screen flow.
- Local solo mode `GameStore`.
- Bot decision heuristics at first, because they already exist in Swift and host controls bots.
- Input validation for user experience. Still validate again in Convex for security.

Later, consider moving bot decisions to Convex if you want fully authoritative bot behavior even when the host is unreliable.

## Auth: Clerk + Convex

This is the migration gate. The chosen identity layer is **Clerk**, integrated with Convex via the official `clerk-convex-swift` bridge.

### Why Clerk

- Mature native iOS SDK (`clerk-ios`) with prebuilt SwiftUI sign-in views.
- Native Sign in with Apple via ID token (no browser redirect).
- Email/password, password reset, email OTP, and OAuth all available out of the box.
- Free tier (10K MAU) covers all foreseeable usage at this app's scale.
- Single vendor, single SDK for the entire identity layer.

### Implementation

Dependencies (Tuist):

- `https://github.com/clerk/clerk-ios` — Clerk iOS SDK (provides `ClerkKit` and `ClerkKitUI` products).
- `https://github.com/clerk/clerk-convex-swift` — bridges Clerk sessions into Convex (provides `ClerkConvex`).

Add to `Tuist/Package.swift` and reference in `Project.swift`:

```swift
.external(name: "ClerkKit"),
.external(name: "ClerkKitUI"),
.external(name: "ClerkConvex"),
```

Then run `tuist install && tuist generate`.

Clerk dashboard setup:

1. Create a Clerk application.
2. Navigate to **Native applications** and enable the Native API.
3. Configure providers: enable email/password and Sign in with Apple at minimum.
4. Add the Convex JWT template (Clerk dashboard → JWT Templates → Convex). This gives Convex the issuer/audience values it needs.
5. Add the iOS app's associated domain capability for Clerk auth flows (required for SIWA).

Convex configuration:

- Create `convex/auth.config.ts`. The shipped implementation reads the Clerk frontend API URL from a Convex env var and silently degrades to `providers: []` if the var is unset:

```ts
import { AuthConfig } from "convex/server";

const runtimeEnv = (globalThis as unknown as {
  process?: { env?: Record<string, string | undefined> };
}).process?.env;
const clerkEnvKey = ["CLERK", "FRONTEND", "API", "URL"].join("_");
const clerkFrontendApiUrl = runtimeEnv?.[clerkEnvKey];

export default {
  providers: clerkFrontendApiUrl
    ? [
        {
          domain: clerkFrontendApiUrl,
          applicationID: "convex",
        },
      ]
    : [],
} satisfies AuthConfig;
```

Then set the env var via `npx convex env set CLERK_FRONTEND_API_URL https://your-clerk.accounts.dev`. See `docs/CLERK_SETUP.md`.

- Replace `ConvexService`'s client with `ConvexClientWithAuth(provider: ClerkConvexAuthProvider())`.

App-side wiring:

- `Clerk.configure(publishableKey:)` at app startup.
- Inject `Clerk.shared` into the SwiftUI environment.
- Replace `AuthService` with a `ClerkAuthService` that observes `Clerk.shared.user` and calls Convex `users.ensureUser` on sign-in.
- Keep `AuthStore`'s public surface unchanged (`isAuthenticated`, `currentUserId`, `userProfile`, `isAnonymous`, `guestDisplayName`) so views don't churn.
- Sign in with Apple uses native ID-token flow:
  ```swift
  signIn = try await signIn.authenticateWithIdToken(idToken, provider: .apple)
  ```
- Use Clerk's prebuilt `AuthView` for sign-in/sign-up, or build custom views against the `clerk-ios` API.

### Known Tradeoffs

- `clerk-convex-swift` is at v0.1.0 (released Feb 2026 — about 3 months old). The pieces it bridges (`clerk-ios` and `convex-swift`) are mature, but the glue is new. Acceptable for this app's scale; revisit if it becomes paid production.
- Anonymous/guest play is not first-class in Clerk. If quick-play without sign-up is a requirement, implement a Convex-side guest pattern: a `users` row with `isAnonymous=true` and a Keychain-stored secret, exposed through a `users.createOrRestoreGuest` mutation. Account merge from guest → Clerk identity is a custom mutation (`users.mergeGuestIntoAccount`).
- Clerk's pricing changes only matter above 10K MAU; Mafia Manager will not approach this.

### Alternatives Considered

These were evaluated and rejected for this app, but documented for future reference:

- **Sign in with Apple via Convex Custom JWT Provider.** Zero third-party vendors, $0 forever. Rejected because it requires writing a custom Swift `AuthProvider`, configuring Custom JWT validation in `convex/auth.config.ts` (`iss=https://appleid.apple.com`, `aud=<bundle ID>`, JWKS at `https://appleid.apple.com/auth/keys`), and rebuilding email/password if needed. More upfront code than Clerk, and loses email/password unless layered with another provider.
- **Auth0 + Convex** via `convex-swift-auth0`. Mature bridge but uses Auth0 Universal Login (web redirect), which is less iOS-native than Clerk's prebuilt SwiftUI flow. Pick only if Auth0-specific features (organizations, advanced rules) become required.
- **Convex guest identity only.** Simplest but drops email/password and cross-device account recovery. Acceptable only if those features are confirmed non-requirements.
- **`@convex-dev/auth`** (the Convex-managed auth library at `labs.convex.dev/auth`). Not viable: React and React Native only, no native Swift support, still in beta.

Do not keep Supabase Auth long-term. It is the hardest lock-in in the current stack.

## Migration Phases

### Phase 0: Preparation and Safety

Goal: Make it possible to add Convex without destabilizing the existing Supabase app.

Tasks:

1. Add a feature flag:
   - `BackendMode.supabase`
   - `BackendMode.convex`
   - default Supabase until Convex flows are tested.
2. Add service protocols:
   - `AuthServicing`
   - `StatsServicing`
   - `MultiplayerSessionServicing`
   - `RealtimeSyncing` or replace with Convex query subscriptions.
3. Add `ConvexService`.
4. Add local config:
   - `ConvexConfig.swift.template`
   - real `ConvexConfig.swift` ignored by git if needed.
5. Add Convex Swift dependency using Tuist.
6. Regenerate project with Tuist.
7. Do not delete any Supabase code yet.

Acceptance criteria:

- App builds with both Supabase and Convex dependencies.
- Existing Supabase multiplayer still works.
- `npx convex dev` runs cleanly.
- Convex MCP `functionSpec` shows at least a health query.
- No `.pbxproj` direct edits.

### Phase 1: Convex Schema and Basic Health

Goal: Establish Convex tables and a Swift connection.

Convex tasks:

1. Implement `convex/schema.ts`.
2. Implement `convex/health.ts`:
   - query returns deployment timestamp/version.
3. Implement `convex/users.ts` minimal user/guest creation depending on auth decision.
4. Run `npx convex dev` to push schema and regenerate `_generated`.

Swift tasks:

1. Add `ConvexService` that initializes the Convex client.
2. Add a debug-only health check method.
3. Add a lightweight logging path for Convex errors.

Acceptance criteria:

- Convex dev deployment shows tables through MCP.
- Swift app can call Convex health query in debug build.
- No user-facing flow has changed yet.

### Phase 2: Auth Replacement (Clerk)

Goal: Stand up Clerk + Convex identity before any user-scoped Convex data is written.

Why this phase moved earlier: Every later phase (stats, multiplayer) writes documents keyed by `user_id`. Without server-side identity (`ctx.auth.getUserIdentity()`), the mutations cannot enforce host-only / player-self / actor-self checks. Auth-first means every Convex write from this point on can be authorized against the real caller.

Tasks:

1. Add `clerk-ios` and `clerk-convex-swift` to `Tuist/Package.swift`; add `.external(name: "ClerkKit")`, `.external(name: "ClerkKitUI")`, and `.external(name: "ClerkConvex")` to `Project.swift`. Run `tuist install && tuist generate`.
2. Create a Clerk application; enable Native API; configure email/password and Sign in with Apple.
3. Add the Convex JWT template in the Clerk dashboard (JWT Templates → Convex).
4. Add associated-domain capability to the iOS app for Clerk auth flows (required for SIWA).
5. Create `convex/auth.config.ts` pointing at Clerk's frontend API URL with `applicationID: "convex"`.
6. Replace `ConvexService` initialization with `ConvexClientWithAuth(provider: ClerkConvexAuthProvider())`.
7. Implement `convex/users.ts`:
   - `ensureUser` mutation: read `ctx.auth.getUserIdentity()`, upsert into `users` by `authSubject`, return doc.
   - `getMe` query: returns current user.
   - `mergeGuestIntoAccount` mutation: stub for now; implemented if/when guest pattern is added.
8. Add `Clerk.configure(publishableKey:)` at app startup; inject `Clerk.shared` into the SwiftUI environment.
9. Replace `AuthService` with `ClerkAuthService` that wraps `Clerk.shared` and calls `users.ensureUser` after sign-in.
10. Keep `AuthStore`'s public surface unchanged (`isAuthenticated`, `currentUserId`, `userProfile`, `isAnonymous`, `guestDisplayName`).
11. Rebuild signup/login/password reset/profile UI using Clerk's prebuilt `AuthView` or custom views built on the `clerk-ios` API.
12. Map current Supabase user IDs to a `legacy_supabase_user_id` field on `users` so historical references can be resolved later (only matters if Phase 6 data migration runs).
13. Update `extractSupabaseMessage` and other Supabase-specific error parsers — replace with Clerk-specific error handling.
14. Delete the manual `setSession` and `Authorization` header workarounds in `DatabaseService` once the Convex client owns auth.

Guest pattern (if quick-play without sign-up is required):

- Add `isAnonymous: v.boolean()` and `guestSecretHash: v.optional(v.string())` to the `users` table (already in the schema draft).
- Implement `users.createOrRestoreGuest` mutation: takes a Keychain-stored secret, returns or creates a `users` row with `isAnonymous=true` and no `authSubject`.
- Implement `users.mergeGuestIntoAccount` mutation: called after a guest signs into Clerk, transfers stats/configs/groups from the guest user to the Clerk-linked user, deletes the guest row.

Acceptance criteria:

- App can sign in / sign up / sign out using new provider.
- Convex `users` table contains a doc for the signed-in user with the correct `authSubject`.
- `AuthStore.currentUserId` returns a Convex `Id<"users">` (or stable string equivalent), not a Supabase UUID.
- Existing Supabase Auth still works behind a feature flag for rollback.
- No new Convex writes use Supabase user IDs.

### Phase 3: Stats and Saved Setup Data

Goal: Move low-risk CRUD first now that identity is solid.

Convex functions:

- `stats.listPlayerStats`
- `stats.getPlayerStat`
- `stats.upsertPlayerStat`
- `stats.deletePlayerStat`
- `stats.listCustomRoleConfigs`
- `stats.createCustomRoleConfig`
- `stats.updateCustomRoleConfig`
- `stats.deleteCustomRoleConfig`
- `stats.listPlayerGroups`
- `stats.createPlayerGroup`
- `stats.updatePlayerGroup`
- `stats.deletePlayerGroup`

Swift changes:

- Create `StatsService` protocol.
- Implement `ConvexStatsService`.
- Make `DatabaseService` either conform to `StatsService` or rename it to `SupabaseStatsService`.
- Update:
  - `PlayerStatsView`
  - `CustomRolesView`
  - `PlayerGroupsView`
  - `SetupView`
  - `GameStore.syncPlayerStatsToCloud()`

Data migration:

- Export Supabase tables:
  - `profiles`
  - `player_stats`
  - `custom_roles_configs`
  - `player_groups`
- Import into Convex with one-off internal functions or CLI scripts.
- Preserve old UUIDs:
  - `legacy_supabase_user_id`
  - `legacySupabaseStatId` if useful for audit.

Acceptance criteria:

- Existing user can see player stats from Convex.
- New game-over stats write to Convex.
- Custom role configs load in setup from Convex.
- Player groups load in setup from Convex.
- Supabase stats tables no longer receive writes when Convex mode is enabled.

### Phase 4: Multiplayer Read Model

Goal: Let the app observe Convex sessions without yet replacing all mutations.

Convex functions:

- `sessions.getSessionByRoomCode`
- `sessions.getSession`
- `players.listVisiblePlayers`
- `actions.listCurrentPhaseActions`
- `actions.listTentativeSelections`

Swift changes:

- Create `ConvexMultiplayerStoreAdapter` or implement service protocols under `MultiplayerGameStore`.
- Replace raw event callbacks with snapshot application.
- Keep `MultiplayerGameStore`'s published properties:
  - `currentSession`
  - `myPlayer`
  - `allPlayers`
  - `visiblePlayers`
  - `myRole`
  - `myNumber`
  - `mafiaTeammates`
  - `isPhaseReadyToAdvance`
  - connection state.

Design decision:

- Convex query snapshots may make `RealtimeEventProcessor` unnecessary.
- Do not delete it until Supabase mode is removed.

Acceptance criteria:

- A test/dev Convex session can be displayed in the lobby.
- Player list changes update live through Convex subscriptions.
- Role visibility is enforced by Convex query return values, not client filtering alone.

### Phase 5: Multiplayer Mutations

Goal: Replace `SessionService` RPC/table writes with Convex mutations.

Implement in this order:

1. `sessions.createSession`
   - generate room code server-side,
   - create session,
   - create host player,
   - create bot players.
2. `sessions.joinSession`
   - validate room code,
   - status must be waiting,
   - no duplicate human user,
   - capacity 4-19.
3. `sessions.leaveSession`
   - delete/mark player,
   - transfer host if needed.
4. `players.updateReady`
5. `players.heartbeat`
6. `gameFlow.startGame`
   - role and number generation must move to Convex.
   - write all player assignments in one mutation.
   - set status and phase.
7. `gameFlow.advanceFromRoleReveal`
8. `actions.submitAction`
   - enforce round ID,
   - enforce actor belongs to caller or actor is a bot controlled by host,
   - enforce targeting rules,
   - upsert by unique action key,
   - return inspector result.
9. `gameFlow.recordNightActions`
10. `gameFlow.resolveNightOutcome`
11. `gameFlow.showVotingResults`
12. `gameFlow.applyVotingResult`
13. `gameFlow.returnToLobby`
14. `players.transferHost`
15. `actions.setTentativeSelection`

Acceptance criteria:

- Two devices can create/join a Convex room.
- Host can add bots.
- Host can start game.
- Every player sees correct role visibility.
- Host with Mafia/Doctor/Inspector role can submit action.
- Night actions resolve with two-phase pattern.
- Round replay is impossible across nights.
- Voting results and vote death reveal remain separated.
- Host transfer works on leave, disconnect, and elimination.
- Play Again resets to lobby.

### Phase 6: Data Migration

Goal: Move existing production data.

Data sets:

- Auth users/profiles:
  - export user IDs and display names from Supabase.
  - Supabase password hashes cannot be exported. Existing users must either set a new Clerk password or sign in with Apple at first launch on the new build. Match historical data via `legacy_supabase_user_id` after their first Clerk sign-in.
- Player stats:
  - migrate by `user_id` and `player_name`.
- Custom role configs:
  - migrate by `user_id` and `config_name`.
- Player groups:
  - migrate by `user_id` and `group_name`.
- Multiplayer sessions:
  - likely do not migrate historical sessions unless needed.
  - Current active rooms should be allowed to finish on Supabase before cutover, or be abandoned.

Recommended approach:

1. Freeze Supabase writes for stats/setup data during migration window.
2. Export Supabase data as JSON.
3. Run Convex internal import mutation/action.
4. Validate row counts.
5. Validate sample users.
6. Flip app feature flag.
7. Keep Supabase read-only fallback for one release if needed.

Do not migrate old `game_actions` and `session_players` unless there is a product reason. They are mostly ephemeral room state.

### Phase 7: Supabase Removal

Goal: Delete Supabase completely after Convex has replaced all behavior.

Remove:

- `Core/Backend/SupabaseService.swift`
- `Core/Backend/SupabaseConfig.swift`
- `Core/Backend/SupabaseConfig.swift.template`
- Supabase implementation of `AuthService`
- Supabase implementation of `DatabaseService`
- Supabase implementation of `SessionService`
- Supabase implementation of `RealtimeService`
- Supabase imports:
  - `import Supabase`
  - `import Auth`
  - `import Realtime`
- Tuist Supabase dependency.
- Supabase-specific docs or update them as archived historical docs.
- Supabase SQL files only after data migration is fully complete and no rollback is needed.

Update:

- `Project.swift`
- `Tuist/Package.swift`
- `AGENTS.md`
- `docs/CLAUDE_PRIMER.md`
- `docs/ARCHITECTURE_NOTES.md`
- `docs/MULTIPLAYER_GUIDE.md`
- Privacy docs (`docs/index.html`) to mention Convex/Auth provider instead of Supabase.

Acceptance criteria:

- `rg "Supabase|supabase|Realtime|PostgREST|RLS|anon key"` has only historical archive references, or none.
- Tuist project regenerates cleanly.
- App builds and tests pass.
- Multiplayer manual test passes on at least two devices/simulators.

## Detailed Implementation Notes

### Swift Service Abstraction

Current views instantiate `DatabaseService()` directly in multiple places. That makes piecemeal replacement harder.

Recommended interim pattern:

```swift
protocol StatsServicing {
    func getPlayerStats(userId: UUID) async throws -> [PlayerStats]
    func upsertPlayerStat(userId: UUID, playerName: String, role: Role, won: Bool, kills: Int) async throws
    // continue existing methods
}
```

Then:

- `SupabaseStatsService: StatsServicing`
- `ConvexStatsService: StatsServicing`
- `DatabaseService` can become a facade that delegates based on `BackendMode`.

Use the same approach for multiplayer:

```swift
protocol MultiplayerSessionServicing {
    func createSession(hostUserId: UUID, maxPlayers: Int, botCount: Int) async throws -> GameSession
    func joinSession(roomCode: String, userId: UUID, playerName: String) async throws -> (GameSession, SessionPlayer)
    func submitAction(_ action: GameAction) async throws -> ActionResponse
    // continue current SessionService surface
}
```

This minimizes view churn.

### Model Compatibility

The current Swift models use UUIDs everywhere. Convex document IDs are typed strings. There are two ways to handle this:

Option 1: Keep UUID strings in app-level fields.

- Keep `GameSession.id` as UUID only in Supabase mode.
- Add Convex-specific IDs separately.
- More transitional complexity.

Option 2: Introduce backend-neutral IDs.

- Use `String` for backend document IDs.
- Keep `playerId` UUID as game identity.
- Larger Swift model change.

Recommended:

- For multiplayer game logic, keep `playerId: UUID` exactly as it is.
- For Convex document IDs, introduce type aliases or separate fields only in Convex DTOs.
- Map Convex DTOs to existing Swift domain models in `ConvexSessionService`.

This keeps most of `MultiplayerGameStore` intact.

### Realtime Replacement

Supabase current model:

- Subscribe to table events.
- Decode insert/update/delete payloads.
- Apply them incrementally.
- Recover with snapshot refresh when events are missed.

Convex target model:

- Subscribe to queries.
- Receive latest query result snapshots.
- Apply snapshots to published state.
- Use fewer event-ordering assumptions.

Recommended state subscriptions:

- Session snapshot.
- Visible players snapshot.
- Current phase actions snapshot.
- Tentative selections snapshot.

Expected simplifications:

- Fewer decode errors from raw Postgres payloads.
- Less need for event FIFO actor.
- Less need for fallback polling.
- Still keep app resume reconnect handling until proven unnecessary on iOS.

### Role Privacy in Convex

Do not send all roles to the client and hide in Swift. Supabase currently uses a view and `get_visible_role`. Convex must enforce equivalent behavior server-side.

`players.listVisiblePlayers` should:

1. Identify current user.
2. Fetch session.
3. Fetch viewer player.
4. Fetch session players.
5. Return player role only when:
   - viewer is host,
   - player is viewer's own player,
   - viewer role is mafia and target player role is mafia,
   - session is game over.
6. Otherwise return `role: nil`.

Host sees all roles by design today. If that is no longer desired, change the rule explicitly, but do not accidentally remove host visibility during migration because host flow currently depends on it.

### Security and Permission Rules

Every Convex mutation should validate:

- Caller identity exists.
- Caller is in the session for session-scoped reads/writes.
- Caller is host for host-only mutations.
- Caller is actor for self action submissions.
- Host can act for bots.
- Session phase matches requested action.
- Round ID matches current round.
- Target is valid for action type:
  - Mafia cannot target Mafia.
  - Inspector cannot inspect Inspector.
  - Doctor can protect anyone alive, including self.
  - Voting target must be alive and valid; bots should never submit nil votes.
- Idempotency:
  - repeated action submissions update the same action doc,
  - repeated night resolution returns safely if already resolved,
  - play-again reset handles concurrent callers.

### Atomic Night Resolution

The current critical pattern must be preserved:

1. `recordNightActions`
   - reads actions for current `roundId`,
   - records `nightHistory` with `isResolved = false`,
   - does not kill players,
   - does not advance phase.
2. `resolveNightOutcome`
   - guards `isResolved`,
   - computes save/death,
   - updates `sessionPlayers.isAlive`,
   - writes final night history,
   - checks win conditions,
   - advances phase,
   - transfers host if host died.

In Convex, both should be mutations. `resolveNightOutcome` should be one mutation that touches all required documents.

### Round Isolation

Current Supabase uses `current_round_id` and `game_actions.round_id` to prevent action replay.

Convex must keep this. On phase transition to night or voting:

- Generate a new `currentRoundId`.
- Require submissions to use that exact value or have the server derive it from the session and ignore client-provided round IDs.

Better Convex design:

- The Swift client sends `sessionId`, `actionType`, `phaseIndex`, and `targetPlayerId`.
- Convex mutation reads `currentRoundId` from session and writes it.
- The client does not provide the round ID.

This removes orphan-action bugs caused by stale clients.

### Vote Results and Vote Death Reveal

Current flow deliberately separates:

1. `showVotingResults`
   - tallies votes,
   - stores `votingResults` phase data,
   - does not eliminate yet.
2. `applyVotingResult`
   - transitions to `voteDeathReveal`,
   - still does not eliminate.
3. `completeVoteDeathReveal`
   - applies elimination,
   - writes day history,
   - checks winners,
   - advances to game over or next night.

Preserve this. Do not compress it into one mutation unless the UI is redesigned.

### Host Transfer

Current transfer paths:

- Host leaves: database trigger transfers to oldest remaining human.
- Host disconnects: clients detect stale heartbeat and call RPC.
- Host eliminated: Swift calls host transfer after death.
- Play Again: first clicker can become host; original host can reclaim later.

Convex replacement:

- `players.leaveSession` handles host leave.
- `players.claimHostIfStale` handles stale heartbeat.
- `gameFlow.resolveNightOutcome` and `gameFlow.completeVoteDeathReveal` can transfer host after elimination.
- `gameFlow.returnToLobby` handles play-again host logic.

Use joined time and heartbeat recency as current code does.

### Presence and Heartbeat

Supabase uses both:

- persisted heartbeat columns,
- optional Realtime presence channel.

Current Swift code mostly depends on persisted `lastHeartbeat`, `isOnline`, timers, and host monitor logic.

Convex replacement:

- Keep persisted heartbeat fields first.
- Add `players.heartbeat` mutation called every 5 seconds while active.
- Derive online status in queries:
  - `isOnline = now - lastHeartbeat < threshold`,
  - or persist `isOnline` for UI compatibility.
- Consider a scheduled cleanup only if stale sessions pile up.

### Tentative Selection

Supabase broadcast is non-durable and realtime-only. Convex should use a table:

- `tentativeSelections`
- upsert by session/phase/action/actor.
- delete or null target on deselect.
- clear on phase transition.

The UI can subscribe to `actions.listTentativeSelections`.

### Data Import Plan

Supabase export queries:

```sql
select * from public.profiles;
select * from public.player_stats;
select * from public.custom_roles_configs;
select * from public.player_groups;
```

Recommended import path:

- Export JSON locally.
- Write `convex/migrations.ts` internal mutation/action to insert batches.
- Convert:
  - UUID strings to `legacy_supabase_user_id`.
  - dates to numeric timestamps.
  - JSONB to Convex objects/arrays.
- Validate:
  - row counts,
  - per-user stats counts,
  - one known custom role config,
  - one known player group.

Do not import passwords. Supabase Auth password hashes should not be moved manually. Use a proper auth provider migration or require users to sign in/create accounts again.

## Testing Plan

### Unit Tests

Existing tests are mostly solo `GameStoreTests`. Add new tests for extracted shared rules where possible:

- role distribution,
- targeting validation,
- win condition thresholds,
- majority target tie-breakers,
- two-phase night record and resolve behavior.

If Convex logic stays in TypeScript, add Convex tests or at minimum one-off function checks for:

- `startGame`
- `submitAction`
- `recordNightActions`
- `resolveNightOutcome`
- `showVotingResults`
- `completeVoteDeathReveal`
- `returnToLobby`
- `transferHost`

### Manual Multiplayer Matrix

Test on at least two simulator/device clients:

1. Create room as guest/permanent user.
2. Join room from second client.
3. Add bots.
4. Start game with 4 players.
5. Verify role privacy:
   - player sees own role,
   - mafia sees mafia teammate,
   - citizen cannot see other roles,
   - host sees all roles if preserving current behavior.
6. Host has active role and submits action.
7. Non-host active role submits action.
8. Bots follow human same-role action.
9. Night target saved by doctor.
10. Night target dies when not saved.
11. Inspector gets `mafia`, `not_mafia`, and `blocked`.
12. Voting tie causes no elimination.
13. Voting single leader shows results, then vote death reveal, then elimination.
14. Mafia win after voting tie/parity.
15. Citizens win after all mafia eliminated.
16. Host leaves in lobby.
17. Host disconnects mid-game.
18. Host dies at night or vote.
19. App background/resume reconnect.
20. Play Again from non-host first, original host later.

### Build/Test Commands

Use Tuist and existing project commands. Do not edit `.pbxproj`.

Suggested during implementation:

```bash
npm run convex:dev
tuist generate
xcodebuild -project mafia_manager.xcodeproj -scheme mafia_manager \
  -configuration Debug -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  build
xcodebuild -project mafia_manager.xcodeproj -scheme mafia_manager test \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro"
```

If the project is run through the workspace after Tuist generation, use the generated workspace/scheme that Tuist creates.

## Risks

### Clerk Glue Maturity Is the Biggest Auth Risk

Auth provider is decided (Clerk) and shipped. The remaining risk is `clerk-convex-swift` 0.1.0 — a young bridge library, ~3 months old at time of writing. Concrete failure modes to watch for: silent token-type mismatches in `ConvexService.logout()` (mitigated by the closure-based logout in `Core/Backend/ConvexService.swift`); SIWA edge cases with email-less Apple sign-ins (those users cannot inherit legacy Supabase data — see ETL caveats below); Clerk session refresh failing during long-running multiplayer sessions.

### ETL Email-Mismatch Silent Data Loss

Users whose email differs between their Supabase profile and their Clerk signup will not auto-link in `users.ensureUser`'s by-email claim path. Mitigations: (1) the `migration.linkLegacyByAdmin` internal mutation provides an admin override; (2) the `migration.listLegacyOrphans` query enumerates unclaimed legacy rows for support reconciliation. Pre-launch comms about "use the same email you used before" reduce the volume.

### ID Migration

Supabase UUIDs and Convex `id: v.string()` UUIDs differ. The shipped schema preserves Supabase UUIDs in `legacy_supabase_user_id` (users) and `legacy_supabase_id` (children) so historical references can be resolved during cutover.

### Moving Too Much at Once

Multiplayer has many race-condition fixes. A direct rewrite can regress:

- round isolation,
- host active-role submission,
- bot vote readiness,
- app resume,
- host transfer,
- two-phase resolution.

Use feature flags and slice migration.

### Role Privacy

Convex functions must not return full `role` fields to unauthorized clients. Do not rely on Swift UI hiding sensitive fields.

### Query Indexes

Convex queries must use indexes for session/player/action reads. Avoid table scans in hot multiplayer subscriptions.

### Current Live Supabase Drift

Live Supabase has some objects not fully reflected in the repo:

- `log_insert_attempt()` trigger function exists live.
- `game_sessions.eliminated_players` exists live but is not represented in `GameSession`.
- legacy overloads exist for `submit_game_action` and `resolve_night_atomic`.

Before final cutover, decide whether those are obsolete and should be ignored or whether they represent behavior to preserve.

## Suggested First Implementation PR

Stand up Convex plus Clerk auth. Nothing user-visible flips yet.

1. Add `clerk-ios` and `clerk-convex-swift` to `Tuist/Package.swift`; reference `ClerkKit`, `ClerkKitUI`, and `ClerkConvex` in `Project.swift`. Run `tuist install && tuist generate`.
2. Create the Clerk application, enable Native API, add the Convex JWT template, enable email/password and Sign in with Apple.
3. Add `convex/schema.ts` with `users` table only and a `convex/health.ts` query.
4. Add `convex/auth.config.ts` pointing at the Clerk frontend API URL.
5. Add `convex/users.ts` with `ensureUser` and `getMe`.
6. Add `Core/Backend/ConvexService.swift` using `ConvexClientWithAuth(provider: ClerkConvexAuthProvider())`.
7. Wire `Clerk.configure(publishableKey:)` at app startup behind a debug build flag.
8. Add `BackendMode` feature flag (Supabase default).
9. Add a debug-only screen that presents Clerk's `AuthView`, calls `users.ensureUser` after sign-in, and shows the resulting user doc.
10. Do not touch stats, multiplayer, or production auth flows.

Why this first:

- Proves Swift-to-Convex wiring and Clerk token plumbing on real infrastructure.
- Validates schema/generated types/deployment workflow.
- Locks in the user identity model before any user-scoped data is written.
- Auth is the riskiest piece; isolating it in PR 1 means later PRs build on a settled foundation.

## Suggested Second Implementation PR

Switch production auth to Clerk, gated by feature flag.

1. Replace `AuthService` with `ClerkAuthService` wrapping `Clerk.shared`.
2. Update `AuthStore` to read from Clerk while preserving its public surface (`isAuthenticated`, `currentUserId`, `userProfile`, `isAnonymous`).
3. Rebuild signup/login/password reset/profile flows using Clerk's prebuilt `AuthView` or custom views.
4. If guest play is required, ship the Convex-side guest pattern (`users.createOrRestoreGuest`, Keychain secret) in this PR too.
5. Remove Supabase-specific error parsers and `setSession` workarounds for Convex-mode users.
6. Keep Supabase Auth available behind the feature flag for rollback.

Acceptance:

- Sign up / sign in / sign out works on Clerk.
- Sign in with Apple works via native ID-token flow.
- `AuthStore.currentUserId` returns a Convex `Id<"users">`.
- Existing Supabase Auth still works with the feature flag flipped back.

## Suggested Third Implementation PR

Move stats and saved setup data.

1. Add `playerStats`, `customRoleConfigs`, `playerGroups` tables to `convex/schema.ts`.
2. Implement `convex/stats.ts` queries and mutations (server-side `upsertPlayerStat`).
3. Add `StatsServicing` protocol; implement `ConvexStatsService`.
4. Wire `PlayerStatsView`, `CustomRolesView`, `PlayerGroupsView`, `SetupView`, and `GameStore.syncPlayerStatsToCloud()` through the protocol.
5. Optional: import existing Supabase stats via `convex/migrations.ts` if data migration is in scope.

Acceptance:

- New game-over stats write to Convex.
- Custom role configs and player groups round-trip through Convex.
- No new writes to Supabase stats tables when Convex mode is on.

## Suggested Fourth Implementation PR

Move multiplayer session creation and lobby only.

1. Convex `sessions.createSession`, `joinSession`, `leaveSession`.
2. Convex `players.listVisiblePlayers` subscription.
3. Server-side room code generation.
4. Lobby UI using Convex mode.
5. No role assignment or gameplay yet.

Acceptance:

- Two clients can create/join/leave a Convex room.
- Host can add bots.
- Player list updates live via subscription, not polling.
- Host transfer on leave works.

## Suggested Fifth Implementation PR

Move game start and role reveal.

1. Convex server-side role and number assignment in `gameFlow.startGame`.
2. `players.listVisiblePlayers` enforces role privacy server-side.
3. Ready / reset-ready mutations.
4. Advance to first night.

Acceptance:

- Correct role visibility for self / Mafia teammates / host / game-over reveal.
- Host and clients agree on numbers/roles.
- No stale role events during lobby reset.

## Suggested Sixth Implementation PR

Move night and voting.

1. `actions.submitAction` with server-derived `currentRoundId`.
2. Bot action support (host-controlled).
3. `gameFlow.recordNightActions` and `gameFlow.resolveNightOutcome` (preserve two-phase pattern).
4. `gameFlow.showVotingResults` and `gameFlow.applyVotingResult` and `gameFlow.completeVoteDeathReveal`.
5. Host transfer and win checks.

Acceptance:

- Full game can complete on Convex.
- Multi-client manual test matrix passes.

## Alternative: Minimal Scope Path

The phased plan above optimizes for safety: feature flag, dual-stack, optional data migration, gradual cutover. For a hobby app at this scale (~10 users), a leaner path is also defensible.

Trade safety for speed by accepting these constraints:

- Users sign up fresh on the new auth provider (no Supabase password hash migration — those cannot be exported anyway).
- No `legacy_supabase_user_id` field, no stats import, no `convex/migrations.ts`.
- One short downtime window between cutover and rollout instead of dual-stack.
- Active multiplayer rooms on Supabase get drained or abandoned at cutover.

Compressed track (3 PRs instead of 6):

1. **PR 1: Convex foundation + auth.** Same as the standard plan's PR 1 + PR 2 combined. Ship to TestFlight; ask existing users to recreate accounts.
2. **PR 2: Stats + multiplayer wholesale.** Schema, stats CRUD, all multiplayer mutations and subscriptions, role privacy, two-phase night, voting flow. Larger PR but no feature flag; the new code is the only code path.
3. **PR 3: Supabase removal.** Delete Supabase imports, Tuist dependency, SQL files, config files, docs.

Why consider this path:

- Removes the largest source of complexity in this plan: the dual-stack period.
- Skips Phase 6 entirely.
- For a private Mafia game with a small known user base, asking everyone to sign up again once is an acceptable cost.

Why skip this path:

- If user-visible data loss is unacceptable, even for hobby users.
- If you want to validate Convex incrementally before betting all gameplay on it.
- If you want CI-style rollback during the cutover window.

Pick the standard plan if "I want a safe, observable migration." Pick this path if "I want the migration to be done in a weekend or two."

## Cutover Criteria

Supabase can be removed only when:

- Auth replacement is live.
- Stats and saved setup data are on Convex.
- Multiplayer is on Convex.
- Data migration is complete or intentionally skipped for old multiplayer sessions.
- Privacy docs are updated.
- No user-facing flow requires Supabase.
- `rg "Supabase|supabase" App Core Features Project.swift Tuist/Package.swift` returns no active implementation references.
- Build and tests pass.
- Manual multiplayer testing passes with multiple clients.

## Open Decisions

Auth provider is **decided: Clerk + Convex.** Remaining decisions:

1. Migration scope:
   - Standard 6-PR plan with feature flag and dual-stack, or 3-PR Minimal Scope Path with fresh-sign-up at cutover.
2. Guest mode:
   - Build a Convex-side guest pattern (anonymous `users` row + Keychain secret + merge mutation), or require Clerk sign-in for all play. Clerk does not support native anonymous accounts, so guest mode requires custom Convex work either way.
3. Existing users:
   - Migrate profiles/stats automatically (Phase 6) or ask users to create new accounts (Minimal Scope Path). Note: Supabase password hashes cannot be migrated regardless — users must reset on Clerk or sign in with Apple.
4. Old multiplayer data:
   - Archive, ignore, or import (recommend ignore — it's ephemeral room state).
5. Host visibility:
   - Keep host seeing all roles or tighten privacy.
6. Bot authority:
   - Keep host-controlled bots initially or move bot decisions to Convex.

## Bottom Line

Convex should become the authoritative backend for multiplayer state, realtime subscriptions, game rules, and user-scoped data. The migration should not copy Supabase's table-event architecture one-to-one. It should use Convex's strengths: reactive queries, transactional server mutations, typed validators, and explicit server-side game authority.

The only part Convex does not replace by itself is Supabase Auth. Decide that first, then migrate in slices.
