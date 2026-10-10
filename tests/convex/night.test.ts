import { afterEach, expect, test, vi } from 'vitest';
import { api } from '../../convex/_generated/api';
import { E } from '../../convex/lib/errors';
import { act, backend, finishNight, room, round, seatRow, sessionRow, start } from './helpers';

afterEach(() => { vi.useRealTimers(); });

test('night is recorded, closed and resolved exactly once per round', async () => {
  const t = backend(); const r = await room(t, 4);
  const { round_id } = await start(t, r, ['citizen', 'mafia', 'inspector', 'citizen']);
  const [host, mafia, insp, cit] = r.humans;
  const hostArgs = { ...r.as(r.host), round_id: round_id! };

  // Ready flags never substitute for the round's actions.
  for (const user of r.users) await t.mutation(api.sessions.setReady, { ...r.as(user), is_ready: true });
  await act(t, r, mafia, 'mafia_target', cit);
  expect((await round(t, r)).ready_to_advance).toBe(false);
  await expect(t.mutation(api.night.recordNightActions, hostArgs)).rejects.toThrow(E.NIGHT_INCOMPLETE);
  await expect(t.mutation(api.night.resolveNightAtomic, hostArgs)).rejects.toThrow(E.NIGHT_NOT_RECORDED);
  await act(t, r, insp, 'inspector_check', mafia);
  expect((await round(t, r)).ready_to_advance).toBe(true);
  await expect(t.mutation(api.night.recordNightActions, { ...r.as(r.users[1]), round_id: round_id! })).rejects.toThrow(E.HOST_ONLY);
  await expect(t.mutation(api.night.recordNightActions, { ...hostArgs, round_id: crypto.randomUUID() })).rejects.toThrow(E.MOVED_ON);

  const record = await t.mutation(api.night.recordNightActions, hostArgs);
  expect(record).toEqual({
    night_index: 0, round_id, is_resolved: false, mafia_target_id: cit.player_id, inspector_checked_id: mafia.player_id,
    target_was_saved: false, resulting_deaths: [], revealed_death_roles: {},
    mafia_player_numbers: [2], doctor_player_numbers: [], inspector_player_numbers: [3], timestamp: expect.any(Number),
  });
  expect(await t.mutation(api.night.recordNightActions, hostArgs)).toEqual(record);
  expect((await sessionRow(t, r.sessionId)).current_phase).toBe('night');
  await expect(act(t, r, mafia, 'mafia_target', host)).rejects.toThrow(E.NIGHT_CLOSED);
  await expect(t.mutation(api.play.setTentativeSelection, { ...r.as(r.users[1]), actor_player_id: mafia.player_id,
    action_type: 'mafia_target', phase_index: 0, target_player_id: host.player_id })).rejects.toThrow(E.NIGHT_CLOSED);

  const outcome = await t.mutation(api.night.resolveNightAtomic, hostArgs);
  expect(outcome).toEqual({ night_index: 0, resulting_deaths: [cit.player_id], next_phase: 'morning', winner: null });
  const after = await sessionRow(t, r.sessionId);
  expect(after).toMatchObject({ current_phase: 'morning', current_phase_data: { type: 'morning', nightIndex: 0 }, current_round_id: round_id });
  expect(after.night_history).toEqual([{ ...record, is_resolved: true, resulting_deaths: [cit.player_id],
    revealed_death_roles: { [cit.player_id]: 'citizen' }, next_phase: 'morning' }]);
  expect(await seatRow(t, cit.player_id)).toMatchObject({ is_alive: false, removal_note: 'night' });
  expect((await round(t, r)).ready_to_advance).toBe(false);

  // Retries never write or move the phase backwards.
  await t.mutation(api.phases.advancePhase, { ...r.as(r.host), to_phase: 'death_reveal' });
  const settled = await sessionRow(t, r.sessionId);
  expect(await t.mutation(api.night.resolveNightAtomic, hostArgs)).toEqual(outcome);
  expect(await t.mutation(api.night.recordNightActions, hostArgs)).toEqual(after.night_history[0]);
  expect(await sessionRow(t, r.sessionId)).toEqual(settled);
  expect(settled.current_phase).toBe('death_reveal');
  await expect(t.mutation(api.night.resolveNightAtomic, { ...hostArgs, round_id: crypto.randomUUID() })).rejects.toThrow(E.MOVED_ON);
  await expect(t.mutation(api.phases.advancePhase, { ...r.as(r.host), to_phase: 'night' })).rejects.toThrow(E.MOVED_ON);
});

test('any doctor protection on the mafia target saves it', async () => {
  const t = backend(); const r = await room(t, 1, 14);
  const botRoles = ['mafia', 'mafia', 'mafia', 'mafia', 'mafia', 'doctor', 'doctor', 'inspector', 'inspector',
    'citizen', 'citizen', 'citizen', 'citizen', 'citizen'] as const;
  await start(t, r, ['citizen'], [...botRoles]);
  const bots = r.bots; const victim = bots[9]; const elsewhere = bots[10];
  for (const mafia of bots.slice(0, 5)) await act(t, r, mafia, 'mafia_target', victim);
  await act(t, r, bots[5], 'doctor_protect', elsewhere);
  await act(t, r, bots[6], 'doctor_protect', victim);
  for (const insp of bots.slice(7, 9)) await act(t, r, insp, 'inspector_check', bots[0]);
  expect(await finishNight(t, r)).toEqual({ night_index: 0, resulting_deaths: [], next_phase: 'morning', winner: null });
  expect((await sessionRow(t, r.sessionId)).night_history[0]).toMatchObject({
    mafia_target_id: victim.player_id, doctor_protected_id: victim.player_id, target_was_saved: true,
    mafia_player_numbers: [2, 3, 4, 5, 6], doctor_player_numbers: [7, 8], inspector_player_numbers: [9, 10],
  });
  expect((await seatRow(t, victim.player_id))!.is_alive).toBe(true);
});

test('mafia ties prefer the human pick, then the earliest submission', async () => {
  // Human priority: the human mafia's pick wins a 1-1 tie with a bot.
  {
    const t = backend(); const r = await room(t, 2, 4);
    await start(t, r, ['citizen', 'mafia'], ['mafia', 'doctor', 'inspector', 'citizen']);
    const [host, humanMafia] = r.humans; const [botMafia, doctor, insp, citizen] = r.bots;
    await act(t, r, botMafia, 'mafia_target', host);
    await act(t, r, humanMafia, 'mafia_target', citizen);
    await act(t, r, doctor, 'doctor_protect', doctor);
    await act(t, r, insp, 'inspector_check', host);
    expect((await finishNight(t, r)).resulting_deaths).toEqual([citizen.player_id]);
  }
  // Two humans tie: earliest created_at wins, and a resubmission refreshes created_at.
  for (const resubmit of [false, true]) {
    vi.useFakeTimers({ toFake: ['Date'] });
    const t = backend(); const r = await room(t, 3, 3);
    await start(t, r, ['citizen', 'mafia', 'mafia'], ['doctor', 'inspector', 'citizen']);
    const [host, m1, m2] = r.humans; const [doctor, insp, citizen] = r.bots;
    vi.setSystemTime(Date.now() + 1000); await act(t, r, m1, 'mafia_target', citizen);
    vi.setSystemTime(Date.now() + 1000); await act(t, r, m2, 'mafia_target', host);
    if (resubmit) { vi.setSystemTime(Date.now() + 1000); await act(t, r, m1, 'mafia_target', citizen); }
    await act(t, r, doctor, 'doctor_protect', doctor);
    await act(t, r, insp, 'inspector_check', m1);
    expect((await finishNight(t, r)).resulting_deaths).toEqual([resubmit ? host.player_id : citizen.player_id]);
    vi.useRealTimers();
  }
});

test('if every mafia abstains the first valid target is used (ported fallback)', async () => {
  const t = backend(); const r = await room(t, 4);
  await start(t, r, ['citizen', 'mafia', 'inspector', 'citizen']);
  const [host, mafia, insp] = r.humans;
  await act(t, r, mafia, 'mafia_target');
  await act(t, r, insp, 'inspector_check', mafia);
  expect((await finishNight(t, r)).resulting_deaths).toEqual([host.player_id]);
});

test('a killed host hands over only to an alive human with a fresh heartbeat', async () => {
  for (const fresh of [true, false]) {
    const t = backend(); const r = await room(t, 4);
    await start(t, r, ['citizen', 'mafia', 'inspector', 'citizen']);
    const [host, mafia, insp] = r.humans;
    if (!fresh) {
      await t.run(async ctx => {
        for (const seat of r.humans.slice(1)) {
          const row = await ctx.db.query('session_players').withIndex('by_app_id', q => q.eq('id', seat.id)).unique();
          await ctx.db.patch(row!._id, { last_heartbeat: 0 });
        }
      });
    }
    await act(t, r, mafia, 'mafia_target', host);
    await t.mutation(api.play.submitAction, { ...r.as(r.users[2]), round_id: (await round(t, r)).round_id!,
      phase_index: 0, action_type: 'inspector_check', actor_player_id: insp.player_id, target_player_id: mafia.player_id });
    expect((await finishNight(t, r)).resulting_deaths).toEqual([host.player_id]);
    expect((await sessionRow(t, r.sessionId)).host_user_id).toBe(fresh ? r.users[1].id : r.host.id);
  }
});

test('game over resets readiness for every seat, bots included', async () => {
  const t = backend(); const r = await room(t, 1, 3);
  await start(t, r, ['citizen'], ['mafia', 'inspector', 'citizen']);
  const [mafia, insp] = r.bots;
  await act(t, r, mafia, 'mafia_target', r.humans[0]);
  await act(t, r, insp, 'inspector_check', mafia);
  expect(await finishNight(t, r)).toEqual({ night_index: 0, resulting_deaths: [r.humans[0].player_id], next_phase: 'game_over', winner: 'mafia' });
  const session = await sessionRow(t, r.sessionId);
  expect(session).toMatchObject({ status: 'completed', is_game_over: true, winner: 'mafia', current_phase: 'game_over',
    current_phase_data: { type: 'gameOver', winner: 'mafia' }, host_user_id: r.host.id });
  const players = await t.query(api.views.getPlayers, r.as(r.host));
  expect(players.map(p => p.is_ready)).toEqual([false, false, false, false]);
  await expect(t.mutation(api.phases.advancePhase, { ...r.as(r.host), to_phase: 'death_reveal' })).rejects.toThrow(E.NOT_ACTIVE);
});

test('a full day cycle: tie keeps everyone, start-of-day parity continues, post-vote parity ends the game', async () => {
  const t = backend(); const r = await room(t, 4);
  const first = await start(t, r, ['citizen', 'mafia', 'inspector', 'citizen']);
  const [host, mafia, insp, cit] = r.humans;
  const host_ = r.as(r.host);
  await act(t, r, mafia, 'mafia_target', cit);
  await act(t, r, insp, 'inspector_check', mafia);
  expect((await finishNight(t, r)).next_phase).toBe('morning');
  await t.mutation(api.phases.advancePhase, { ...host_, to_phase: 'death_reveal' });
  expect(await t.mutation(api.phases.advancePhase, { ...host_, to_phase: 'voting' })).toEqual({ current_phase: 'voting' });
  expect(await t.mutation(api.phases.advancePhase, { ...host_, to_phase: 'voting' })).toEqual({ current_phase: 'voting' });
  const day0 = await round(t, r);
  expect(day0).toMatchObject({ phase: 'voting', phase_index: 0 });
  expect(day0.round_id).not.toBe(first.round_id);

  await act(t, r, host, 'vote', mafia);
  await act(t, r, mafia, 'vote', insp);
  await act(t, r, insp, 'vote', host);
  expect(await t.mutation(api.voting.closeVoting, { ...host_, round_id: day0.round_id! })).toEqual({ day_index: 0, eliminated_player_id: null });
  await t.mutation(api.phases.advancePhase, { ...host_, to_phase: 'vote_death_reveal' });
  expect(await t.mutation(api.voting.resolveVoteAtomic, { ...host_, round_id: day0.round_id! }))
    .toEqual({ day_index: 0, eliminated_player_id: null, next_phase: 'night', winner: null });

  const night1 = await round(t, r);
  expect(night1).toMatchObject({ phase: 'night', phase_index: 1 });
  expect(night1.round_id).not.toBe(day0.round_id);
  expect((await sessionRow(t, r.sessionId)).day_index).toBe(1);
  expect((await t.query(api.views.getPlayers, host_)).filter(p => !p.is_ready).map(p => p.player_id).sort())
    .toEqual([host, mafia, insp, cit].map(p => p.player_id).sort());
  await act(t, r, mafia, 'mafia_target', insp);
  await act(t, r, insp, 'inspector_check', mafia);
  // 1 mafia vs 1 citizen at the start of the day is not yet a mafia win.
  expect(await finishNight(t, r)).toEqual({ night_index: 1, resulting_deaths: [insp.player_id], next_phase: 'morning', winner: null });

  await t.mutation(api.phases.advancePhase, { ...host_, to_phase: 'death_reveal' });
  await t.mutation(api.phases.advancePhase, { ...host_, to_phase: 'voting' });
  const day1 = await round(t, r);
  expect(day1.phase_index).toBe(1);
  await act(t, r, host, 'vote');
  await act(t, r, mafia, 'vote');
  expect(await t.mutation(api.voting.closeVoting, { ...host_, round_id: day1.round_id! })).toEqual({ day_index: 1, eliminated_player_id: null });
  await t.mutation(api.phases.advancePhase, { ...host_, to_phase: 'vote_death_reveal' });
  // After a vote, parity is enough.
  expect(await t.mutation(api.voting.resolveVoteAtomic, { ...host_, round_id: day1.round_id! }))
    .toEqual({ day_index: 1, eliminated_player_id: null, next_phase: 'game_over', winner: 'mafia' });
  const session = await sessionRow(t, r.sessionId);
  expect(session.day_history.map((d: any) => [d.day_index, d.removed_player_ids, d.next_phase]))
    .toEqual([[0, [], 'night'], [1, [], 'game_over']]);
  expect(session.night_history.map((n: any) => n.night_index)).toEqual([0, 1]);
  expect((await t.query(api.views.getPlayers, host_)).every(p => !p.is_ready)).toBe(true);
});

test('night is_ready is masked for everyone but the viewer and the host', async () => {
  const t = backend(); const r = await room(t, 4);
  await start(t, r, ['citizen', 'mafia', 'inspector', 'citizen']);
  await t.mutation(api.sessions.setReady, { ...r.as(r.users[1]), is_ready: true });
  await t.mutation(api.sessions.setReady, { ...r.as(r.users[3]), is_ready: true });
  const readyIn = async (viewer: number) =>
    (await t.query(api.views.getPlayers, r.as(r.users[viewer]))).filter(p => p.is_ready).map(p => p.player_name).sort();
  expect(await readyIn(0)).toEqual(['QA 1', 'QA 3']);
  expect(await readyIn(1)).toEqual(['QA 1']);
  expect(await readyIn(2)).toEqual([]);
  expect(await readyIn(3)).toEqual(['QA 3']);
});

test('actions from a mafia who left or was kicked are not counted (D1)', async () => {
  for (const how of ['leave', 'kick'] as const) {
    const t = backend(); const r = await room(t, 2, 4);
    await start(t, r, ['citizen', 'mafia'], ['mafia', 'doctor', 'inspector', 'citizen']);
    const [host, gone] = r.humans; const [botMafia, doctor, insp, citizen] = r.bots;
    // Counted, the departed mafia's earlier pick would win the 1-1 tie on created_at.
    await act(t, r, gone, 'mafia_target', host);
    await act(t, r, botMafia, 'mafia_target', citizen);
    if (how === 'leave') await t.mutation(api.sessions.leaveSession, r.as(r.users[1]));
    else await t.mutation(api.sessions.removePlayer, { ...r.as(r.host), player_record_id: gone.id });
    await act(t, r, doctor, 'doctor_protect', doctor);
    await act(t, r, insp, 'inspector_check', botMafia);
    expect((await finishNight(t, r)).resulting_deaths).toEqual([citizen.player_id]);
    expect((await sessionRow(t, r.sessionId)).night_history[0].mafia_player_numbers).toEqual([3]);
  }
});
