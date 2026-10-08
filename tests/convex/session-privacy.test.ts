import { expect, test } from 'vitest';
import { api } from '../../convex/_generated/api';
import { backend, guest, proof, room, startNight } from './helpers';

test('discovery and member snapshots never reveal private night fields', async () => {
  const t = backend();
  const r = await room(t, 5);
  await startNight(t, r);
  const night = {
    night_index: 0, is_resolved: true, mafia_target_id: r.players[4].player_id,
    doctor_protected_id: r.players[4].player_id, inspector_result: 'mafia',
    inspector_checked_id: r.players[1].player_id, mafia_player_numbers: [2],
    doctor_player_numbers: [3], inspector_player_numbers: [4],
    resulting_deaths: [], revealed_death_roles: {}, timestamp: 123,
  };
  await t.mutation(api.sessions.updateSessionState, {
    ...r.hostArgs, night_history: [night], current_phase_data: { type: 'morning', nightIndex: 0, private_target: 'secret' },
  });
  const discover = await t.query(api.sessions.getSessionByRoomCode, { room_code: r.session.room_code });
  const publicById = await t.query(api.sessions.getSessionById, { session_id: r.session.id });
  const outsider = await guest(t, 'QA outsider');
  const outsiderView = await t.query(api.sessions.getSessionById, r.viewerArgs(outsider));
  for (const row of [discover, publicById, outsiderView]) {
    expect(row!.night_history).toEqual([]);
    expect(row!.current_phase_data).toBeUndefined();
    expect(row!.current_round_id).toBeUndefined();
    expect(row!.assigned_numbers).toEqual([]);
  }
  const member = await t.query(api.sessions.getSessionById, r.viewerArgs(r.users[4]));
  expect(member!.night_history).toEqual([{
    night_index: 0, is_resolved: true, resulting_deaths: [], revealed_death_roles: {}, timestamp: 123,
  }]);
  expect(member!.current_phase_data).toEqual({ type: 'morning', nightIndex: 0 });
  const host = await t.query(api.sessions.getSessionById, r.viewerArgs(r.host));
  expect(host!.night_history).toEqual([night]);
  await expect(t.query(api.sessions.getSessionById, { ...r.viewerArgs(r.host), ...proof(outsider) })).rejects.toThrow();
  await t.mutation(api.sessions.updateSessionState, { ...r.hostArgs, is_game_over: true, current_phase: 'game_over' });
  expect((await t.query(api.sessions.getSessionById, r.viewerArgs(r.users[4])))!.night_history).toEqual([night]);
  expect((await t.query(api.sessions.getSessionById, { session_id: r.session.id }))!.night_history).toEqual([]);
});
