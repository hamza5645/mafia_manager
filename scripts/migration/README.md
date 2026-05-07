# Supabase → Convex Migration

One-shot ETL to move durable user data from Supabase to Convex.

## Prerequisites

- `node` >= 20
- `npm install` at the repo root (installs `@supabase/supabase-js` and `convex`)
- `.env.migration` in this directory with:

```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJ...
CONVEX_DEPLOY_KEY=...
CONVEX_URL=https://energized-herring-345.eu-west-1.convex.cloud
```

`.env.migration` and `exports/` are gitignored.

## Run order

```bash
node scripts/migration/export.mjs   # Supabase -> exports/*.json
node scripts/migration/ingest.mjs   # exports/*.json -> Convex
node scripts/migration/verify.mjs   # parity assertions, exit 0 on success
```

Each step is idempotent. Re-run after fixing transient errors. Ingest order
is users → player_stats → custom_roles_configs → player_groups.

## What gets migrated

- `auth.users` joined with `profiles` → `users` (`legacy_supabase_user_id`, `email` set; `auth_subject` set on first Clerk sign-in via `users.ensureUser`).
- `player_stats`, `custom_roles_configs`, `player_groups` → same table names in Convex (`legacy_supabase_id`, `legacy_supabase_user_id` set; `user_id` resolved to the Convex `users.id` via the legacy index).

Game state (`game_sessions`, `session_players`, `game_actions`) is NOT migrated.
