#!/usr/bin/env node
/**
 * Dump durable user data from Supabase to local JSON for Convex ingestion.
 *
 * Output:
 *   scripts/migration/exports/users.json
 *   scripts/migration/exports/player_stats.json
 *   scripts/migration/exports/custom_roles_configs.json
 *   scripts/migration/exports/player_groups.json
 *
 * Timestamps are normalized to seconds-since-2001 (Apple/NSDate epoch) to
 * match convex/lib.ts:nowAppleEpochSeconds(). The Swift client decodes via
 * Date(timeIntervalSinceReferenceDate:), so this is the canonical format.
 */

import { createClient } from "@supabase/supabase-js";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import dotenv from "dotenv";

const here = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(here, ".env.migration") });

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in .env.migration");
  process.exit(1);
}

const APPLE_REFERENCE_OFFSET_SECONDS = 978307200;

function toAppleEpochSeconds(value) {
  if (value === null || value === undefined) return undefined;
  const ms = typeof value === "number" ? value : new Date(value).getTime();
  if (Number.isNaN(ms)) return undefined;
  return ms / 1000 - APPLE_REFERENCE_OFFSET_SECONDS;
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const exportsDir = path.join(here, "exports");
await fs.mkdir(exportsDir, { recursive: true });

async function dumpAll(table) {
  const all = [];
  let from = 0;
  const pageSize = 1000;
  while (true) {
    const { data, error } = await supabase
      .from(table)
      .select("*")
      .range(from, from + pageSize - 1);
    if (error) {
      throw new Error(`${table}: ${error.message}`);
    }
    if (!data || data.length === 0) break;
    all.push(...data);
    if (data.length < pageSize) break;
    from += pageSize;
  }
  return all;
}

async function dumpAuthUsers() {
  const all = [];
  let page = 1;
  const perPage = 1000;
  while (true) {
    const { data, error } = await supabase.auth.admin.listUsers({ page, perPage });
    if (error) throw new Error(`auth.users: ${error.message}`);
    if (!data || data.users.length === 0) break;
    all.push(...data.users);
    if (data.users.length < perPage) break;
    page += 1;
  }
  return all;
}

console.log("[export] dumping auth.users...");
const authUsers = await dumpAuthUsers();
console.log(`[export]   ${authUsers.length} auth.users rows`);

console.log("[export] dumping profiles...");
const profiles = await dumpAll("profiles");
console.log(`[export]   ${profiles.length} profiles rows`);

const profileById = new Map(profiles.map((p) => [p.id, p]));

const usersOut = authUsers.map((au) => {
  const profile = profileById.get(au.id);
  const displayName =
    profile?.display_name?.trim() ||
    au.user_metadata?.display_name?.trim() ||
    au.email ||
    "Player";
  return {
    legacy_supabase_user_id: au.id,
    email: au.email ? au.email.toLowerCase() : undefined,
    display_name: displayName,
    is_anonymous: profile?.is_anonymous ?? false,
    created_at: toAppleEpochSeconds(au.created_at),
    updated_at: toAppleEpochSeconds(profile?.updated_at ?? au.updated_at ?? au.created_at),
  };
});

await fs.writeFile(
  path.join(exportsDir, "users.json"),
  JSON.stringify(usersOut, null, 2),
);

async function dumpChildTable(table, mapper) {
  console.log(`[export] dumping ${table}...`);
  const rows = await dumpAll(table);
  console.log(`[export]   ${rows.length} ${table} rows`);
  const mapped = rows.map(mapper);
  await fs.writeFile(
    path.join(exportsDir, `${table}.json`),
    JSON.stringify(mapped, null, 2),
  );
}

await dumpChildTable("player_stats", (row) => ({
  legacy_supabase_id: row.id,
  legacy_supabase_user_id: row.user_id,
  player_name: row.player_name,
  games_played: row.games_played ?? 0,
  games_won: row.games_won ?? 0,
  games_lost: row.games_lost ?? 0,
  total_kills: row.total_kills ?? 0,
  times_mafia: row.times_mafia ?? 0,
  times_doctor: row.times_doctor ?? 0,
  times_inspector: row.times_inspector ?? 0,
  times_citizen: row.times_citizen ?? 0,
  created_at: toAppleEpochSeconds(row.created_at),
  updated_at: toAppleEpochSeconds(row.updated_at),
}));

await dumpChildTable("custom_roles_configs", (row) => ({
  legacy_supabase_id: row.id,
  legacy_supabase_user_id: row.user_id,
  config_name: row.config_name,
  role_distribution: row.role_distribution,
  created_at: toAppleEpochSeconds(row.created_at),
  updated_at: toAppleEpochSeconds(row.updated_at),
}));

await dumpChildTable("player_groups", (row) => ({
  legacy_supabase_id: row.id,
  legacy_supabase_user_id: row.user_id,
  group_name: row.group_name,
  player_names: row.player_names ?? [],
  created_at: toAppleEpochSeconds(row.created_at),
  updated_at: toAppleEpochSeconds(row.updated_at),
}));

console.log(`[export] wrote ${exportsDir}`);
