# AGENTS.md

This file provides guidance to Codex when working in this repository.

## Project Overview

**Mafia Manager** is an iOS game assistant for the party game Mafia.

Modes:
- **Solo mode**: pass-and-play on one device, fully offline.
- **Multiplayer mode**: multi-device gameplay with room codes, Convex realtime/database, and Clerk account auth.

Tech stack:
- SwiftUI + MVVM
- iOS 26+
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

3. **Preserve the two-phase night pattern.**
   - Solo: `endNight()` records actions; `resolveNightOutcome()` applies outcomes.
   - Multiplayer: record submitted actions first; apply final night state through the Convex atomic night mutation.

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

`MultiplayerGameStore` coordinates room/session state and calls:
- `SessionService` for Convex mutations and snapshots.
- `RealtimeService` for Convex reactive subscriptions.

Critical files:
- `Core/Multiplayer/Store/MultiplayerGameStore.swift`
- `Core/Multiplayer/Services/SessionService.swift`
- `Core/Multiplayer/Services/RealtimeService.swift`
- `Core/Multiplayer/Models/GameSession.swift`
- `Core/Multiplayer/Models/SessionPlayer.swift`
- `Core/Multiplayer/Models/GameAction.swift`
- `convex/schema.ts`
- `convex/sessions.ts`

### Auth and Cloud Data

Auth/account state:
- `Core/Auth/Store/AuthStore.swift`
- `Core/Auth/Services/AuthService.swift`
- `Core/Auth/Models/UserProfile.swift`

Backend wiring:
- `Core/Backend/ConvexConfig.swift`
- `Core/Backend/ConvexService.swift`
- `Core/Backend/DatabaseService.swift`

Convex backend:
- `convex/auth.config.ts`
- `convex/users.ts`
- `convex/stats.ts`
- `convex/health.ts`

## Backend Setup Notes

`Core/Backend/ConvexConfig.swift` must contain:
- Convex deployment URL.
- Clerk publishable key.

`convex/auth.config.ts` reads the Clerk issuer/frontend API URL from the Convex `CLERK_FRONTEND_API_URL` environment variable.

Guest mode uses a local Keychain secret hashed into `users.guest_secret_hash`; account mode uses Clerk identity subject mapped into `users.auth_subject`.

## Common Gotchas

- Convex Swift `ConvexEncodable` arguments must encode to raw JSON strings.
- Swift dates are encoded as seconds since Apple reference date; Convex timestamp helpers should match that for direct `Date` decoding.
- Role privacy must be enforced in Convex query results, not just hidden in SwiftUI.
- `current_round_id` must be regenerated for each night/voting phase so old actions cannot replay.
- Realtime subscriptions emit snapshots; `RealtimeService` diffs snapshots into app events.
- Host players can also have active roles and must still submit their night actions.

## Documentation Index

- `docs/CLAUDE_PRIMER.md` - quick project overview.
- `docs/ARCHITECTURE_NOTES.md` - deeper architecture notes.
- `docs/MULTIPLAYER_GUIDE.md` - multiplayer backend and test guide.
- `docs/CLERK_SETUP.md` - required Clerk dashboard and config values.
- `docs/SUPABASE_TO_CONVEX_MIGRATION_PLAN.md` - migration plan and audit history.
