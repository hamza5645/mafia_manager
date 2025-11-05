# Mafia Manager — Quick Start

**What it is**: Offline-first iOS game assistant for the party game Mafia. Built with SwiftUI (iOS 16+), MVVM pattern, local JSON persistence + optional Supabase cloud sync.

**Key directories**:
- `Core/` — Models, GameStore (single source of truth), AuthStore, Services (Persistence, Supabase)
- `Features/` — SwiftUI views (Setup, Night, Day, GameOver, Auth, Stats)
- `scripts/` — Build/launch automation
- `supabase/` — Database schema (setup.sql)

**Run on simulator**:
```bash
./scripts/run_ios_sim.sh
```

**Run via Xcode**:
```bash
xcodebuild -project mafia_manager.xcodeproj -scheme mafia_manager \
  -configuration Debug -destination "platform=iOS Simulator,name=iPhone 17 Pro" build
```

**Critical architecture**:
- **GameStore** = all game logic + mutations. Views never modify state directly.
- **Night resolution is TWO-PHASE**: `endNight()` records actions, then `resolveNightOutcome()` applies deaths.
- **Persistence**: JSON to Application Support after every state change.
- **Cloud sync**: Only on game completion via `syncPlayerStatsToCloud()` (requires auth).

**Supabase setup**:
1. Run `supabase/setup.sql` in SQL Editor
2. Disable email confirmation (Auth → Providers → Email)
3. Update `Core/Services/SupabaseConfig.swift` with your URL + anon key

**Read next**: `docs/ARCHITECTURE_NOTES.md` for deep patterns, `docs/ASKING_CLAUDE_EFFECTIVELY.md` for how to query me efficiently.
