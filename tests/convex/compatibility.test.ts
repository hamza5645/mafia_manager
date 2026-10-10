import { expect, test } from 'vitest';
import { api } from '../../convex/_generated/api';
import { backend, guest, proof } from './helpers';

test('deployment advertises guest proof API and rejects unproven profile access', async () => {
  const t = backend();
  expect(await t.query(api.health.check, {})).toMatchObject({ ok: true, api_contract: 3 });
  const user = await guest(t, 'QA compatibility');
  await expect(t.query(api.users.getUserProfile, { user_id: user.id })).rejects.toThrow();
  expect(await t.query(api.users.getUserProfile, { user_id: user.id, ...proof(user) })).toMatchObject({ id: user.id });
  expect(await t.mutation(api.sessions.createSession, {
    host_user_id: user.id, max_players: 4, bot_count: 0, ...proof(user),
  })).toMatchObject({ host_user_id: user.id });
});
