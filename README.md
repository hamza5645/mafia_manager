mafia_manager (SwiftUI, iOS 26+)
================================

**Version 3.0** - An autonomous game manager for the party game Mafia. Single-phone pass-around gameplay with no moderator required. Built with Swift 5.10+, SwiftUI, MVVM, and no third‑party dependencies. State persists to a single JSON file in Application Support.

 Targets and identifiers
 - Bundle Identifier: `com.hamza.mafia-manager`
 - Version: 3.0
 - Minimum iOS: 26.0 (uses iOS 26 liquid glass UI).

Game Flow
1. **Setup**: Enter 4–19 unique player names; numbers are unique random values from 1–99.
2. **Role Reveal**: Sequential role reveals with privacy screens. Each player receives the phone individually, taps to reveal their role (number + role + description), then passes it with a 2-second privacy blur between players.
3. **Night Phase** (repeats each night):
   - "Everyone Close Your Eyes" screen - place phone in middle
   - 2-second transition blur with sound alert
   - **Mafia wakes up**: All mafia members see each other (by name initial), select one non-mafia target to eliminate
   - 3-second transition blur between roles
   - **Police wakes up**: Select one player to investigate (shows if Mafia or role)
   - 3-second transition blur
   - **Doctor wakes up**: Select one player to protect from Mafia (can self-protect)
4. **Morning Summary**: Shows night results with proper formatting:
   - Mafia: #1, #2 → #5 (who they targeted)
   - Killed: #5 or "None (Doctor saved #5)"
   - Police: #3 → #7 (who they investigated)
   - Doctor: #4 → #5 (who they protected)
5. **Day Phase**: Public discussion and voting. Mark eliminated players with optional notes. Live counts shown (Mafia vs Others).
6. **Game Over**: Detects Villagers win (no Mafia) or Mafia win (Mafia >= Non‑Mafia at morning). Export full log as text.

Features
- **Autonomous gameplay**: No moderator needed - the phone manages the entire game
- **Privacy-first design**: Blur screens, no back navigation, sequential reveals
- **Role assignment**: Balanced distribution (with 4 players: 1 Mafia, 1 Police, 2 Citizens), capped at 5 Mafia, 2 Doctors, 2 Police
- **Night mechanics**:
  - Mafia cannot target other Mafia
  - Police cannot identify other Police
  - Doctor can protect themselves
  - Two-phase resolution: actions recorded then outcomes applied
- **Phase-based state machine**: roleReveal → nightWakeUp → nightAction → nightTransition → morning → day → gameOver
- **Audio & haptic feedback**: System sounds and vibrations for transitions
- **Cloud sync**: Optional Supabase integration for player stats (requires authentication)

Persistence
- Local: JSON saved to Application Support under `com.hamza.mafia-manager/GameState.json`
- Cloud: Optional Supabase sync for player statistics (requires authentication via AuthStore)

Project structure (by feature)
- `Core/Models`: Role, Player, NightAction (with isResolved flag), DayAction, GameState (with GamePhase enum)
- `Core/Store`:
  - GameStore (ObservableObject) - All game logic, phase management, persistence
  - AuthStore - Supabase authentication state
- `Core/Services`:
  - PersistenceService (JSON to disk)
  - DatabaseService (Supabase cloud sync)
  - SeededRandom (deterministic RNG)
- `Core/Components`: PrivacyBlurView, CTAButtonStyle, Chip, Design tokens
- `Features/Setup`: SetupView (player entry)
- `Features/Assignments`: RoleRevealView (sequential reveals with privacy)
- `Features/Night`: NightWakeUpView (role-specific wake-ups and actions)
- `Features/Morning`: MorningSummaryView (night outcome display)
- `Features/Day`: DayManagementView (voting and elimination)
- `Features/GameOver`: GameOverView (winner announcement, log export)
- `Features/Settings`: SettingsView (version info, cloud sync controls)

Key Architecture Patterns
- **Phase-based state machine**: GamePhase enum drives navigation (no NavigationLinks)
- **Single source of truth**: All state lives in GameStore, flows down via @EnvironmentObject
- **Two-phase night resolution**:
  1. `endNight()` - Records actions from Mafia/Police/Doctor
  2. `resolveNightOutcome()` - Applies death outcomes and sets isResolved flag
- **Proper night tracking**: isResolved flag prevents role actions from being applied to wrong nights
- **Privacy preservation**: No back navigation during reveals/night phases, blur screens between transitions
- **Haptic & audio feedback**: UINotificationFeedbackGenerator + AudioServicesPlaySystemSound for transitions

Notes
- All mutations flow through `GameStore` methods to maintain invariants
- Numbers are kept secret until role reveal phase
- Night actions show name initials instead of numbers for privacy
- Navigation uses phase-based routing via RootView switch statement
- Back button hidden and interactive dismiss disabled during sensitive phases
