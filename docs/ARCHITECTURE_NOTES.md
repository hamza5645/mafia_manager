# Architecture Deep Dive

## Solo GameStore Pattern

`GameStore` is the single source of truth for solo mode. It is `@MainActor`, publishes game state, and owns all mutations. Views subscribe to state and call store methods; they should not mutate models directly.

Key solo methods:
- `assignNumbersAndRoles(names:)` - setup, number assignment, and role distribution.
- `endNight(mafiaTargetID:inspectorCheckedID:doctorProtectedID:)` - records night actions without applying deaths.
- `resolveNightOutcome(targetWasSaved:)` - applies the night outcome and checks win conditions.
- `recordVote(from:for:)` and `applyVotingResult()` - record day votes, then eliminate and check win conditions.
- At game over the store queues the finished game in `StatsOutbox`, which sends it with `stats:recordGame`.

## Night Resolution

Night resolution must remain two-phase.

1. `NightWakeUpView` collects role actions and calls `endNight()`.
2. The outcome UI asks whether the Doctor save worked.
3. `resolveNightOutcome()` applies death/save state and marks the night as resolved.

Human and bot turns share `NightWakeUpView.finishTurn(_:)`: `completeRoleAction`, then `resolveNightOutcome()` after the Doctor. The timed steps are `.task(id:)` work owned by the view, so End Game cancels them, and both store methods do nothing once the game is over.

Multiplayer keeps the pattern, but Convex computes every outcome:
- players submit actions with `play:submitAction` for the current `round_id`; the host sends all bot actions of a pass with one `play:submitBotActions` call, which validates each item like `submitAction` and reports per-bot results;
- the host's Finish Night calls `night:finishNight`, which runs both steps below in one transaction and is idempotent per round, so every phone sees a single transition;
- the record step (`night:recordNightActions`) checks that every action is in, stores the unresolved night record and locks the night;
- the resolve step (`night:resolveNightAtomic`) applies deaths and saves, checks winners, and moves to `morning` or `game_over`; both steps remain callable on their own;
- voting mirrors it: `voting:closeVoting` tallies the votes, then `voting:resolveVoteAtomic` applies the elimination and starts the next night or ends the game;
- the host client only calls these and `phases:advancePhase`; all are safe to retry and never move the phase backwards.

How the server picks the night outcome:
- Mafia target: once a living human Mafia has named a target, only human rows decide; bot rows only break a tie among the human leaders, then the earliest human row wins. Without a human pick (an all-bot team, or every human abstained) every row counts. Host bots back the human plurality, so they cannot outvote it.
- Night picks and votes on a seat that is no longer alive (left or kicked) are ignored at resolution, and `voteCounts` no longer list departed players. A lone Mafia whose only target left kills nobody. A leave after the vote reveal still removes nobody.
- Re-sending the same target writes nothing (`submitAction`, `setTentativeSelection`, `submitBotActions`).

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
- `convex/sessions.ts` - create/join/leave, kick, host claim, heartbeat (presence), readiness, start, return to lobby.
- `convex/phases.ts` - `advancePhase`.
- `convex/play.ts` - action submission (one at a time, or a batch of bot actions) and tentative selections.
- `convex/night.ts`, `convex/voting.ts` - the record/resolve pairs and `night:finishNight`.
- `convex/views.ts` - the four subscription queries.
- `convex/health.ts` - health check (`api_contract` 5, `min_client_contract` 5; the app blocks online play only when its own contract is older).
- `convex/lib/` - identity, guards, game rules, transitions, presence, privacy projections, error messages.

## Identity Model

App IDs are UUID strings stored in each document's `id` field; `player_stats`, `custom_roles_configs`, `player_groups` and `game_sessions` look them up through `by_app_id`. Clients cannot choose them.

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
- `session_presence` - one row per human seat with its last heartbeat
- `game_actions`
- `tentative_selections`
- `recorded_games` - which games each user has already recorded (makes `stats:recordGame` idempotent)

Core session rules:
- room codes are generated server-side;
- host user ID is stored on `game_sessions`;
- player rows hold public metadata plus private role/number data;
- action rows are keyed by session, round ID, action type, phase index, and actor;
- the server issues a new `current_round_id` for each night and voting phase, which isolates actions and prevents replay;
- presence lives in `session_presence`, not on the seat: `sessions:heartbeat` upserts only the caller's row, so heartbeats never re-run `getPlayers` or `getRoundState`. When the host heartbeats, the server sets each seat's `is_online` (heartbeat within 20 s), writing only seats that changed;
- `views:getHostPresence` reads only the session, the caller's seat and the host's presence row, and returns the host's last heartbeat with the server clock and the stale threshold (90 s while waiting, else 15 s). Any member may then call `sessions:claimHost`; the server installs its own successor (a seat that heartbeated within 15 s), who may be someone other than the caller;
- the client judges the host from the server's age at receipt plus local monotonic time, never from its own clock, and concludes nothing while the socket reconnects. An original host who comes back takes the lobby back with `sessions:returnToLobby` after its first successful heartbeat.

Data lifecycle (`convex/crons.ts` → `cleanup:sweep`, hourly at minute 17 UTC, 20 rooms per transaction):
- lobbies and games with no presence heartbeat for 6 h are cancelled; rooms from before `session_presence` fall back to the seats' `last_heartbeat` or `joined_at`, and `updated_at` is never used;
- finished games lose seats, presence, actions and drafts 24 h after `completed_at`;
- cancelled and finished rooms are deleted after 30 days, which frees their room codes;
- guest user rows are not deleted. Dev QA data is removed with the env-gated `testing:purgeQa` (see `AGENTS.md`).

Guest merge (`users:mergeGuestIntoAccount`):
- a seat conflict refuses the merge only for an `in_progress` room, and the message names the room; in other rooms the seat used last (presence heartbeat, else the seat's old `last_heartbeat`, else `joined_at`) is kept and the other seat is deleted;
- only waiting, in-progress, and finished-with-a-guest-seat rooms change host fields; the guest's `recorded_games` move to the account; `merged_guest_digests` keeps the last 20.

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
Game over -> GameStore queues the game in StatsOutbox (file) -> stats:recordGame (all rows in one transaction, idempotent per game id)
```
The outbox flushes on enqueue, on an identity change and when the app returns from the background, and keeps an entry until the server acknowledges it. An account's games are sent only for that account; games played as a guest or signed out go to the next identity on the device.

Multiplayer:
```text
View action -> MultiplayerGameStore -> SessionService -> Convex mutation (server computes outcomes)
views:* subscription -> SubscriptionSupervisor -> MultiplayerGameStore state (assigned as-is) -> SwiftUI refresh
```
Contract fixtures in `tests/fixtures/contract/` are real `views:*` and mutation results from convex-test; the Swift tests decode them, so a shape change fails both suites.

## Win Conditions

The rule is the same in solo and multiplayer (parity):
- Citizens win when no Mafia are alive.
- Mafia win when alive Mafia are at least the alive non-Mafia, after a night and after a vote.
- When only bots are alive the game ends: Citizens win if no Mafia remain, otherwise Mafia.
- Checks happen after night resolution and after day eliminations; in multiplayer the server runs them. `tests/fixtures/rules-parity.json` holds the shared cases (with the role table, target rules and shared error strings) and is checked by vitest and by the Swift tests.
- Nobody alive ends the game with no winner.
- Changed in contract 5: a multiplayer night that leaves N Mafia against N others now ends the game instead of playing another day, and a solo game where only bots are alive ends at once.

## Tuist

The Xcode project is generated by Tuist.

Use:
```bash
tuist install
tuist generate
tuist build mafia_manager
tuist test mafia_manager --no-selective-testing
```

Edit `Project.swift` and `Tuist/Package.swift` for project/dependency changes. Do not hand-edit `.pbxproj`.
