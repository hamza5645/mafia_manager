import { expect, test } from 'vitest';
import { api } from '../../convex/_generated/api';
import { backend, proof, room, startNight } from './helpers';

test('only the stored original host can reclaim a play-again lobby', async () => {
  const t = backend(); const r = await room(t, 5); await startNight(t, r);
  const back = (i: number) => ({ session_id: r.session.id, player_id: r.players[i].id, player_user_id: r.users[i].id, ...proof(r.users[i]) });
  await expect(t.mutation(api.sessions.returnToLobby, back(1))).rejects.toThrow();
  await t.mutation(api.sessions.updateSessionState, { ...r.hostArgs, current_phase: 'game_over', is_game_over: true });
  await t.mutation(api.sessions.returnToLobby, back(1));
  expect((await t.query(api.sessions.getSessionById, r.viewerArgs(r.users[1])))!.host_user_id).toBe(r.users[1].id);
  await expect(t.mutation(api.sessions.returnToLobby, { ...back(4), original_host_user_id: r.users[4].id })).rejects.toThrow();
  await t.mutation(api.sessions.returnToLobby, back(4));
  expect((await t.query(api.sessions.getSessionById, r.viewerArgs(r.users[1])))!.host_user_id).toBe(r.users[1].id);
  await t.mutation(api.sessions.returnToLobby, back(0));
  expect((await t.query(api.sessions.getSessionById, r.viewerArgs(r.host)))!.host_user_id).toBe(r.host.id);
  expect((await t.query(api.sessions.getAllActions, r.viewerArgs(r.host)))).toEqual([]);
});
