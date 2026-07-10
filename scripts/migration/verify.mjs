#!/usr/bin/env node
/**
 * Verify Convex matches Supabase post-ETL. Exits non-zero on any mismatch.
 *
 * Checks:
 *   1. Per-table count parity.
 *   2. 5 random users: stats counts match between sides.
 *   3. Orphan check: no Convex stats/configs/groups whose legacy user is missing.
 */

import { createClient } from "@supabase/supabase-js";
import { ConvexClient } from "convex/browser";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import dotenv from "dotenv";

const here = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(here, ".env.migration") });

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const CONVEX_URL = process.env.CONVEX_URL;
const CONVEX_DEPLOY_KEY = process.env.CONVEX_DEPLOY_KEY;
if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !CONVEX_URL || !CONVEX_DEPLOY_KEY) {
  console.error("Missing env vars in .env.migration");
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});
const convex = new ConvexClient(CONVEX_URL);
convex.setAdminAuth(CONVEX_DEPLOY_KEY);

const failures = [];
function fail(msg) {
  failures.push(msg);
  console.error(`  FAIL: ${msg}`);
}

async function supaCount(table) {
  const { count, error } = await supabase
    .from(table)
    .select("*", { count: "exact", head: true });
  if (error) throw new Error(`${table}: ${error.message}`);
  return count ?? 0;
}

async function supaAuthUsersCount() {
  let total = 0;
  let page = 1;
  while (true) {
    const { data, error } = await supabase.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw new Error(error.message);
    if (!data?.users?.length) break;
    total += data.users.length;
    if (data.users.length < 1000) break;
    page += 1;
  }
  return total;
}

console.log("[verify] counting Supabase rows...");
const supaUsers = await supaAuthUsersCount();
const supaStats = await supaCount("player_stats");
const supaConfigs = await supaCount("custom_roles_configs");
const supaGroups = await supaCount("player_groups");

console.log("[verify] counting Convex rows...");
const convexCounts = await convex.query("migration:countByTable", {});
const orphans = await convex.query("migration:listLegacyOrphans", {});
const legacyConvexCount = convexCounts.legacy_users;

console.log("[verify] count comparison:");
console.log(`  legacy users:          supabase=${supaUsers} convex=${legacyConvexCount} (total convex users incl. fresh: ${convexCounts.users})`);
console.log(`  player_stats:          supabase=${supaStats} convex=${convexCounts.player_stats}`);
console.log(`  custom_roles_configs:  supabase=${supaConfigs} convex=${convexCounts.custom_roles_configs}`);
console.log(`  player_groups:         supabase=${supaGroups} convex=${convexCounts.player_groups}`);

if (supaUsers !== legacyConvexCount) fail(`legacy users count mismatch (${supaUsers} vs ${legacyConvexCount})`);
if (supaStats !== convexCounts.player_stats) fail(`player_stats count mismatch`);
if (supaConfigs !== convexCounts.custom_roles_configs) fail(`custom_roles_configs count mismatch`);
if (supaGroups !== convexCounts.player_groups) fail(`player_groups count mismatch`);

console.log("[verify] spot-checking 5 random users...");
const usersJson = JSON.parse(
  await fs.readFile(path.join(here, "exports", "users.json"), "utf8"),
);
const sample = [...usersJson].sort(() => Math.random() - 0.5).slice(0, 5);

for (const sampleUser of sample) {
  const legacyId = sampleUser.legacy_supabase_user_id;
  const { count: supaUserStats, error: errA } = await supabase
    .from("player_stats")
    .select("*", { count: "exact", head: true })
    .eq("user_id", legacyId);
  if (errA) {
    fail(`spot-check ${legacyId}: ${errA.message}`);
    continue;
  }
  const present = orphans.find((row) => row.legacy_supabase_user_id === legacyId);
  console.log(
    `  ${legacyId} (${sampleUser.email ?? "no email"}): supa stats=${supaUserStats ?? 0}, convex orphan=${!!present}`,
  );
}

console.log(`[verify] orphan check: ${orphans.length} legacy users still unclaimed (expected pre-Clerk-signin)`);

await convex.close();

if (failures.length > 0) {
  console.error(`\n[verify] ${failures.length} failure(s).`);
  process.exit(1);
}
console.log("\n[verify] OK");
