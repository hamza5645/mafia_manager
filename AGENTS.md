# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

**Mafia Manager** is an iOS game assistant for the party game Mafia. The app supports two modes:
- **Solo mode**: Pass-and-play on single device with optional AI bots (fully offline)
- **Multiplayer mode**: Multi-device gameplay via Supabase Realtime with room codes

**Tech Stack**: SwiftUI + MVVM, iOS 16+, zero dependencies (native Swift/SwiftUI only)
**Key Architecture Pattern**: GameStore as single source of truth, phase-based routing (no NavigationLinks), two-phase night resolution
**Game Features**: 4-19 players, 4 roles (Mafia, Police/Inspector, Doctor, Citizen), voting elimination, win conditions

## Documentation Index

**Start here**: [`docs/CLAUDE_PRIMER.md`](docs/CLAUDE_PRIMER.md) — Project overview, how to build/run, critical architecture summary (2 min read).

**Deep dive**: [`docs/ARCHITECTURE_NOTES.md`](docs/ARCHITECTURE_NOTES.md) — GameStore pattern, two-phase night resolution, service layer, data flow, Supabase schema.

**Query guide**: [`docs/ASKING_CLAUDE_EFFECTIVELY.md`](docs/ASKING_CLAUDE_EFFECTIVELY.md) — How to ask me for focused help without blowing the token budget.

## Build & Test Commands

### Running on Simulator
```bash
# Full build, sign, and launch (iPhone 17 Pro)
./scripts/run_ios_sim.sh

# Or build without auto-launch (uses default ~/Library/Developer/Xcode/DerivedData)
xcodebuild -project mafia_manager.xcodeproj -scheme mafia_manager \
  -configuration Debug -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  build
```

### Running Tests
```bash
# Run all unit tests (uses default DerivedData outside the repo)
xcodebuild -project mafia_manager.xcodeproj -scheme mafia_manager test \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro"

# Or via Xcode UI: Cmd+U
```

### Cleaning
```bash
xcodebuild -project mafia_manager.xcodeproj -scheme mafia_manager clean
# Leave DerivedData at its default location (~/Library/Developer/Xcode/DerivedData)
# to avoid ballooning the repo directory. Use `rm -rf ~/Library/Developer/Xcode/DerivedData/mafia_manager-*`
# if you need a full reset.
```

## Architecture at a Glance

**Single Source of Truth**: `GameStore` (@MainActor, @Published) manages all solo game state. Views call GameStore methods—never mutate directly.

**Phase-Based Routing**: Navigation driven entirely by `GamePhase` enum in `RootView`. No NavigationLinks in phase views. GameStore methods transition phases.

**Two-Phase Night Resolution**:
1. `endNight(mafiaTargetID, inspectorCheckedID, doctorProtectedID)` — Records actions, no deaths applied
2. `resolveNightOutcome(targetWasSaved: Bool)` — Applies death (or save), checks win conditions

**Persistence**: Automatic JSON save to Application Support after every mutation, debounced at 300ms.

**Multiplayer**: SessionService handles session CRUD, RealtimeService subscribes to Supabase Realtime tables (game_sessions, session_players, game_actions, phase_timers). Host controls phases; clients submit actions.

## Codebase Overview

**Tech stack**: SwiftUI + MVVM, iOS 16+, no third-party dependencies, local JSON + optional Supabase.

**Two game modes**:
1. **Solo mode** (original): Pass-and-play on single device, all state in GameStore
2. **Multiplayer mode** (new): Multi-device via Supabase Realtime, state in SessionService

**Feature-based structure**:
- `App/` — App entry point and root phase routing
- `Core/Auth/` — Auth state, auth services, and `UserProfile`
- `Core/Backend/` — Shared Supabase/database wiring
- `Core/Gameplay/` — Shared gameplay models plus solo persistence/store logic
- `Core/Multiplayer/` — Multiplayer models, services, and store
- `Core/Stats/` — Stats/custom-role/player-group models
- `Core/Support/` — Shared utilities such as validation
- `Core/Components/` — Reusable UI building blocks (PrivacyBlurView, CTAButtonStyle, Chips)
- `Core/UI/` — Design tokens and theme configuration
- `Features/` — Screen-specific views
  - Solo: `Setup`, `Assignments`, `Night`, `Day`, `Morning`, `GameOver`
  - Multiplayer: `Entry/` (menu/create/join) and `Flow/` (lobby/gameplay screens)
  - Shared: `Auth`, `Stats`, `Settings`

## Critical Patterns

### Solo Mode (GameStore)
**Single source of truth**: All game state in GameStore (@MainActor, @Published). Views never mutate directly—always call GameStore methods.

**Night resolution is TWO-PHASE**:
1. `endNight(mafiaTargetID, inspectorCheckedID, doctorProtectedID)` — Records actions, no deaths applied
2. `resolveNightOutcome(targetWasSaved: Bool)` — Applies death (or save), checks win conditions

This allows the UI to ask "Was target saved?" before committing the death.

**Navigation**: Phase-based routing via `RootView` switch on `GamePhase` enum. No NavigationLinks—GameStore methods transition phases directly.

**Persistence**: Automatic JSON save to Application Support after every GameStore mutation via Persistence service.

### Multiplayer Mode (SessionService + RealtimeService)
**Realtime sync**: Host controls phase transitions, all clients subscribe to `game_sessions` table changes via Supabase Realtime.

**State management**:
- `SessionService` (@MainActor) manages multiplayer state and session mutations
- `RealtimeService` (@MainActor) handles Realtime subscriptions and broadcasts
- Session state stored in Supabase: `game_sessions`, `session_players`, `game_actions`, `phase_timers`

**Host authority**: Only host can advance phases, kick players, start game. Clients submit actions via `game_actions` table.

**Heartbeat system**: Players send periodic heartbeats to track online status. Missing heartbeats = offline.

**Win conditions**:
- Citizens win: No alive Mafia (checked after night resolution)
- Mafia win: Alive Mafia >= Alive Non-Mafia (checked at day start and after day removals)

**Role targeting rules**:
- Mafia cannot target other Mafia
- Inspector cannot inspect other Inspectors
- Doctor can protect anyone (including self)

## Project Structure (Quick Reference)

```
App/                — App entry point & root view setup
Core/               — Domain-organized business logic
Features/           — UI screens (phase views + auth/stats/settings)
mafia_managerTests/ — Unit tests
supabase/           — Database schema (setup.sql, multiplayer_schema.sql)
docs/               — Architecture guides & documentation
scripts/            — Build automation (run_ios_sim.sh)
```

## Key Files (What's Important & Why)

### Solo Mode Core
- [Core/Gameplay/Store/GameStore.swift](Core/Gameplay/Store/GameStore.swift) — **Central state manager**. All game mutations (setupPlayers, assignRoles, endNight, voting) flow through here. Views are subscribers, never direct mutators.
- [App/mafia_managerApp.swift](App/mafia_managerApp.swift) — **Root view with phase-based routing**. Switches on `gameStore.state.currentPhase` to display appropriate UI. No NavigationLinks—phases transition via GameStore methods.
- [Core/Gameplay/Models/GameState.swift](Core/Gameplay/Models/GameState.swift) — **Root state model for solo mode** (players, currentPhase, nightHistory, dayHistory, gameResult). Fully Codable.
- [Core/Gameplay/Models/NightAction.swift](Core/Gameplay/Models/NightAction.swift) — **Night phase outcomes** (mafiaTargetID, inspectorCheckedID, doctorProtectedID, deaths). Used by two-phase resolution.
- [Features/Night/NightWakeUpView.swift](Features/Night/NightWakeUpView.swift) — **Implements two-phase resolution pattern**. Calls endNight(), then asks Doctor if save succeeded, then resolveNightOutcome(). Critical reference for night logic.

### Multiplayer Mode Core
- [Core/Multiplayer/Services/SessionService.swift](Core/Multiplayer/Services/SessionService.swift) — **Session CRUD & mutations**. Create sessions, join, submit actions. Writes to Supabase tables.
- [Core/Multiplayer/Services/RealtimeService.swift](Core/Multiplayer/Services/RealtimeService.swift) — **Realtime subscriptions manager**. Listens to game_sessions, session_players, game_actions, phase_timers. Broadcasts changes to MultiplayerGameStore.
- [Core/Multiplayer/Models/GameSession.swift](Core/Multiplayer/Models/GameSession.swift) — **Session metadata** (roomCode, host, phase, winner). Synced via Realtime.
- [Core/Multiplayer/Models/GameAction.swift](Core/Multiplayer/Models/GameAction.swift) — **Night/day actions** submitted by players (Mafia target, Police investigation, Doctor protection, vote). Synced to Supabase.

### Shared Services
- [Core/Auth/Store/AuthStore.swift](Core/Auth/Store/AuthStore.swift) — **Authentication state** (user, token, isAuthenticated). Manages Supabase Auth sessions & keychain.
- [Core/Gameplay/Services/Persistence.swift](Core/Gameplay/Services/Persistence.swift) — **JSON persistence** with debouncing (300ms). Atomic writes to Application Support. Error callbacks for UI.
- [supabase/setup.sql](supabase/setup.sql) — **Base tables**: profiles, player_stats, custom_roles_configs. Run this first.
- [supabase/multiplayer_schema.sql](supabase/multiplayer_schema.sql) — **Multiplayer tables**: game_sessions, session_players, game_actions, phase_timers. Requires RLS policies.

## Testing

Unit tests live in `mafia_managerTests/GameStoreTests.swift`. Tests cover:
- Setup phase (role assignment, number generation, validation)
- Night resolution (action recording, death outcomes, inspector checks)
- Day phase (voting removals)
- Win conditions (Mafia victory, Citizen victory)

Run with `Cmd+U` in Xcode or via xcodebuild test command above.

## Common Development Tasks

### Adding a New Phase to Solo Mode
1. Add case to `GamePhase` enum in `Core/Gameplay/Models/GameState.swift`
2. Create view in `Features/[PhaseName]/[PhaseName]View.swift`
3. Add switch case in `App/mafia_managerApp.swift`'s `phaseBasedView` to display the view
4. Add phase transition method in `GameStore` (e.g., `func advanceToNextPhase()`)
5. Call that method from your new view's button actions

**Example**: To add a "Confession" phase between Morning and Day:
```swift
// GamePhase.swift
case confession

// ConfessionView.swift (new file)
var body: some View {
    Button("Continue to Voting") {
        gameStore.startVoting()  // New method in GameStore
    }
}

// GameStore.swift
func startVoting() {
    state.currentPhase = .votingIndividual(currentPlayerIndex: 0)
}
```

### Modifying Night Resolution (CRITICAL Pattern)
**Always preserve the two-phase pattern**—never fold `endNight()` and `resolveNightOutcome()` into one method.

**To record a new night action**:
1. Add property to `NightAction` struct (e.g., `tutorProtectedID: Int?`)
2. In `GameStore.endNight()`, record the action: `nightAction.tutorProtectedID = tutorID`
3. In `NightWakeUpView`, ask the necessary question (if needed)
4. In `GameStore.resolveNightOutcome()`, apply the effect (e.g., prevent death)

**Example**: Adding Tutor role protection
```swift
// NightAction.swift
struct NightAction {
    var tutorProtectedID: Int?
}

// GameStore.swift
func endNight(mafiaTargetID: Int, ..., tutorProtectedID: Int?) {
    nightAction.tutorProtectedID = tutorProtectedID
}

func resolveNightOutcome(targetWasSaved: Bool) {
    if nightAction.tutorProtectedID == targetID {
        // Apply tutor protection
    }
}
```

### Adding Tests for Game Logic
Add test cases to `mafia_managerTests/GameStoreTests.swift`:

```swift
func testTutorProtection() {
    gameStore.setupPlayers(["Alice", "Bob", "Carol"])
    gameStore.assignNumbersAndRoles()
    // Carol is Tutor, protecting Bob
    gameStore.endNight(mafiaTargetID: 1, ..., tutorProtectedID: 1)
    let saved = true  // Bob's protection succeeded
    gameStore.resolveNightOutcome(targetWasSaved: saved)
    XCTAssertTrue(gameStore.state.players[1].isAlive)
}
```

Run tests: `xcodebuild test -destination "platform=iOS Simulator,name=iPhone 17 Pro"`

## Supabase Setup

### Required for Multiplayer
1. Run `supabase/setup.sql` in your SQL Editor to create base tables
2. Run `supabase/multiplayer_schema.sql` to create multiplayer tables
3. Disable email confirmation: Settings → Auth Providers → Email → Email Confirmations (OFF)
4. Update `Core/Backend/SupabaseConfig.swift` with your project URL + anon key
5. Enable Realtime for tables: `game_sessions`, `session_players`, `game_actions`, `phase_timers`

### Solo Mode Only
Solo mode works fully offline without Supabase. Authentication is optional (only needed for cloud stats sync).

## Debugging Multiplayer

**Realtime subscriptions not syncing?**
- Verify Realtime is enabled for tables: `game_sessions`, `session_players`, `game_actions`, `phase_timers` (Supabase dashboard → Realtime)
- Check `SupabaseConfig.swift` has correct project URL and anon key
- Test with 2+ simulator instances or browser tabs (single instance won't show sync)
- Enable Logger statements in `RealtimeService.subscribeToSession()` to track subscription status

**Host can't advance phase?**
- Verify `isHost = true` in `session_players` table for this user
- Check all required actions are in `game_actions` table (phase may require all players to act first)
- Ensure only one user is host in the session

**Phase transitions stuck or lagging?**
- Check if `RealtimeService` is actually subscribed (not just `SessionService`)
- Verify network connectivity—Realtime requires active WebSocket connection
- Check Supabase logs for subscription errors
- Try resetting Realtime: close and rejoin the session

**Players can't see each other's actions?**
- Verify `game_actions` table has `select` RLS policy allowing all authenticated users to read
- Check players are using same `session_id`
- Confirm both are authenticated (not in anonymous mode)

**Room code collision or invalid?**
- Room codes generated via RPC function—check `generate_room_code()` exists in Supabase
- Verify RLS policy on `game_sessions` allows creation
- Test in Supabase SQL editor: `SELECT * FROM game_sessions WHERE room_code = 'ABC123'`

## Development Notes

**Design tokens**: Dark mode only. Colors defined in `Core/UI/` (surface0/1/2, accent, role-specific).

**Privacy by design**: Back button hidden during Setup, Role Reveal, and Night phases. Blur screens between transitions. Numbers hidden until role reveal.

**Audio/haptic feedback**: System sounds + UINotificationFeedbackGenerator for phase transitions.

**No dependencies**: Project uses only Swift Standard Library + SwiftUI + XCTest. Keep it that way.

## Essential Rules for iOS Work with Codex

1. **Never modify .pbxproj files** — I will create files via Codex and you add them manually in Xcode. One corrupted project file wastes hours. If a .pbxproj edit is unavoidable, ask first.

2. **Document platform gotchas immediately** — Hit an iOS API issue? Add it to this AGENTS.md that session. Platform-specific workarounds become tribal knowledge and prevent repeated mistakes.

3. **Use feature flags for experimental code** — Toggle new features on/off without rebuilding. Keeps rollback instant when something breaks at 11pm (e.g., `#if EXPERIMENTAL_FEATURE`).

4. **Always request debug logging** — For complex async flows (auth, night resolution, persistence), ask me to add Logger statements. Future debugging of camera issues, async state mutations, etc. becomes exponentially easier.

5. **Test after every change** — Clean build folder (`Cmd+Shift+K`), run on device/simulator, verify in console. Catch issues before they compound. Don't let multiple changes accumulate without validation.

6. **Keep conversations focused on single components** — Don't ask to "refactor the whole app." Smaller scope = better results. Example: "Fix the night phase buttons" beats "improve the entire Night view."

7. **Document what changed in session** — End every major change with a markdown file (e.g., `SESSION_CHANGES.md`) explaining:
   - What broke/was added
   - How it was fixed
   - Rollback steps (if applicable)
   - Known gotchas for next session

8. **Respect the two-phase night pattern (Solo)** — Any changes to solo night resolution must preserve the `endNight()` → `resolveNightOutcome()` flow. Don't fold them into one method.

9. **Understand mode separation** — Solo and Multiplayer are separate code paths:
   - Solo: GameStore + local JSON persistence
   - Multiplayer: SessionService + Supabase Realtime
   - Don't mix patterns or share state between modes

10. **Test multiplayer with multiple devices/tabs** — Realtime subscriptions only work with actual Supabase connections. Use multiple simulator instances or browser tabs for Supabase Dashboard to verify sync.

11. **Delegate to Codex MCP aggressively** — Codex has access to Codex Agent (GPT-5.1 with high reasoning) via the Task tool with `subagent_type='codex-delegator'`. **Delegate as many tasks as possible to Codex** for:
    - Complex debugging and root cause analysis
    - Refactoring suggestions across multiple files
    - Implementation planning for new features
    - Code review and optimization suggestions
    - Test case generation
    - Architecture analysis and design decisions
    - Bug investigation and triage
    - Performance optimization strategies
    - Any task requiring deep reasoning or multi-file analysis

    **How to delegate**: Use the Task tool with `subagent_type='codex-delegator'` in your prompt. This is the preferred method over direct MCP calls and provides better integration with the agent workflow.

    **When to delegate**: Proactively use Codex **BEFORE** making changes, not just when stuck. Codex excels at analysis and recommendations; Codex excels at applying those recommendations using its tools.

    **CODEX-FIRST WORKFLOW PATTERN** (Required for complex tasks):

    ❌ **WRONG Approach** (Manual-first):
    ```
    1. Codex manually reviews git diff
    2. Codex manually fixes build errors
    3. Codex manually writes reports
    ```

    ✅ **CORRECT Approach** (Codex-first):
    ```
    1. Codex: Analyze impact → "Review git diff, identify breaking changes"
    2. Codex: Root cause analysis → "Analyze build errors, recommend fixes"
    3. Codex: Execute fixes → Use Edit/Write tools to apply recommendations
    4. ios-simulator: Test → Verify fixes work in simulator
    5. Codex: Final review → "Review test results, provide merge recommendation"
    ```

    **Real Example from Session:**
    - Task: Verify refactor didn't break anything
    - Should have: Codex analyze diff → Codex identify risks → Codex fix → Test → Codex review
    - Actually did: Codex manually analyzed everything (missed opportunity for deeper insights)

    **Key Principle**: If you're about to analyze, reason deeply, or make architectural decisions → **STOP and delegate to Codex first**. Let GPT-5.1 do the thinking, then execute the plan with precision tools.

12. **Always use ios-simulator-test-orchestrator for simulator interactions** — For ANY interaction with the iOS Simulator (testing UI, verifying fixes, running flows, taking screenshots, etc.), use the Task tool with `subagent_type='ios-simulator-test-orchestrator'`. This specialized agent handles:
    - Building and launching the app
    - UI automation (tapping, swiping, typing)
    - Screenshot capture and verification
    - Full test scenario execution
    - Console log monitoring
    - Multi-step user flows

    **Important**: When prompting the orchestrator, explicitly instruct it to use the `ios-simulator-skill` for all simulator interactions:
    ```
    "Use the ios-simulator-skill for all iOS simulator interactions. Test the [scenario]..."
    ```

    The skill provides 21 production-ready scripts for semantic UI navigation, accessibility testing, and simulator lifecycle management. It uses accessibility-driven navigation (find by text/type/ID) instead of brittle pixel coordinates.

    **Never** manually use MCP simulator tools or bash commands for simulator testing. The orchestrator + skill provides better automation, error handling, and reporting.

## Codex Decision Triggers (Quick Reference)

**ASK YOURSELF**: Does this task involve...
- ❓ Analyzing changes across multiple files → **USE CODEX**
- ❓ Identifying breaking changes or risks → **USE CODEX**
- ❓ Root cause analysis of build errors → **USE CODEX**
- ❓ Architecture review or design decisions → **USE CODEX**
- ❓ Planning implementation steps → **USE CODEX**
- ❓ Code quality or optimization review → **USE CODEX**
- ❓ Debugging complex async/state issues → **USE CODEX**
- ❓ Writing comprehensive reports → **USE CODEX**

**Codex is your thinking partner. Use it BEFORE executing with tools.**

Typical task delegation:
- **Codex** (GPT-5.1): Analysis, reasoning, recommendations, architecture review
- **Codex** (you): File operations (Read, Edit, Write), builds, applying fixes
- **ios-simulator-test-orchestrator**: UI testing, verification, screenshots

## Multiplayer Architecture

**Host-client model**: One player is host (creates session), others are clients (join via room code).

**Room codes**: 6-digit numeric codes, collision-safe via DB unique constraint.

**Phase flow** (host controls):
1. `lobby` → Host configures settings, players join, mark ready
2. `role_reveal` → Sequential reveals, players see their role
3. `night` → Role-specific actions submitted to `game_actions` table
4. `morning` → Host resolves night outcomes, displays results
5. `death_reveal` → Show who died
6. `voting` → Players vote to eliminate
7. Repeat 3-6 until `game_over`

**Action submission**: Players submit actions via `SessionService.submitAction()` → inserts into `game_actions` → host reads all actions before advancing phase.

**Realtime sync**: `RealtimeService.subscribeToSession()` listens to:
- `game_sessions` changes → session state updates
- `session_players` changes → player list updates
- `game_actions` changes → action submissions
- `phase_timers` changes → timer expirations

**Bot support**: Bots have `is_bot=true`, `user_id=null`. Host controls bot actions locally, writes them as `game_actions`.

### Two-Phase Night Resolution (Critical Pattern)

Multiplayer night resolution follows a strict two-phase pattern to prevent state corruption, action replay, and race conditions:

**Phase 1: Record Actions** (`recordNightActions()`)
- Fetches all night actions filtered by `session.currentRoundId` (prevents action replay)
- Records actions in `nightHistory` with `isResolved=false` and `resultingDeaths=[]`
- Does NOT mutate player state (no deaths applied)
- Guarded by `isResolved` flag to prevent duplicate recording

**Phase 2: Resolve Outcome** (`resolveNightOutcome(targetWasSaved:)`)
- Checks `isResolved` guard to prevent duplicate resolution
- Applies deaths via atomic RPC `resolve_night_atomic()` which updates:
  - `session_players.is_alive = false` for eliminated players
  - `nightHistory` with `isResolved=true` and final `resultingDeaths`
  - `current_phase` and `current_phase_data` to advance game
- All mutations happen in single database transaction (prevents race conditions)

**UI Flow** (MultiplayerNightView):
1. Host clicks "Finish Night Phase" → calls `recordNightActions()`
2. Sheet displays night results: who mafia targeted, who doctor protected, save outcome
3. Host clicks "Continue to Morning" → calls `resolveNightOutcome()` with auto-determined save status
4. Phase advances to morning

**Round Isolation** (`current_round_id`):
- New UUID generated for each night phase transition (in `updateSessionPhase()`)
- All actions submitted with `round_id` matching current round
- Action queries filtered by `round_id` to prevent old actions from being re-applied
- Prevents action replay bug where Night 2 actions could affect Night 1 outcomes

**Atomic Database Operations**:
- `resolve_night_atomic()` RPC function ensures player eliminations and history updates happen in single transaction
- No window for race conditions between Realtime events
- Idempotent: safe to call multiple times (guards check `isResolved`)

**Realtime Filtering**:
- `handleActionUpdate()` filters actions by active `phase_index` to prevent stale events
- Only processes actions matching current night/day phase
- Prevents Realtime replays from triggering duplicate resolution

**Why Two-Phase?**
- Solo mode asks Doctor "Was target saved?" before committing death
- Multiplayer auto-determines save by comparing `mafiaTargetId == doctorProtectedId`
- Separation allows host to review outcomes before finalizing
- Matches established solo mode UX pattern

**Critical: Never Merge Phases**
- Always call `recordNightActions()` before `resolveNightOutcome()`
- Never fold into single method—breaks duplicate resolution guards
- UI must show intermediate results sheet between phases

## Known Fixes & Gotchas

### Host with Active Roles (Mafia/Doctor/Inspector)
**Issue**: In multiplayer mode, if the host is assigned an active role (Mafia, Doctor, or Inspector), they must be able to submit their night actions just like any other player.

**Solution** (fixed in MultiplayerNightView.swift:61): The "Submit Action" button must be shown to ALL players with active roles, not just non-host players. The host needs to submit their action before they can finish the night phase.

**Critical check**: When modifying night phase UI, never add `!multiplayerStore.isHost` conditions that would prevent the host from submitting role-specific actions. The host is both a player AND a phase controller.
- don't marke linear issues as done. when you finish mark them as in review
