import { expect, test } from 'vitest';
import { api } from '../../convex/_generated/api';
import { backend, guest, proof, room, startNight } from './helpers';

test('a proven member can restore the same seat in a full lobby', async () => {
  const t = backend(); const r = await room(t);
  await t.run(async ctx => {
    const session = await ctx.db.query('game_sessions').withIndex('by_app_id', q => q.eq('id', r.session.id)).unique();
    await ctx.db.patch(session!._id, { max_players: 4 });
  });
  const result = await t.mutation(api.sessions.joinSession, {
    room_code: r.session.room_code, user_id: r.users[1].id,
    player_name: 'Should not replace the saved seat name', ...proof(r.users[1]),
  });
  expect(result.player.id).toBe(r.players[1].id);
  expect(result.player.player_id).toBe(r.players[1].player_id);
  expect(result.player.player_name).toBe(r.players[1].player_name);
  expect(await t.query(api.sessions.getSessionPlayers, r.viewerArgs(r.host))).toHaveLength(4);
});

test('active reentry preserves elimination/readiness and filters private history', async () => {
  const t = backend(); const r = await room(t);
  const active = await startNight(t, r);
  await t.mutation(api.sessions.updateSessionState, { ...r.hostArgs, night_history: [{
    night_index: 0, is_resolved: true, mafia_target_id: r.players[0].player_id,
    doctor_protected_id: r.players[0].player_id, inspector_result: 'mafia',
    inspector_checked_id: r.players[1].player_id, mafia_player_numbers: [2],
    doctor_player_numbers: [3], inspector_player_numbers: [4], timestamp: 123,
  }] });
  await t.run(async ctx => {
    const player = await ctx.db.query('session_players').withIndex('by_app_id', q => q.eq('id', r.players[1].id)).unique();
    await ctx.db.patch(player!._id, { is_alive: false, is_ready: true, is_online: false, last_heartbeat: 0 });
  });
  const result = await t.mutation(api.sessions.joinSession, {
    room_code: r.session.room_code, user_id: r.users[1].id, player_name: 'QA reentry', ...proof(r.users[1]),
  });
  expect(result.session.current_round_id).toBe(active.current_round_id);
  expect(result.player).toMatchObject({ id: r.players[1].id, role: 'mafia', is_alive: false, is_ready: true, is_online: true });
  expect(result.player.last_heartbeat).toBeGreaterThan(0);
  expect(result.session.night_history[0].doctor_protected_id).toBeUndefined();
  expect(result.session.night_history[0].inspector_result).toBeUndefined();
  const outsider = await guest(t, 'QA late joiner');
  await expect(t.mutation(api.sessions.joinSession, {
    room_code: r.session.room_code, user_id: outsider.id, player_name: outsider.display_name, ...proof(outsider),
  })).rejects.toThrow();
  await expect(t.mutation(api.sessions.joinSession, {
    room_code: r.session.room_code, user_id: r.users[1].id, player_name: 'QA forged', ...proof(outsider),
  })).rejects.toThrow();
});

test('a Clerk account can restore its own seat without guest credentials', async () => {
  const t = backend(); const client = t.withIdentity({ subject: crypto.randomUUID(), email: 'qa-reentry@example.com' });
  const account = await client.mutation(api.users.ensureUser, {});
  const session = await client.mutation(api.sessions.createSession, { host_user_id: account.id, max_players: 4, bot_count: 0 });
  const args = { room_code: session.room_code, user_id: account.id, player_name: 'QA account' };
  const first = await client.mutation(api.sessions.joinSession, args);
  const again = await client.mutation(api.sessions.joinSession, args);
  expect(again.player.id).toBe(first.player.id);
  expect(await client.query(api.sessions.getSessionPlayers, { session_id: session.id, viewer_user_id: account.id })).toHaveLength(1);
});

test('cancelled rooms cannot be reopened by a former member', async () => {
  const t = backend(); const r = await room(t);
  await t.mutation(api.sessions.cancelSession, r.hostArgs);
  await expect(t.mutation(api.sessions.joinSession, {
    room_code: r.session.room_code, user_id: r.host.id, player_name: r.host.display_name, ...proof(r.host),
  })).rejects.toThrow();
});
