# Multiplayer Mafia Manager

## Overview

Multiplayer mode turns the local pass-and-play Mafia assistant into online rooms where each player uses their own device. Convex is the authoritative backend: it stores room state, actions and roles, and it computes every night and vote outcome. Clerk is the account auth provider, while guest mode uses a Convex guest profile.

## Architecture

- **Server (Convex)** validates every action and transition, computes outcomes and win checks, and projects private data per viewer.
- **Host client** only requests transitions and drives the bots. It never writes outcomes.
- **Every client** sends its own actions and renders four snapshot subscriptions.

Key components:
- `MultiplayerGameStore` (+`Connection`, +`HostPhases`) - snapshot state, player actions, host requests, heartbeat.
- `BotDirector` - host-side bot actions and votes, driven by `views:getRoundState` snapshots and sent in one `play:submitBotActions` call per pass.
- `SessionService` - Convex mutations.
- `SubscriptionSupervisor` - keeps one subscription alive.
- `convex/sessions.ts`, `phases.ts`, `play.ts`, `night.ts`, `voting.ts`, `views.ts` - server logic; shared helpers are in `convex/lib/`.

Identity: no function takes a user id. The server derives the caller: a valid guest proof (`guest_secret_hash`, injected by `ConvexService`) means that guest, otherwise the Clerk user.

## Backend Setup

1. Start Convex:
```bash
npx convex dev
```

2. Configure Clerk for the app:
- set the Clerk publishable key in `Configuration/Debug.xcconfig` (Release: `Configuration/Production.xcconfig`);
- set `CLERK_FRONTEND_API_URL` on the Convex deployment (read by `convex/auth.config.ts`);
- configure the Clerk `convex` JWT template (audience `convex`, including `email_verified`) in the Clerk dashboard.

3. Validate functions and the API contract:
```bash
npx convex dev --once
node scripts/e2e/verify-deployment.mjs          # development; --prod checks Configuration/Production.xcconfig's deployment
```
The check passes when the deployment's `api_contract` is at least the app's `ConvexConfig.apiContractVersion` (5) and its `min_client_contract` is at most the app's. `npm run convex:deploy` runs the backend tests, deploys, then runs the check with `--prod`. Backend and app ship together at contract 5.

## Game Flow

1. The host calls `sessions:createSession`. The server creates the 6-digit room code, the host seat and the bot seats.
2. Players join with `sessions:joinSession`. Rejoining restores the existing seat and returns `rejoined: true`, so a cancelled re-entry keeps it.
3. The host calls `sessions:startGame`, which assigns every role and number in one mutation and enters `role_reveal`.
4. Players reveal their roles and mark ready (`sessions:setReady` with `phase: "role_reveal"`; the server ignores it in any other phase). The host calls `phases:advancePhase(night)`.
5. Night: players submit `play:submitAction` for the current `round_id`; the host sends the bots' actions with `play:submitBotActions`. The host's Finish Night calls `night:finishNight`, which records the night and resolves it in one transaction and moves to `morning` or `game_over`. (`night:recordNightActions` and `night:resolveNightAtomic` remain as the two separate steps.)
6. The host calls `phases:advancePhase(death_reveal)`, then `phases:advancePhase(voting)`.
7. Voting: players submit votes. The host calls `voting:closeVoting` (results), `phases:advancePhase(vote_death_reveal)`, then `voting:resolveVoteAtomic`, which starts the next night or ends the game.
8. Play Again calls `sessions:returnToLobby`; the host's End Game calls `sessions:cancelSession`.

The host sees who the phase is waiting for (role reveal, night, voting), with an offline badge and Remove; a removed player can rejoin only after the game ends. The host can start the night before everyone confirmed their role. Night finishes on its own for a citizen or eliminated host; an alive Inspector host taps Finish Night.

Host calls are safe to retry. Clients heartbeat every 5 s with `sessions:heartbeat`, which writes only the caller's `session_presence` row; the host's heartbeat also refreshes each seat's `is_online`. Clients watch the host through `views:getHostPresence`, which compares the host's last heartbeat with the server clock. Once the host is stale (90 s in the lobby, 15 s in a game), any member may call `sessions:claimHost`, and the server installs the successor.

## Privacy Rules

`convex/lib/projections.ts` filters every `views:*` result for the caller:

- A player sees their own role.
- Mafia see other Mafia roles.
- The host sees all roles, because it drives the bots.
- Everyone sees final roles after game over.
- During the night, non-host viewers see every other seat as not ready.
- Other roles are omitted from the query result, not merely hidden in SwiftUI.

## Realtime

`MultiplayerGameStore` subscribes to:
- `views:getSessionView`
- `views:getPlayers`
- `views:getRoundState`
- `views:getHostPresence` (reads only the host's presence row, so other players' heartbeats never re-run it)

Each snapshot is assigned directly to store state unless it equals the current value; everything else is derived. There is no polling. A `SubscriptionSupervisor` resubscribes after a failure with `min(30, 2^attempt)` s backoff and jitter. It also restarts on app foreground and when the guest proof changes. A value that fails to decode twice in a row stops the subscription and asks for an app update (`BackendCompatibility`).

A 5 s ticker heartbeats, checks the host and re-runs host automation, so failed bot submissions and the role-reveal advance retry without new snapshots. Heartbeats and host claims go one at a time with the 12 s mutation limit, so a call that never returns cannot stop them and an outage queues one per limit, not one per tick. Create and join stop the user's wait after 12 s; a room or new seat that arrives later, or after a Cancel, is given back. "Reconnecting…" shows after 3 failed retries, 2.5 s of socket reconnecting, or a tap still sending after 5 s; the banner always has Retry.

## Testing

Use multiple simulator/device instances to verify realtime behavior.

Test scenarios:
- room creation and joining;
- guest profile restoration;
- Clerk account sign-in;
- role privacy for host, Mafia, and non-Mafia players;
- night action submission and `night:finishNight`;
- voting and tie/no-elimination behavior;
- reconnect after backgrounding;
- bot auto-actions;
- completed-game stats sync.

Server rules are covered by `npm run test:backend`, which type-checks the tests and then checks `tests/fixtures/rules-parity.json` (role table, target rules, parity win cases, shared error strings) and the contract fixtures in `tests/fixtures/contract/` that the Swift decoding tests read. A normal run fails when either drifts; regenerate on purpose with `npx vitest run tests/convex/contract.test.ts -u` or `npx vitest run tests/convex/rules-parity.test.ts -u` and update the Swift side in the same change. CI runs it on every pull request.

The store runs against `FakeSessionService` and `ManualClock` in unit tests (`MultiplayerStoreTests`, `BotDirectorTests`, `SubscriptionSupervisorTests`). The live suite is opt-in: `TEST_RUNNER_CONVEX_INTEGRATION=1`, and in Debug `TEST_RUNNER_MAFIA_CONVEX_URL=<url>` for another backend. It runs one live store per identity and names its guests `QA …`, which the dev-only `testing:purgeQa` mutation removes (see `AGENTS.md`).

Win rule (both modes): Mafia win when living Mafia are at least the living non-Mafia, after a night and after a vote; Citizens win when no Mafia are alive; a game with only bots alive ends.

## Troubleshooting

- Run `npx convex dev --once` to catch schema/function errors.
- Use Convex dashboard logs for backend exceptions.
- Check `MAFIA_CLERK_PUBLISHABLE_KEY` in `Configuration/*.xcconfig` and `CLERK_FRONTEND_API_URL` on the deployment if Clerk users cannot authenticate to Convex.
- Errors from Convex are short user-facing strings; anything else shows a generic message.
- Check `current_round_id` if an action or host call is rejected as belonging to an old round.
