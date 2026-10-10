import { expect, test } from 'vitest';
import { api, internal } from '../../convex/_generated/api';
import { backend, guest, proof } from './helpers';

test('internal migration audit counts only legacy rows and returns no personal fields', async () => {
  const t = backend(); const legacy = crypto.randomUUID();
  await t.mutation(internal.migration.ingestUsers, { rows: [{ legacy_supabase_user_id: legacy, display_name: 'Legacy Name', email: 'legacy@example.com' }] });
  await t.mutation(internal.migration.ingestPlayerStats, { rows: [{
    legacy_supabase_id: crypto.randomUUID(), legacy_supabase_user_id: legacy, player_name: 'Legacy Player', created_at: 123, updated_at: 123,
    games_played: 1, games_won: 1, games_lost: 0, total_kills: 0, times_mafia: 0, times_doctor: 0, times_inspector: 0, times_citizen: 1,
  }] });
  const fresh = await guest(t, 'Fresh Personal Name');
  await t.mutation(api.stats.upsertPlayerStat, { user_id: fresh.id, player_name: 'Fresh Player', role: 'citizen', won: true, kills: 0, ...proof(fresh) });
  expect(await t.query(internal.migration.countByTable, {})).toMatchObject({ users: 2, legacy_users: 1, player_stats: 2, legacy_player_stats: 1 });
  const audit = await t.query(internal.migration.getOwnershipSnapshot, {});
  const json = JSON.stringify(audit);
  expect(json).not.toContain('example.com');
  expect(json).not.toContain('Personal Name');
  expect(json).not.toContain(fresh.hash);
  expect(json).not.toContain('Legacy Player');
  expect(audit.users).toHaveLength(2);
});
