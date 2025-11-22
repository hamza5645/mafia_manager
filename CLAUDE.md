# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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

## Codebase Overview

**Tech stack**: SwiftUI + MVVM, iOS 26+, no third-party dependencies, local JSON + optional Supabase.

**Two game modes**:
1. **Solo mode** (original): Pass-and-play on single device, all state in GameStore
2. **Multiplayer mode** (new): Multi-device via Supabase Realtime, state in SessionService

**Feature-based structure**:
- `Core/Models/` — Codable data models
  - Solo: `Player`, `Role`, `GameState`, `NightAction`, `DayAction`
  - Multiplayer: `GameSession`, `SessionPlayer`, `GameAction`, `PhaseTimer`
- `Core/Store/` — **GameStore** (solo game logic) and **AuthStore** (auth state)
- `Core/Services/` — Persistence (JSON), Supabase Auth/Database/Realtime, SeededRandom
  - Multiplayer: `SessionService`, `RealtimeService`
- `Core/Components/` — Reusable UI building blocks (PrivacyBlurView, CTAButtonStyle, Chips)
- `Core/UI/` — Design tokens and theme configuration
- `Features/` — Screen-specific views
  - Solo: `Setup`, `Assignments`, `Night`, `Day`, `Morning`, `GameOver`
  - Multiplayer: `GameModeSelection`, `CreateGame`, `JoinGame`, `MultiplayerLobby`, `MultiplayerNight`, `MultiplayerVoting`
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

## Key Files

### Solo Mode
- [Core/Store/GameStore.swift](Core/Store/GameStore.swift) — All solo game mutations and phase transitions
- [Core/Models/GameState.swift](Core/Models/GameState.swift) — Root state model for solo
- [Core/Models/NightAction.swift](Core/Models/NightAction.swift) — Night phase outcomes

### Multiplayer Mode
- [Core/Services/Multiplayer/SessionService.swift](Core/Services/Multiplayer/SessionService.swift) — Multiplayer session management
- [Core/Services/Multiplayer/RealtimeService.swift](Core/Services/Multiplayer/RealtimeService.swift) — Supabase Realtime subscriptions
- [Core/Models/Multiplayer/GameSession.swift](Core/Models/Multiplayer/GameSession.swift) — Multiplayer session model
- [Core/Models/Multiplayer/SessionPlayer.swift](Core/Models/Multiplayer/SessionPlayer.swift) — Player in multiplayer session
- [Core/Models/Multiplayer/GameAction.swift](Core/Models/Multiplayer/GameAction.swift) — Night/day actions in multiplayer

### Shared
- [Core/Store/AuthStore.swift](Core/Store/AuthStore.swift) — Supabase auth state
- [supabase/setup.sql](supabase/setup.sql) — Database schema (profiles, player_stats, custom_roles_configs)
- [supabase/multiplayer_schema.sql](supabase/multiplayer_schema.sql) — Multiplayer tables (game_sessions, session_players, game_actions, phase_timers)

## Testing

Unit tests live in `mafia_managerTests/GameStoreTests.swift`. Tests cover:
- Setup phase (role assignment, number generation, validation)
- Night resolution (action recording, death outcomes, inspector checks)
- Day phase (voting removals)
- Win conditions (Mafia victory, Citizen victory)

Run with `Cmd+U` in Xcode or via xcodebuild test command above.

## Supabase Setup

### Required for Multiplayer
1. Run `supabase/setup.sql` in your SQL Editor to create base tables
2. Run `supabase/multiplayer_schema.sql` to create multiplayer tables
3. Disable email confirmation: Settings → Auth Providers → Email → Email Confirmations (OFF)
4. Update `Core/Services/SupabaseConfig.swift` with your project URL + anon key
5. Enable Realtime for tables: `game_sessions`, `session_players`, `game_actions`, `phase_timers`

### Solo Mode Only
Solo mode works fully offline without Supabase. Authentication is optional (only needed for cloud stats sync).

## Development Notes

**Design tokens**: Dark mode only. Colors defined in `Core/UI/` (surface0/1/2, accent, role-specific).

**Privacy by design**: Back button hidden during Setup, Role Reveal, and Night phases. Blur screens between transitions. Numbers hidden until role reveal.

**Audio/haptic feedback**: System sounds + UINotificationFeedbackGenerator for phase transitions.

**No dependencies**: Project uses only Swift Standard Library + SwiftUI + XCTest. Keep it that way.

## Essential Rules for iOS Work with Claude Code

1. **Never modify .pbxproj files** — I will create files via Claude Code and you add them manually in Xcode. One corrupted project file wastes hours. If a .pbxproj edit is unavoidable, ask first.

2. **Document platform gotchas immediately** — Hit an iOS API issue? Add it to this CLAUDE.md that session. Platform-specific workarounds become tribal knowledge and prevent repeated mistakes.

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

11. **Delegate to Codex MCP aggressively** — Claude Code has access to Codex Agent (GPT-5.1 with high reasoning) via MCP. **Delegate as many tasks as possible to Codex** using the `mcp__codex-cli__codex` tool for:
    - Complex debugging and root cause analysis
    - Refactoring suggestions across multiple files
    - Implementation planning for new features
    - Code review and optimization suggestions
    - Test case generation
    - Architecture analysis and design decisions
    - Bug investigation and triage
    - Performance optimization strategies
    - Any task requiring deep reasoning or multi-file analysis

    **When to delegate**: Proactively use Codex before making changes, not just when stuck. Codex excels at analysis and recommendations; Claude Code excels at applying those recommendations using its tools.

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

## Multiplayer Architecture

**Host-client model**: One player is host (creates session), others are clients (join via room code).

**Room codes**: 6-character uppercase alphanumeric, collision-safe via DB unique constraint.

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

## Known Fixes & Gotchas

### Host with Active Roles (Mafia/Doctor/Inspector)
**Issue**: In multiplayer mode, if the host is assigned an active role (Mafia, Doctor, or Inspector), they must be able to submit their night actions just like any other player.

**Solution** (fixed in MultiplayerNightView.swift:61): The "Submit Action" button must be shown to ALL players with active roles, not just non-host players. The host needs to submit their action before they can finish the night phase.

**Critical check**: When modifying night phase UI, never add `!multiplayerStore.isHost` conditions that would prevent the host from submitting role-specific actions. The host is both a player AND a phase controller.
