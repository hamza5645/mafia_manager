# Architecture Deep Dive

## GameStore Pattern

**Single source of truth**: All game state lives in `GameStore` (`@MainActor`, `@Published`). Views are read-only subscriptions.

**Key methods**:
- `assignNumbersAndRoles(names:)` — Setup phase: generates unique numbers, distributes roles
- `endNight(mafiaTargetID, inspectorCheckedID, doctorProtectedID)` — Records night WITHOUT deaths
- `resolveNightOutcome(targetWasSaved:)` — Applies death (or save), checks win conditions
- `applyDayRemovals(removed:, notes:)` — Marks players dead, checks win conditions
- `syncPlayerStatsToCloud()` — Pushes stats to Supabase (game over only)

## Night Resolution (Critical!)

**Two-phase system**:
1. `NightPhaseView` → user selects actions → `store.endNight()` (creates NightAction, NO deaths)
2. `NightOutcomeView` → user confirms saved/died → `store.resolveNightOutcome()` (applies death, evaluates winners)

**Why?** Allows UI to ask if Doctor saved target before committing the death.

## Win Conditions

- **Citizens win**: No alive Mafia (checked after night resolution)
- **Mafia win**: Alive Mafia >= Alive Non-Mafia (checked at day start AND after day removals)

## Role Distribution

Hardcoded in `GameStore.roleDistribution()`:
```
4-5:   1 Mafia, 0-1 Doctor, 1 Police
6-8:   2 Mafia, 1 Doctor, 1 Police
9-14:  4 Mafia, 1 Doctor, 2 Police
15-19: 5 Mafia, 2 Doctors, 2 Police
```

## Inspector Logic

- Cannot check other inspectors (targeting rule)
- Returns full Role if target is not inspector
- Stores both `inspectorResultIsMafia: Bool?` and `inspectorResultRole: Role?`

## Service Layer

**Persistence** (`Core/Services/Persistence.swift`):
- Singleton, thread-safe (`@unchecked Sendable`)
- JSON to Application Support: `save(GameState)`, `load()`, `reset()`
- Atomic writes, pretty-printed, silent failures

**AuthService** (`@MainActor`):
- Wraps Supabase Auth: `signUp`, `signIn`, `signOut`, `onAuthStateChange` (async stream)
- Profile auto-created via DB trigger (no manual creation)

**DatabaseService** (`@MainActor`):
- PostgREST CRUD for `player_stats`, `custom_roles_configs`
- `upsertPlayerStat()` — create or increment existing
- Snake_case ↔ CamelCase via `CodingKeys`

## Data Flow

```
User action → View calls GameStore method → GameStore mutates state →
  → Persistence.save() → @Published triggers view refresh
```

On game completion:
```
GameOverView.task → store.syncPlayerStatsToCloud() →
  → DatabaseService.upsertPlayerStat() for each player
```

## Models Hierarchy

```
GameState (root, Codable)
├── players: [Player] (id, number, name, role, alive, removalNote)
├── nightHistory: [NightAction] (targets, results, deaths, mafiaNumbers snapshot)
├── dayHistory: [DayAction] (removedPlayerIDs)
├── dayIndex, isGameOver, winner

AuthStore (parallel)
├── isAuthenticated, currentUserId, userProfile
```

## Supabase Schema

**Tables**: `profiles`, `player_stats`, `custom_roles_configs`

**RLS pattern** (all tables):
```sql
FOR SELECT USING (user_id = auth.uid());
FOR INSERT WITH CHECK (user_id = auth.uid());
```

**Trigger**: `handle_new_user()` fires on signup → auto-creates profile row with display_name from metadata.

## Kill Attribution

Kills credited by scanning `nightHistory`:
- Find nights where `resultingDeaths.count > 0`
- Find all alive Mafia during that night
- Increment `totalKills` for each

All Mafia share credit for each kill.

## Adding New Roles

1. Add case to `Role` enum
2. Add `displayName`, `accentColor` (RoleStyle), `symbolName`
3. Update `roleDistribution()` in GameStore
4. Update targeting filters in `NightPhaseView`
5. Update win condition logic if needed

## Navigation Flow

`RootView` decides based on GameStore state:
- `isFreshSetup == true` → SetupView
- `isGameOver == true` → GameOverView
- Otherwise → AssignmentsView → Night/Day loop

`flowID` (UUID) changes on `resetAll()` to force NavigationStack reset.

## Design System

**Dark mode only** (`preferredColorScheme(.dark)`).

**Colors**: `surface0/1/2`, `textPrimary/Secondary`, `accent`, role-specific (mafiaRed, doctorGreen, policeBlue, citizenGray)

**Card modifier**: `.designCard` applies surface1 background, border, shadow, 16pt radius.

## Testing Without Supabase

App works fully offline:
- Skip login
- All game features work via local JSON
- GameOverView won't sync stats (silent no-op if not authenticated)
