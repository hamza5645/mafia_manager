import { expect, test } from 'vitest';
import { api } from '../../convex/_generated/api';
import { backend, proof, room, startNight } from './helpers';

const cases = [
  ['wrong role', { action_type: 'inspector_check' }, 4],
  ['vote during night', { action_type: 'vote' }, 4],
  ['wrong index', { phase_index: 99 }, 1],
  ['missing target', { target_player_id: crypto.randomUUID() }, 1],
  ['mafia self target', { targetIndex: 1 }, 1],
  ['mafia teammate target', { targetIndex: 5 }, 1],
  ['inspector self target', { action_type: 'inspector_check', targetIndex: 3 }, 3],
] as const;
for (const [name, overrides, actorIndex] of cases) {
  test(`reject ${name} in submitted and tentative actions`, async () => {
    const t = backend(); const r = await room(t, 6); const active = await startNight(t, r);
    const { targetIndex, ...fields } = overrides as any;
    const args = {
      session_id: r.session.id, actor_player_id: r.players[actorIndex].player_id,
      action_type: 'mafia_target' as const, phase_index: 0,
      target_player_id: r.players[targetIndex ?? 4].player_id, ...proof(r.users[actorIndex]), ...fields,
    };
    await expect(t.mutation(api.sessions.submitAction, { ...args, round_id: active.current_round_id! })).rejects.toThrow();
    await expect(t.mutation(api.sessions.setTentativeSelection, args)).rejects.toThrow();
    expect(await t.query(api.sessions.getAllActions, r.viewerArgs(r.host))).toEqual([]);
  });
}

test('reject dead actors/targets and completed games, allow valid actions and abstention', async () => {
  const t = backend(); const r = await room(t, 5); const active = await startNight(t, r);
  const args = { session_id: r.session.id, round_id: active.current_round_id!, action_type: 'mafia_target' as const,
    phase_index: 0, actor_player_id: r.players[1].player_id, target_player_id: r.players[4].player_id, ...proof(r.users[1]) };
  const life = (index: number, alive: boolean) => t.mutation(api.sessions.updatePlayerLifeStatus, {
    record_id: r.players[index].id, is_alive: alive, caller_user_id: r.host.id, ...proof(r.host),
  });
  await life(1, false);
  await expect(t.mutation(api.sessions.submitAction, args)).rejects.toThrow();
  await life(1, true); await life(4, false);
  await expect(t.mutation(api.sessions.submitAction, args)).rejects.toThrow();
  await life(4, true);
  await t.mutation(api.sessions.submitAction, args); await t.mutation(api.sessions.submitAction, args);
  expect(await t.query(api.sessions.getAllActions, r.viewerArgs(r.host))).toHaveLength(1);
  await t.mutation(api.sessions.submitAction, { ...args, action_type: 'doctor_protect', actor_player_id: r.players[2].player_id,
    target_player_id: r.players[2].player_id, ...proof(r.users[2]) });
  await t.mutation(api.sessions.updateSessionPhase, { ...r.hostArgs, current_phase: 'voting', current_phase_data: { type: 'voting', dayIndex: 0 } });
  const voting = await t.query(api.sessions.getSessionById, r.viewerArgs(r.host));
  await expect(t.mutation(api.sessions.submitAction, { ...args, round_id: voting!.current_round_id! })).rejects.toThrow();
  await life(4, false);
  const vote = { ...args, round_id: voting!.current_round_id!, actor_player_id: r.players[4].player_id,
    action_type: 'vote' as const, target_player_id: undefined, ...proof(r.users[4]) };
  await expect(t.mutation(api.sessions.submitAction, vote)).rejects.toThrow();
  await life(4, true); await t.mutation(api.sessions.submitAction, vote);
  await t.mutation(api.sessions.updateSessionState, { ...r.hostArgs, is_game_over: true });
  await expect(t.mutation(api.sessions.submitAction, vote)).rejects.toThrow();
});
