import { afterAll, expect, test, vi } from 'vitest';
import { api } from '../../convex/_generated/api';
import { Backend, Guest, NightType, Room, act, advance, backend, guest, proof, room, round, start } from './helpers';

// Contract fixtures for the Swift decoders (PA-11): the exact JSON the real
// functions return in one scripted game. Ids become fixed UUIDs and the clock
// is fake, so timestamps are fixed Apple-epoch seconds and regenerating gives
// identical files. A normal run fails on any drift; regenerate on purpose with
// `npx vitest run tests/convex/contract.test.ts -u`.
// Files are copied flat into the Swift test bundle, so names must stay unique.

afterAll(() => { vi.useRealTimers(); });

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const KIND = { user: 1, session: 2, seat: 3, player: 4, round: 5, other: 15 } as const;
const fixed = (kind: number, n: number) => `${kind.toString(16).padStart(8, '0')}-0000-4000-8000-${n.toString(16).padStart(12, '0')}`;

// Every real id maps to a fixed one; ids not named up front (action rows) are
// numbered in the order they first appear, which the script makes stable.
const aliases = new Map<string, string>();
const counters = new Map<number, number>();
const name = (id: string, kind: number) => {
  if (aliases.has(id)) return;
  const n = (counters.get(kind) ?? 0) + 1;
  counters.set(kind, n);
  aliases.set(id, fixed(kind, n));
};
let roomCode = '';

function normalize(value: unknown): unknown {
  if (typeof value === 'string') {
    if (UUID.test(value)) { name(value, KIND.other); return aliases.get(value); }
    return value === roomCode ? '123456' : value;
  }
  if (Array.isArray(value)) return value.map(normalize);
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [normalize(k) as string, normalize(v)]));
  }
  return value;
}

const fixture = async (file: string, value: unknown) =>
  await expect(`${JSON.stringify(normalize(value), null, 2)}\n`).toMatchFileSnapshot(`../fixtures/contract/contract_${file}.json`);

// humans: host citizen, A mafia, B doctor, C citizen; bots: mafia, inspector.
async function game() {
  vi.useFakeTimers({ toFake: ['Date'] });
  // A fractional second, as real timestamps have.
  vi.setSystemTime(new Date('2026-10-11T12:00:00.500Z'));
  const t = backend();
  const r = await room(t, 4, 2);
  const outsider = await guest(t, 'QA Outsider');
  roomCode = r.roomCode;
  for (const user of [...r.users, outsider]) name(user.id, KIND.user);
  name(r.sessionId, KIND.session);
  for (const seat of [...r.humans, ...r.bots]) { name(seat.id, KIND.seat); name(seat.player_id, KIND.player); }
  advance(60);
  await start(t, r, ['citizen', 'mafia', 'doctor', 'citizen'], ['mafia', 'inspector']);
  name((await round(t, r)).round_id!, KIND.round);
  return { t, r, outsider };
}

const view = (t: Backend, r: Room, user: Guest, fn: any) => t.query(fn, r.as(user));

test('contract fixtures match what the backend returns', async () => {
  const { t, r, outsider } = await game();
  const [host, A, B, C] = r.users;
  const [, hA, hB, hC] = r.humans;
  const [botMafia, botInspector] = r.bots;
  type BotAction = { actor_player_id: string; action_type: NightType | 'vote'; target_player_id?: string };
  const bots = (round_id: string, phase_index: number, actions: BotAction[]) =>
    t.mutation(api.play.submitBotActions, { ...r.as(host), round_id, phase_index, actions });

  // Night 0: A drafts and picks C, B protects the host, the bots act in one batch.
  advance(5);
  await t.mutation(api.play.setTentativeSelection, { ...r.as(A), actor_player_id: hA.player_id, action_type: 'mafia_target',
    phase_index: 0, target_player_id: hC.player_id });
  advance(5); await act(t, r, hA, 'mafia_target', hC);
  advance(5); await act(t, r, hB, 'doctor_protect', r.humans[0]);
  advance(5);
  const night0 = (await round(t, r)).round_id!;
  await fixture('submitBotActions_host', await bots(night0, 0, [
    { actor_player_id: botMafia.player_id, action_type: 'mafia_target', target_player_id: hC.player_id },
    { actor_player_id: botInspector.player_id, action_type: 'inspector_check', target_player_id: hA.player_id },
    { actor_player_id: botMafia.player_id, action_type: 'mafia_target', target_player_id: hA.player_id },
  ]));
  // A and B are online; C has been silent since joining, so the host's sweep marks C offline.
  advance(5);
  await t.mutation(api.sessions.heartbeat, r.as(A));
  await t.mutation(api.sessions.heartbeat, r.as(B));
  await t.mutation(api.sessions.heartbeat, r.as(host));
  advance(3);
  await fixture('getRoundState_host', await view(t, r, host, api.views.getRoundState));
  await fixture('getRoundState_citizen', await view(t, r, C, api.views.getRoundState));
  await fixture('getPlayers_host', await view(t, r, host, api.views.getPlayers));
  await fixture('getPlayers_mafia', await view(t, r, A, api.views.getPlayers));
  await fixture('getPlayers_citizen', await view(t, r, C, api.views.getPlayers));
  await fixture('getHostPresence_member', await view(t, r, A, api.views.getHostPresence));

  advance(5);
  await fixture('finishNight_host', await t.mutation(api.night.finishNight, { ...r.as(host), round_id: night0 }));

  // Day 0: A is voted out.
  advance(5);
  await t.mutation(api.phases.advancePhase, { ...r.as(host), to_phase: 'death_reveal' });
  await t.mutation(api.phases.advancePhase, { ...r.as(host), to_phase: 'voting' });
  const day0 = (await round(t, r)).round_id!;
  name(day0, KIND.round);
  advance(5); await act(t, r, r.humans[0], 'vote', hA);
  advance(5); await act(t, r, hB, 'vote', hA);
  await fixture('getRoundState_voter', await view(t, r, B, api.views.getRoundState));
  advance(5); await act(t, r, hA, 'vote', r.humans[0]);
  advance(5);
  await bots(day0, 0, [
    { actor_player_id: botInspector.player_id, action_type: 'vote', target_player_id: hA.player_id },
    { actor_player_id: botMafia.player_id, action_type: 'vote', target_player_id: r.humans[0].player_id },
  ]);
  advance(5);
  expect(await t.mutation(api.voting.closeVoting, { ...r.as(host), round_id: day0 }))
    .toEqual({ day_index: 0, eliminated_player_id: hA.player_id });
  await t.mutation(api.phases.advancePhase, { ...r.as(host), to_phase: 'vote_death_reveal' });
  advance(5);
  expect(await t.mutation(api.voting.resolveVoteAtomic, { ...r.as(host), round_id: day0 }))
    .toMatchObject({ next_phase: 'night', winner: null });
  name((await round(t, r)).round_id!, KIND.round);

  // Night 1, with one night and one day in the history.
  advance(5);
  await fixture('getSessionView_host', await view(t, r, host, api.views.getSessionView));
  await fixture('getSessionView_member', await view(t, r, B, api.views.getSessionView));
  await fixture('getSessionView_outsider', await view(t, r, outsider, api.views.getSessionView));

  await fixture('recordGame_guest', await t.mutation(api.stats.recordGame, { ...proof(host), game_id: crypto.randomUUID(), results: [
    { player_name: 'Ann', role: 'mafia', won: true, kills: 2 },
    { player_name: '', role: 'citizen', won: false, kills: 0 },
  ] }));
  await fixture('health_check', await t.query(api.health.check, {}));

  // Entering: the host's new seat, and C coming back to the running game (PA-09).
  await fixture('createSession_host', r.entered);
  await fixture('joinSession_rejoin', await t.mutation(api.sessions.joinSession, {
    ...proof(C), room_code: r.roomCode, player_name: C.display_name }));
});

test('the views reject a projection that drifts from their returns validators', async () => {
  const { t, r } = await game();
  const patchSession = (patch: object) => t.run(async ctx => {
    const s = await ctx.db.query('game_sessions').withIndex('by_app_id', q => q.eq('id', r.sessionId)).unique();
    await ctx.db.patch(s!._id, patch);
  });
  await act(t, r, r.humans[2], 'doctor_protect', r.humans[0]);
  await t.run(async ctx => {
    const row = (await ctx.db.query('game_actions').collect())[0];
    await ctx.db.patch(row._id, { action_data: { inspector_result: 'maybe' } });
  });
  await expect(view(t, r, r.host, api.views.getRoundState)).rejects.toThrow(/Validator error/);
  // Unknown keys in stored rows are dropped, not passed through.
  await patchSession({ current_phase_data: { type: 'night', nightIndex: 0, private_target: 'secret' },
    night_history: [{ night_index: 0, is_resolved: true, resulting_deaths: [], revealed_death_roles: {}, timestamp: 1, extra: 1 }] });
  const host = (await view(t, r, r.host, api.views.getSessionView))!;
  expect(host.session.current_phase_data).toEqual({ type: 'night', nightIndex: 0 });
  expect(host.session.night_history).toEqual([{ night_index: 0, is_resolved: true, resulting_deaths: [], revealed_death_roles: {}, timestamp: 1 }]);
  // A known key with the wrong type is drift.
  await patchSession({ current_phase_data: { type: 'night', nightIndex: 'zero' } });
  await expect(view(t, r, r.host, api.views.getSessionView)).rejects.toThrow(/Validator error/);
});
