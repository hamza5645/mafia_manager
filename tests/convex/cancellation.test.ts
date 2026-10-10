import { expect, test } from 'vitest';
import { api } from '../../convex/_generated/api';
import { backend, guest, proof, room, startNight } from './helpers';

test('last human departure cancels a bot-only room and removes bots', async () => {
  const t = backend(); const r = await room(t, 2);
  await t.mutation(api.sessions.addPlayer, { ...r.hostArgs, player_name: 'QA bot', is_bot: true });
  await t.mutation(api.sessions.leaveSession, { session_id: r.session.id, user_id: r.host.id, ...proof(r.host) });
  expect((await t.query(api.sessions.getSessionById, r.viewerArgs(r.users[1])))!.host_user_id).toBe(r.users[1].id);
  await t.mutation(api.sessions.leaveSession, { session_id: r.session.id, user_id: r.users[1].id, ...proof(r.users[1]) });
  expect(await t.query(api.sessions.getSessionById, { session_id: r.session.id })).toMatchObject({ status: 'cancelled', current_phase: 'cancelled' });
  expect(await t.run(ctx => ctx.db.query('session_players').withIndex('by_session', q => q.eq('session_id', r.session.id)).collect())).toEqual([]);
});

test('creator can leave a room whose seat was never created', async () => {
  const t = backend(); const host = await guest(t, 'QA empty creator');
  const session = await t.mutation(api.sessions.createSession, { host_user_id: host.id, max_players: 4, bot_count: 0, ...proof(host) });
  await t.mutation(api.sessions.leaveSession, { session_id: session.id, user_id: host.id, ...proof(host) });
  expect((await t.query(api.sessions.getSessionById, { session_id: session.id }))!.status).toBe('cancelled');
});

test('host End Game removes every seat and action; members cannot cancel', async () => {
  const t = backend(); const r = await room(t, 5); const active = await startNight(t, r);
  await t.mutation(api.sessions.submitAction, { session_id: r.session.id, round_id: active.current_round_id!, action_type: 'mafia_target',
    phase_index: 0, actor_player_id: r.players[1].player_id, target_player_id: r.players[4].player_id, ...proof(r.users[1]) });
  await expect(t.mutation(api.sessions.cancelSession, { session_id: r.session.id, caller_user_id: r.users[1].id, ...proof(r.users[1]) })).rejects.toThrow();
  await t.mutation(api.sessions.cancelSession, r.hostArgs);
  expect((await t.query(api.sessions.getSessionById, { session_id: r.session.id }))!.status).toBe('cancelled');
  expect(await t.query(api.sessions.getSessionPlayers, r.viewerArgs(r.users[1]))).toEqual([]);
  expect(await t.run(ctx => ctx.db.query('game_actions').withIndex('by_session', q => q.eq('session_id', r.session.id)).collect())).toEqual([]);
});
