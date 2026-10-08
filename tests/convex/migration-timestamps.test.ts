import { expect, test } from 'vitest';
import { internal } from '../../convex/_generated/api';
import { backend } from './helpers';

const tables = ['player_stats', 'custom_roles_configs', 'player_groups'] as const;
const functions = { player_stats: internal.migration.ingestPlayerStats, custom_roles_configs: internal.migration.ingestCustomRolesConfigs, player_groups: internal.migration.ingestPlayerGroups };
function payload(table: typeof tables[number], owner: string) {
  const base = { legacy_supabase_id: crypto.randomUUID(), legacy_supabase_user_id: owner };
  if (table === 'player_stats') return { ...base, player_name: 'QA timestamp', games_played: 0, games_won: 0, games_lost: 0, total_kills: 0, times_mafia: 0, times_doctor: 0, times_inspector: 0, times_citizen: 0 };
  if (table === 'custom_roles_configs') return { ...base, config_name: 'QA timestamp', role_distribution: { mafia_count: 1, doctor_count: 1, inspector_count: 1, citizen_count: 1, total_players: 4 } };
  return { ...base, group_name: 'QA timestamp', player_names: ['QA One', 'QA Two'] };
}
for (const table of tables) {
  test(`${table}: missing optional timestamps get valid defaults`, async () => {
    const t = backend(); const owner = crypto.randomUUID();
    await t.mutation(internal.migration.ingestUsers, { rows: [{ legacy_supabase_user_id: owner, display_name: 'QA Legacy' }] });
    const row = payload(table, owner);
    await t.mutation(functions[table], { rows: [row] } as any);
    const stored = await t.run(ctx => ctx.db.query(table).withIndex('by_legacy_supabase_id', q => q.eq('legacy_supabase_id', row.legacy_supabase_id)).unique());
    expect(Number.isFinite(stored!.created_at)).toBe(true);
    expect(Number.isFinite(stored!.updated_at)).toBe(true);
  });
  test(`${table}: retry without timestamps preserves creation date and row identity`, async () => {
    const t = backend(); const owner = crypto.randomUUID();
    await t.mutation(internal.migration.ingestUsers, { rows: [{ legacy_supabase_user_id: owner, display_name: 'QA Legacy' }] });
    const row = payload(table, owner);
    await t.mutation(functions[table], { rows: [{ ...row, created_at: 42, updated_at: 43 }] } as any);
    const first = await t.run(ctx => ctx.db.query(table).withIndex('by_legacy_supabase_id', q => q.eq('legacy_supabase_id', row.legacy_supabase_id)).unique());
    await t.mutation(functions[table], { rows: [row] } as any);
    const next = await t.run(ctx => ctx.db.query(table).withIndex('by_legacy_supabase_id', q => q.eq('legacy_supabase_id', row.legacy_supabase_id)).unique());
    expect(next!.id).toBe(first!.id);
    expect(next!.created_at).toBe(42);
    expect(Number.isFinite(next!.updated_at)).toBe(true);
  });
}
