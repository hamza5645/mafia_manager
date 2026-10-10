import { expect, test } from 'vitest';
import { api } from '../../convex/_generated/api';
import { backend } from './helpers';

test('identity refresh preserves edited names and explicit changes still work', async () => {
  const t = backend(); const subject = crypto.randomUUID();
  const accountClient = t.withIdentity({ subject, email: 'qa-name@example.com', name: 'Clerk Name' });
  const account = await accountClient.mutation(api.users.ensureUser, {});
  expect(account.display_name).toBe('Clerk Name');
  await accountClient.mutation(api.users.updateProfile, { user_id: account.id, display_name: 'Edited Name' });
  const refreshed = t.withIdentity({ subject, email: 'qa-name@example.com', name: 'Different Clerk Name' });
  expect((await refreshed.mutation(api.users.ensureUser, {})).display_name).toBe('Edited Name');
  expect((await refreshed.mutation(api.users.ensureUser, { display_name: ' New Explicit Name ' })).display_name).toBe('New Explicit Name');
  expect((await refreshed.mutation(api.users.ensureUser, {})).display_name).toBe('New Explicit Name');
});

test('claiming a legacy profile preserves its saved name and app identity', async () => {
  const t = backend(); const id = crypto.randomUUID();
  await t.run(ctx => ctx.db.insert('users', {
    id, display_name: 'Legacy Saved Name', email: 'qa-legacy@example.com', is_anonymous: false,
    legacy_supabase_user_id: crypto.randomUUID(), created_at: 123, updated_at: 123,
  }));
  const client = t.withIdentity({ subject: crypto.randomUUID(), email: 'qa-legacy@example.com', name: 'Clerk Default Name' });
  expect(await client.mutation(api.users.ensureUser, {})).toMatchObject({ id, display_name: 'Legacy Saved Name', is_anonymous: false });
});
