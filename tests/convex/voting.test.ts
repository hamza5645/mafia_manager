import { expect, test } from 'vitest';
import { api } from '../../convex/_generated/api';
import { E } from '../../convex/lib/errors';
import { readVoteCounts } from '../../convex/lib/rules';
import { act, backend, finishNight, room, round, seatRow, sessionRow, start } from './helpers';

// humans: host citizen, 1 mafia, 2 citizen; bots: mafia, doctor, inspector. Night 0 kills nobody.
async function votingRoom() {
  const t = backend(); const r = await room(t, 3, 3);
  await start(t, r, ['citizen', 'mafia', 'citizen'], ['mafia', 'doctor', 'inspector']);
  const [, mafia, cit] = r.humans; const [botMafia, doctor, insp] = r.bots;
  await act(t, r, mafia, 'mafia_target', cit);
  await act(t, r, botMafia, 'mafia_target', cit);
  await act(t, r, doctor, 'doctor_protect', cit);
  await act(t, r, insp, 'inspector_check', mafia);
  expect((await finishNight(t, r)).resulting_deaths).toEqual([]);
  await t.mutation(api.phases.advancePhase, { ...r.as(r.host), to_phase: 'death_reveal' });
  await t.mutation(api.phases.advancePhase, { ...r.as(r.host), to_phase: 'voting' });
  const { round_id } = await round(t, r);
  return { t, r, hostArgs: { ...r.as(r.host), round_id: round_id! } };
}

test('votes must be complete; humans may abstain but bots need a target', async () => {
  const { t, r, hostArgs } = await votingRoom();
  const [host, mafia, cit] = r.humans; const [botMafia, doctor, insp] = r.bots;
  await act(t, r, host, 'vote', mafia);
  await act(t, r, mafia, 'vote', cit);
  await act(t, r, cit, 'vote');
  await act(t, r, botMafia, 'vote', cit);
  await act(t, r, doctor, 'vote', mafia);
  await act(t, r, insp, 'vote');
  expect((await round(t, r)).ready_to_advance).toBe(false);
  await expect(t.mutation(api.voting.closeVoting, hostArgs)).rejects.toThrow(E.VOTES_INCOMPLETE);
  await expect(t.mutation(api.voting.resolveVoteAtomic, hostArgs)).rejects.toThrow(E.WRONG_PHASE);
  await act(t, r, insp, 'vote', mafia);
  expect((await round(t, r)).ready_to_advance).toBe(true);

  const closed = { day_index: 0, eliminated_player_id: mafia.player_id };
  expect(await t.mutation(api.voting.closeVoting, hostArgs)).toEqual(closed);
  expect(await t.mutation(api.voting.closeVoting, hostArgs)).toEqual(closed);
  const results = await sessionRow(t, r.sessionId);
  expect(results.current_phase_data).toEqual({ type: 'votingResults', dayIndex: 0, eliminatedPlayerId: mafia.player_id,
    voteCounts: Object.fromEntries([[host.player_id, 0], [mafia.player_id, 3], [cit.player_id, 2],
      [botMafia.player_id, 0], [doctor.player_id, 0], [insp.player_id, 0]]) });
  await expect(t.mutation(api.voting.resolveVoteAtomic, hostArgs)).rejects.toThrow(E.WRONG_PHASE);
  await expect(act(t, r, host, 'vote', cit)).rejects.toThrow(E.WRONG_PHASE);

  await t.mutation(api.phases.advancePhase, { ...r.as(r.host), to_phase: 'vote_death_reveal' });
  expect((await sessionRow(t, r.sessionId)).current_phase_data).toEqual({ type: 'voteDeathReveal', dayIndex: 0,
    eliminatedPlayerId: mafia.player_id, eliminatedPlayerName: 'QA 1', eliminatedPlayerNumber: 2, eliminatedPlayerRole: 'mafia', voteCount: 3 });
  expect(await t.mutation(api.voting.closeVoting, hostArgs)).toEqual(closed);
  const outcome = { day_index: 0, eliminated_player_id: mafia.player_id, next_phase: 'night', winner: null };
  expect(await t.mutation(api.voting.resolveVoteAtomic, hostArgs)).toEqual(outcome);
  const night = await sessionRow(t, r.sessionId);
  expect(night).toMatchObject({ current_phase: 'night', current_phase_data: { type: 'night', nightIndex: 1 }, day_index: 1 });
  expect(night.current_round_id).not.toBe(hostArgs.round_id);
  expect(await seatRow(t, mafia.player_id)).toMatchObject({ is_alive: false, removal_note: 'Voted out' });
  expect(await t.mutation(api.voting.resolveVoteAtomic, hostArgs)).toEqual(outcome);
  expect(await t.mutation(api.voting.closeVoting, hostArgs)).toEqual(closed);
  expect(await sessionRow(t, r.sessionId)).toEqual(night);
  await expect(t.mutation(api.voting.closeVoting, { ...hostArgs, round_id: crypto.randomUUID() })).rejects.toThrow(E.MOVED_ON);
  await expect(t.mutation(api.voting.resolveVoteAtomic, { ...hostArgs, round_id: crypto.randomUUID() })).rejects.toThrow(E.MOVED_ON);
});

test('a voted-out host hands over; a tie eliminates nobody', async () => {
  const { t, r, hostArgs } = await votingRoom();
  const [host, mafia, cit] = r.humans; const [botMafia, doctor, insp] = r.bots;
  await act(t, r, host, 'vote', mafia);
  await act(t, r, mafia, 'vote', host);
  await act(t, r, cit, 'vote', host);
  for (const bot of [botMafia, doctor, insp]) await act(t, r, bot, 'vote', bot === insp ? mafia : host);
  expect(await t.mutation(api.voting.closeVoting, hostArgs)).toEqual({ day_index: 0, eliminated_player_id: host.player_id });
  await t.mutation(api.phases.advancePhase, { ...r.as(r.host), to_phase: 'vote_death_reveal' });
  await t.mutation(api.voting.resolveVoteAtomic, hostArgs);
  expect((await sessionRow(t, r.sessionId)).host_user_id).toBe(r.users[1].id);

  const tie = await votingRoom();
  const [h2, m2] = tie.r.humans;
  for (const [i, seat] of [...tie.r.humans, ...tie.r.bots].entries()) await act(tie.t, tie.r, seat, 'vote', i % 2 ? h2 : m2);
  expect(await tie.t.mutation(api.voting.closeVoting, tie.hostArgs)).toEqual({ day_index: 0, eliminated_player_id: null });
  await tie.t.mutation(api.phases.advancePhase, { ...tie.r.as(tie.r.host), to_phase: 'vote_death_reveal' });
  expect((await sessionRow(tie.t, tie.r.sessionId)).current_phase_data).toEqual({ type: 'voteDeathReveal', dayIndex: 0 });
  expect(await tie.t.mutation(api.voting.resolveVoteAtomic, tie.hostArgs))
    .toEqual({ day_index: 0, eliminated_player_id: null, next_phase: 'night', winner: null });
  expect((await tie.t.query(api.views.getPlayers, tie.r.as(tie.r.host))).every(p => p.is_alive)).toBe(true);
});

test('legacy Swift voting results (alternating array, upper-case ids) still resolve', async () => {
  const { t, r, hostArgs } = await votingRoom();
  const mafia = r.humans[1];
  await t.run(async ctx => {
    const s = await ctx.db.query('game_sessions').withIndex('by_app_id', q => q.eq('id', r.sessionId)).unique();
    await ctx.db.patch(s!._id, { current_phase: 'voting_results', current_phase_data: { type: 'votingResults', dayIndex: 0,
      voteCounts: [mafia.player_id.toUpperCase(), 4, r.humans[0].player_id.toUpperCase(), 2],
      eliminatedPlayerId: mafia.player_id.toUpperCase() } });
  });
  expect(await t.mutation(api.voting.closeVoting, hostArgs)).toEqual({ day_index: 0, eliminated_player_id: mafia.player_id });
  await t.mutation(api.phases.advancePhase, { ...r.as(r.host), to_phase: 'vote_death_reveal' });
  expect((await sessionRow(t, r.sessionId)).current_phase_data).toMatchObject({
    eliminatedPlayerId: mafia.player_id, eliminatedPlayerName: 'QA 1', voteCount: 4 });
  expect((await t.mutation(api.voting.resolveVoteAtomic, hostArgs)).eliminated_player_id).toBe(mafia.player_id);
  expect(readVoteCounts({ voteCounts: { a: 1 } })).toEqual({ a: 1 });
  expect(readVoteCounts({ voteCounts: ['A', 2, 'B'] })).toEqual({ a: 2 });
  expect(readVoteCounts({})).toEqual({});
});

test('a voted-out player who left before the reveal removes nobody (D2)', async () => {
  const { t, r, hostArgs } = await votingRoom();
  const [host, mafia, cit] = r.humans;
  for (const seat of [host, cit, ...r.bots]) await act(t, r, seat, 'vote', mafia);
  await act(t, r, mafia, 'vote', cit);
  expect((await t.mutation(api.voting.closeVoting, hostArgs)).eliminated_player_id).toBe(mafia.player_id);
  await t.mutation(api.phases.advancePhase, { ...r.as(r.host), to_phase: 'vote_death_reveal' });
  await t.mutation(api.sessions.leaveSession, r.as(r.users[1]));
  expect(await t.mutation(api.voting.resolveVoteAtomic, hostArgs))
    .toEqual({ day_index: 0, eliminated_player_id: null, next_phase: 'night', winner: null });
  expect((await sessionRow(t, r.sessionId)).day_history[0].removed_player_ids).toEqual([]);
});
