import { expect, test } from 'vitest';
import { api } from '../../convex/_generated/api';
import { E } from '../../convex/lib/errors';
import { backend, guest, proof, room } from './helpers';

const dist = (mafia: number, doctor: number, inspector: number, citizen: number, total = mafia + doctor + inspector + citizen) =>
  ({ mafia_count: mafia, doctor_count: doctor, inspector_count: inspector, citizen_count: citizen, total_players: total });

test('upsertPlayerStat records one game per call and validates bounds', async () => {
  const t = backend(); const g = await guest(t, 'QA Stats');
  const first = await t.mutation(api.stats.upsertPlayerStat, { player_name: ' Ann ', role: 'mafia', won: true, kills: 2, ...proof(g) });
  expect(Object.keys(first).sort()).toEqual(['created_at', 'games_lost', 'games_played', 'games_won', 'id', 'player_name',
    'times_citizen', 'times_doctor', 'times_inspector', 'times_mafia', 'total_kills', 'updated_at', 'user_id']);
  expect(first).toMatchObject({ user_id: g.id, player_name: 'Ann', games_played: 1, games_won: 1, games_lost: 0, total_kills: 2, times_mafia: 1 });
  const second = await t.mutation(api.stats.upsertPlayerStat, { player_name: 'Ann', role: 'doctor', won: false, kills: 0, ...proof(g) });
  expect(second).toMatchObject({ id: first.id, games_played: 2, games_won: 1, games_lost: 1, total_kills: 2, times_mafia: 1, times_doctor: 1 });
  expect(await t.query(api.stats.getPlayerStat, { player_name: 'Ann', ...proof(g) })).toEqual(second);
  expect(await t.query(api.stats.listPlayerStats, proof(g))).toEqual([second]);
  for (const kills of [-1, 1.5, 101]) {
    await expect(t.mutation(api.stats.upsertPlayerStat, { player_name: 'Ann', role: 'citizen', won: true, kills, ...proof(g) }))
      .rejects.toThrow(E.KILLS);
  }
  for (const player_name of ['', 'x'.repeat(51)]) {
    await expect(t.mutation(api.stats.upsertPlayerStat, { player_name, role: 'citizen', won: true, kills: 0, ...proof(g) }))
      .rejects.toThrow(E.PLAYER_NAME);
  }
  await expect(t.mutation(api.stats.upsertPlayerStat, { player_name: 'Ann', role: 'citizen', won: true, kills: 0 }))
    .rejects.toThrow(E.AUTH);
});

test('library rows are scoped to the caller and never leak existence', async () => {
  const t = backend(); const owner = await guest(t, 'QA Owner'); const other = await guest(t, 'QA Other');
  const stat = await t.mutation(api.stats.upsertPlayerStat, { player_name: 'Ann', role: 'citizen', won: true, kills: 0, ...proof(owner) });
  const config = await t.mutation(api.stats.createCustomRoleConfig, { config_name: 'Six', role_distribution: dist(2, 1, 1, 2), ...proof(owner) });
  const group = await t.mutation(api.stats.createPlayerGroup, { group_name: 'Friday', player_names: [' Ann ', 'Bo'], ...proof(owner) });
  expect(group.player_names).toEqual(['Ann', 'Bo']);
  expect(await t.query(api.stats.listPlayerStats, proof(other))).toEqual([]);
  expect(await t.query(api.stats.listCustomRoleConfigs, proof(other))).toEqual([]);
  expect(await t.query(api.stats.listPlayerGroups, proof(other))).toEqual([]);
  expect(await t.query(api.stats.getPlayerStat, { player_name: 'Ann', ...proof(other) })).toBeNull();
  await t.mutation(api.stats.deletePlayerStat, { id: stat.id, ...proof(other) });
  await t.mutation(api.stats.deleteCustomRoleConfig, { id: config.id, ...proof(other) });
  await t.mutation(api.stats.deletePlayerGroup, { id: group.id, ...proof(other) });
  await expect(t.mutation(api.stats.updateCustomRoleConfig, { id: config.id, config_name: 'Mine', role_distribution: dist(1, 0, 1, 2), ...proof(other) }))
    .rejects.toThrow(E.CONFIG_NOT_FOUND);
  await expect(t.mutation(api.stats.updatePlayerGroup, { id: group.id, group_name: 'Mine', player_names: ['x'], ...proof(other) }))
    .rejects.toThrow(E.GROUP_NOT_FOUND);
  await expect(t.mutation(api.stats.updateCustomRoleConfig, { id: crypto.randomUUID(), config_name: 'Mine', role_distribution: dist(1, 0, 1, 2), ...proof(owner) }))
    .rejects.toThrow(E.CONFIG_NOT_FOUND);
  expect(await t.query(api.stats.listPlayerStats, proof(owner))).toHaveLength(1);
  expect(await t.query(api.stats.listCustomRoleConfigs, proof(owner))).toEqual([config]);
  expect(await t.query(api.stats.listPlayerGroups, proof(owner))).toEqual([group]);
  await t.mutation(api.stats.deletePlayerStat, { id: stat.id, ...proof(owner) });
  await t.mutation(api.stats.deleteCustomRoleConfig, { id: config.id, ...proof(owner) });
  await t.mutation(api.stats.deletePlayerGroup, { id: group.id, ...proof(owner) });
  expect(await t.query(api.stats.listPlayerStats, proof(owner))).toEqual([]);
  expect(await t.query(api.stats.listCustomRoleConfigs, proof(owner))).toEqual([]);
  expect(await t.query(api.stats.listPlayerGroups, proof(owner))).toEqual([]);
});

test('config and group names are unique per user and inputs are bounded', async () => {
  const t = backend(); const g = await guest(t, 'QA Library'); const other = await guest(t, 'QA Other');
  const a = await t.mutation(api.stats.createCustomRoleConfig, { config_name: 'A', role_distribution: dist(1, 0, 1, 2), ...proof(g) });
  const b = await t.mutation(api.stats.createCustomRoleConfig, { config_name: 'B', role_distribution: dist(1, 0, 1, 2), ...proof(g) });
  await t.mutation(api.stats.createCustomRoleConfig, { config_name: 'A', role_distribution: dist(1, 0, 1, 2), ...proof(other) });
  await expect(t.mutation(api.stats.createCustomRoleConfig, { config_name: ' A ', role_distribution: dist(1, 0, 1, 2), ...proof(g) }))
    .rejects.toThrow(E.CONFIG_EXISTS);
  await expect(t.mutation(api.stats.updateCustomRoleConfig, { id: b.id, config_name: 'A', role_distribution: dist(1, 0, 1, 2), ...proof(g) }))
    .rejects.toThrow(E.CONFIG_EXISTS);
  expect(await t.mutation(api.stats.updateCustomRoleConfig, { id: a.id, config_name: 'A', role_distribution: dist(2, 1, 1, 2), ...proof(g) }))
    .toMatchObject({ id: a.id, config_name: 'A', role_distribution: dist(2, 1, 1, 2) });
  for (const bad of [dist(-1, 0, 1, 2), dist(1, 0, 1, 2, 5), dist(0, 0, 0, 0), dist(31, 0, 0, 0), dist(1.5, 0, 1, 2), dist(10, 10, 10, 1)]) {
    await expect(t.mutation(api.stats.createCustomRoleConfig, { config_name: 'Bad', role_distribution: bad, ...proof(g) }))
      .rejects.toThrow(E.ROLE_COUNTS);
  }
  for (const config_name of ['', ' ', 'x'.repeat(101), 'a\rb']) {
    await expect(t.mutation(api.stats.createCustomRoleConfig, { config_name, role_distribution: dist(1, 0, 1, 2), ...proof(g) }))
      .rejects.toThrow(E.LIBRARY_NAME);
  }

  const ga = await t.mutation(api.stats.createPlayerGroup, { group_name: 'G', player_names: ['a'], ...proof(g) });
  const gb = await t.mutation(api.stats.createPlayerGroup, { group_name: 'H', player_names: ['a'], ...proof(g) });
  await expect(t.mutation(api.stats.createPlayerGroup, { group_name: 'G', player_names: ['b'], ...proof(g) })).rejects.toThrow(E.GROUP_EXISTS);
  await expect(t.mutation(api.stats.updatePlayerGroup, { id: gb.id, group_name: 'G', player_names: ['b'], ...proof(g) })).rejects.toThrow(E.GROUP_EXISTS);
  expect(await t.mutation(api.stats.updatePlayerGroup, { id: ga.id, group_name: 'G', player_names: ['b', 'c'], ...proof(g) }))
    .toMatchObject({ id: ga.id, player_names: ['b', 'c'] });
  for (const player_names of [[], Array.from({ length: 20 }, (_, i) => `P${i}`)]) {
    await expect(t.mutation(api.stats.createPlayerGroup, { group_name: 'Size', player_names, ...proof(g) })).rejects.toThrow(E.GROUP_SIZE);
  }
  await expect(t.mutation(api.stats.createPlayerGroup, { group_name: 'Names', player_names: ['ok', ''], ...proof(g) })).rejects.toThrow(E.PLAYER_NAME);
  await expect(t.mutation(api.stats.createPlayerGroup, { group_name: 'x'.repeat(101), player_names: ['a'], ...proof(g) })).rejects.toThrow(E.LIBRARY_NAME);
});

for (const duplicateCount of [1, 2]) {
  test(`merge sums every counter and consolidates ${duplicateCount} account rows`, async () => {
    const t = backend(); const g = await guest(t, 'QA stats guest');
    const account = t.withIdentity({ subject: crypto.randomUUID(), email: 'qa@example.com', name: 'QA Account' });
    await account.mutation(api.users.ensureUser, {});
    const name = 'QA Collision';
    const original = await account.mutation(api.stats.upsertPlayerStat, { player_name: name, role: 'mafia', won: true, kills: 2 });
    if (duplicateCount === 2) {
      await t.run(async ctx => {
        const { _id, _creationTime, ...row } = (await ctx.db.query('player_stats').withIndex('by_app_id', q => q.eq('id', original.id)).unique())!;
        await ctx.db.insert('player_stats', { ...row, id: crypto.randomUUID() });
      });
    }
    await t.mutation(api.stats.upsertPlayerStat, { player_name: name, role: 'doctor', won: false, kills: 1, ...proof(g) });
    await t.mutation(api.stats.upsertPlayerStat, { player_name: 'QA New Name', role: 'inspector', won: true, kills: 0, ...proof(g) });
    expect(await account.mutation(api.users.mergeGuestIntoAccount, proof(g)))
      .toEqual({ success: true, merged_count: 2, transferred_count: 2 });
    expect(await account.query(api.stats.listPlayerStats, {})).toHaveLength(2);
    expect(await account.query(api.stats.getPlayerStat, { player_name: name })).toMatchObject({
      games_played: duplicateCount + 1, games_won: duplicateCount, games_lost: 1,
      total_kills: 2 * duplicateCount + 1, times_mafia: duplicateCount, times_doctor: 1, times_inspector: 0, times_citizen: 0,
    });
    expect(await t.query(api.users.getMe, proof(g))).toBeNull();
  });
}

test('merge renames colliding configs and groups instead of breaking uniqueness', async () => {
  const t = backend(); const g = await guest(t, 'QA Guest');
  const account = t.withIdentity({ subject: crypto.randomUUID(), email: 'qa-rename@example.com' });
  await account.mutation(api.users.ensureUser, {});
  const long = 'L'.repeat(100);
  for (const config_name of ['Six', 'Six (Guest)', long]) {
    await account.mutation(api.stats.createCustomRoleConfig, { config_name, role_distribution: dist(2, 1, 1, 2) });
  }
  for (const config_name of ['Six', 'Solo', long]) {
    await t.mutation(api.stats.createCustomRoleConfig, { config_name, role_distribution: dist(1, 0, 1, 2), ...proof(g) });
  }
  await account.mutation(api.stats.createPlayerGroup, { group_name: 'Friday', player_names: ['a'] });
  await t.mutation(api.stats.createPlayerGroup, { group_name: 'Friday', player_names: ['b'], ...proof(g) });
  expect(await account.mutation(api.users.mergeGuestIntoAccount, proof(g)))
    .toEqual({ success: true, merged_count: 4, transferred_count: 4 });
  const configs = (await account.query(api.stats.listCustomRoleConfigs, {})).map(c => c.config_name).sort();
  expect(configs).toEqual([long, `${'L'.repeat(92)} (Guest)`, 'Six', 'Six (Guest 2)', 'Six (Guest)', 'Solo'].sort());
  expect((await account.query(api.stats.listPlayerGroups, {})).map(row => row.group_name).sort()).toEqual(['Friday', 'Friday (Guest)']);
});

test('merge moves seats and host ownership, but refuses a second seat in the same room', async () => {
  const t = backend(); const r = await room(t, 4);
  const account = t.withIdentity({ subject: crypto.randomUUID(), email: 'qa-room@example.com' });
  const me = await account.mutation(api.users.ensureUser, {});
  await account.mutation(api.users.mergeGuestIntoAccount, proof(r.host));
  const view = await account.query(api.views.getSessionView, { session_id: r.sessionId });
  expect(view!.session).toMatchObject({ host_user_id: me.id, original_host_user_id: me.id });
  expect(view!.viewer).toMatchObject({ user_id: me.id, player_record_id: r.humans[0].id, is_member: true, is_host: true });

  const r2 = await room(t, 4);
  await account.mutation(api.sessions.joinSession, { room_code: r2.roomCode, player_name: 'QA Account' });
  await expect(account.mutation(api.users.mergeGuestIntoAccount, proof(r2.host))).rejects.toThrow(E.MERGE_SEAT_CONFLICT);
  expect(await t.query(api.users.getMe, proof(r2.host))).toMatchObject({ id: r2.host.id, is_anonymous: true });
});
