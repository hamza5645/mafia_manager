import { expect, test } from 'vitest';
import { api } from '../../convex/_generated/api';
import { backend, proof, room, startNight } from './helpers';

test('proven guest viewer survives Clerk creation and old subscription args survive merge', async () => {
  const t = backend(); const r = await room(t, 5); await startNight(t, r);
  const client = t.withIdentity({ subject: crypto.randomUUID(), email: 'qa-upgrade@example.com' });
  const account = await client.mutation(api.users.ensureUser, {});
  const oldArgs = r.viewerArgs(r.host);
  expect(await client.query(api.sessions.getSessionPlayers, oldArgs)).toHaveLength(5);
  expect((await client.query(api.sessions.getSessionById, oldArgs))!.current_phase_data).toMatchObject({ type: 'night', nightIndex: 0 });
  expect(await client.query(api.sessions.getAllActions, oldArgs)).toEqual([]);
  expect(await client.query(api.sessions.listTentativeSelectionsForSession, oldArgs)).toEqual([]);
  await client.mutation(api.users.mergeGuestIntoAccount, { guest_user_id: r.host.id, target_user_id: account.id, ...proof(r.host) });
  const players = await client.query(api.sessions.getSessionPlayers, oldArgs);
  expect(players).toHaveLength(5);
  expect(players.find(p => p.id === r.players[0].id)!.user_id).toBe(account.id);
  expect(await client.query(api.sessions.getAllActions, oldArgs)).toEqual([]);
  expect(await client.query(api.sessions.listTentativeSelectionsForSession, oldArgs)).toEqual([]);
});

test('a Clerk identity cannot acquire a guest viewer by supplying a guessed ID/proof', async () => {
  const t = backend(); const r = await room(t, 5); await startNight(t, r);
  const subject = crypto.randomUUID();
  await t.run(async ctx => {
    const user = await ctx.db.query('users').withIndex('by_app_id', q => q.eq('id', r.users[4].id)).unique();
    await ctx.db.patch(user!._id, { auth_subject: subject, is_anonymous: false });
  });
  const client = t.withIdentity({ subject });
  const spoof = { ...r.viewerArgs(r.host), guest_secret_hash: 'wrong' };
  const players = await client.query(api.sessions.getSessionPlayers, spoof);
  expect(players.filter(p => p.role)).toHaveLength(1);
  expect(players.find(p => p.role)!.user_id).toBe(r.users[4].id);
  expect(await client.query(api.sessions.getAllActions, spoof)).toEqual([]);
  // Mutation caller assertions remain strict; read handoff cannot transfer host.
  await expect(client.mutation(api.sessions.updateSessionStatus, { ...r.hostArgs, guest_secret_hash: 'wrong', status: 'completed' })).rejects.toThrow();
});
