#!/usr/bin/env node
/** Read-only legacy count, per-user count, and owner-reference verification. */
import { createClient } from '@supabase/supabase-js';
import { ConvexHttpClient } from 'convex/browser';
import path from 'node:path';
import fs from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import dotenv from 'dotenv';
import { compareOwnership } from './compare-ownership.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(here, '.env.migration') });
const { SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, CONVEX_URL, CONVEX_DEPLOY_KEY } = process.env;
const useExport = process.env.MIGRATION_VERIFY_SOURCE === 'export';
if (!CONVEX_URL || !CONVEX_DEPLOY_KEY || (!useExport && (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY))) {
  console.error('Missing env vars in .env.migration'); process.exit(1);
}
const supabase = useExport ? null : createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { autoRefreshToken: false, persistSession: false } });
const convex = new ConvexHttpClient(CONVEX_URL);
convex.setAdminAuth(CONVEX_DEPLOY_KEY);

async function authUsers() {
  const rows = [];
  for (let page = 1; ; page++) {
    const { data, error } = await supabase.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw new Error(`auth.users: ${error.message}`);
    const users = data?.users ?? [];
    rows.push(...users.map(user => ({ id: user.id })));
    if (users.length < 1000) return rows;
  }
}
async function children(table) {
  const rows = [];
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await supabase.from(table).select('id,user_id').order('id').range(offset, offset + 999);
    if (error) throw new Error(`${table}: ${error.message}`);
    rows.push(...(data ?? []));
    if ((data ?? []).length < 1000) return rows;
  }
}
try {
  console.log(`[verify] reading ${useExport ? 'saved export (not live source)' : 'live source'} IDs and owner references...`);
  const tables = ['player_stats', 'custom_roles_configs', 'player_groups'];
  let source;
  if (useExport) {
    const rows = await Promise.all(['users', ...tables].map(async table => {
      const exported = JSON.parse(await fs.readFile(path.join(here, 'exports', `${table}.json`), 'utf8'));
      return [table, exported.map(row => table === 'users'
        ? { id: row.legacy_supabase_user_id }
        : { id: row.legacy_supabase_id, user_id: row.legacy_supabase_user_id })];
    }));
    source = Object.fromEntries(rows);
  } else {
    const [users, ...childRows] = await Promise.all([authUsers(), ...tables.map(children)]);
    source = { users, ...Object.fromEntries(tables.map((table, i) => [table, childRows[i]])) };
  }
  const target = await convex.query('migration:getOwnershipSnapshot', {});
  const report = compareOwnership(source, target);
  console.log(JSON.stringify(report, null, 2));
  if (!report.passed) process.exitCode = 1;
  else console.log('[verify] OK: every legacy ID, owner mapping, and per-user count matches.');
} catch (error) {
  console.error(`[verify] could not complete verification: ${error.message}`);
  process.exitCode = 1;
}
