import { afterEach, expect, test, vi } from 'vitest';
import { api } from '../../convex/_generated/api';
import { E, mergeSeatConflict } from '../../convex/lib/errors';
import { sha256Hex } from '../../convex/lib/util';
import { Backend, advance, backend, guest, presenceRows, proof, room, sessionRow } from './helpers';

afterEach(() => { vi.useRealTimers(); });

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
  expect(await t.query(api.stats.getPlayerStat, { player_name: ' Ann ', ...proof(g) })).toEqual(second);
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

test('merge moves seats and host ownership', async () => {
  const t = backend(); const r = await room(t, 4);
  const account = t.withIdentity({ subject: crypto.randomUUID(), email: 'qa-room@example.com' });
  const me = await account.mutation(api.users.ensureUser, {});
  await account.mutation(api.users.mergeGuestIntoAccount, proof(r.host));
  const view = await account.query(api.views.getSessionView, { session_id: r.sessionId });
  expect(view!.session).toMatchObject({ host_user_id: me.id, original_host_user_id: me.id });
  expect(view!.viewer).toMatchObject({ user_id: me.id, player_record_id: r.humans[0].id, is_member: true, is_host: true });
  // The host's presence moves with the seat, so the host is not seen as gone.
  expect((await presenceRows(t, r.sessionId)).map(p => p.user_id).sort()).toEqual([me.id, ...r.users.slice(1).map(u => u.id)].sort());
  expect((await account.query(api.views.getHostPresence, { session_id: r.sessionId }))!.host_last_heartbeat).not.toBeNull();
});

const patchRoom = (t: Backend, sessionId: string, patch: object) => t.run(async ctx => {
  const s = await ctx.db.query('game_sessions').withIndex('by_app_id', q => q.eq('id', sessionId)).unique();
  await ctx.db.patch(s!._id, patch);
});

test('a seat conflict refuses the merge only during a game, and names the room', async () => {
  const t = backend(); const r = await room(t, 4);
  const account = t.withIdentity({ subject: crypto.randomUUID(), email: 'qa-conflict@example.com' });
  await account.mutation(api.users.ensureUser, {});
  await account.mutation(api.sessions.joinSession, { room_code: r.roomCode, player_name: 'QA Account' });
  await patchRoom(t, r.sessionId, { status: 'in_progress' });
  const message = mergeSeatConflict(r.roomCode);
  // The app recognises the conflict by this prefix.
  expect(message).toBe(`Leave your other seat in room ${r.roomCode} before saving guest progress.`);
  await expect(account.mutation(api.users.mergeGuestIntoAccount, proof(r.host))).rejects.toThrow(message);
  expect(await t.query(api.users.getMe, proof(r.host))).toMatchObject({ id: r.host.id, is_anonymous: true });
  expect(await t.query(api.views.getPlayers, r.as(r.host))).toHaveLength(5);
});

test('in a lobby or a finished game the merge keeps the seat used last', async () => {
  vi.useFakeTimers({ toFake: ['Date'] });
  for (const status of ['waiting', 'completed'] as const) {
    for (const newer of ['guest', 'account'] as const) {
      const t = backend(); const r = await room(t, 3);
      const account = t.withIdentity({ subject: crypto.randomUUID(), email: 'qa-keep@example.com' });
      const me = await account.mutation(api.users.ensureUser, {});
      advance(5);
      const mine = await account.mutation(api.sessions.joinSession, { room_code: r.roomCode, player_name: 'QA Account' });
      advance(5);
      if (newer === 'guest') await t.mutation(api.sessions.heartbeat, r.as(r.host));
      if (status === 'completed') await patchRoom(t, r.sessionId, { status, current_phase: 'game_over', is_game_over: true });
      await account.mutation(api.users.mergeGuestIntoAccount, proof(r.host));

      const kept = newer === 'guest' ? r.humans[0].player_id : mine.player_id;
      const players = await account.query(api.views.getPlayers, { session_id: r.sessionId });
      expect(players.filter(p => p.user_id === me.id).map(p => p.player_id)).toEqual([kept]);
      expect(players).toHaveLength(3);
      expect((await presenceRows(t, r.sessionId)).filter(p => p.user_id === me.id)).toHaveLength(1);
      expect(await sessionRow(t, r.sessionId)).toMatchObject({ host_user_id: me.id, original_host_user_id: me.id });
    }
  }
});

test('merge hands over only rooms that can still matter, once each', async () => {
  vi.useFakeTimers({ toFake: ['Date'] });
  const t = backend(); const g = await guest(t, 'QA Guest'); const other = await guest(t, 'QA Other');
  const host = () => t.mutation(api.sessions.createSession, { player_name: 'QA Guest', max_players: 19, bot_count: 0, ...proof(g) });
  const lobby = await host(); const cancelled = await host(); const finished = await host(); const left = await host();
  await t.mutation(api.sessions.cancelSession, { session_id: cancelled.session_id, ...proof(g) });
  // The guest leaves `left` (host moves to `other`), and both games finish.
  await t.mutation(api.sessions.joinSession, { room_code: left.room_code, player_name: 'QA Other', ...proof(other) });
  await t.mutation(api.sessions.leaveSession, { session_id: left.session_id, ...proof(g) });
  for (const room of [finished, left]) await patchRoom(t, room.session_id, { status: 'completed', is_game_over: true });
  const rows = async () => Object.fromEntries(await Promise.all([lobby, cancelled, finished, left]
    .map(async room => [room.session_id, await sessionRow(t, room.session_id)])));
  const before = await rows();
  advance(60);

  const account = t.withIdentity({ subject: crypto.randomUUID(), email: 'qa-rooms@example.com' });
  const me = await account.mutation(api.users.ensureUser, {});
  await account.mutation(api.users.mergeGuestIntoAccount, proof(g));
  const after = await rows();
  for (const room of [lobby, finished]) {
    expect(after[room.session_id]).toMatchObject({ host_user_id: me.id, original_host_user_id: me.id });
    expect(after[room.session_id].updated_at).toBeGreaterThan(before[room.session_id].updated_at);
  }
  // Dead rooms are not rewritten: no new owner and no updated_at bump.
  for (const room of [cancelled, left]) expect(after[room.session_id]).toEqual(before[room.session_id]);
  expect(after[left.session_id]).toMatchObject({ host_user_id: other.id, original_host_user_id: g.id });
});

test('merge keeps only the latest 20 tombstones, and a retry still finds its own', async () => {
  const t = backend(); const subject = crypto.randomUUID();
  const account = t.withIdentity({ subject, email: 'qa-tombstones@example.com' });
  await account.mutation(api.users.ensureUser, {});
  const old = Array.from({ length: 20 }, (_, i) => `old-${i}`);
  const accountRow = () => t.run(ctx => ctx.db.query('users').withIndex('by_auth_subject', q => q.eq('auth_subject', subject)).unique());
  const { _id } = (await accountRow())!;
  await t.run(ctx => ctx.db.patch(_id, { merged_guest_digests: old }));
  const g = await guest(t, 'QA Guest');
  await account.mutation(api.users.mergeGuestIntoAccount, proof(g));
  expect((await accountRow())!.merged_guest_digests).toEqual([...old.slice(1), await sha256Hex(g.hash)]);
  expect(await account.mutation(api.users.mergeGuestIntoAccount, proof(g))).toEqual({ success: true, merged_count: 0, transferred_count: 0 });
});

const result = (player_name: string, role: 'mafia' | 'doctor' | 'inspector' | 'citizen', won: boolean, kills = 0) =>
  ({ player_name, role, won, kills });

test('recordGame counts a game once per game_id and skips invalid rows', async () => {
  const t = backend(); const g = await guest(t, 'QA Stats'); const other = await guest(t, 'QA Other');
  const game = { game_id: crypto.randomUUID(), results: [
    result(' Ann ', 'mafia', true, 2), result('Bo', 'citizen', false), result('', 'doctor', true),
    result('x'.repeat(51), 'citizen', true), result('Cy', 'inspector', false, 1.5), result('Di', 'doctor', true, 101),
    result('a\nb', 'citizen', true),
  ] };
  expect(await t.mutation(api.stats.recordGame, { ...game, ...proof(g) })).toEqual({ recorded: true, skipped: 5 });
  const stats = async (user = g) => (await t.query(api.stats.listPlayerStats, proof(user)))
    .map(row => [row.player_name, row.games_played, row.games_won, row.games_lost, row.total_kills, row.times_mafia, row.times_citizen])
    .sort();
  const once = [['Ann', 1, 1, 0, 2, 1, 0], ['Bo', 1, 0, 1, 0, 0, 1]];
  expect(await stats()).toEqual(once);
  // A retry, even with different rows, writes nothing.
  expect(await t.mutation(api.stats.recordGame, { ...game, ...proof(g) })).toEqual({ recorded: false, skipped: 0 });
  expect(await t.mutation(api.stats.recordGame, { game_id: game.game_id, results: [result('Ann', 'mafia', true)], ...proof(g) }))
    .toEqual({ recorded: false, skipped: 0 });
  expect(await stats()).toEqual(once);
  // game_id is per caller.
  expect(await t.mutation(api.stats.recordGame, { ...game, ...proof(other) })).toEqual({ recorded: true, skipped: 5 });
  expect(await stats(other)).toEqual(once);
  // A second game adds to the same rows; a game with only invalid rows is still recorded.
  expect(await t.mutation(api.stats.recordGame, { game_id: crypto.randomUUID(), results: [result('Ann', 'doctor', false, 1)], ...proof(g) }))
    .toEqual({ recorded: true, skipped: 0 });
  expect((await stats())[0]).toEqual(['Ann', 2, 1, 1, 3, 1, 0]);
  const invalidOnly = { game_id: crypto.randomUUID(), results: [result('', 'citizen', true)] };
  expect(await t.mutation(api.stats.recordGame, { ...invalidOnly, ...proof(g) })).toEqual({ recorded: true, skipped: 1 });
  expect(await t.mutation(api.stats.recordGame, { ...invalidOnly, ...proof(g) })).toEqual({ recorded: false, skipped: 0 });
  expect(await t.mutation(api.stats.recordGame, { game_id: crypto.randomUUID(), results: [], ...proof(g) })).toEqual({ recorded: true, skipped: 0 });
  await expect(t.mutation(api.stats.recordGame, game)).rejects.toThrow(E.AUTH);
});

test('a recordGame retried after the guest merged into an account does not count twice', async () => {
  const t = backend(); const g = await guest(t, 'QA Guest');
  const account = t.withIdentity({ subject: crypto.randomUUID(), email: 'qa-record@example.com' });
  await account.mutation(api.users.ensureUser, {});
  const shared = { game_id: crypto.randomUUID(), results: [result('Ann', 'mafia', true, 1)] };
  const both = { game_id: crypto.randomUUID(), results: [result('Bo', 'citizen', true)] };
  await t.mutation(api.stats.recordGame, { ...shared, ...proof(g) });
  await t.mutation(api.stats.recordGame, { ...both, ...proof(g) });
  await account.mutation(api.stats.recordGame, both);
  await account.mutation(api.users.mergeGuestIntoAccount, proof(g));
  expect(await account.mutation(api.stats.recordGame, shared)).toEqual({ recorded: false, skipped: 0 });
  expect(await account.mutation(api.stats.recordGame, both)).toEqual({ recorded: false, skipped: 0 });
  expect((await account.query(api.stats.getPlayerStat, { player_name: 'Ann' }))!.games_played).toBe(1);
  const games = await t.run(ctx => ctx.db.query('recorded_games').collect());
  expect(games.map(row => row.game_id).sort()).toEqual([shared.game_id, both.game_id].sort());
  expect(new Set(games.map(row => row.user_id)).size).toBe(1);
});
