import { expect, test } from 'vitest';
import { api } from '../../convex/_generated/api';
import { backend, proof, room } from './helpers';

test('votes stay private until all living players vote, and drafts remain private', async () => {
  const t = backend(); const r = await room(t, 3);
  await t.mutation(api.sessions.updateSessionStatus, { ...r.hostArgs, status: 'in_progress' });
  await t.mutation(api.sessions.updateSessionPhase, { ...r.hostArgs, current_phase: 'voting', current_phase_data: { type: 'voting', dayIndex: 0 } });
  const active = await t.query(api.sessions.getSessionById, r.viewerArgs(r.host));
  const vote = (i: number) => ({ session_id: r.session.id, actor_player_id: r.players[i].player_id,
    target_player_id: r.players[(i + 1) % 3].player_id, action_type: 'vote' as const, phase_index: 0, ...proof(r.users[i]) });
  await t.mutation(api.sessions.setTentativeSelection, vote(1));
  await t.mutation(api.sessions.submitAction, { ...vote(1), round_id: active!.current_round_id! });
  expect(await t.query(api.sessions.getAllActions, r.viewerArgs(r.users[2]))).toEqual([]);
  expect(await t.query(api.sessions.getActionsForPhase, { ...r.viewerArgs(r.users[2]), action_type: 'vote', phase_index: 0, round_id: active!.current_round_id })).toEqual([]);
  expect(await t.query(api.sessions.listTentativeSelectionsForSession, r.viewerArgs(r.users[2]))).toEqual([]);
  expect(await t.query(api.sessions.listTentativeSelections, { ...r.viewerArgs(r.users[2]), action_type: 'vote', phase_index: 0 })).toEqual([]);
  expect(await t.query(api.sessions.getAllActions, r.viewerArgs(r.users[1]))).toHaveLength(1);
  expect(await t.query(api.sessions.getAllActions, r.viewerArgs(r.host))).toHaveLength(1);
  for (const i of [0, 2]) await t.mutation(api.sessions.submitAction, { ...vote(i), round_id: active!.current_round_id! });
  expect(await t.query(api.sessions.getAllActions, r.viewerArgs(r.users[2]))).toHaveLength(3);
  expect(await t.query(api.sessions.getActionsForPhase, { ...r.viewerArgs(r.users[2]), action_type: 'vote', phase_index: 0, round_id: active!.current_round_id })).toHaveLength(3);
  expect(await t.query(api.sessions.listTentativeSelectionsForSession, r.viewerArgs(r.users[2]))).toEqual([]);
  await t.mutation(api.sessions.updateSessionPhase, { ...r.hostArgs, current_phase: 'voting_results', current_phase_data: { type: 'votingResults', dayIndex: 0, voteCounts: {}, eliminatedPlayerId: undefined } });
  expect(await t.query(api.sessions.getAllActions, r.viewerArgs(r.users[2]))).toHaveLength(3);
});
