# Multiplayer Mafia Manager

## Overview

Multiplayer mode turns the local pass-and-play Mafia assistant into online rooms where each player uses their own device. Convex is the authoritative backend: it stores room state, actions and roles, and it computes every night and vote outcome. Clerk is the account auth provider, while guest mode uses a Convex guest profile.

## Architecture

- **Server (Convex)** validates every action and transition, computes outcomes and win checks, and projects private data per viewer.
- **Host client** only requests transitions and drives the bots. It never writes outcomes.
- **Every client** sends its own actions and renders three snapshot subscriptions.

Key components:
- `MultiplayerGameStore` (+`Connection`, +`HostPhases`) - snapshot state, player actions, host requests, heartbeat.
- `BotDirector` - host-side bot actions and votes, driven by `views:getRoundState` snapshots.
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
node scripts/e2e/verify-deployment.mjs
```

## Game Flow

1. The host calls `sessions:createSession`. The server creates the 6-digit room code, the host seat and the bot seats.
2. Players join with `sessions:joinSession`. Rejoining restores the existing seat.
3. The host calls `sessions:startGame`, which assigns every role and number in one mutation and enters `role_reveal`.
4. Players reveal their roles and mark ready. The host calls `phases:advancePhase(night)`.
5. Night: players submit `play:submitAction` for the current `round_id`. The host calls `night:recordNightActions`, then `night:resolveNightAtomic`, which moves to `morning` or `game_over`.
6. The host calls `phases:advancePhase(death_reveal)`, then `phases:advancePhase(voting)`.
7. Voting: players submit votes. The host calls `voting:closeVoting` (results), `phases:advancePhase(vote_death_reveal)`, then `voting:resolveVoteAtomic`, which starts the next night or ends the game.
8. Play Again calls `sessions:returnToLobby`; the host's End Game calls `sessions:cancelSession`.

Host calls are safe to retry. Clients heartbeat every 5 s. If the host's heartbeat is older than 15 s, the successor calls `sessions:claimHost`.

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

Each snapshot is assigned directly to store state; everything else is derived. There is no diffing or polling. A `SubscriptionSupervisor` resubscribes after a failure with `min(30, 2^attempt)` s backoff and jitter. It also restarts on app foreground and on an identity change, when the guest proof changes.

## Testing

Use multiple simulator/device instances to verify realtime behavior.

Test scenarios:
- room creation and joining;
- guest profile restoration;
- Clerk account sign-in;
- role privacy for host, Mafia, and non-Mafia players;
- night action submission and `night:resolveNightAtomic`;
- voting and tie/no-elimination behavior;
- reconnect after backgrounding;
- bot auto-actions;
- completed-game stats sync.

Server rules are covered by `npm run test:backend`.

## Troubleshooting

- Run `npx convex dev --once` to catch schema/function errors.
- Use Convex dashboard logs for backend exceptions.
- Check `MAFIA_CLERK_PUBLISHABLE_KEY` in `Configuration/*.xcconfig` and `CLERK_FRONTEND_API_URL` on the deployment if Clerk users cannot authenticate to Convex.
- Errors from Convex are short user-facing strings; anything else shows a generic message.
- Check `current_round_id` if an action or host call is rejected as belonging to an old round.
