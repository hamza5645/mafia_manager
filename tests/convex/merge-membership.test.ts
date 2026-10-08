import { expect, test } from 'vitest';
import { api } from '../../convex/_generated/api';
import { backend, proof, room, startNight } from './helpers';

test('guest upgrade transfers active seat, host, and original ownership without changing gameplay', async () => {
  const t = backend(); const r = await room(t, 5); const active = await startNight(t, r);
  const accountClient = t.withIdentity({ subject: crypto.randomUUID(), email: 'qa-room@example.com' });
  const account = await accountClient.mutation(api.users.ensureUser, {});
  await accountClient.mutation(api.users.mergeGuestIntoAccount, { guest_user_id: r.host.id, target_user_id: account.id, ...proof(r.host) });
  const args = { session_id: r.session.id, viewer_user_id: account.id };
  const after = await accountClient.query(api.sessions.getSessionById, args);
  expect(after).toMatchObject({ host_user_id: account.id, original_host_user_id: account.id,
    current_phase: 'night', current_round_id: active.current_round_id });
  const seat = (await accountClient.query(api.sessions.getSessionPlayers, args)).find(p => p.id === r.players[0].id)!;
  expect(seat).toMatchObject({ id: r.players[0].id, player_id: r.players[0].player_id, user_id: account.id, role: 'citizen' });
  await accountClient.mutation(api.sessions.updateSessionPhase, { session_id: r.session.id, caller_user_id: account.id,
    current_phase: 'voting', current_phase_data: { type: 'voting', dayIndex: 0 } });
  const voting = await accountClient.query(api.sessions.getSessionById, args);
  await accountClient.mutation(api.sessions.submitAction, { session_id: r.session.id, round_id: voting!.current_round_id!,
    action_type: 'vote', phase_index: 0, actor_player_id: seat.player_id, target_player_id: r.players[1].player_id });
  await expect(t.query(api.users.getUserProfile, { user_id: r.host.id, ...proof(r.host) })).rejects.toThrow();
  await accountClient.mutation(api.sessions.leaveSession, { session_id: r.session.id, user_id: account.id });
  expect(await t.run(ctx => ctx.db.query('session_players').withIndex('by_user', q => q.eq('user_id', r.host.id)).collect())).toEqual([]);
  expect((await t.query(api.sessions.getSessionPlayers, r.viewerArgs(r.users[1])))).toHaveLength(4);
});

test('an account already seated in the room cannot create duplicate membership by merging', async () => {
  const t = backend(); const r = await room(t);
  const accountClient = t.withIdentity({ subject: crypto.randomUUID(), email: 'qa-seated@example.com' });
  const account = await accountClient.mutation(api.users.ensureUser, {});
  await accountClient.mutation(api.sessions.joinSession, { room_code: r.session.room_code, user_id: account.id, player_name: 'QA Account' });
  await expect(accountClient.mutation(api.users.mergeGuestIntoAccount, {
    guest_user_id: r.host.id, target_user_id: account.id, ...proof(r.host),
  })).rejects.toThrow('existing seat');
  expect((await t.query(api.users.getUserProfile, { user_id: r.host.id, ...proof(r.host) }))!.is_anonymous).toBe(true);
  expect((await t.query(api.sessions.getSessionById, r.viewerArgs(r.host)))!.host_user_id).toBe(r.host.id);
});
