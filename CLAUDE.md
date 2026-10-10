# CLAUDE.md

Use `AGENTS.md` as the source of truth for this repository.

Important current facts:
- The project is Tuist-managed. Use `Project.swift`, `Tuist/Package.swift`, `tuist install`, and `tuist generate`; do not hand-edit `.pbxproj`.
- The active backend is Convex + Clerk, with Convex guest profiles for guest play.
- Active Swift backend files live under `Core/Backend/`, `Core/Auth/`, and `Core/Multiplayer/Services/`.
- Convex backend files live under `convex/`.
- Solo night resolution must remain two-phase: `endNight()` then `resolveNightOutcome()`.
- Multiplayer outcomes are computed by Convex with the same record-then-resolve flow: `night:recordNightActions` → `night:resolveNightAtomic`, and `voting:closeVoting` → `voting:resolveVoteAtomic`. The host client only requests transitions (`phases:advancePhase`) and drives bots.
- Convex functions never take user ids: the server derives the caller (valid guest proof → that guest, else the Clerk user). `ConvexService` injects `guest_secret_hash`.

Common commands:
```bash
tuist install
tuist generate
tuist build mafia_manager
tuist test mafia_manager
npx convex dev --once
```
