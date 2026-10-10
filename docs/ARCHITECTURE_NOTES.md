# Architecture Deep Dive

## Solo GameStore Pattern

`GameStore` is the single source of truth for solo mode. It is `@MainActor`, publishes game state, and owns all mutations. Views subscribe to state and call store methods; they should not mutate models directly.

Key solo methods:
- `assignNumbersAndRoles(names:)` - setup, number assignment, and role distribution.
- `endNight(mafiaTargetID:inspectorCheckedID:doctorProtectedID:)` - records night actions without applying deaths.
- `resolveNightOutcome(targetWasSaved:)` - applies the night outcome and checks win conditions.
- `applyDayRemovals(removed:notes:)` - marks players dead and checks win conditions.
- `syncPlayerStatsToCloud()` - syncs completed-game stats through `DatabaseService`.

## Night Resolution

Night resolution must remain two-phase.

1. `NightPhaseView` / `NightWakeUpView` collects role actions and calls `endNight()`.
2. The outcome UI asks whether the Doctor save worked.
3. `resolveNightOutcome()` applies death/save state and marks the night as resolved.

Multiplayer keeps the pattern, but Convex computes every outcome:
- players submit actions with `play:submitAction` for the current `round_id`;
- `night:recordNightActions` checks that every action is in, stores the unresolved night record and locks the night;
- `night:resolveNightAtomic` applies deaths and saves, checks winners, and moves to `morning` or `game_over`;
- voting mirrors it: `voting:closeVoting` tallies the votes, then `voting:resolveVoteAtomic` applies the elimination and starts the next night or ends the game;
- the host client only calls these and `phases:advancePhase`; all are safe to retry and never move the phase backwards.

## Backend Stack

The backend is Convex + Clerk.

- `Core/Backend/ConvexService.swift` owns the Convex Swift client and injects the guest proof into every call.
- `Core/Backend/ConvexConfig.swift` reads the Convex deployment URL and Clerk publishable key from Info.plist, set by `Configuration/*.xcconfig`.
- `Core/Auth/Services/AuthService.swift` wraps Clerk sign-up/sign-in/reset flows and creates/restores Convex user documents.
- `Core/Auth/Store/AuthStore.swift` is the UI-facing auth facade, including guest mode.
- `Core/Backend/DatabaseService.swift` handles stats, custom role configs, and player groups via Convex.
- `Core/Backend/BackendError.swift` shows a `ConvexError` string as-is and a generic message for anything else.
- `Core/Multiplayer/Services/SessionService.swift` calls Convex multiplayer mutations.
- `Core/Multiplayer/Services/SubscriptionSupervisor.swift` keeps one subscription alive and resubscribes with backoff.
- `Core/Multiplayer/Store/BotDirector.swift` submits bot actions and votes from the host's snapshots.

Convex backend files:
- `convex/schema.ts` - schema and indexes.
- `convex/users.ts` - Clerk/guest profiles, guest merge, legacy-account claim.
- `convex/stats.ts` - stats/custom role/player group CRUD.
- `convex/sessions.ts` - create/join/leave, kick, host claim, heartbeat, readiness, start, return to lobby.
- `convex/phases.ts` - `advancePhase`.
- `convex/play.ts` - action submission and tentative selections.
- `convex/night.ts`, `convex/voting.ts` - the record/resolve pairs.
- `convex/views.ts` - the three subscription queries.
- `convex/health.ts` - health check (`api_contract` 4).
- `convex/lib/` - identity, guards, game rules, transitions, privacy projections, error messages.

## Identity Model

App IDs are UUID strings stored in each document's `id` field (`by_app_id` index). Clients cannot choose them.

The server resolves the caller for every function; no function accepts a user id:
1. If `guest_secret_hash` matches a live guest (`users.guest_secret_digest` is sha256 of it), the caller is that guest.
2. Otherwise the caller is the Clerk user (`identity.subject` → `users.auth_subject`).
3. Otherwise the caller is unauthenticated.

Guests: the app keeps a random secret in the Keychain and sends its sha256 hex as `guest_secret_hash` while the user is a guest or a guest merge is pending.
Accounts: Convex validates the Clerk JWT from the `convex` template. `users:ensureUser` claims a legacy row only when the token's email is verified.

## Multiplayer Model

Convex tables:
- `users`
- `player_stats`
- `custom_roles_configs`
- `player_groups`
- `game_sessions`
- `session_players`
- `game_actions`
- `tentative_selections`

Core session rules:
- room codes are generated server-side;
- host user ID is stored on `game_sessions`;
- player rows hold public metadata plus private role/number data;
- action rows are keyed by session, round ID, action type, phase index, and actor;
- the server issues a new `current_round_id` for each night and voting phase, which isolates actions and prevents replay.

Role privacy is enforced in `convex/lib/projections.ts`, which every `views:*` query uses:
- players can see their own role;
- Mafia can see Mafia teammates;
- the host can see all roles (it drives the bots);
- everyone can see final roles after game over;
- during the night, non-host viewers see other seats as not ready, so readiness does not reveal roles.

## Data Flow

Solo:
```text
View action -> GameStore method -> GameState mutation -> Persistence.save() -> SwiftUI refresh
```

Cloud stats:
```text
GameOverView.task -> GameStore.syncPlayerStatsToCloud() -> DatabaseService -> Convex stats mutation
```

Multiplayer:
```text
View action -> MultiplayerGameStore -> SessionService -> Convex mutation (server computes outcomes)
views:* subscription -> SubscriptionSupervisor -> MultiplayerGameStore state (assigned as-is) -> SwiftUI refresh
```

## Win Conditions

- Citizens win when no Mafia are alive.
- Mafia win when alive Mafia outnumber alive non-Mafia after a night, or equal or outnumber them after a vote.
- Checks happen after night resolution and after day eliminations; in multiplayer the server runs them.

## Tuist

The Xcode project is generated by Tuist.

Use:
```bash
tuist install
tuist generate
tuist build mafia_manager
tuist test mafia_manager
```

Edit `Project.swift` and `Tuist/Package.swift` for project/dependency changes. Do not hand-edit `.pbxproj`.
