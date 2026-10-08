/// <reference types="vite/client" />
import { convexTest } from 'convex-test';
import schema from '../../convex/schema';
import { api } from '../../convex/_generated/api';

const modules = import.meta.glob('../../convex/**/*.ts');
export const backend = () => convexTest(schema, modules);
export type Backend = ReturnType<typeof backend>;

export async function guest(t: Backend, name: string) {
  const hash = crypto.randomUUID();
  const user = await t.mutation(api.users.createOrRestoreGuest, {
    display_name: name, guest_secret_hash: hash,
  });
  return { ...user, hash };
}
export type Guest = Awaited<ReturnType<typeof guest>>;
export const proof = (user: Guest) => ({ guest_secret_hash: user.hash });

export async function room(t: Backend, members = 4) {
  const users = await Promise.all(Array.from({ length: members }, (_, i) => guest(t, `QA ${i}`)));
  const host = users[0];
  const session = await t.mutation(api.sessions.createSession, {
    host_user_id: host.id, max_players: 12, bot_count: 0, ...proof(host),
  });
  const players = [];
  for (const user of users) {
    const { player } = await t.mutation(api.sessions.joinSession, {
      room_code: session.room_code, user_id: user.id, player_name: user.display_name, ...proof(user),
    });
    players.push(player);
  }
  return {
    session, users, players, host,
    hostArgs: { session_id: session.id, caller_user_id: host.id, ...proof(host) },
    viewerArgs: (user: Guest) => ({ session_id: session.id, viewer_user_id: user.id, ...proof(user) }),
  };
}

export async function startNight(t: Backend, r: Awaited<ReturnType<typeof room>>) {
  const roles = ['citizen', 'mafia', 'doctor', 'inspector', 'citizen', 'mafia'] as const;
  await t.mutation(api.sessions.assignRolesAndNumbers, {
    ...r.hostArgs,
    assignments: r.players.map((player, i) => ({ player_id: player.player_id, role: roles[i], number: i + 1 })),
  });
  await t.mutation(api.sessions.updateSessionStatus, { ...r.hostArgs, status: 'in_progress' });
  await t.mutation(api.sessions.updateSessionPhase, {
    ...r.hostArgs, current_phase: 'night', current_phase_data: { type: 'night', nightIndex: 0 },
  });
  const active = await t.query(api.sessions.getSessionById, { session_id: r.session.id });
  return active!;
}
