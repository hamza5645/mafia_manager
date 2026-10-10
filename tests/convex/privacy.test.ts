import { expect, test } from 'vitest';
import { api } from '../../convex/_generated/api';
import { act, backend, guest, proof, room, start } from './helpers';

// humans: 0 citizen (host), 1 mafia, 2 doctor, 3 inspector, 4 citizen, 5 mafia
const ROLES = ['citizen', 'mafia', 'doctor', 'inspector', 'citizen', 'mafia'] as const;
const FORBIDDEN = ['_id', '_creationTime', 'auth_subject', 'email', 'guest_secret_hash', 'guest_secret_digest',
  'merged_guest_digests', 'legacy_supabase_id', 'legacy_supabase_user_id', 'phase_sequence', 'night_resolution'];

async function nightRoom() {
  const t = backend(); const r = await room(t, 6);
  await start(t, r, [...ROLES]);
  const h = r.humans;
  const draft = (i: number, action_type: any, target: number) => t.mutation(api.play.setTentativeSelection, {
    ...r.as(r.users[i]), actor_player_id: h[i].player_id, action_type, phase_index: 0, target_player_id: h[target].player_id,
  });
  for (const [i, type, target] of [[1, 'mafia_target', 4], [2, 'doctor_protect', 4], [3, 'inspector_check', 1]] as const) {
    await draft(i, type, target);
    await act(t, r, h[i], type, h[target]);
  }
  const rows = async (i: number) => (await t.query(api.views.getRoundState, r.as(r.users[i])))!;
  return { t, r, rows };
}

test('night actions and drafts are visible only to the host, the actor and same-role teammates', async () => {
  const { t, r, rows } = await nightRoom();
  const host = await rows(0);
  expect(host.actions).toHaveLength(3);
  expect(host.tentative).toHaveLength(3);
  expect(host.actions.find(a => a.action_type === 'inspector_check')!.action_data).toEqual({ inspector_result: 'mafia' });
  for (const row of [...host.actions, ...host.tentative]) for (const key of FORBIDDEN) expect(row).not.toHaveProperty(key);
  expect(Object.keys(host.tentative[0]).sort()).toEqual(['action_type', 'actor_player_id', 'phase_index', 'target_player_id', 'updated_at']);

  const citizen = await rows(4);
  expect([citizen.actions, citizen.tentative]).toEqual([[], []]);
  expect(citizen.ready_to_advance).toBe(false);
  const teammate = await rows(5);
  expect(teammate.actions.map(a => a.action_type)).toEqual(['mafia_target']);
  expect(teammate.tentative.map(a => a.action_type)).toEqual(['mafia_target']);
  expect((await rows(2)).actions.map(a => a.action_type)).toEqual(['doctor_protect']);
  const inspector = await rows(3);
  expect(inspector.actions.map(a => [a.action_type, a.action_data])).toEqual([['inspector_check', { inspector_result: 'mafia' }]]);

  // A second inspector sees the row but not its result.
  await t.run(async ctx => {
    const row = await ctx.db.query('session_players').withIndex('by_app_id', q => q.eq('id', r.humans[4].id)).unique();
    await ctx.db.patch(row!._id, { role: 'inspector' });
  });
  const peer = await rows(4);
  expect(peer.actions).toHaveLength(1);
  expect(peer.actions[0]).not.toHaveProperty('action_data');
  expect(peer.tentative).toHaveLength(1);

  const outsider = await guest(t, 'QA Outsider');
  expect(await t.query(api.views.getRoundState, r.as(outsider))).toBeNull();
  expect(await t.query(api.views.getRoundState, { session_id: r.sessionId })).toBeNull();

  await t.run(async ctx => {
    const s = await ctx.db.query('game_sessions').withIndex('by_app_id', q => q.eq('id', r.sessionId)).unique();
    await ctx.db.patch(s!._id, { is_game_over: true });
  });
  const over = await rows(4);
  expect(over.actions).toHaveLength(3);
  expect(over.actions.find(a => a.action_type === 'inspector_check')!.action_data).toEqual({ inspector_result: 'mafia' });
});

test('roles are visible to self, the host, mafia teammates, and everyone after the game', async () => {
  const { t, r } = await nightRoom();
  const rolesSeenBy = async (i: number) =>
    (await t.query(api.views.getPlayers, r.as(r.users[i]))).map(p => p.role ?? null);
  const order = (await t.query(api.views.getPlayers, r.as(r.host))).map(p => r.humans.findIndex(h => h.player_id === p.player_id));
  const expected = (visible: number[]) => order.map(i => (visible.includes(i) ? ROLES[i] : null));
  expect(await rolesSeenBy(0)).toEqual(expected([0, 1, 2, 3, 4, 5]));
  expect(await rolesSeenBy(4)).toEqual(expected([4]));
  expect(await rolesSeenBy(1)).toEqual(expected([1, 5]));
  expect(await rolesSeenBy(3)).toEqual(expected([3]));
  const players = await t.query(api.views.getPlayers, r.as(r.users[4]));
  expect(players.filter(p => p.is_me).map(p => p.player_id)).toEqual([r.humans[4].player_id]);
  for (const p of players) for (const key of FORBIDDEN) expect(p).not.toHaveProperty(key);
  const outsider = await guest(t, 'QA Outsider');
  expect(await t.query(api.views.getPlayers, r.as(outsider))).toEqual([]);
  expect(await t.query(api.views.getPlayers, { session_id: r.sessionId })).toEqual([]);
  await t.run(async ctx => {
    const s = await ctx.db.query('game_sessions').withIndex('by_app_id', q => q.eq('id', r.sessionId)).unique();
    await ctx.db.patch(s!._id, { current_phase: 'game_over' });
  });
  expect(await rolesSeenBy(4)).toEqual(expected([0, 1, 2, 3, 4, 5]));
});

test('votes stay hidden until every living player has voted; vote drafts stay private', async () => {
  const t = backend(); const r = await room(t, 4);
  await start(t, r, ['citizen', 'mafia', 'inspector', 'citizen']);
  const [host, mafia, insp, cit] = r.humans;
  await act(t, r, mafia, 'mafia_target', cit);
  await act(t, r, insp, 'inspector_check', mafia);
  const { round_id } = (await t.query(api.views.getRoundState, r.as(r.host)))!;
  await t.mutation(api.night.recordNightActions, { ...r.as(r.host), round_id: round_id! });
  await t.mutation(api.night.resolveNightAtomic, { ...r.as(r.host), round_id: round_id! });
  await t.mutation(api.phases.advancePhase, { ...r.as(r.host), to_phase: 'death_reveal' });
  await t.mutation(api.phases.advancePhase, { ...r.as(r.host), to_phase: 'voting' });
  await t.mutation(api.play.setTentativeSelection, { ...r.as(r.users[1]), actor_player_id: mafia.player_id,
    action_type: 'vote', phase_index: 0, target_player_id: host.player_id });
  await act(t, r, mafia, 'vote', host);
  const seen = async (i: number) => (await t.query(api.views.getRoundState, r.as(r.users[i])))!;
  expect((await seen(2)).actions).toEqual([]);
  expect((await seen(2)).tentative).toEqual([]);
  expect((await seen(1)).actions.map(a => a.action_type)).toEqual(['vote']);
  expect((await seen(0)).actions.map(a => a.action_type)).toEqual(['vote']);
  expect((await seen(0)).tentative).toHaveLength(1);
  // The dead citizen does not need to vote.
  await act(t, r, host, 'vote', mafia);
  await act(t, r, insp, 'vote');
  expect((await seen(2)).actions).toHaveLength(3);
  expect((await seen(3)).actions).toHaveLength(3);
  expect((await seen(2)).tentative).toEqual([]);
});

test('session projection depends on the viewer', async () => {
  const t = backend(); const r = await room(t, 4);
  await start(t, r, ['citizen', 'mafia', 'inspector', 'citizen']);
  const [, mafia, insp, cit] = r.humans;
  await act(t, r, mafia, 'mafia_target', cit);
  await act(t, r, insp, 'inspector_check', mafia);
  const { round_id } = (await t.query(api.views.getRoundState, r.as(r.host)))!;
  await t.mutation(api.night.recordNightActions, { ...r.as(r.host), round_id: round_id! });
  const view = async (args: object) => (await t.query(api.views.getSessionView, { session_id: r.sessionId, ...args }))!;

  const host = await view(proof(r.host));
  expect(host.viewer).toEqual({ user_id: r.host.id, player_record_id: r.humans[0].id, player_id: r.humans[0].player_id, is_member: true, is_host: true });
  expect(host.session.night_history).toHaveLength(1);
  expect(host.session.night_history[0]).toMatchObject({ round_id, is_resolved: false, mafia_target_id: cit.player_id });
  expect(host.session.current_round_id).toBe(round_id);
  for (const key of FORBIDDEN) expect(host.session).not.toHaveProperty(key);

  const member = await view(proof(r.users[3]));
  expect(member.viewer).toMatchObject({ is_member: true, is_host: false });
  expect(member.session).toMatchObject({ night_history: [], current_round_id: round_id, original_host_user_id: r.host.id,
    current_phase_data: { type: 'night', nightIndex: 0 } });
  expect(member.session.assigned_numbers).toEqual(r.humans.map((h, i) => ({ player_id: h.player_id, number: i + 1 })));

  await t.mutation(api.night.resolveNightAtomic, { ...r.as(r.host), round_id: round_id! });
  await t.run(async ctx => {
    const s = await ctx.db.query('game_sessions').withIndex('by_app_id', q => q.eq('id', r.sessionId)).unique();
    await ctx.db.patch(s!._id, { current_phase_data: { ...s!.current_phase_data, private_target: 'secret' } });
  });
  const resolved = await view(proof(r.users[3]));
  expect(resolved.session.night_history).toEqual([{ night_index: 0, is_resolved: true, resulting_deaths: [cit.player_id],
    revealed_death_roles: { [cit.player_id]: 'citizen' }, timestamp: expect.any(Number) }]);
  expect(resolved.session.current_phase_data).toEqual({ type: 'morning', nightIndex: 0 });

  const stranger = await guest(t, 'QA Outsider');
  for (const args of [{}, proof(stranger)]) {
    const outsider = await view(args);
    expect(outsider.viewer).toMatchObject({ player_record_id: null, player_id: null, is_member: false, is_host: false });
    expect(outsider.session).toMatchObject({ id: r.sessionId, room_code: r.roomCode, status: 'in_progress',
      assigned_numbers: [], night_history: [], day_history: [] });
    for (const key of ['current_phase_data', 'current_round_id', 'original_host_user_id']) expect(outsider.session).not.toHaveProperty(key);
  }
  expect(await t.query(api.views.getSessionView, { session_id: crypto.randomUUID() })).toBeNull();
});
