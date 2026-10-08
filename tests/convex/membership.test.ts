import { expect, test } from 'vitest';
import { api } from '../../convex/_generated/api';
import { backend, guest, proof, room } from './helpers';

test('kicking emits a safe empty roster for the proven former member', async () => {
  const t = backend();
  const r = await room(t);
  const user = r.users[1];
  expect(await t.query(api.sessions.getSessionPlayers, r.viewerArgs(user))).toHaveLength(4);
  await t.mutation(api.sessions.removePlayer, { caller_user_id: r.host.id, ...proof(r.host), player_id: r.players[1].id });
  expect(await t.query(api.sessions.getSessionPlayers, r.viewerArgs(user))).toEqual([]);
  expect(await t.query(api.sessions.getSessionPlayers, r.viewerArgs(r.host))).toHaveLength(3);
  await expect(t.query(api.sessions.getSessionPlayers, { ...r.viewerArgs(user), ...proof(r.host) })).rejects.toThrow();
  const outsider = await guest(t, 'QA outsider');
  expect(await t.query(api.sessions.getSessionPlayers, r.viewerArgs(outsider))).toEqual([]);
  expect(await t.query(api.sessions.getSessionPlayers, { session_id: r.session.id })).toEqual([]);
});
