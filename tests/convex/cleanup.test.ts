import { afterEach, expect, test, vi } from 'vitest';
import { api, internal } from '../../convex/_generated/api';
import { finishGame } from '../../convex/lib/transitions';
import { nowAppleEpochSeconds } from '../../convex/lib/util';
import { Backend, Room, act, advance, backend, room, start } from './helpers';

afterEach(() => { vi.useRealTimers(); });

const HOUR = 3600;
const DAY = 24 * HOUR;

// The cron's job, run to the end (every scheduled continuation page).
async function sweep(t: Backend) {
  await t.mutation(internal.cleanup.sweep, {});
  await t.finishAllScheduledFunctions(vi.runAllTimers);
}

const sessionDoc = (t: Backend, sessionId: string) =>
  t.run(ctx => ctx.db.query('game_sessions').withIndex('by_app_id', q => q.eq('id', sessionId)).unique());

// How many rows of each kind the room still owns.
const owned = (t: Backend, sessionId: string) => t.run(async ctx => ({
  seats: (await ctx.db.query('session_players').withIndex('by_session', q => q.eq('session_id', sessionId)).collect()).length,
  presence: (await ctx.db.query('session_presence').withIndex('by_session', q => q.eq('session_id', sessionId)).collect()).length,
  actions: (await ctx.db.query('game_actions').withIndex('by_unique_action', q => q.eq('session_id', sessionId)).collect()).length,
}));

const patchRoom = (t: Backend, r: Room, patch: object) => t.run(async ctx => {
  const s = await ctx.db.query('game_sessions').withIndex('by_app_id', q => q.eq('id', r.sessionId)).unique();
  await ctx.db.patch(s!._id, patch);
});

// A room from before session_presence: no presence rows; the seats may carry
// their own last heartbeat.
const withoutPresence = (t: Backend, r: Room, seatHeartbeat?: number) => t.run(async ctx => {
  for (const row of await ctx.db.query('session_presence').withIndex('by_session', q => q.eq('session_id', r.sessionId)).collect()) {
    await ctx.db.delete(row._id);
  }
  if (seatHeartbeat === undefined) return;
  for (const seat of await ctx.db.query('session_players').withIndex('by_session', q => q.eq('session_id', r.sessionId)).collect()) {
    await ctx.db.patch(seat._id, { last_heartbeat: seatHeartbeat });
  }
});

test('the sweep cancels abandoned rooms by presence and ages out finished ones', async () => {
  vi.useFakeTimers();
  const t = backend();
  const abandoned = await room(t, 2);
  const playing = await room(t, 4);
  await start(t, playing, ['citizen', 'mafia', 'inspector', 'citizen']);
  await act(t, playing, playing.humans[1], 'mafia_target', playing.humans[3]);
  const quietHost = await room(t, 3);
  const legacyRecent = await room(t, 2);
  const legacyStale = await room(t, 2);
  const [doneYesterday, doneToday, doneLastMonth, cancelledLastMonth, cancelledRecently] =
    [await room(t, 2), await room(t, 2), await room(t, 2), await room(t, 2), await room(t, 2)];
  // More abandoned lobbies than one page holds, with no seats at all.
  const strays = await t.run(async ctx => {
    const ids: string[] = [];
    for (let i = 0; i < 25; i++) {
      const id = crypto.randomUUID(); ids.push(id);
      await ctx.db.insert('game_sessions', { id, room_code: String(200000 + i), host_user_id: crypto.randomUUID(), status: 'waiting',
        created_at: nowAppleEpochSeconds(), max_players: 19, bot_count: 0, current_phase: 'lobby', day_index: 0,
        is_game_over: false, assigned_numbers: [], night_history: [], day_history: [], updated_at: nowAppleEpochSeconds() });
    }
    return ids;
  });

  // Seven hours later only some players are still around.
  advance(7 * HOUR);
  const now = nowAppleEpochSeconds();
  // A recent session write does not keep an abandoned room alive...
  await patchRoom(t, abandoned, { updated_at: now });
  // ...and an old one does not end a room whose players are still here.
  await t.mutation(api.sessions.heartbeat, quietHost.as(quietHost.users[2]));
  const fresh = await room(t, 2);
  await withoutPresence(t, legacyRecent, now - HOUR);
  await withoutPresence(t, legacyStale);
  // Finished before next_cleanup_at existed: these rooms have no date yet.
  const finish = (r: Room, hoursAgo: number) => patchRoom(t, r, { status: 'completed', current_phase: 'game_over',
    is_game_over: true, completed_at: now - hoursAgo * HOUR });
  await finish(doneYesterday, 25);
  await finish(doneToday, 1);
  await finish(doneLastMonth, 31 * 24);
  for (const [r, daysAgo] of [[cancelledLastMonth, 31], [cancelledRecently, 29]] as const) {
    await t.mutation(api.sessions.cancelSession, r.as(r.host));
    // As if it had been cancelled that long ago.
    await patchRoom(t, r, { completed_at: now - daysAgo * DAY, next_cleanup_at: now - daysAgo * DAY + 30 * DAY });
  }

  await sweep(t);

  for (const r of [abandoned, playing, legacyStale]) {
    expect(await sessionDoc(t, r.sessionId)).toMatchObject({ status: 'cancelled', current_phase: 'cancelled' });
    expect(await owned(t, r.sessionId)).toEqual({ seats: 0, presence: 0, actions: 0 });
  }
  for (const id of strays) expect((await sessionDoc(t, id))!.status).toBe('cancelled');
  for (const [r, seats] of [[quietHost, 3], [fresh, 2], [legacyRecent, 2]] as const) {
    expect((await sessionDoc(t, r.sessionId))!.status).toBe('waiting');
    expect((await owned(t, r.sessionId)).seats).toBe(seats);
  }
  // A finished game keeps its seats for a day, then only the session remains.
  expect(await owned(t, doneToday.sessionId)).toEqual({ seats: 2, presence: 2, actions: 0 });
  expect((await sessionDoc(t, doneYesterday.sessionId))!.status).toBe('completed');
  expect(await owned(t, doneYesterday.sessionId)).toEqual({ seats: 0, presence: 0, actions: 0 });
  // After 30 days finished and cancelled rooms are gone.
  for (const r of [doneLastMonth, cancelledLastMonth]) expect(await sessionDoc(t, r.sessionId)).toBeNull();
  expect((await sessionDoc(t, cancelledRecently.sessionId))!.status).toBe('cancelled');

  // A second sweep changes nothing.
  const everything = () => t.run(async ctx => [
    await ctx.db.query('game_sessions').collect(), await ctx.db.query('session_players').collect(),
    await ctx.db.query('session_presence').collect(), await ctx.db.query('game_actions').collect(),
  ]);
  const settled = await everything();
  await sweep(t);
  expect(await everything()).toEqual(settled);
});

test('a lobby is cancelled 6 hours after its last heartbeat, not before', async () => {
  vi.useFakeTimers();
  const t = backend(); const r = await room(t, 3);
  advance(5 * HOUR);
  await t.mutation(api.sessions.heartbeat, r.as(r.users[1]));
  advance(5 * HOUR);
  await sweep(t);
  expect((await sessionDoc(t, r.sessionId))!.status).toBe('waiting');
  advance(2 * HOUR);
  await sweep(t);
  expect((await sessionDoc(t, r.sessionId))!.status).toBe('cancelled');
});

test('an ended room is listed only when its next cleanup is due', async () => {
  vi.useFakeTimers();
  const t = backend();
  const [finished, cancelled, again] = [await room(t, 2), await room(t, 2), await room(t, 2)];
  const finishNow = (r: Room) => t.run(async ctx => {
    const session = await ctx.db.query('game_sessions').withIndex('by_app_id', q => q.eq('id', r.sessionId)).unique();
    const seats = await ctx.db.query('session_players').withIndex('by_session', q => q.eq('session_id', r.sessionId)).collect();
    await finishGame(ctx, session!, seats, 'mafia');
  });
  await finishNow(finished); await finishNow(again);
  await t.mutation(api.sessions.cancelSession, cancelled.as(cancelled.host));
  // Play Again takes the room off the calendar.
  await t.mutation(api.sessions.returnToLobby, again.as(again.host));
  expect(await sessionDoc(t, again.sessionId)).not.toHaveProperty('next_cleanup_at');
  // How many ended rooms one sweep reads; each one listed is cleaned.
  const listed = async () => {
    let count = 0;
    for (const status of ['completed', 'cancelled'] as const) {
      for (const undated of [false, true]) {
        count += await t.mutation(internal.cleanup.sweepRooms, { status, undated, now: nowAppleEpochSeconds(), cursor: null });
      }
    }
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    return count;
  };
  expect(await listed()).toBe(0);
  // A day later the finished game is due once: its seats go and its date moves to day 30.
  advance(25 * HOUR);
  expect(await listed()).toBe(1);
  expect(await owned(t, finished.sessionId)).toEqual({ seats: 0, presence: 0, actions: 0 });
  expect((await sessionDoc(t, finished.sessionId))!.status).toBe('completed');
  expect(await listed()).toBe(0);
  advance(28 * DAY);
  expect(await listed()).toBe(0);
  // Day 30: both ended rooms are deleted.
  advance(DAY);
  expect(await listed()).toBe(2);
  for (const r of [finished, cancelled]) expect(await sessionDoc(t, r.sessionId)).toBeNull();
  expect((await sessionDoc(t, again.sessionId))!.status).toBe('waiting');
});

test('each listed room is cleaned on its own: one that vanished is skipped, the rest still go', async () => {
  vi.useFakeTimers();
  const t = backend();
  const [first, second] = [await room(t, 2), await room(t, 2)];
  for (const r of [first, second]) await t.mutation(api.sessions.cancelSession, r.as(r.host));
  advance(31 * DAY);
  // The room listed first is gone by the time its own transaction runs.
  await t.mutation(internal.cleanup.sweepRooms, { status: 'cancelled', now: nowAppleEpochSeconds(), cursor: null });
  const gone = (await sessionDoc(t, first.sessionId))!._id;
  await t.run(ctx => ctx.db.delete(gone));
  await t.finishAllScheduledFunctions(vi.runAllTimers);
  expect(await sessionDoc(t, second.sessionId)).toBeNull();
});
