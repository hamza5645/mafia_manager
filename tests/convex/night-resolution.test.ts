import { expect, test } from 'vitest';
import { api } from '../../convex/_generated/api';
import { backend, proof, room, startNight } from './helpers';

async function submitNightActions(t: ReturnType<typeof backend>, r: Awaited<ReturnType<typeof room>>, round: string) {
  for (const [actor, type, target] of [[1, 'mafia_target', 4], [2, 'doctor_protect', 4], [3, 'inspector_check', 1]] as const) {
    await t.mutation(api.sessions.submitAction, { session_id: r.session.id, round_id: round,
      actor_player_id: r.players[actor].player_id, target_player_id: r.players[target].player_id,
      action_type: type, phase_index: 0, ...proof(r.users[actor]) });
  }
}

test('atomic night is idempotent and stale requests cannot rewind or add deaths', async () => {
  const t = backend(); const r = await room(t, 5); const active = await startNight(t, r);
  await submitNightActions(t, r, active.current_round_id!);
  const request = { ...r.hostArgs, expected_round_id: active.current_round_id!,
    night_record: { night_index: 0, is_resolved: true, resulting_deaths: [], timestamp: 123 },
    eliminated_player_ids: [], next_phase: 'morning', next_phase_data: { type: 'morning', nightIndex: 0 } };
  expect(await t.mutation(api.sessions.resolveNightAtomic, request)).toBe(true);
  const first = await t.query(api.sessions.getSessionById, r.viewerArgs(r.host));
  expect(await t.mutation(api.sessions.resolveNightAtomic, request)).toBe(true);
  expect(await t.query(api.sessions.getSessionById, r.viewerArgs(r.host))).toEqual(first);
  await expect(t.mutation(api.sessions.resolveNightAtomic, { ...request, eliminated_player_ids: [r.players[4].player_id] })).rejects.toThrow();
  expect((await t.query(api.sessions.getSessionPlayers, r.viewerArgs(r.host))).every(p => p.is_alive)).toBe(true);
  await t.mutation(api.sessions.updateSessionPhase, { ...r.hostArgs, current_phase: 'voting', current_phase_data: { type: 'voting', dayIndex: 0 } });
  await expect(t.mutation(api.sessions.resolveNightAtomic, request)).rejects.toThrow();
  expect((await t.query(api.sessions.getSessionById, r.viewerArgs(r.host)))!.current_phase).toBe('voting');
  await t.mutation(api.sessions.updateSessionPhase, { ...r.hostArgs, current_phase: 'night', current_phase_data: { type: 'night', nightIndex: 0 } });
  await expect(t.mutation(api.sessions.resolveNightAtomic, request)).rejects.toThrow();
});

test('night resolution requires expected round, active index, valid targets and final state', async () => {
  const t = backend(); const r = await room(t, 5); const active = await startNight(t, r);
  await submitNightActions(t, r, active.current_round_id!);
  const request = { ...r.hostArgs, expected_round_id: active.current_round_id!,
    night_record: { night_index: 0, is_resolved: true, resulting_deaths: [], timestamp: 123 },
    eliminated_player_ids: [], next_phase: 'morning', next_phase_data: { type: 'morning', nightIndex: 0 } };
  for (const override of [
    { expected_round_id: crypto.randomUUID() },
    { night_record: { ...request.night_record, night_index: 1 } },
    { night_record: { ...request.night_record, is_resolved: false } },
    { eliminated_player_ids: [crypto.randomUUID()] },
    { next_phase: 'voting' },
  ]) await expect(t.mutation(api.sessions.resolveNightAtomic, { ...request, ...override })).rejects.toThrow();
  const final = { ...request, next_phase: 'game_over', next_phase_data: { type: 'gameOver', winner: 'mafia' },
    is_game_over: true, winner: 'mafia' as const };
  expect(await t.mutation(api.sessions.resolveNightAtomic, final)).toBe(true);
  expect(await t.mutation(api.sessions.resolveNightAtomic, final)).toBe(true);
  expect((await t.query(api.sessions.getSessionById, r.viewerArgs(r.host)))!.status).toBe('completed');
});

test('ready flags cannot substitute for current-round night actions', async () => {
  const t = backend(); const r = await room(t, 5); const active = await startNight(t, r);
  for (let i = 0; i < r.players.length; i++) await t.mutation(api.sessions.updatePlayerReady, {
    player_id: r.players[i].id, is_ready: true, ...proof(r.users[i]) });
  const request = { ...r.hostArgs, expected_round_id: active.current_round_id!,
    night_record: { night_index: 0, is_resolved: true, resulting_deaths: [] },
    eliminated_player_ids: [], next_phase: 'morning', next_phase_data: { type: 'morning', nightIndex: 0 } };
  await expect(t.mutation(api.sessions.resolveNightAtomic, request)).rejects.toThrow('Waiting for all night actions');
  await submitNightActions(t, r, active.current_round_id!);
  expect(await t.mutation(api.sessions.resolveNightAtomic, request)).toBe(true);
});

test('new night and voting rounds atomically clear human readiness', async () => {
  const t = backend(); const r = await room(t, 5);
  for (const phase of ['night', 'voting']) {
    for (let i = 0; i < r.players.length; i++) await t.mutation(api.sessions.updatePlayerReady, {
      player_id: r.players[i].id, is_ready: true, ...proof(r.users[i]) });
    await t.mutation(api.sessions.updateSessionPhase, { ...r.hostArgs, current_phase: phase,
      current_phase_data: phase === 'night' ? { type: 'night', nightIndex: 0 } : { type: 'voting', dayIndex: 0 } });
    expect((await t.query(api.sessions.getSessionPlayers, r.viewerArgs(r.host))).every(p => !p.is_ready)).toBe(true);
  }
});
