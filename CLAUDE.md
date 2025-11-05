# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Mafia Manager** is an offline-first iOS game assistant for the party game Mafia, built with SwiftUI (iOS 16+) using MVVM architecture. The app manages game state locally via JSON persistence and optionally syncs player statistics to Supabase when authenticated.

**Key Technologies**: Swift 5.10+, SwiftUI, Supabase (Auth + PostgREST), iOS 26.0 target

**Bundle ID**: `com.example.mafia_manager` (change in Xcode if deploying)

## Building and Running

### iOS Simulator (Recommended)
```bash
# Build, sign, and launch on iPhone 17 Pro simulator
./scripts/run_ios_sim.sh
```

The script:
- Builds for iOS Simulator with code signing disabled
- Ad-hoc signs the .app bundle
- Boots the simulator if needed
- Installs and launches the app
- Outputs logs to `/tmp/run_ios_sim_*.log`

To change the target simulator, edit `SIMULATOR_NAME` in `scripts/run_ios_sim.sh`.

### Xcode Build
```bash
xcodebuild \
  -project mafia_manager.xcodeproj \
  -scheme mafia_manager \
  -configuration Debug \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  build
```

### Running on Physical Device
Open `mafia_manager.xcodeproj` in Xcode, select your device as the destination, configure code signing in Build Settings, and run.

## Architecture Overview

### Core Design Pattern: Single Source of Truth

**GameStore** (`Core/Store/GameStore.swift`) is the heart of the app:
- `@MainActor` ObservableObject holding the entire `GameState`
- All game logic mutations flow through GameStore methods
- Automatically persists to JSON after every state change
- No view directly mutates game state; all changes via store methods

**AuthStore** (`Core/Store/AuthStore.swift`) manages authentication:
- Handles Supabase Auth lifecycle (signup, signin, signout)
- Maintains `isAuthenticated`, `currentUserId`, and `userProfile` state
- Async listener for auth state changes
- Error mapping for user-friendly messages

### Directory Structure

```
Core/
├── Models/          # Codable game state models (GameState, Player, Role, NightAction, DayAction)
│                    # Cloud models (PlayerStats, UserProfile, CustomRoleConfig)
├── Store/           # GameStore (game logic + local persistence) and AuthStore
├── Services/        # Persistence (JSON), AuthService, DatabaseService, SupabaseService/Config
└── UI/              # DesignSystem (colors, card styles), RoleStyle (role-specific visuals)

Features/
├── Setup/           # Initial player name entry
├── Assignments/     # Role assignment display (private cards)
├── Night/           # NightPhaseView (record actions) + NightOutcomeView (resolve deaths)
├── Morning/         # MorningSummaryView (display night results)
├── Day/             # DayManagementView (record removals/lynching)
├── GameOver/        # GameOverView (winner display + export log + cloud sync)
├── Auth/            # LoginView, SignupView, ProfileView
├── Settings/        # SettingsView (hub for Profile/Stats/Custom Roles)
└── Stats/           # PlayerStatsView, CustomRolesView (Supabase-backed)

mafia_managerApp.swift  # Entry point: creates GameStore + AuthStore, shows RootView
```

### Critical Game Flow

#### Setup → Night → Day Loop

1. **Setup**: User enters 4-19 names → `GameStore.assignNumbersAndRoles(names:)` generates unique numbers (1-99 range) and distributes roles per booklet rules
2. **Assignments**: Display private cards (number + role) to each player
3. **Night Phase** (TWO-STEP PROCESS):
   - `NightPhaseView`: Record Mafia target, Police check, Doctor protect → call `store.endNight(...)` (does NOT apply deaths yet)
   - `NightOutcomeView`: User confirms if target died or was saved → call `store.resolveNightOutcome(targetWasSaved:)` (applies death, checks win conditions)
4. **Morning**: Display night results (numbers only), show Police identity check, show if Doctor protected
5. **Day**: Mark removals (voting/lynching) → `store.applyDayRemovals(...)` → checks win conditions
6. **Game Over**: If win condition met, sync stats to Supabase (if authenticated), display winner, allow log export

#### Win Conditions (checked at multiple points)
- **Citizens win**: No alive Mafia remain (checked after night resolution)
- **Mafia win**: Alive Mafia >= Alive Non-Mafia (checked at day start AND after day removals)

### Role Distribution Algorithm

Hardcoded in `GameStore.roleDistribution(playerCount:)`:
```
4-5 players:   1 Mafia, 0-1 Doctor, 1 Police, rest Citizens
6-8 players:   2 Mafia, 1 Doctor, 1 Police, rest Citizens
9-14 players:  4 Mafia, 1 Doctor, 2 Police, rest Citizens
15-19 players: 5 Mafia, 2 Doctors, 2 Police, rest Citizens
```

Roles are shuffled independently from names and numbers to ensure randomness.

### Persistence System

#### Local (JSON)
- **Location**: Application Support/`com.example.mafia_manager/GameState.json`
- **Strategy**: Save after every mutation (atomic writes, pretty-printed)
- **Models**: All game state is `Codable` and persisted via `Persistence.shared`

#### Cloud (Supabase)
- **Tables**: `profiles`, `player_stats`, `custom_roles_configs`
- **RLS**: All tables restrict access to `auth.uid()` (users only see/modify their own rows)
- **Sync**: Only on game completion via `GameStore.syncPlayerStatsToCloud()` (called from GameOverView)
- **Schema**: See `supabase/setup.sql` for full DDL

#### Database Setup
1. Run `supabase/setup.sql` in Supabase SQL Editor
2. Disable email confirmation: Authentication → Providers → Email → turn off "Confirm email"
3. Update `Core/Services/SupabaseConfig.swift` with your project URL and anon key

### Key Models & Relationships

- **GameState**: Root model containing `players: [Player]`, `nightHistory: [NightAction]`, `dayHistory: [DayAction]`, `dayIndex`, `isGameOver`, `winner`
- **Player**: `id` (UUID), `number` (1-99), `name`, `role` (enum), `alive` (Bool), `removalNote`
- **NightAction**: Records night phase actions (targets, inspector results, deaths, mafia snapshot)
- **DayAction**: Records `dayIndex` and `removedPlayerIDs`
- **PlayerStats**: Cloud-synced cumulative stats (games played/won/lost, role counts, kills)

### Night Resolution: Two-Phase System

**Critical Implementation Detail**:
1. `GameStore.endNight(...)` - Records night actions WITHOUT applying deaths (creates NightAction)
2. `GameStore.resolveNightOutcome(targetWasSaved:)` - Applies death (or not), updates `resultingDeaths`, checks win conditions

This split allows the UI to ask the user if the Doctor saved the target before committing the death.

### Inspector (Police) Logic

- **Cannot check other inspectors** (targeting rule in NightPhaseView)
- **Returns full Role** if target is not an inspector
- Stores both `inspectorResultIsMafia: Bool?` and `inspectorResultRole: Role?` in NightAction

### Mafia Kill Attribution

When syncing stats, kills are attributed by:
1. Scanning `nightHistory` for nights where `resultingDeaths.count > 0`
2. Finding all alive Mafia during that night
3. Incrementing `totalKills` for each alive Mafia

This means all Mafia share credit for each kill.

### Service Architecture

#### AuthService (@MainActor)
- Wraps Supabase Auth client
- Methods: `signUp`, `signIn`, `signOut`, `resetPasswordForEmail`, `onAuthStateChange` (async stream)
- Profile creation automatic via Supabase trigger (no manual `createUserProfile` call)

#### DatabaseService (@MainActor)
- All PostgREST operations (CRUD for `player_stats`, `custom_roles_configs`)
- Uses `upsertPlayerStat()` for smart create-or-update logic
- Snake_case ↔ CamelCase mapping via `CodingKeys` in models

#### Persistence (unchecked Sendable singleton)
- Thread-safe JSON file I/O
- Methods: `save(GameState)`, `load() -> GameState?`, `reset()`
- Silent failures (no throwing; production should add logging)

### Design System

**Colors**: Dark mode only (preferredColorScheme enforced)
- Surface tiers: surface0, surface1, surface2
- Text: textPrimary, textSecondary
- Accent: accent, accentLight
- Role-specific: mafiaRed, doctorGreen, policeBlue, citizenGray

**Card Styling**: `.designCard` modifier applies surface1 background, border, shadow, 16pt radius

**Role Icons**: SF Symbols mapped per role (flame.fill, cross.case.fill, eye.fill, person.fill)

## Common Development Tasks

### Adding a New Role

1. Add case to `Role` enum (Core/Models/Role.swift)
2. Add `displayName` for the new role
3. Add `accentColor` in `RoleStyle.swift`
4. Add `symbolName` (SF Symbol) in `RoleStyle.swift`
5. Update `roleDistribution(playerCount:)` in GameStore
6. Update targeting filters in `NightPhaseView.swift` if role has night actions
7. Update win condition logic if role affects team balance

### Adding New Cloud Data

1. Create model struct: `Codable`, `Sendable`, with `CodingKeys` for snake_case mapping
2. Add table to Supabase with RLS policy (pattern: `auth.uid() = user_id`)
3. Add CRUD methods to `DatabaseService.swift` (@MainActor, async/await)
4. Create SwiftUI view in `Features/` folder
5. Call DatabaseService methods from view lifecycle (`.task`, `.refreshable`)

### Modifying GameState Schema

1. Update `GameState` or related models (must remain `Codable`)
2. Test with fresh install (old saves will fail to decode if breaking changes)
3. For production: add migration logic in `Persistence.load()` to handle old formats

### Testing Locally Without Supabase

The app works fully offline. Simply:
1. Don't authenticate (skip login)
2. All game functionality works via local JSON persistence
3. GameOverView won't sync stats to cloud (silent no-op if not authenticated)

## Important Notes

### Navigation Flow

**RootView** (root navigation) decides which view to show based on GameStore state:
- `isFreshSetup == true` → SetupView
- `isGameOver == true` → GameOverView
- Otherwise → AssignmentsView → Night/Day loop

**flowID**: UUID property in GameStore that changes on `resetAll()` to force NavigationStack reset

### Ruby Scripts in Root

Several Ruby scripts exist for Xcode project file manipulation (adding files, fixing duplicates, etc.). These were used during setup; you should NOT need them during normal development. Modify the Xcode project via Xcode UI instead.

### Liquid Glass UI (iOS 26)

The README mentions "iOS 26 liquid glass UI" but this is aspirational/placeholder (iOS 26 doesn't exist yet). The app currently uses standard SwiftUI components with a dark mode design system.

### Missing App Icon

The app uses SF Symbol `person.3.fill` as a placeholder. To add a proper app icon, configure an App Icon asset in Xcode's Asset Catalog (Assets.xcassets).

## Supabase Configuration

### Required Environment Setup

1. Create Supabase project at supabase.com
2. Run `supabase/setup.sql` in SQL Editor (creates tables, RLS policies, trigger)
3. Disable email confirmation:
   - Navigate to Authentication → Providers → Email
   - Toggle OFF "Confirm email"
4. Copy Project URL and anon key from Settings → API
5. Update `Core/Services/SupabaseConfig.swift`:
   ```swift
   static let supabaseURL = "https://YOUR_PROJECT.supabase.co"
   static let supabaseAnonKey = "YOUR_ANON_KEY"
   ```

### Trigger: Auto-Profile Creation

The `handle_new_user()` function fires after `auth.users` INSERT:
- Extracts `display_name` from signup metadata (or defaults to email)
- Creates matching `profiles` table row
- No manual profile creation needed in Swift code

### RLS Policy Pattern

All tables follow this pattern:
```sql
-- Users can only interact with their own rows
FOR SELECT USING (user_id = auth.uid());
FOR INSERT WITH CHECK (user_id = auth.uid());
FOR UPDATE USING (user_id = auth.uid());
FOR DELETE USING (user_id = auth.uid());
```

## Code Style & Patterns

### SwiftUI Patterns
- Use `@EnvironmentObject` for GameStore and AuthStore injection
- All store classes are `@MainActor` (UI and game logic on main thread)
- Views don't hold complex logic; delegate to store methods
- Use `.task {}` for async operations on view appear

### Error Handling
- AuthStore maps errors to user-friendly strings via `parseSupabaseError()`
- DatabaseService and Persistence fail silently (no throwing)
- Production apps should add logging/telemetry

### Async/Await
- All Supabase calls are async/await (no completion handlers)
- Use `@MainActor` annotation to prevent threading issues
- Prefer structured concurrency (task groups, async let) for parallel operations

### Model Design
- All persisted models: `Codable` + `Sendable`
- Use `CodingKeys` enum for snake_case ↔ camelCase mapping
- UUIDs for primary keys, FK relationships explicit

### Validation
- Game rules enforced in GameStore (targeting restrictions, role counts, win conditions)
- Never allow invalid state through view layer; views only display and call store methods

## Troubleshooting

### Build Errors in Xcode
- Ensure `DerivedData` is not corrupted: `rm -rf DerivedData && xcodebuild clean`
- Verify code signing settings for your target device
- Check Swift version (requires 5.10+)

### Simulator Launch Failures
- Check logs: `tail -f /tmp/run_ios_sim_*.log`
- Verify simulator exists: `xcrun simctl list devices`
- Reset simulator: `xcrun simctl erase "iPhone 17 Pro"`

### Supabase Connection Issues
- Verify URL and anon key in `SupabaseConfig.swift`
- Check network connectivity (app works offline if unauthenticated)
- Test in Supabase Dashboard SQL Editor first

### Game State Corruption
- Delete local state: `GameStore.resetAll()` or manually delete `~/Library/Application Support/com.example.mafia_manager/GameState.json`
- Check logs for Codable decoding errors

### Auth Errors
- "Email not confirmed": Disable email confirmation in Supabase settings
- "Invalid credentials": Check user exists via Supabase Dashboard → Authentication
- Token expiry: AuthStore listener should auto-refresh via `onAuthStateChange`

## Future Vision (from Vision.md)

Planned features:
1. Login, accounts, save groups, names, scores, history ✅ (implemented)
2. App becomes manager by itself (automated gameplay)
3. Full online multiplayer game
