import { expect, test } from 'vitest';
import { api } from '../../convex/_generated/api';
import { backend, room, startNight } from './helpers';

test('atomic night is idempotent and stale requests cannot rewind or add deaths', async () => {
  const t = backend(); const r = await room(t, 5); const active = await startNight(t, r);
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
