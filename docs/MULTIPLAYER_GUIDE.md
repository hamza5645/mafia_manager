# Multiplayer Mafia Manager

## Overview

Multiplayer mode turns the local pass-and-play Mafia assistant into online rooms where each player uses their own device. Convex is the authoritative backend for room state, actions, realtime updates, and game resolution. Clerk is the account auth provider, while guest mode uses a Convex guest profile.

## Architecture

Three layers:
- **Personal layer**: my role, my number, my submitted actions.
- **Shared layer**: room code, lobby players, alive/dead state, votes, announcements.
- **Authority layer**: Convex functions that store roles/actions and resolve phase transitions.

Key components:
- `MultiplayerGameStore` - coordinates multiplayer UI state.
- `SessionService` - Convex mutations and snapshot queries.
- `RealtimeService` - Convex reactive query subscriptions.
- `convex/sessions.ts` - server-side room, player, action, and phase logic.

## Backend Setup

1. Start Convex:
```bash
npx convex dev
```

2. Configure Clerk for the app:
- set the Clerk publishable key in `Core/Backend/ConvexConfig.swift`;
- set the real Clerk issuer/frontend API URL in `convex/auth.config.ts`;
- configure the Clerk Convex JWT integration/template in the Clerk dashboard.

3. Validate functions:
```bash
npx convex dev --once
```

## Game Flow

1. Host creates a session and receives a 6-digit room code.
2. Players join by room code.
3. Host starts the game once enough players are ready.
4. Convex stores role and number assignments.
5. Players reveal roles on their own devices.
6. Night actions are submitted as Convex `game_actions`.
7. Host resolves the night with the two-phase pattern.
8. Day voting writes vote actions and advances to results.
9. Convex stores completed game state and winner.

## Privacy Rules

Convex filters `session_players` in `sessions:getSessionPlayers`.

- A player sees their own role.
- Mafia see other Mafia roles.
- The host sees all roles.
- Everyone sees final roles after game over.
- Other roles are omitted from the query result, not merely hidden in SwiftUI.

For guest multiplayer, the app passes the current Convex app user ID to the player query so the server can apply the same visibility rules even without a Clerk session.

## Realtime

`RealtimeService` subscribes to these Convex queries:
- `sessions:getSessionById`
- `sessions:getSessionPlayers`
- `sessions:getAllActions`
- `sessions:listTentativeSelectionsForSession`

Each subscription emits full query snapshots. `RealtimeService` diffs snapshots locally and forwards changed session/player/action/tentative-selection events to `MultiplayerGameStore`.

## Core API

`SessionService`:
```swift
createSession(hostUserId:maxPlayers:botCount:) async throws -> GameSession
joinSession(roomCode:userId:playerName:) async throws -> (GameSession, SessionPlayer)
leaveSession(sessionId:userId:) async throws
getSessionPlayers(sessionId:viewerUserId:) async throws -> [SessionPlayer]
assignRolesAndNumbers(sessionId:assignments:) async throws
submitAction(_:) async throws -> ActionResponse
resolveNightAtomic(...) async throws -> Bool
```

`MultiplayerGameStore`:
```swift
createSession(playerName:botCount:nightTimerSeconds:dayTimerSeconds:) async throws
joinSession(roomCode:playerName:) async throws
leaveSession() async throws
startGame() async throws
submitNightAction(actionType:nightIndex:targetPlayerId:) async throws
submitVote(dayIndex:targetPlayerId:) async throws
toggleReady() async throws
```

## Testing

Use multiple simulator/device instances to verify realtime behavior.

Test scenarios:
- room creation and joining;
- guest profile restoration;
- Clerk account sign-in once real keys are configured;
- role privacy for host, Mafia, and non-Mafia players;
- night action submission and `resolveNightAtomic`;
- voting and tie/no-elimination behavior;
- reconnect after backgrounding;
- bot auto-actions;
- completed-game stats sync.

## Troubleshooting

- Run `npx convex dev --once` to catch schema/function errors.
- Use Convex dashboard logs for backend exceptions.
- Check `ConvexConfig.clerkPublishableKey` and `convex/auth.config.ts` if Clerk users cannot authenticate to Convex.
- Check `current_round_id` if old actions appear to affect a new night or vote.
- Check `phase_sequence` and trigger a snapshot resync if a device misses a realtime update.
