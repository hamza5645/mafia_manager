mafia_manager (SwiftUI, iOS 16+)
================================

An offline assistant for the referee/manager of the party game Mafia. Built with Swift 5.10+, SwiftUI, MVVM, and no third‑party dependencies. State persists to a single JSON file in Application Support.

 Targets and identifiers
 - Bundle Identifier: `com.example.mafia_manager` (placeholder — change in Xcode if desired).
 - Minimum iOS: 26.0 (uses iOS 26 liquid glass UI).

Features
- Setup: enter 5–19 unique player names; numbers are unique random values from 1–99.
- Assignments: each player gets a unique random number (1–99) and roles per booklet rules (with 5 players: 1 Mafia, 1 Inspector, 3 Citizens), capped at 5 Mafia, 2 Doctors, 2 Inspectors.
- Night: record Mafia kill (cannot target Mafia), Inspector check (shows full identity; cannot check Inspectors), Doctor protect (self allowed; hidden if no Doctor alive).
- Morning: summary with numbers only (Mafia numbers, killed, inspector’s identity result, doctor protected if present).
- Day: mark removals (lynch/other), live counts, then continue to next night.
- Game over: detects Villagers win (no Mafia) or Mafia win (Mafia >= Non‑Mafia at day start); export full log as text.

Persistence
- JSON is saved to Application Support under `com.example.mafia_manager/GameState.json`.

App icon
- Uses a simple SF Symbol (`person.3.fill`) in the UI as a placeholder. App icons in iOS require bitmap assets; set an App Icon in Assets or with an Xcode App Icon Catalog if you want an actual icon. Missing icons only produce warnings in Debug builds.

Project structure (by feature)
- `Core/Models`: Role, Player, NightAction, DayAction, GameState.
- `Core/Store`: GameStore (ObservableObject), game logic + persistence hooks.
- `Core/Services`: Persistence (JSON to disk), Seeded RNG.
- `Features/*`: Setup, Assignments, Night, Morning, Day, Game Over views.

Notes
- All mutations flow through `GameStore` methods to keep invariants.
- Night and day logs store only numbers by default; Game Over screen can include names for private reference.
