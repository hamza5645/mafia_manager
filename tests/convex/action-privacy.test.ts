import { expect, test } from 'vitest';
import { api } from '../../convex/_generated/api';
import { backend, proof, room, startNight } from './helpers';

test('all action and selection queries enforce role privacy while host can resolve', async () => {
  const t = backend();
  const r = await room(t, 6);
  const active = await startNight(t, r);
  const types = ['mafia_target', 'doctor_protect', 'inspector_check'] as const;
  for (const [i, action_type] of types.entries()) {
    const actor = i + 1;
    const args = {
      session_id: r.session.id, actor_player_id: r.players[actor].player_id,
      target_player_id: r.players[4].player_id, action_type, phase_index: 0, ...proof(r.users[actor]),
    };
    await t.mutation(api.sessions.submitAction, { ...args, round_id: active.current_round_id! });
    await t.mutation(api.sessions.setTentativeSelection, args);
  }
  expect(await t.query(api.sessions.getAllActions, r.viewerArgs(r.users[4]))).toEqual([]);
  expect(await t.query(api.sessions.listTentativeSelectionsForSession, r.viewerArgs(r.users[4]))).toEqual([]);
  for (const action_type of types) {
    expect(await t.query(api.sessions.getActionsForPhase, {
      ...r.viewerArgs(r.users[4]), phase_index: 0, action_type,
    })).toEqual([]);
    expect(await t.query(api.sessions.listTentativeSelections, {
      ...r.viewerArgs(r.users[4]), phase_index: 0, action_type,
    })).toEqual([]);
  }
  const hostRows = await t.query(api.sessions.getAllActions, r.viewerArgs(r.host));
  expect(hostRows).toHaveLength(3);
  expect(hostRows.find(row => row.action_type === 'inspector_check')?.action_data.inspector_result).toBe('not_mafia');
  expect(await t.query(api.sessions.getAllActions, r.viewerArgs(r.users[5]))).toHaveLength(1);
  expect(await t.query(api.sessions.listTentativeSelectionsForSession, r.viewerArgs(r.users[5]))).toHaveLength(1);
  const own = await t.query(api.sessions.getAllActions, r.viewerArgs(r.users[3]));
  expect(own).toHaveLength(1);
  expect(own[0].action_data.inspector_result).toBe('not_mafia');
  await t.run(async ctx => {
    const otherInspector = await ctx.db.query('session_players').withIndex('by_app_id', q => q.eq('id', r.players[4].id)).unique();
    await ctx.db.patch(otherInspector!._id, { role: 'inspector' });
  });
  const peer = await t.query(api.sessions.getAllActions, r.viewerArgs(r.users[4]));
  expect(peer).toHaveLength(1);
  expect(peer[0].action_data?.inspector_result).toBeUndefined();
  await t.mutation(api.sessions.updateSessionState, { ...r.hostArgs, is_game_over: true, current_phase: 'game_over' });
  expect(await t.query(api.sessions.getAllActions, r.viewerArgs(r.users[4]))).toHaveLength(3);
});
