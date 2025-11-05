# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Documentation Index

**Start here**: [`docs/CLAUDE_PRIMER.md`](docs/CLAUDE_PRIMER.md) — Project overview, how to build/run, critical architecture summary (2 min read).

**Deep dive**: [`docs/ARCHITECTURE_NOTES.md`](docs/ARCHITECTURE_NOTES.md) — GameStore pattern, two-phase night resolution, service layer, data flow, Supabase schema.

**Query guide**: [`docs/ASKING_CLAUDE_EFFECTIVELY.md`](docs/ASKING_CLAUDE_EFFECTIVELY.md) — How to ask me for focused help without blowing the token budget.

## Quick Reference

**Build & run**: `./scripts/run_ios_sim.sh` (builds, signs, launches on iPhone 17 Pro simulator)

**Key files**:
- `Core/Store/GameStore.swift` — All game logic (single source of truth)
- `Core/Store/AuthStore.swift` — Authentication state
- `supabase/setup.sql` — Database schema (run in Supabase SQL Editor)

**Critical pattern**: Night resolution is TWO-PHASE (`endNight()` then `resolveNightOutcome()`). See primer for details.
