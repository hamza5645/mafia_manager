# Mafia Manager - Quick Start

**What it is**: Offline-first iOS game assistant for Mafia with optional online multiplayer. Built with SwiftUI, MVVM, Tuist, local JSON persistence, Convex backend/realtime, and Clerk account auth.

**Key directories**:
- `App/` - app entry point and root phase routing
- `Core/` - domain logic (`Auth`, `Backend`, `Gameplay`, `Multiplayer`, `Stats`, `Support`)
- `Features/` - SwiftUI views
- `convex/` - Convex schema, queries, mutations, auth config, and generated API files
- `scripts/` - simulator launch helper, Clerk test-user cleanup, deployment check (`e2e/`)

**Run on simulator** (runs `tuist install` and `tuist generate`, then builds, boots the simulator if needed, installs and launches; defaults to the first available iPhone):
```bash
./scripts/run_ios_sim.sh ["iPhone 18 Pro"]
```

**Tuist build/test**:
```bash
tuist install
tuist generate
tuist build mafia_manager
tuist test mafia_manager --no-selective-testing
npm run test:backend
```

**Convex backend**:
```bash
npx convex dev
npx convex dev --once
```

**Critical architecture**:
- `GameStore` owns solo game mutations. Views never mutate solo state directly.
- Night resolution is two-phase: `endNight()` records actions, then `resolveNightOutcome()` applies deaths.
- Multiplayer outcomes are computed by Convex with the same pattern (`night:finishNight` runs `recordNightActions` then `resolveNightAtomic` in one transaction; `voting:closeVoting` → `voting:resolveVoteAtomic`). The host only requests transitions (`phases:advancePhase`) and drives bots.
- Solo persistence writes JSON to Application Support.
- Multiplayer sends mutations through `SessionService` and assigns four supervised subscriptions (`views:getSessionView`, `views:getPlayers`, `views:getRoundState`, `views:getHostPresence`) directly to `MultiplayerGameStore` state.
- Custom roles and player groups sync through `DatabaseService`; finished solo games go through `StatsOutbox` to `stats:recordGame`.

**Auth setup**:
- Clerk is the account auth provider.
- Clerk publishable key is configured in `Configuration/Debug.xcconfig` (Release: `Configuration/Production.xcconfig`).
- `CLERK_FRONTEND_API_URL` is set in the Convex dev deployment for account auth.
- Guest mode uses a Keychain secret and a Convex guest profile for quick play. `ConvexService` sends its sha256 as `guest_secret_hash`; the server derives the caller, so no function takes a user id.
- See `docs/CLERK_SETUP.md` before testing account sign-in.

**Read next**: `docs/ARCHITECTURE_NOTES.md`, `docs/MULTIPLAYER_GUIDE.md`, `docs/CLERK_SETUP.md`, and `docs/BACKEND_DECISIONS.md`.
