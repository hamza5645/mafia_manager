import { expect, test } from 'vitest';
import { api } from '../../convex/_generated/api';
import { E } from '../../convex/lib/errors';
import { sha256Hex } from '../../convex/lib/util';
import { backend, guest, proof, randomHash, room } from './helpers';

test('sha256Hex matches the FIPS 180-2 "abc" vector', async () => {
  expect(await sha256Hex('abc')).toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
});

test('guests are stored by digest only and restored by the same hash', async () => {
  const t = backend();
  const g = await guest(t, ' QA Guest ');
  expect(Object.keys(g).sort()).toEqual(['created_at', 'display_name', 'hash', 'id', 'is_anonymous', 'updated_at']);
  expect(g).toMatchObject({ display_name: 'QA Guest', is_anonymous: true });
  const row = await t.run(ctx => ctx.db.query('users').withIndex('by_app_id', q => q.eq('id', g.id)).unique());
  expect(row!.guest_secret_digest).toBe(await sha256Hex(g.hash));
  const again = await t.mutation(api.users.createOrRestoreGuest, { display_name: 'Renamed', guest_secret_hash: g.hash });
  expect(again).toMatchObject({ id: g.id, display_name: 'Renamed' });
  for (const bad of ['', 'abc', g.hash.toUpperCase(), `${g.hash}0`]) {
    await expect(t.mutation(api.users.createOrRestoreGuest, { display_name: 'QA', guest_secret_hash: bad }))
      .rejects.toThrow(E.GUEST_INVALID);
  }
  await expect(t.mutation(api.users.createOrRestoreGuest, { display_name: ' ', guest_secret_hash: randomHash() }))
    .rejects.toThrow(E.DISPLAY_NAME);
  await expect(t.mutation(api.users.createOrRestoreGuest, { display_name: 'x'.repeat(101), guest_secret_hash: randomHash() }))
    .rejects.toThrow(E.DISPLAY_NAME);
});

test('a live guest proof wins over Clerk; after the merge the account takes over', async () => {
  const t = backend(); const g = await guest(t, 'QA Pending');
  const client = t.withIdentity({ subject: crypto.randomUUID(), email: 'qa-precedence@example.com', emailVerified: true });
  const account = await client.mutation(api.users.ensureUser, {});
  expect(await client.query(api.users.getMe, {})).toMatchObject({ id: account.id });
  expect(await client.query(api.users.getMe, proof(g))).toMatchObject({ id: g.id });
  expect(await client.query(api.users.getMe, { guest_secret_hash: randomHash() })).toMatchObject({ id: account.id });
  expect(await t.query(api.users.getMe, {})).toBeNull();

  expect(await client.mutation(api.users.mergeGuestIntoAccount, proof(g)))
    .toEqual({ success: true, merged_count: 0, transferred_count: 0 });
  expect(await client.query(api.users.getMe, proof(g))).toMatchObject({ id: account.id });
  expect(await t.query(api.users.getMe, proof(g))).toBeNull();
  // Retry after a lost response finds the tombstone.
  expect(await client.mutation(api.users.mergeGuestIntoAccount, proof(g)))
    .toEqual({ success: true, merged_count: 0, transferred_count: 0 });
  await expect(client.mutation(api.users.mergeGuestIntoAccount, { guest_secret_hash: randomHash() }))
    .rejects.toThrow(E.GUEST_NOT_FOUND);
  await expect(t.mutation(api.users.mergeGuestIntoAccount, proof(g))).rejects.toThrow(E.AUTH);
});

test('ensureUser claims a legacy row only for a verified email and keeps edited names', async () => {
  const t = backend(); const id = crypto.randomUUID();
  await t.run(ctx => ctx.db.insert('users', {
    id, display_name: 'Legacy Saved Name', email: 'qa-legacy@example.com', is_anonymous: false,
    legacy_supabase_user_id: crypto.randomUUID(), created_at: 123, updated_at: 123,
  }));
  const unverified = t.withIdentity({ subject: crypto.randomUUID(), email: 'QA-Legacy@example.com', name: 'Clerk Name' });
  const fresh = await unverified.mutation(api.users.ensureUser, {});
  expect(fresh.id).not.toBe(id);
  expect(fresh.display_name).toBe('Clerk Name');
  const verified = t.withIdentity({ subject: crypto.randomUUID(), email: 'qa-legacy@example.com', emailVerified: true });
  expect(await verified.mutation(api.users.ensureUser, {}))
    .toEqual({ id, display_name: 'Legacy Saved Name', is_anonymous: false, created_at: 123, updated_at: expect.any(Number) });

  await verified.mutation(api.users.updateProfile, { display_name: 'Edited Name' });
  expect((await verified.mutation(api.users.ensureUser, {})).display_name).toBe('Edited Name');
  expect((await verified.mutation(api.users.ensureUser, { display_name: ' Explicit ' })).display_name).toBe('Explicit');
  await expect(verified.mutation(api.users.ensureUser, { display_name: 'x'.repeat(101) })).rejects.toThrow(E.DISPLAY_NAME);
  await expect(t.mutation(api.users.ensureUser, {})).rejects.toThrow(E.AUTH);
  await expect(t.mutation(api.users.updateProfile, { display_name: 'Nobody' })).rejects.toThrow(E.AUTH);
});

test('updateProfile acts on the caller only', async () => {
  const t = backend(); const g = await guest(t, 'QA Before');
  expect(await t.mutation(api.users.updateProfile, { display_name: ' QA After ', ...proof(g) }))
    .toMatchObject({ id: g.id, display_name: 'QA After', is_anonymous: true });
  await expect(t.mutation(api.users.updateProfile, { display_name: 'a\nb', ...proof(g) })).rejects.toThrow(E.DISPLAY_NAME);
});

test('health reports api_contract 4 and accepts the guest proof', async () => {
  const t = backend();
  expect(await t.query(api.health.check, {})).toMatchObject({ ok: true, backend: 'convex', version: 'convex-clerk-v4', api_contract: 4 });
  expect(await t.query(api.health.check, { guest_secret_hash: randomHash() })).toMatchObject({ api_contract: 4 });
});

test('every function rejects the removed identity and id args', async () => {
  const t = backend(); const r = await room(t); const g = r.host; const sid = r.sessionId;
  const old = { user_id: g.id, ...proof(g) };
  const cases: [any, 'query' | 'mutation', Record<string, unknown>][] = [
    [api.users.getMe, 'query', { user_id: g.id }],
    [api.users.updateProfile, 'mutation', { ...old, display_name: 'x' }],
    [api.users.mergeGuestIntoAccount, 'mutation', { guest_user_id: g.id, target_user_id: g.id, ...proof(g) }],
    [api.stats.listPlayerStats, 'query', old],
    [api.stats.upsertPlayerStat, 'mutation', { ...old, player_name: 'x', role: 'citizen', won: true, kills: 0 }],
    [api.stats.createCustomRoleConfig, 'mutation', { ...proof(g), id: crypto.randomUUID(), config_name: 'x',
      role_distribution: { mafia_count: 1, doctor_count: 0, inspector_count: 1, citizen_count: 2, total_players: 4 } }],
    [api.stats.createPlayerGroup, 'mutation', { ...proof(g), id: crypto.randomUUID(), group_name: 'x', player_names: ['a'] }],
    [api.sessions.createSession, 'mutation', { ...proof(g), host_user_id: g.id, player_name: 'x', max_players: 4, bot_count: 0 }],
    [api.sessions.joinSession, 'mutation', { ...old, room_code: r.roomCode, player_name: 'x' }],
    [api.sessions.leaveSession, 'mutation', { ...old, session_id: sid }],
    [api.sessions.cancelSession, 'mutation', { ...proof(g), session_id: sid, caller_user_id: g.id }],
    [api.sessions.setReady, 'mutation', { ...proof(g), session_id: sid, is_ready: true, player_id: r.humans[0].id }],
    [api.sessions.returnToLobby, 'mutation', { ...proof(g), session_id: sid, player_user_id: g.id }],
    [api.phases.advancePhase, 'mutation', { ...proof(g), session_id: sid, to_phase: 'night', caller_user_id: g.id }],
    [api.views.getSessionView, 'query', { ...proof(g), session_id: sid, viewer_user_id: g.id }],
    [api.views.getPlayers, 'query', { ...proof(g), session_id: sid, viewer_user_id: g.id }],
    [api.views.getRoundState, 'query', { ...proof(g), session_id: sid, viewer_user_id: g.id }],
  ];
  for (const [fn, kind, args] of cases) {
    await expect(kind === 'query' ? t.query(fn, args) : t.mutation(fn, args)).rejects.toThrow(/Validator error: Unexpected field/);
  }
});
