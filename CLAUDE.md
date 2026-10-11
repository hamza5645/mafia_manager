# CLAUDE.md

Use `AGENTS.md` as the source of truth for this repository.

Important current facts:
- The project is Tuist-managed. Use `Project.swift`, `Tuist/Package.swift`, `tuist install`, and `tuist generate`; do not hand-edit `.pbxproj`.
- The active backend is Convex + Clerk, with Convex guest profiles for guest play.
- Active Swift backend files live under `Core/Backend/`, `Core/Auth/`, and `Core/Multiplayer/Services/`.
- Convex backend files live under `convex/`.
- Solo night resolution must remain two-phase: `endNight()` then `resolveNightOutcome()`.
- Multiplayer outcomes are computed by Convex with the same record-then-resolve flow: `night:finishNight` runs `recordNightActions` then `resolveNightAtomic` in one transaction, and `voting:closeVoting` → `voting:resolveVoteAtomic`. The host client only requests transitions (`phases:advancePhase`) and drives bots (`play:submitBotActions`).
- Heartbeats write only `session_presence`; `views:getHostPresence` reads only the host's row. Win rule is parity in both modes: Mafia win when living Mafia >= living non-Mafia, after a night and after a vote.
- Convex functions never take user ids: the server derives the caller (valid guest proof → that guest, else the Clerk user). `ConvexService` injects `guest_secret_hash`.
- API contract is 5 (`ConvexConfig.apiContractVersion`, `health:check`); backend and app ship in lockstep. Stats go through `StatsOutbox` → `stats:recordGame` (idempotent per game id). An hourly cron (`convex/crons.ts`) cancels rooms with no heartbeat for 6 h and deletes ended rooms after 30 days.
- `npx convex codegen` contacts the configured dev deployment. When you must not touch a deployment, hand-edit `convex/_generated/api.d.ts`.
- Generated fixtures (`tests/fixtures/contract/`, `tests/fixtures/rules-parity.json`) fail `vitest` on drift; regenerate with `-u` only on purpose and update the Swift tests in the same change (see `AGENTS.md`).

Common commands:
```bash
tuist install
tuist generate
tuist build mafia_manager
tuist test mafia_manager --no-selective-testing
npm run test:backend
npx convex dev --once
```

Keep clones and worktrees outside iCloud-synced folders (`~/Documents`, `~/Desktop`); iCloud conflict copies (`Foo 2.swift`) break the Tuist build.
