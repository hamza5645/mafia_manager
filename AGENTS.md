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
   - Multiplayer: Convex computes every outcome. Night: `night:recordNightActions` → `night:resolveNightAtomic`. Voting: `voting:closeVoting` → `voting:resolveVoteAtomic`. The host client only requests transitions (`phases:advancePhase`) and drives bots.

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
tuist test mafia_manager
```

Convex:
```bash
npx convex dev
npx convex dev --once
```

Simulator helper:
```bash
./scripts/run_ios_sim.sh
```

## Architecture

### Solo Mode

`GameStore` is the single source of truth. Views call store methods and never mutate the solo state directly.

Critical files:
- `Core/Gameplay/Store/GameStore.swift`
- `Core/Gameplay/Models/GameState.swift`
- `Core/Gameplay/Models/NightAction.swift`
- `Features/Night/NightWakeUpView.swift`
- `App/mafia_managerApp.swift`

### Multiplayer Mode

`MultiplayerGameStore` holds three Convex snapshot subscriptions (`views:getSessionView`, `views:getPlayers`, `views:getRoundState`) and assigns each value directly to store state; everything else is derived. Each subscription is supervised and resubscribed with backoff. Mutations go through `SessionService`.

Critical files:
- `Core/Multiplayer/Store/MultiplayerGameStore.swift` - snapshot state, player actions
- `Core/Multiplayer/Store/MultiplayerGameStore+Connection.swift` - subscriptions, heartbeat, host-offline claim
- `Core/Multiplayer/Store/MultiplayerGameStore+HostPhases.swift` - host transition requests
- `Core/Multiplayer/Store/BotDirector.swift` - host-driven bot actions and votes
- `Core/Multiplayer/Services/SessionService.swift` - Convex mutations
- `Core/Multiplayer/Services/SubscriptionSupervisor.swift` - keeps one subscription alive
- `Core/Multiplayer/Models/` - `GameSession`, `SessionPlayer`, `GameAction`, `SessionSnapshots`
- `convex/schema.ts`, `convex/sessions.ts` (lobby, membership, host), `convex/phases.ts`, `convex/play.ts` (actions, tentative selections), `convex/night.ts`, `convex/voting.ts`, `convex/views.ts` (subscription queries)
- `convex/lib/` - identity, guards, rules, transitions, privacy projections, errors

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

## Backend Setup Notes

`Configuration/Debug.xcconfig` (Debug) and `Configuration/Production.xcconfig` (Release) must contain:
- Convex deployment host (`MAFIA_CONVEX_HOST`).
- Clerk publishable key (`MAFIA_CLERK_PUBLISHABLE_KEY`) and frontend host (`MAFIA_CLERK_FRONTEND_HOST`).

`Core/Backend/ConvexConfig.swift` reads them from Info.plist and stops the app if one is missing; Release also requires a `pk_live_` key.

`convex/auth.config.ts` reads the Clerk issuer/frontend API URL from the Convex `CLERK_FRONTEND_API_URL` environment variable.

Identity is derived on the server; no Convex function accepts a user id. A valid guest proof makes the caller that guest, otherwise the caller is the Clerk user (`identity.subject` → `users.auth_subject`). The guest proof is the sha256 hex of a Keychain secret, sent as `guest_secret_hash`, which `ConvexService` injects into every call. The server stores only `users.guest_secret_digest`, a sha256 of that value.

## Common Gotchas

- Convex Swift `ConvexEncodable` arguments must encode to raw JSON strings.
- Swift dates are encoded as seconds since Apple reference date; Convex timestamp helpers should match that for direct `Date` decoding.
- Role privacy must be enforced in Convex query results, not just hidden in SwiftUI.
- The server issues a new `current_round_id` for each night/voting phase; actions and the record/resolve mutations must carry the current one.
- Subscriptions emit full snapshots that are assigned to store state as-is; there is no diffing or polling.
- Every `ConvexError` is a short user-facing string; Swift shows it through `BackendError`.
- Host players can also have active roles and must still submit their night actions.

## Documentation Index

- `docs/CLAUDE_PRIMER.md` - quick project overview.
- `docs/ARCHITECTURE_NOTES.md` - deeper architecture notes.
- `docs/MULTIPLAYER_GUIDE.md` - multiplayer backend and test guide.
- `docs/CLERK_SETUP.md` - required Clerk dashboard and config values.
- `docs/BACKEND_DECISIONS.md` - why Convex + Clerk, guest proof, legacy-account claiming.
