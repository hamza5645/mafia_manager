import { afterEach, expect, test, vi } from 'vitest';
import { api } from '../../convex/_generated/api';
import { E } from '../../convex/lib/errors';
import { heartbeat, setReady } from '../../convex/sessions';
import { Backend, advance, backend, guest, presenceRows, proof, room, round, seatRow, sessionRow, setHeartbeat, start } from './helpers';

afterEach(() => { vi.useRealTimers(); });

test('createSession creates the host seat and bot seats atomically', async () => {
  const t = backend(); const host = await guest(t, 'QA Host');
  const entered = await t.mutation(api.sessions.createSession, { player_name: ' Host ', max_players: 19, bot_count: 3, ...proof(host) });
  expect(Object.keys(entered).sort()).toEqual(['player_id', 'player_record_id', 'rejoined', 'room_code', 'session_id']);
  expect(entered.rejoined).toBe(false);
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
  expect(seat.rejoined).toBe(false);
  expect((await presenceRows(t, entered.session_id)).map(p => p.user_id).sort()).toEqual([host.id, a.id].sort());
  await t.run(async ctx => {
    const row = await ctx.db.query('session_players').filter(q => q.eq(q.field('id'), seat.player_record_id)).unique();
    await ctx.db.patch(row!._id, { is_online: false });
  });
  await setHeartbeat(t, entered.session_id, a.id, 0);
  // The same seat, flagged as one that existed before this call.
  expect(await t.mutation(api.sessions.joinSession, { room_code: entered.room_code, player_name: 'Renamed', ...proof(a) }))
    .toEqual({ ...seat, rejoined: true });
  const row = await seatRow(t, seat.player_id);
  expect(row).toMatchObject({ player_name: 'A', is_online: true });
  expect(row).not.toHaveProperty('last_heartbeat');
  expect((await presenceRows(t, entered.session_id)).find(p => p.user_id === a.id)!.last_heartbeat).toBeGreaterThan(0);
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
  expect(await t.mutation(api.sessions.joinSession, { room_code: r.roomCode, player_name: 'x', ...proof(r.users[1]) }))
    .toMatchObject({ player_id: r.humans[1].player_id, rejoined: true });
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

test('in a game, any member can report a host silent for 15 s; the server installs its fresh successor', async () => {
  vi.useFakeTimers({ toFake: ['Date'] });
  const t = backend(); const r = await room(t, 4);
  await start(t, r, ['citizen', 'mafia', 'inspector', 'citizen']);
  const claim = (i: number) => t.mutation(api.sessions.claimHost, r.as(r.users[i]));
  const beat = (i: number) => t.mutation(api.sessions.heartbeat, r.as(r.users[i]));
  const host = async () => (await sessionRow(t, r.sessionId)).host_user_id;
  await expect(claim(3)).rejects.toThrow(E.HOST_ACTIVE);
  advance(14);
  await expect(claim(3)).rejects.toThrow(E.HOST_ACTIVE);
  // users[1] joined first but is silent too, so it is not a successor.
  advance(2); await beat(2); await beat(3);
  await claim(3);
  expect(await host()).toBe(r.users[2].id);
  await claim(2);
  await claim(2);
  expect(await host()).toBe(r.users[2].id);
  // The old host coming back does not take it back by claiming.
  await beat(0);
  await expect(claim(0)).rejects.toThrow(E.HOST_ACTIVE);
  // Nobody fresh to take over.
  advance(20);
  await expect(claim(3)).rejects.toThrow(E.HOST_SUCCESSOR);
  expect(await host()).toBe(r.users[2].id);
  // Dead players are never successors.
  await beat(0); await beat(1);
  await t.run(async ctx => {
    const row = await ctx.db.query('session_players').filter(q => q.eq(q.field('id'), r.humans[0].id)).unique();
    await ctx.db.patch(row!._id, { is_alive: false });
  });
  await claim(0);
  expect(await host()).toBe(r.users[1].id);

  const outsider = await guest(t, 'QA Out');
  await expect(t.mutation(api.sessions.claimHost, r.as(outsider))).rejects.toThrow(E.NOT_MEMBER);
  await t.mutation(api.sessions.heartbeat, r.as(outsider));
  expect((await presenceRows(t, r.sessionId)).map(p => p.user_id)).not.toContain(outsider.id);
  await expect(t.mutation(api.sessions.heartbeat, { session_id: r.sessionId })).rejects.toThrow(E.AUTH);
  await t.mutation(api.sessions.heartbeat, { session_id: crypto.randomUUID(), ...proof(r.host) });
});

test('in the lobby the host keeps the room for 90 s; getHostPresence reports the threshold', async () => {
  vi.useFakeTimers({ toFake: ['Date'] });
  const t = backend(); const r = await room(t, 4);
  const claim = (i: number) => t.mutation(api.sessions.claimHost, r.as(r.users[i]));
  const beat = (i: number) => t.mutation(api.sessions.heartbeat, r.as(r.users[i]));
  const presence = (i: number) => t.query(api.views.getHostPresence, r.as(r.users[i]));
  const joined = (await presence(1))!.host_last_heartbeat!;
  expect(await presence(1)).toEqual({ host_user_id: r.host.id, host_last_heartbeat: joined, server_now: joined, stale_after_seconds: 90 });
  advance(89); await beat(2); await beat(3);
  await expect(claim(3)).rejects.toThrow(E.HOST_ACTIVE);
  expect(await presence(3)).toEqual({ host_user_id: r.host.id, host_last_heartbeat: joined, server_now: joined + 89, stale_after_seconds: 90 });
  advance(2);
  await claim(3);
  // users[1] has been silent for 91 s, beyond the 15 s successor freshness.
  expect((await sessionRow(t, r.sessionId)).host_user_id).toBe(r.users[2].id);
  expect(await presence(0)).toMatchObject({ host_user_id: r.users[2].id, host_last_heartbeat: joined + 89 });

  await beat(0); await beat(1);
  await t.mutation(api.sessions.returnToLobby, r.as(r.host));
  expect((await sessionRow(t, r.sessionId)).host_user_id).toBe(r.host.id);
  await start(t, r, ['citizen', 'mafia', 'inspector', 'citizen']);
  expect((await presence(1))!.stale_after_seconds).toBe(15);

  const outsider = await guest(t, 'QA Out');
  expect(await t.query(api.views.getHostPresence, r.as(outsider))).toBeNull();
  expect(await t.query(api.views.getHostPresence, { session_id: r.sessionId })).toBeNull();
  expect(await t.query(api.views.getHostPresence, { session_id: crypto.randomUUID(), ...proof(r.host) })).toBeNull();
});

// Runs a mutation's handler with a db that records the table of every write.
// A patch that writes the value a field already has leaves the document
// unchanged, so comparing documents cannot see it; recording the writes can.
async function writesOf(t: Backend, fn: unknown, args: Record<string, unknown>) {
  return await t.run(async ctx => {
    const writes: string[] = [];
    const tables = ['session_players', 'session_presence', 'game_sessions', 'users'];
    const tableOf = (target: any, args: any[]) =>
      args.find(a => tables.includes(a)) ?? tables.find(table => target.normalizeId(table, args[0]) !== null) ?? '?';
    const db = new Proxy(ctx.db, {
      get(target: any, prop) {
        const value = target[prop];
        if (typeof value !== 'function') return value;
        if (!['insert', 'patch', 'replace', 'delete'].includes(String(prop))) return value.bind(target);
        return (...args: any[]) => { writes.push(tableOf(target, args)); return value.apply(target, args); };
      },
    });
    await (fn as any)._handler({ ...ctx, db }, args);
    return writes;
  });
}
const heartbeatWrites = (t: Backend, args: Record<string, unknown>) => writesOf(t, heartbeat, args);

test('heartbeats write only presence; the host sweep writes is_online only when it changes', async () => {
  vi.useFakeTimers({ toFake: ['Date'] });
  const t = backend(); const r = await room(t, 3, 1);
  const seats = () => t.run(ctx => ctx.db.query('session_players').withIndex('by_session', q => q.eq('session_id', r.sessionId)).collect());
  const online = async () => (await t.query(api.views.getPlayers, r.as(r.host))).map(p => [p.player_name, p.is_online]);
  advance(5);
  // Nobody's state changed: a member's beat and the host's sweep write only
  // their own presence row, never a seat.
  expect(await heartbeatWrites(t, r.as(r.users[1]))).toEqual(['session_presence']);
  expect(await heartbeatWrites(t, r.as(r.host))).toEqual(['session_presence']);
  expect(await online()).toEqual([['QA 0', true], ['Bot 1', false], ['QA 1', true], ['QA 2', true]]);
  advance(16);
  expect(await heartbeatWrites(t, r.as(r.users[1]))).toEqual(['session_presence']);
  // QA 2 went quiet: the sweep patches that one seat.
  expect(await heartbeatWrites(t, r.as(r.host))).toEqual(['session_presence', 'session_players']);
  expect(await online()).toEqual([['QA 0', true], ['Bot 1', false], ['QA 1', true], ['QA 2', false]]);
  expect(await heartbeatWrites(t, r.as(r.host))).toEqual(['session_presence']);
  // Coming back is picked up by the host's next sweep, or at once by re-entering.
  await t.mutation(api.sessions.heartbeat, r.as(r.users[2]));
  expect(await online()).toEqual([['QA 0', true], ['Bot 1', false], ['QA 1', true], ['QA 2', false]]);
  await t.mutation(api.sessions.heartbeat, r.as(r.host));
  expect(await online()).toEqual([['QA 0', true], ['Bot 1', false], ['QA 1', true], ['QA 2', true]]);
  advance(30);
  await t.mutation(api.sessions.heartbeat, r.as(r.host));
  expect((await online()).filter(([, on]) => on)).toEqual([['QA 0', true]]);
  await t.mutation(api.sessions.joinSession, { room_code: r.roomCode, player_name: 'x', ...proof(r.users[1]) });
  expect((await online()).filter(([, on]) => on)).toEqual([['QA 0', true], ['QA 1', true]]);
  for (const row of await seats()) expect(row).not.toHaveProperty('last_heartbeat');
});

test("another player's heartbeat leaves every view result unchanged (PA-96)", async () => {
  vi.useFakeTimers({ toFake: ['Date'] });
  const t = backend(); const r = await room(t, 4);
  const views = async (i: number) => ({
    session: await t.query(api.views.getSessionView, r.as(r.users[i])),
    players: await t.query(api.views.getPlayers, r.as(r.users[i])),
    round: await t.query(api.views.getRoundState, r.as(r.users[i])),
    host: await t.query(api.views.getHostPresence, r.as(r.users[i])),
  });
  const check = async () => {
    advance(5);
    const before = await views(1);
    await t.mutation(api.sessions.heartbeat, r.as(r.users[2]));
    expect(await views(1)).toEqual(before);
    await t.mutation(api.sessions.heartbeat, r.as(r.users[1]));
    expect(await views(1)).toEqual(before);
    // Only the host's own heartbeat moves getHostPresence.
    await t.mutation(api.sessions.heartbeat, r.as(r.host));
    const after = await views(1);
    expect(after.host!.host_last_heartbeat).toBeGreaterThan(before.host!.host_last_heartbeat!);
    expect({ ...after, host: before.host }).toEqual(before);
  };
  await check();
  await start(t, r, ['citizen', 'mafia', 'inspector', 'citizen']);
  await check();
});

test('leaving, kicks and cancelling delete presence rows', async () => {
  const t = backend(); const r = await room(t, 4);
  const users = async () => (await presenceRows(t, r.sessionId)).map(p => p.user_id).sort();
  expect(await users()).toEqual(r.users.map(u => u.id).sort());
  await t.mutation(api.sessions.leaveSession, r.as(r.users[3]));
  await t.mutation(api.sessions.removePlayer, { ...r.as(r.host), player_record_id: r.humans[2].id });
  expect(await users()).toEqual([r.host.id, r.users[1].id].sort());
  await t.mutation(api.sessions.heartbeat, r.as(r.users[2]));
  expect(await users()).toEqual([r.host.id, r.users[1].id].sort());
  await t.mutation(api.sessions.cancelSession, r.as(r.host));
  expect(await presenceRows(t, r.sessionId)).toEqual([]);
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

test('setReady counts only in the phase it was sent from and writes only a change', async () => {
  const t = backend(); const r = await room(t, 4);
  await start(t, r, ['citizen', 'mafia', 'inspector', 'citizen']);
  const ready = async (i: number) => (await seatRow(t, r.humans[i].player_id))!.is_ready;
  // A role-reveal confirmation the client resends after a reconnect lands at night: dropped.
  expect(await ready(1)).toBe(false);
  await t.mutation(api.sessions.setReady, { ...r.as(r.users[1]), is_ready: true, phase: 'role_reveal' });
  expect(await ready(1)).toBe(false);
  await t.mutation(api.sessions.setReady, { ...r.as(r.users[1]), is_ready: true, phase: 'night' });
  expect(await ready(1)).toBe(true);
  // The same value again writes nothing.
  expect(await writesOf(t, setReady, { ...r.as(r.users[1]), is_ready: true, phase: 'night' })).toEqual([]);
  expect(await writesOf(t, setReady, { ...r.as(r.users[1]), is_ready: false })).toEqual(['session_players']);
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
    const row = await ctx.db.query('session_players').filter(q => q.eq(q.field('id'), r.humans[0].id)).unique();
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
