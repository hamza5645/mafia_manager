import { expect, test } from 'vitest';
import { api } from '../../convex/_generated/api';
import { backend, proof, room, startNight } from './helpers';

test('rematch cannot alter an active game, but a completed game resets safely', async () => {
  const t = backend(); const r = await room(t, 5); const active = await startNight(t, r);
  await t.mutation(api.sessions.submitAction, {
    session_id: r.session.id, round_id: active.current_round_id!, phase_index: 0,
    action_type: 'mafia_target', actor_player_id: r.players[1].player_id,
    target_player_id: r.players[4].player_id, ...proof(r.users[1]),
  });
  const before = await t.query(api.sessions.getSessionById, r.viewerArgs(r.host));
  const players = await t.query(api.sessions.getSessionPlayers, r.viewerArgs(r.host));
  await expect(t.mutation(api.sessions.executeRematch, r.hostArgs)).rejects.toThrow();
  expect(await t.query(api.sessions.getSessionById, r.viewerArgs(r.host))).toEqual(before);
  expect(await t.query(api.sessions.getSessionPlayers, r.viewerArgs(r.host))).toEqual(players);
  expect(await t.query(api.sessions.getAllActions, r.viewerArgs(r.host))).toHaveLength(1);
  await t.mutation(api.sessions.updateSessionState, { ...r.hostArgs, current_phase: 'game_over', current_phase_data: { type: 'gameOver', winner: 'citizen' }, is_game_over: true });
  for (let i = 0; i < r.players.length; i++) await t.mutation(api.sessions.updatePlayerReady, {
    player_id: r.players[i].id, is_ready: true, ...proof(r.users[i]),
  });
  expect((await t.mutation(api.sessions.executeRematch, r.hostArgs)).success).toBe(true);
  const lobby = await t.query(api.sessions.getSessionById, r.viewerArgs(r.host));
  expect(lobby).toMatchObject({ status: 'waiting', current_phase: 'lobby', is_game_over: false, night_history: [], assigned_numbers: [] });
  expect(await t.query(api.sessions.getAllActions, r.viewerArgs(r.host))).toEqual([]);
  const resetPlayers = await t.query(api.sessions.getSessionPlayers, r.viewerArgs(r.host));
  expect(resetPlayers).toHaveLength(5);
  expect(resetPlayers.every(p => p.is_alive && !p.is_ready && !p.role && !p.player_number)).toBe(true);
  await expect(t.mutation(api.sessions.executeRematch, r.hostArgs)).rejects.toThrow();
});
