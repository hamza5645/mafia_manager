# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Documentation Index

**Start here**: [`docs/CLAUDE_PRIMER.md`](docs/CLAUDE_PRIMER.md) — Project overview, how to build/run, critical architecture summary (2 min read).

**Deep dive**: [`docs/ARCHITECTURE_NOTES.md`](docs/ARCHITECTURE_NOTES.md) — GameStore pattern, two-phase night resolution, service layer, data flow, Supabase schema.

**Query guide**: [`docs/ASKING_CLAUDE_EFFECTIVELY.md`](docs/ASKING_CLAUDE_EFFECTIVELY.md) — How to ask me for focused help without blowing the token budget.

**Codex delegation**: [`docs/CODEX_DELEGATION.md`](docs/CODEX_DELEGATION.md) — When and how Claude Code should delegate tasks to Codex Agent CLI to save tokens.

## Build & Test Commands

### Running on Simulator
```bash
# Full build, sign, and launch (iPhone 17 Pro)
./scripts/run_ios_sim.sh

# Or build without auto-launch
xcodebuild -project mafia_manager.xcodeproj -scheme mafia_manager \
  -configuration Debug -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -derivedDataPath DerivedData build
```

### Running Tests
```bash
# Run all unit tests
xcodebuild -project mafia_manager.xcodeproj -scheme mafia_manager test \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -derivedDataPath DerivedData

# Or via Xcode UI: Cmd+U
```

### Cleaning
```bash
xcodebuild -project mafia_manager.xcodeproj -scheme mafia_manager clean
rm -rf DerivedData
```

## Codebase Overview

**Tech stack**: SwiftUI + MVVM, iOS 16+, no third-party dependencies, local JSON + optional Supabase.

**Feature-based structure**:
- `Core/Models/` — Codable data models (Player, Role, GameState, NightAction, etc.)
- `Core/Store/` — **GameStore** (game logic, mutations) and **AuthStore** (auth state)
- `Core/Services/` — Persistence (JSON), Supabase Auth/Database, SeededRandom
- `Core/Components/` — Reusable UI building blocks (PrivacyBlurView, CTAButtonStyle, Chips)
- `Core/UI/` — Design tokens and theme configuration
- `Features/` — Screen-specific views (Setup, Assignments, Night, Day, Morning, GameOver, Auth, Stats, Settings)

## Critical Patterns

**Single source of truth**: All game state in GameStore (@MainActor, @Published). Views never mutate directly—always call GameStore methods.

**Night resolution is TWO-PHASE**:
1. `endNight(mafiaTargetID, inspectorCheckedID, doctorProtectedID)` — Records actions, no deaths applied
2. `resolveNightOutcome(targetWasSaved: Bool)` — Applies death (or save), checks win conditions

This allows the UI to ask "Was target saved?" before committing the death.

**Navigation**: Phase-based routing via `RootView` switch on `GamePhase` enum. No NavigationLinks—GameStore methods transition phases directly.

**Persistence**: Automatic JSON save to Application Support after every GameStore mutation via Persistence service.

**Win conditions**:
- Citizens win: No alive Mafia (checked after night resolution)
- Mafia win: Alive Mafia >= Alive Non-Mafia (checked at day start and after day removals)

**Role targeting rules**:
- Mafia cannot target other Mafia
- Inspector cannot inspect other Inspectors
- Doctor can protect anyone (including self)

## Key Files

- [Core/Store/GameStore.swift](Core/Store/GameStore.swift) — All game mutations and phase transitions
- [Core/Store/AuthStore.swift](Core/Store/AuthStore.swift) — Supabase auth state
- [Core/Models/GameState.swift](Core/Models/GameState.swift) — Root state model
- [Core/Models/NightAction.swift](Core/Models/NightAction.swift) — Night phase outcomes
- [supabase/setup.sql](supabase/setup.sql) — Database schema (profiles, player_stats, custom_roles_configs)

## Testing

Unit tests live in `mafia_managerTests/GameStoreTests.swift`. Tests cover:
- Setup phase (role assignment, number generation, validation)
- Night resolution (action recording, death outcomes, inspector checks)
- Day phase (voting removals)
- Win conditions (Mafia victory, Citizen victory)

Run with `Cmd+U` in Xcode or via xcodebuild test command above.

## Supabase Setup (Optional)

1. Run `supabase/setup.sql` in your SQL Editor to create tables
2. Disable email confirmation: Settings → Auth Providers → Email → Email Confirmations (OFF)
3. Update `Core/Services/SupabaseConfig.swift` with your project URL + anon key

App works fully offline if you skip authentication (no cloud sync, but all game features work).

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

8. **Respect the two-phase night pattern** — Any changes to night resolution must preserve the `endNight()` → `resolveNightOutcome()` flow. Don't fold them into one method.

9. **Autonomously delegate tasks to Codex Agent** — Claude Code should proactively delegate tasks to Codex Agent (GPT-5.1 with high reasoning) to save tokens and leverage its capabilities. Codex is very capable and can handle complex tasks. Delegate using `./scripts/codex_analyze.sh "task" [files...]` and apply the recommendations. See delegation criteria below.

## Autonomous Codex Delegation

Claude Code has access to Codex Agent (GPT-5.1 with high reasoning) and should **autonomously delegate** tasks without asking. Use `./scripts/codex_analyze.sh` to get analysis and recommendations, then apply the changes.

### When to Delegate (Do This Proactively)

**Always Consider Delegating:**
- Complex debugging tasks (Codex has high reasoning capabilities)
- Refactoring across multiple files
- Code analysis and optimization suggestions
- Bug hunting and root cause analysis
- Implementation planning for new features
- Test case generation
- Code review and security analysis
- Performance optimization suggestions
- When token budget is >50% used and task is suitable

**Keep in Claude Code:**
- Final file modifications (Codex provides recommendations, Claude applies them)
- Direct user interaction and questions
- Tasks requiring real-time project state (e.g., current git status, file checks)
- Very simple one-liner changes (faster to do directly)

### Delegation Pattern

```bash
# 1. Delegate to Codex for analysis
CODEX_OUTPUT=$(./scripts/codex_analyze.sh "Analyze GameStore night resolution and suggest improvements" Core/Store/GameStore.swift)

# 2. Review Codex's recommendations
# 3. Apply the suggested changes using Claude Code's tools
```

**Example workflow:**
- User: "Fix the multiplayer sync issues"
- Claude Code: [Autonomously delegates to Codex] → Gets analysis → Applies recommended fixes → Reports to user
