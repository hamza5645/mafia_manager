mafia_manager (SwiftUI, iOS 18+)
================================

**Version 5.0** - An autonomous game manager for the party game Mafia. The app supports local pass-and-play and online multiplayer rooms. It is built with SwiftUI, MVVM, Tuist, local JSON persistence, Convex for backend data/realtime, and Clerk for account auth.

Targets and identifiers
- Bundle Identifier: `com.hamza5645.mafia`
- Version: 5.0
- Minimum iOS: 18.0

Backend
- **Convex**: authoritative multiplayer state, room codes, night/vote outcomes, win checks, role privacy, realtime subscriptions, stats, custom role configs, and player groups. The server derives the caller from the guest proof or Clerk token; functions never take user ids.
- **Clerk**: email/password account auth, password reset, and Convex authentication tokens.
- **Guest mode**: local Keychain guest secret mapped to a Convex guest profile for quick multiplayer entry.
- Convex dev deployment: `https://energized-herring-345.eu-west-1.convex.cloud`

Prerequisites
- Xcode 27 and Tuist 4.198.1 on an Apple Silicon Mac (simulator builds exclude x86_64 because ConvexMobile ships no Intel slice). `mise.toml` pins Tuist and Node: `mise trust && mise install`.
- Clone outside iCloud-synced folders (`~/Documents`, `~/Desktop`): iCloud conflict copies break the Tuist build.
- Node >= 22.12, then `npm ci` and `npm run test:backend` for the Convex function tests.
- Convex/Clerk dashboard access is needed only for backend changes and the opt-in live integration tests.

Build and test
```bash
tuist install
tuist generate
tuist build mafia_manager
tuist test mafia_manager --no-selective-testing
npm run test:backend
```

CI (`.github/workflows/ci.yml`) runs the backend tests on every pull request and the iOS unit tests on pull requests into `main`.

Convex development
```bash
npx convex dev
npx convex dev --once
```

Required app configuration
- `Configuration/Debug.xcconfig` (Debug) and `Configuration/Production.xcconfig` (Release) hold the Convex host, Clerk publishable key and Clerk frontend host; `ConvexConfig` reads them from Info.plist.
- `CLERK_FRONTEND_API_URL` is set in the Convex dev deployment.
- See `docs/CLERK_SETUP.md` for Clerk dashboard/config notes.

Game Flow
1. **Setup**: Enter 4-19 unique player names; numbers are unique random values from 1-99.
2. **Role Reveal**: Sequential role reveals with privacy screens.
3. **Night Phase**: Mafia, Inspector, and Doctor act with role-specific targeting rules.
4. **Morning Summary**: Shows night results after two-phase resolution.
5. **Day Phase**: Public discussion and voting.
6. **Game Over**: Detects Citizens or Mafia victory (Mafia win at parity). Finished games are queued in a local outbox and recorded with `stats:recordGame` once signed in.

Key architecture patterns
- **Tuist-managed project**: edit `Project.swift` and `Tuist/Package.swift`, then regenerate. Do not hand-edit `.pbxproj`.
- **Phase-based state machine**: `GamePhase` drives solo navigation; multiplayer phases live in `GameSession.currentPhaseData`.
- **Single source of truth**: solo state lives in `GameStore`; multiplayer state lives in `MultiplayerGameStore`.
- **Two-phase resolution**: `endNight()` records actions, then `resolveNightOutcome()` applies outcomes. Multiplayer does the same on the server: `night:finishNight` runs the record and resolve steps in one transaction, and `voting:closeVoting` → `voting:resolveVoteAtomic`; the host only requests transitions and drives bots.
- **Snapshot data flow**: `MultiplayerGameStore` assigns four supervised Convex subscriptions (`views:getSessionView`, `views:getPlayers`, `views:getRoundState`, `views:getHostPresence`) straight to state.
- **Backend service layer**: `ConvexService`, `AuthService`, `DatabaseService`, `SessionService`, and `SubscriptionSupervisor`.

Project structure
- `App/` - app entry point and root routing
- `Core/Auth/` - Clerk/guest auth facade and user profile model
- `Core/Backend/` - Convex config, Convex client singleton, stats/storage facade
- `Core/Gameplay/` - solo models, persistence, and `GameStore`
- `Core/Multiplayer/` - multiplayer models, services, and store
- `Core/Stats/` - player stats, custom roles, and player groups
- `Features/` - SwiftUI screens
- `convex/` - Convex schema and backend functions
- `docs/` - architecture and migration notes
