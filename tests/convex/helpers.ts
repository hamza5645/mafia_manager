/// <reference types="vite/client" />
import { convexTest } from 'convex-test';
import schema from '../../convex/schema';
import { api } from '../../convex/_generated/api';

const modules = import.meta.glob('../../convex/**/*.ts');
export const backend = () => convexTest(schema, modules);
export type Backend = ReturnType<typeof backend>;
export type Role = 'mafia' | 'doctor' | 'inspector' | 'citizen';
export type NightType = 'mafia_target' | 'doctor_protect' | 'inspector_check';

// Same format as the app: lowercase hex sha256 of a Keychain secret.
export const randomHash = () =>
  Array.from(crypto.getRandomValues(new Uint8Array(32)), b => b.toString(16).padStart(2, '0')).join('');

export async function guest(t: Backend, name: string) {
  const hash = randomHash();
  const user = await t.mutation(api.users.createOrRestoreGuest, { display_name: name, guest_secret_hash: hash });
  return { ...user, hash };
}
export type Guest = Awaited<ReturnType<typeof guest>>;
export const proof = (user: { hash: string }) => ({ guest_secret_hash: user.hash });

// A lobby with `humans` guests (users[0] hosts) and `bots` bots.
export async function room(t: Backend, humans = 4, bots = 0) {
  const users: Guest[] = [];
  for (let i = 0; i < humans; i++) users.push(await guest(t, `QA ${i}`));
  const host = users[0];
  const entered = await t.mutation(api.sessions.createSession, {
    player_name: host.display_name, max_players: 19, bot_count: bots, ...proof(host),
  });
  for (const user of users.slice(1)) {
    await t.mutation(api.sessions.joinSession, { room_code: entered.room_code, player_name: user.display_name, ...proof(user) });
  }
  const sessionId = entered.session_id;
  const as = (user: { hash: string }) => ({ session_id: sessionId, ...proof(user) });
  const all = await t.query(api.views.getPlayers, as(host));
  return {
    sessionId, roomCode: entered.room_code, users, host, as,
    humans: users.map(user => all.find(p => p.user_id === user.id)!),
    bots: all.filter(p => p.is_bot),
  };
}
export type Room = Awaited<ReturnType<typeof room>>;

// Starts the game (humans' roles first, then bots') and enters night 0.
export async function start(t: Backend, r: Room, humanRoles: Role[], botRoles: Role[] = []) {
  const seats = [...r.humans, ...r.bots];
  const roles = [...humanRoles, ...botRoles];
  await t.mutation(api.sessions.startGame, {
    ...r.as(r.host),
    assignments: seats.map((seat, i) => ({ player_id: seat.player_id, role: roles[i], number: i + 1 })),
  });
  await t.mutation(api.phases.advancePhase, { ...r.as(r.host), to_phase: 'night' });
  return await round(t, r);
}

export async function round(t: Backend, r: Room) {
  return (await t.query(api.views.getRoundState, r.as(r.host)))!;
}

// Submits an action for `actor`; bots are driven by the host.
export async function act(
  t: Backend, r: Room, actor: { player_id: string; user_id?: string }, action_type: NightType | 'vote',
  target?: { player_id: string },
) {
  const state = await round(t, r);
  const caller = r.users.find(u => u.id === actor.user_id) ?? r.host;
  return await t.mutation(api.play.submitAction, {
    ...r.as(caller), round_id: state.round_id!, phase_index: state.phase_index!, action_type,
    actor_player_id: actor.player_id, target_player_id: target?.player_id,
  });
}

export async function finishNight(t: Backend, r: Room) {
  const { round_id } = await round(t, r);
  await t.mutation(api.night.recordNightActions, { ...r.as(r.host), round_id: round_id! });
  return await t.mutation(api.night.resolveNightAtomic, { ...r.as(r.host), round_id: round_id! });
}

export async function seatRow(t: Backend, playerId: string) {
  return await t.run(ctx => ctx.db.query('session_players').filter(q => q.eq(q.field('player_id'), playerId)).first());
}

export async function sessionRow(t: Backend, sessionId: string) {
  return (await t.run(ctx => ctx.db.query('game_sessions').withIndex('by_app_id', q => q.eq('id', sessionId)).unique()))!;
}
