mafia_manager (SwiftUI, iOS 26+)
================================

**Version 3.0** - An autonomous game manager for the party game Mafia. The app supports local pass-and-play and online multiplayer rooms. It is built with SwiftUI, MVVM, Tuist, local JSON persistence, Convex for backend data/realtime, and Clerk for account auth.

Targets and identifiers
- Bundle Identifier: `com.hamza.mafia-manager`
- Version: 3.0
- Minimum iOS: 26.0

Backend
- **Convex**: authoritative multiplayer state, room codes, player/action documents, realtime subscriptions, stats, custom role configs, and player groups.
- **Clerk**: email/password account auth, password reset, and Convex authentication tokens.
- **Guest mode**: local Keychain guest secret mapped to a Convex guest profile for quick multiplayer entry.
- Convex dev deployment: `https://energized-herring-345.eu-west-1.convex.cloud`

Build and test
```bash
tuist install
tuist generate
tuist build mafia_manager
tuist test mafia_manager
```

Convex development
```bash
npx convex dev
npx convex dev --once
```

Required app configuration
- `Core/Backend/ConvexConfig.swift` contains the Convex deployment URL.
- `Core/Backend/ConvexConfig.swift` contains the Clerk publishable key.
- `CLERK_FRONTEND_API_URL` is set in the Convex dev deployment.
- See `docs/CLERK_SETUP.md` for Clerk dashboard/config notes.

Game Flow
1. **Setup**: Enter 4-19 unique player names; numbers are unique random values from 1-99.
2. **Role Reveal**: Sequential role reveals with privacy screens.
3. **Night Phase**: Mafia, Inspector, and Doctor act with role-specific targeting rules.
4. **Morning Summary**: Shows night results after two-phase resolution.
5. **Day Phase**: Public discussion and voting.
6. **Game Over**: Detects Citizens or Mafia victory and can sync stats to Convex when authenticated.

Key architecture patterns
- **Tuist-managed project**: edit `Project.swift` and `Tuist/Package.swift`, then regenerate. Do not hand-edit `.pbxproj`.
- **Phase-based state machine**: `GamePhase` drives solo navigation; multiplayer phases live in `GameSession.currentPhaseData`.
- **Single source of truth**: solo state lives in `GameStore`; multiplayer state lives in `MultiplayerGameStore`.
- **Two-phase night resolution**: `endNight()` records actions, then `resolveNightOutcome()` applies outcomes. Multiplayer mirrors this with Convex mutations and `resolveNightAtomic`.
- **Backend service layer**: `ConvexService`, `AuthService`, `DatabaseService`, `SessionService`, and `RealtimeService`.

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
