# Mafia Manager Audit Findings - 2026-04-25

## Scope

This document captures the current verified review findings from the simulator and command-line audit pass. No source files were modified during this audit.

## Current Findings

### 1. [P0] Build fails copying missing Swift Crypto bundle

- File: `mafia_manager.xcodeproj/project.pbxproj`
- Location: line 799
- Status: Verified

The app target has a stale `swift-crypto_Crypto.bundle` resource entry. A fresh `xcodebuild test` run against the booted iPhone 17 Pro simulator failed before tests executed because DerivedData did not contain that bundle.

Recommended fix: regenerate the Xcode project/package references via Tuist or Xcode. Do not hand-edit the `.pbxproj` unless explicitly approved.

### 2. [P1] Multiplayer night UI bypasses two-phase review

- File: `Features/Multiplayer/Flow/MultiplayerNightView.swift`
- Location: lines 244-248
- Status: Verified

The finish-night task records night actions and immediately resolves the outcome, so the host never sees the intermediate review sheet required by the project's two-phase night pattern.

Recommended fix: keep `recordNightActions()` and `resolveNightOutcome()` separated by UI state that displays the recorded result before final resolution.

### 3. [P1] Atomic night resolution failures are swallowed

- File: `Core/Multiplayer/Services/SessionService.swift`
- Location: lines 424-426
- Status: Verified

`resolveNightAtomic` catches Supabase/RPC errors and returns `false`, so callers using `try await` do not enter their `catch` path and the UI cannot surface the actual failure.

Recommended fix: throw the original error or return a typed failure that `resolveNightOutcome` converts into user-visible state.

### 4. [P2] Live Supabase config is tracked

- File: `Core/Backend/SupabaseConfig.swift`
- Location: lines 11-13
- Status: Verified

The file says it should be gitignored, and `.gitignore` does ignore it, but the file is still tracked and contains active Supabase project configuration. Supabase anon keys are public client credentials, but tracking the active project config increases exposure if RLS ever regresses.

Recommended fix: keep a template in source control and inject local/CI config outside tracked source.

## Additional Simulator Audit Notes

These were also observed during the resumed simulator audit and should be tracked separately if they are not already in review:

- `Features/Multiplayer/Entry/GameModeSelectionView.swift:106-116`: hidden empty `NavigationLink`s are exposed as unnamed accessibility buttons.
- `Features/Multiplayer/Entry/CreateGameView.swift:71-76`: the bot-count slider is exposed as an unnamed slider with no accessibility label/value. This made automated and assistive interaction with multiplayer bot setup unreliable.
- `Features/Intro/IntroView.swift:52-54`: subtractive geometry height can emit invalid frame dimension warnings.
- `Core/Auth/Store/AuthStore.swift:73-88`: startup auth restoration relies on Supabase's legacy initial-session behavior and suppresses session errors.

## Verification

- Fresh XCTest run: blocked by the P0 build failure; no XCTest cases executed.
- Live simulator smoke test: intro skip, local mode selection, local setup, player entry, bot count changes, and role reveal navigation were exercised successfully.
- Accessibility screen mapping: intro controls were named; game-mode selection exposed unnamed focusable controls.
- Completed a solo game through Mafia victory on the simulator: role reveal, two night cycles, one tied vote, night kill, game-over routing, and scroll-to-actions behavior worked.
- Multiplayer two-client smoke test: guest auth, room creation, room-code join, host lobby realtime update, online status, host-only kick affordance, and disabled start validation were verified on two booted simulators.
- Full multiplayer phase-flow testing was not completed because the current room had only two human clients and the create-room bot slider could not be reliably set through the available accessibility automation.
