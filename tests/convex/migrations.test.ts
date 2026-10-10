import { afterEach, expect, test, vi } from 'vitest';
import { api, internal } from '../../convex/_generated/api';
import { sha256Hex } from '../../convex/lib/util';
import { backend, randomHash, room } from './helpers';

afterEach(() => { vi.useRealTimers(); });

async function auditAll(t: ReturnType<typeof backend>, table: 'users' | 'game_sessions') {
  let cursor: string | null = null; let remaining = 0; let scanned = 0;
  for (;;) {
    const page: any = await t.query(internal.migrations.auditLegacyFields, { table, cursor });
    remaining += page.remaining_legacy; scanned += page.scanned;
    if (page.is_done) return { remaining, scanned };
    cursor = page.continue_cursor;
  }
}

test('backfillGuestSecretDigests reschedules itself until every guest has a digest', async () => {
  vi.useFakeTimers();
  const t = backend();
  const hashes = Array.from({ length: 5 }, randomHash);
  await t.run(async ctx => {
    for (const [i, hash] of hashes.entries()) {
      await ctx.db.insert('users', { id: crypto.randomUUID(), display_name: `Legacy ${i}`, is_anonymous: true,
        guest_secret_hash: hash, created_at: 1, updated_at: 1 });
    }
    await ctx.db.insert('users', { id: crypto.randomUUID(), display_name: 'Account', is_anonymous: false, auth_subject: 'x', created_at: 1, updated_at: 1 });
  });
  expect(await auditAll(t, 'users')).toEqual({ remaining: 5, scanned: 6 });
  const first = await t.mutation(internal.migrations.backfillGuestSecretDigests, { batch_size: 2 });
  expect(first).toMatchObject({ updated: 2, is_done: false });
  await t.finishAllScheduledFunctions(vi.runAllTimers);
  expect(await auditAll(t, 'users')).toEqual({ remaining: 0, scanned: 6 });
  const rows = await t.run(ctx => ctx.db.query('users').collect());
  expect(rows.filter(row => row.guest_secret_hash !== undefined)).toEqual([]);
  for (const hash of hashes) {
    expect(await t.query(api.users.getMe, { guest_secret_hash: hash })).toMatchObject({ is_anonymous: true });
  }
  expect(rows.map(row => row.guest_secret_digest).filter(Boolean).sort())
    .toEqual((await Promise.all(hashes.map(sha256Hex))).sort());
  expect(await t.mutation(internal.migrations.backfillGuestSecretDigests, {}))
    .toEqual({ updated: 0, is_done: true, continue_cursor: expect.any(String) });
});

test('cleanupSessionFields unsets phase_sequence and night_resolution', async () => {
  vi.useFakeTimers();
  const t = backend();
  for (let i = 0; i < 3; i++) await room(t, 1);
  await t.run(async ctx => {
    const sessions = await ctx.db.query('game_sessions').collect();
    await ctx.db.patch(sessions[0]._id, { phase_sequence: 7 });
    await ctx.db.patch(sessions[2]._id, { phase_sequence: 2, night_resolution: { round_id: 'r', fingerprint: 'f', next_phase: 'morning' } });
  });
  expect(await auditAll(t, 'game_sessions')).toEqual({ remaining: 2, scanned: 3 });
  expect(await t.mutation(internal.migrations.cleanupSessionFields, { batch_size: 1 })).toMatchObject({ updated: 1, is_done: false });
  await t.finishAllScheduledFunctions(vi.runAllTimers);
  expect(await auditAll(t, 'game_sessions')).toEqual({ remaining: 0, scanned: 3 });
  expect((await t.mutation(internal.migrations.cleanupSessionFields, {})).updated).toBe(0);
});
