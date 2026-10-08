import { expect, test } from 'vitest';
import { api } from '../../convex/_generated/api';
import { backend, guest, proof } from './helpers';

for (const duplicateCount of [1, 2]) {
  test(`merge sums every counter and consolidates ${duplicateCount} account rows`, async () => {
    const t = backend(); const g = await guest(t, 'QA stats guest');
    const accountClient = t.withIdentity({ subject: crypto.randomUUID(), email: 'qa@example.com', name: 'QA Account' });
    const account = await accountClient.mutation(api.users.ensureUser, {});
    const name = 'QA Collision';
    const original = await accountClient.mutation(api.stats.upsertPlayerStat, { user_id: account.id, player_name: name, role: 'mafia', won: true, kills: 2 });
    if (duplicateCount === 2) {
      await t.run(async ctx => {
        const { _id, _creationTime, ...row } = (await ctx.db.query('player_stats').withIndex('by_app_id', q => q.eq('id', original.id)).unique())!;
        await ctx.db.insert('player_stats', { ...row, id: crypto.randomUUID() });
      });
    }
    await t.mutation(api.stats.upsertPlayerStat, { user_id: g.id, player_name: name, role: 'doctor', won: false, kills: 1, ...proof(g) });
    await t.mutation(api.stats.upsertPlayerStat, { user_id: g.id, player_name: 'QA New Name', role: 'inspector', won: true, kills: 0, ...proof(g) });
    await accountClient.mutation(api.users.mergeGuestIntoAccount, { guest_user_id: g.id, target_user_id: account.id, ...proof(g) });
    const rows = await accountClient.query(api.stats.listPlayerStats, { user_id: account.id });
    expect(rows).toHaveLength(2);
    const combined = await accountClient.query(api.stats.getPlayerStat, { user_id: account.id, player_name: name });
    expect(combined).toMatchObject({
      games_played: duplicateCount + 1, games_won: duplicateCount, games_lost: 1,
      total_kills: 2 * duplicateCount + 1, times_mafia: duplicateCount, times_doctor: 1,
      times_inspector: 0, times_citizen: 0,
    });
    const next = await accountClient.mutation(api.stats.upsertPlayerStat, { user_id: account.id, player_name: name, role: 'citizen', won: true, kills: 0 });
    expect(next.games_played).toBe(duplicateCount + 2);
    expect(next.times_citizen).toBe(1);
    await expect(t.query(api.users.getUserProfile, { user_id: g.id, ...proof(g) })).rejects.toThrow();
  });
}
