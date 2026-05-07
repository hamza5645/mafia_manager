#!/usr/bin/env node
/**
 * Read scripts/migration/exports/*.json and feed each through the matching
 * internalMutation in convex/migration.ts. Idempotent — safe to re-run.
 *
 * Order: users → player_stats → custom_roles_configs → player_groups.
 * Children resolve user_id via the by_legacy_supabase_user_id index, so
 * users must be ingested first.
 */

import { ConvexClient } from "convex/browser";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import dotenv from "dotenv";

const here = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(here, ".env.migration") });

const CONVEX_URL = process.env.CONVEX_URL;
const CONVEX_DEPLOY_KEY = process.env.CONVEX_DEPLOY_KEY;
if (!CONVEX_URL || !CONVEX_DEPLOY_KEY) {
  console.error("Missing CONVEX_URL or CONVEX_DEPLOY_KEY in .env.migration");
  process.exit(1);
}

const exportsDir = path.join(here, "exports");

const client = new ConvexClient(CONVEX_URL);
client.setAdminAuth(CONVEX_DEPLOY_KEY);

async function readJson(name) {
  return JSON.parse(await fs.readFile(path.join(exportsDir, name), "utf8"));
}

const BATCH_SIZE = 500;

async function ingestBatched(mutationName, rows) {
  let processed = 0;
  for (let i = 0; i < rows.length; i += BATCH_SIZE) {
    const batch = rows.slice(i, i + BATCH_SIZE);
    const result = await client.mutation(mutationName, { rows: batch });
    processed += batch.length;
    console.log(
      `[ingest] ${mutationName} batch ${i / BATCH_SIZE + 1}: ${batch.length} rows`,
      result,
    );
  }
  return processed;
}

console.log(`[ingest] target: ${CONVEX_URL}`);

const users = await readJson("users.json");
console.log(`[ingest] users: ${users.length}`);
await ingestBatched("migration:ingestUsers", users);

const stats = await readJson("player_stats.json");
console.log(`[ingest] player_stats: ${stats.length}`);
await ingestBatched("migration:ingestPlayerStats", stats);

const configs = await readJson("custom_roles_configs.json");
console.log(`[ingest] custom_roles_configs: ${configs.length}`);
await ingestBatched("migration:ingestCustomRolesConfigs", configs);

const groups = await readJson("player_groups.json");
console.log(`[ingest] player_groups: ${groups.length}`);
await ingestBatched("migration:ingestPlayerGroups", groups);

const counts = await client.query("migration:countByTable", {});
console.log("[ingest] post-ingest Convex counts:", counts);

await client.close();
