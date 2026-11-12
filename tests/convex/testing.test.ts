import { afterEach, expect, test, vi } from 'vitest';
import { api, internal } from '../../convex/_generated/api';
import { Backend, backend, guest, proof, room } from './helpers';

afterEach(() => { vi.unstubAllEnvs(); });

// Runs testing:purgeQa page by page, as an operator would, and adds up the counts.
async function purgeAll(t: Backend, batch: number) {
  const total = { users: 0, seats: 0, rooms: 0, library_rows: 0 };
  let cursor: string | null = null;
  do {
    const page: { cursor: string | null } & typeof total = await t.mutation(internal.testing.purgeQa, { cursor, batch });
    for (const key of Object.keys(total) as (keyof typeof total)[]) total[key] += page[key];
    cursor = page.cursor;
  } while (cursor !== null);
  return total;
}

const tables = (t: Backend) => t.run(async ctx => ({
  users: (await ctx.db.query('users').collect()).map(u => u.display_name).sort(),
  sessions: (await ctx.db.query('game_sessions').collect()).map(s => s.id),
  seats: (await ctx.db.query('session_players').collect()).map(s => s.player_name).sort(),
  presence: (await ctx.db.query('session_presence').collect()).length,
  stats: (await ctx.db.query('player_stats').collect()).map(s => s.user_id),
  games: (await ctx.db.query('recorded_games').collect()).length,
  groups: (await ctx.db.query('player_groups').collect()).length,
}));

test('purgeQa refuses to run unless the deployment opts in', async () => {
  const t = backend(); await guest(t, 'QA Guest');
  await expect(t.mutation(internal.testing.purgeQa, {})).rejects.toThrow(/MAFIA_ALLOW_QA_PURGE/);
  vi.stubEnv('MAFIA_ALLOW_QA_PURGE', 'true');
  await expect(t.mutation(internal.testing.purgeQa, {})).rejects.toThrow(/MAFIA_ALLOW_QA_PURGE/);
  expect((await tables(t)).users).toEqual(['QA Guest']);
});

test('purgeQa deletes only QA users and what they leave behind', async () => {
  vi.stubEnv('MAFIA_ALLOW_QA_PURGE', '1');
  const t = backend();
  // A QA lobby, a cancelled QA room, QA stats, and a QA guest seated in a real player's room.
  const qa = await room(t, 2);
  const old = await t.mutation(api.sessions.createSession, { player_name: 'QA 0', max_players: 4, bot_count: 0, ...proof(qa.host) });
  await t.mutation(api.sessions.cancelSession, { session_id: old.session_id, ...proof(qa.host) });
  const game = (player_name: string) => ({ game_id: crypto.randomUUID(), results: [{ player_name, role: 'mafia' as const, won: true, kills: 1 }] });
  await t.mutation(api.stats.recordGame, { ...game('Ann'), ...proof(qa.host) });
  const ann = await guest(t, 'Ann');
  const annRoom = await t.mutation(api.sessions.createSession, { player_name: 'Ann', max_players: 4, bot_count: 1, ...proof(ann) });
  await t.mutation(api.sessions.joinSession, { room_code: annRoom.room_code, player_name: 'QA 1', ...proof(qa.users[1]) });
  await t.mutation(api.stats.recordGame, { ...game('Bo'), ...proof(ann) });
  // A Clerk test account, as ClerkAccountIntegrationTests signs up.
  const qaAccount = t.withIdentity({ subject: crypto.randomUUID(), email: `mafia-native-${crypto.randomUUID()}+clerk_test@example.com`, name: 'QA Native Account' });
  await qaAccount.mutation(api.users.ensureUser, {});
  await qaAccount.mutation(api.stats.createPlayerGroup, { group_name: 'QA', player_names: ['a'] });
  // Lookalikes that are not QA data.
  const lookalike = t.withIdentity({ subject: crypto.randomUUID(), email: 'mafia-native-someone@example.com', name: 'QA Real Person' });
  await lookalike.mutation(api.users.ensureUser, {});
  await guest(t, 'QAnna');

  expect(await purgeAll(t, 2)).toEqual({ users: 3, seats: 3, rooms: 2, library_rows: 3 });
  expect(await tables(t)).toEqual({
    users: ['Ann', 'QA Real Person', 'QAnna'], sessions: [annRoom.session_id], seats: ['Ann', 'Bot 1'],
    presence: 1, stats: [ann.id], games: 1, groups: 0,
  });
  expect((await t.query(api.views.getSessionView, { session_id: annRoom.session_id, ...proof(ann) }))!.session)
    .toMatchObject({ status: 'waiting', host_user_id: ann.id });
  expect(await purgeAll(t, 2)).toEqual({ users: 0, seats: 0, rooms: 0, library_rows: 0 });
});
