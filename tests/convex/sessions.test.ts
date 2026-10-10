import { expect, test } from 'vitest';
import { api } from '../../convex/_generated/api';
import { E } from '../../convex/lib/errors';
import { backend, guest, proof, room, round, seatRow, sessionRow, start } from './helpers';

test('createSession creates the host seat and bot seats atomically', async () => {
  const t = backend(); const host = await guest(t, 'QA Host');
  const entered = await t.mutation(api.sessions.createSession, { player_name: ' Host ', max_players: 19, bot_count: 3, ...proof(host) });
  expect(Object.keys(entered).sort()).toEqual(['player_id', 'player_record_id', 'room_code', 'session_id']);
  expect(entered.room_code).toMatch(/^\d{6}$/);
  const players = await t.query(api.views.getPlayers, { session_id: entered.session_id, ...proof(host) });
  expect(players.map(p => [p.player_name, p.is_bot, p.is_online, p.is_ready, p.is_me])).toEqual([
    ['Host', false, true, true, true], ['Bot 1', true, false, true, false],
    ['Bot 2', true, false, true, false], ['Bot 3', true, false, true, false],
  ]);
  expect(players[0]).toMatchObject({ id: entered.player_record_id, player_id: entered.player_id, user_id: host.id });
  const view = await t.query(api.views.getSessionView, { session_id: entered.session_id, ...proof(host) });
  expect(view!.session).toMatchObject({ status: 'waiting', current_phase: 'lobby', current_phase_data: { type: 'lobby' },
    host_user_id: host.id, original_host_user_id: host.id, bot_count: 3, max_players: 19 });
  expect(view!.session).not.toHaveProperty('phase_sequence');
  for (const [max_players, bot_count, error] of [[3, 0, E.MAX_PLAYERS], [20, 0, E.MAX_PLAYERS], [4.5, 0, E.MAX_PLAYERS],
    [4, 4, E.BOT_COUNT], [4, -1, E.BOT_COUNT], [4, 1.5, E.BOT_COUNT]] as const) {
    await expect(t.mutation(api.sessions.createSession, { player_name: 'H', max_players, bot_count, ...proof(host) })).rejects.toThrow(error);
  }
  await expect(t.mutation(api.sessions.createSession, { player_name: 'x'.repeat(51), max_players: 4, bot_count: 0, ...proof(host) }))
    .rejects.toThrow(E.PLAYER_NAME);
  await expect(t.mutation(api.sessions.createSession, { player_name: 'H', max_players: 4, bot_count: 0 })).rejects.toThrow(E.AUTH);
});

test('joinSession re-enters the same seat and enforces lobby rules', async () => {
  const t = backend(); const host = await guest(t, 'QA Host');
  const entered = await t.mutation(api.sessions.createSession, { player_name: 'Host', max_players: 4, bot_count: 2, ...proof(host) });
  const a = await guest(t, 'QA A');
  const seat = await t.mutation(api.sessions.joinSession, { room_code: ` ${entered.room_code} `, player_name: 'A', ...proof(a) });
  await t.run(async ctx => {
    const row = await ctx.db.query('session_players').withIndex('by_app_id', q => q.eq('id', seat.player_record_id)).unique();
    await ctx.db.patch(row!._id, { is_online: false, last_heartbeat: 0 });
  });
  expect(await t.mutation(api.sessions.joinSession, { room_code: entered.room_code, player_name: 'Renamed', ...proof(a) })).toEqual(seat);
  const row = await seatRow(t, seat.player_id);
  expect(row).toMatchObject({ player_name: 'A', is_online: true });
  expect(row!.last_heartbeat).toBeGreaterThan(0);
  const late = await guest(t, 'QA Late');
  await expect(t.mutation(api.sessions.joinSession, { room_code: entered.room_code, player_name: 'L', ...proof(late) })).rejects.toThrow(E.GAME_FULL);
  for (const room_code of ['000000', 'abcdef', '12345']) {
    await expect(t.mutation(api.sessions.joinSession, { room_code, player_name: 'L', ...proof(late) })).rejects.toThrow(E.GAME_NOT_FOUND);
  }
  await expect(t.mutation(api.sessions.joinSession, { room_code: entered.room_code, player_name: 'L' })).rejects.toThrow(E.AUTH);
});

test('started games accept re-entry but not newcomers; cancelled rooms are gone', async () => {
  const t = backend(); const r = await room(t, 4);
  await start(t, r, ['citizen', 'mafia', 'inspector', 'citizen']);
  const outsider = await guest(t, 'QA Late');
  await expect(t.mutation(api.sessions.joinSession, { room_code: r.roomCode, player_name: 'L', ...proof(outsider) })).rejects.toThrow(E.GAME_STARTED);
  expect((await t.mutation(api.sessions.joinSession, { room_code: r.roomCode, player_name: 'x', ...proof(r.users[1]) })).player_id)
    .toBe(r.humans[1].player_id);
  await t.mutation(api.sessions.cancelSession, r.as(r.host));
  await expect(t.mutation(api.sessions.joinSession, { room_code: r.roomCode, player_name: 'x', ...proof(r.host) })).rejects.toThrow(E.GAME_NOT_FOUND);
});

test('leaving hands host to the earliest human; the last human cancels the room', async () => {
  const t = backend(); const r = await room(t, 2, 2);
  await t.mutation(api.sessions.leaveSession, r.as(r.host));
  await t.mutation(api.sessions.leaveSession, r.as(r.host));
  const view = await t.query(api.views.getSessionView, r.as(r.users[1]));
  expect(view!.session.host_user_id).toBe(r.users[1].id);
  expect(view!.viewer.is_host).toBe(true);
  await t.mutation(api.sessions.leaveSession, r.as(r.users[1]));
  expect((await t.query(api.views.getSessionView, { session_id: r.sessionId }))!.session)
    .toMatchObject({ status: 'cancelled', current_phase: 'cancelled' });
  expect(await t.run(ctx => ctx.db.query('session_players').withIndex('by_session', q => q.eq('session_id', r.sessionId)).collect())).toEqual([]);
  await t.mutation(api.sessions.leaveSession, r.as(r.users[1]));
  await t.mutation(api.sessions.leaveSession, { session_id: crypto.randomUUID(), ...proof(r.host) });
});

test('host removes players and cancels; members cannot', async () => {
  const t = backend(); const r = await room(t, 4);
  const kicked = r.users[1];
  await expect(t.mutation(api.sessions.removePlayer, { ...r.as(kicked), player_record_id: r.humans[2].id })).rejects.toThrow(E.HOST_ONLY);
  await expect(t.mutation(api.sessions.removePlayer, { ...r.as(r.host), player_record_id: r.humans[0].id })).rejects.toThrow(E.REMOVE_SELF);
  await expect(t.mutation(api.sessions.removePlayer, { ...r.as(r.host), player_record_id: crypto.randomUUID() })).rejects.toThrow(E.PLAYER_NOT_FOUND);
  await t.mutation(api.sessions.removePlayer, { ...r.as(r.host), player_record_id: r.humans[1].id });
  expect(await t.query(api.views.getPlayers, r.as(kicked))).toEqual([]);
  expect(await t.query(api.views.getRoundState, r.as(kicked))).toBeNull();
  expect((await t.query(api.views.getSessionView, r.as(kicked)))!.viewer).toEqual({
    user_id: kicked.id, player_record_id: null, player_id: null, is_member: false, is_host: false,
  });
  await expect(t.mutation(api.sessions.setReady, { ...r.as(kicked), is_ready: true })).rejects.toThrow(E.NOT_MEMBER);
  await expect(t.mutation(api.sessions.cancelSession, r.as(r.users[2]))).rejects.toThrow(E.HOST_ONLY);
  await expect(t.mutation(api.sessions.cancelSession, { session_id: crypto.randomUUID(), ...proof(r.host) })).rejects.toThrow(E.GAME_NOT_FOUND);
  await t.mutation(api.sessions.cancelSession, r.as(r.host));
  await t.mutation(api.sessions.cancelSession, r.as(r.host));
  expect((await t.query(api.views.getSessionView, r.as(r.users[2])))!.viewer.is_member).toBe(false);
});

test('only the server-chosen successor can claim host, and only from a stale host', async () => {
  const t = backend(); const r = await room(t, 3);
  const claim = (i: number) => t.mutation(api.sessions.claimHost, r.as(r.users[i]));
  await expect(claim(1)).rejects.toThrow(E.HOST_ACTIVE);
  await t.run(async ctx => {
    const host = await ctx.db.query('session_players').withIndex('by_app_id', q => q.eq('id', r.humans[0].id)).unique();
    await ctx.db.patch(host!._id, { last_heartbeat: 0 });
  });
  await expect(claim(2)).rejects.toThrow(E.HOST_SUCCESSOR);
  await claim(1);
  await claim(1);
  expect((await sessionRow(t, r.sessionId)).host_user_id).toBe(r.users[1].id);
  await t.mutation(api.sessions.heartbeat, r.as(r.host));
  expect((await seatRow(t, r.humans[0].player_id))!.last_heartbeat).toBeGreaterThan(0);
  await expect(claim(0)).rejects.toThrow(E.HOST_ACTIVE);
  const outsider = await guest(t, 'QA Out');
  await expect(t.mutation(api.sessions.claimHost, r.as(outsider))).rejects.toThrow(E.NOT_MEMBER);
  await t.mutation(api.sessions.heartbeat, r.as(outsider));
  await expect(t.mutation(api.sessions.heartbeat, { session_id: r.sessionId })).rejects.toThrow(E.AUTH);
});

test('startGame checks coverage and role counts, and runs once', async () => {
  const t = backend(); const r = await room(t, 2, 4);
  const seats = [...r.humans, ...r.bots];
  const roles = ['citizen', 'mafia', 'doctor', 'inspector', 'citizen', 'mafia'] as const;
  const assignments = seats.map((s, i) => ({ player_id: s.player_id, role: roles[i], number: i + 7 }));
  const startWith = (a: typeof assignments, user = r.host) => t.mutation(api.sessions.startGame, { ...r.as(user), assignments: a });
  await expect(startWith(assignments, r.users[1])).rejects.toThrow(E.HOST_ONLY);
  for (const bad of [
    assignments.slice(1),
    [...assignments.slice(1), assignments[1]],
    [...assignments.slice(1), { ...assignments[0], player_id: crypto.randomUUID() }],
    [...assignments.slice(1), { ...assignments[0], number: 8 }],
    [...assignments.slice(1), { ...assignments[0], number: 13 }],
    [...assignments.slice(1), { ...assignments[0], number: 0 }],
    [...assignments.slice(1), { ...assignments[0], number: 1.5 }],
  ]) await expect(startWith(bad)).rejects.toThrow(E.ASSIGNMENT_COVERAGE);
  await expect(startWith(assignments.map((a, i) => ({ ...a, role: i === 0 ? 'mafia' as const : a.role }))))
    .rejects.toThrow(E.ASSIGNMENT_ROLES);
  await startWith(assignments);
  await expect(startWith(assignments)).rejects.toThrow(E.GAME_STARTED);
  const view = await t.query(api.views.getSessionView, r.as(r.host));
  expect(view!.session).toMatchObject({ status: 'in_progress', current_phase: 'role_reveal',
    current_phase_data: { type: 'roleReveal', currentPlayerIndex: 0 }, original_host_user_id: r.host.id,
    assigned_numbers: assignments.map(a => ({ player_id: a.player_id, number: a.number })) });
  const players = await t.query(api.views.getPlayers, r.as(r.host));
  for (const [i, seat] of seats.entries()) {
    expect(players.find(p => p.player_id === seat.player_id)).toMatchObject({ role: roles[i], player_number: i + 7, is_ready: seat.is_bot });
  }
  const state = await round(t, r);
  expect(state).toMatchObject({ phase: 'role_reveal', round_id: null, phase_index: null, ready_to_advance: false });
  for (const user of r.users) await t.mutation(api.sessions.setReady, { ...r.as(user), is_ready: true });
  expect((await round(t, r)).ready_to_advance).toBe(true);
  expect((await t.query(api.views.getRoundState, r.as(r.users[1])))!.ready_to_advance).toBe(false);
});

test('startGame requires 4 to 19 seats within max_players', async () => {
  const t = backend(); const r = await room(t, 3);
  const assignments = r.humans.map((s, i) => ({ player_id: s.player_id, role: 'citizen' as const, number: i + 1 }));
  await expect(t.mutation(api.sessions.startGame, { ...r.as(r.host), assignments })).rejects.toThrow(E.PLAYER_COUNT);
});

test('Play Again resets the finished game; the original host reclaims the lobby', async () => {
  const t = backend(); const r = await room(t, 4);
  await start(t, r, ['citizen', 'mafia', 'inspector', 'citizen']);
  await expect(t.mutation(api.sessions.returnToLobby, r.as(r.users[1]))).rejects.toThrow(E.NOT_GAME_OVER);
  await t.run(async ctx => {
    const s = await ctx.db.query('game_sessions').withIndex('by_app_id', q => q.eq('id', r.sessionId)).unique();
    await ctx.db.patch(s!._id, { current_phase: 'game_over', is_game_over: true, status: 'completed', winner: 'mafia' });
  });
  await t.mutation(api.sessions.returnToLobby, r.as(r.users[1]));
  const lobby = await t.query(api.views.getSessionView, r.as(r.users[1]));
  expect(lobby!.session).toMatchObject({ host_user_id: r.users[1].id, original_host_user_id: r.host.id, status: 'waiting',
    current_phase: 'lobby', day_index: 0, is_game_over: false, assigned_numbers: [], night_history: [], day_history: [] });
  expect(lobby!.session).not.toHaveProperty('winner');
  expect(lobby!.session).not.toHaveProperty('current_round_id');
  const players = await t.query(api.views.getPlayers, r.as(r.users[1]));
  expect(players.map(p => [p.role, p.player_number, p.is_alive, p.is_ready]))
    .toEqual(r.users.map(u => [undefined, undefined, true, u.id === r.users[1].id]));
  await t.mutation(api.sessions.returnToLobby, r.as(r.users[3]));
  expect((await sessionRow(t, r.sessionId)).host_user_id).toBe(r.users[1].id);
  await t.mutation(api.sessions.returnToLobby, r.as(r.host));
  expect((await sessionRow(t, r.sessionId)).host_user_id).toBe(r.host.id);
  expect((await t.query(api.views.getPlayers, r.as(r.host))).filter(p => p.is_ready)).toHaveLength(3);
});

test('a host without a seat can still leave and hand over host', async () => {
  const t = backend(); const r = await room(t, 3);
  await t.run(async ctx => {
    const row = await ctx.db.query('session_players').withIndex('by_app_id', q => q.eq('id', r.humans[0].id)).unique();
    await ctx.db.delete(row!._id);
  });
  await t.mutation(api.sessions.leaveSession, r.as(r.host));
  expect(await sessionRow(t, r.sessionId)).toMatchObject({ host_user_id: r.users[1].id, status: 'waiting' });
});

test('the host can remove a bot seat', async () => {
  const t = backend(); const r = await room(t, 2, 2);
  await t.mutation(api.sessions.removePlayer, { ...r.as(r.host), player_record_id: r.bots[0].id });
  expect((await t.query(api.views.getPlayers, r.as(r.host))).map(p => p.player_name)).toEqual(['QA 0', 'Bot 2', 'QA 1']);
  expect((await sessionRow(t, r.sessionId)).host_user_id).toBe(r.host.id);
});
