import { afterEach, expect, test, vi } from 'vitest';
import { api } from '../../convex/_generated/api';
import { E } from '../../convex/lib/errors';
import { act, advance, backend, finishNight, room, round, seatRow, start } from './helpers';

afterEach(() => { vi.useRealTimers(); });

// humans: 0 citizen (host), 1 mafia, 2 doctor, 3 inspector, 4 citizen, 5 mafia
const ROLES = ['citizen', 'mafia', 'doctor', 'inspector', 'citizen', 'mafia'] as const;

async function nightRoom() {
  const t = backend(); const r = await room(t, 6);
  const state = await start(t, r, [...ROLES]);
  const args = (actor: number, action_type: any, target?: number, extra: Record<string, unknown> = {}) => ({
    ...r.as(r.users[actor]), actor_player_id: r.humans[actor].player_id, action_type, phase_index: 0,
    target_player_id: target === undefined ? undefined : r.humans[target].player_id, ...extra,
  });
  const submit = (a: ReturnType<typeof args>) => t.mutation(api.play.submitAction, { round_id: state.round_id!, ...a });
  const draft = (a: ReturnType<typeof args>) => t.mutation(api.play.setTentativeSelection, a);
  return { t, r, state, args, submit, draft };
}

test('submitted and tentative actions share every validation rule', async () => {
  const { t, r, args, submit, draft } = await nightRoom();
  const cases: [ReturnType<typeof args>, string][] = [
    [args(4, 'mafia_target', 2), E.WRONG_ROLE],
    [args(1, 'vote', 2), E.WRONG_PHASE],
    [args(1, 'mafia_target', 2, { phase_index: 1 }), E.MOVED_ON],
    [args(1, 'mafia_target', 2, { target_player_id: crypto.randomUUID() }), E.TARGET_DEAD],
    [args(1, 'mafia_target', 1), E.MAFIA_TEAMMATE],
    [args(1, 'mafia_target', 5), E.MAFIA_TEAMMATE],
    [args(3, 'inspector_check', 3), E.INSPECT_SELF],
    [args(1, 'mafia_target', 2, { actor_player_id: crypto.randomUUID() }), E.PLAYER_NOT_FOUND],
    [args(1, 'mafia_target', 2, { guest_secret_hash: r.users[5].hash }), E.NOT_YOUR_PLAYER],
    [args(1, 'mafia_target', 2, { guest_secret_hash: undefined }), E.AUTH],
  ];
  for (const [a, error] of cases) {
    await expect(submit(a)).rejects.toThrow(error);
    await expect(draft(a)).rejects.toThrow(error);
  }
  await expect(t.mutation(api.play.submitAction, { ...args(1, 'mafia_target', 2), round_id: crypto.randomUUID() }))
    .rejects.toThrow(E.MOVED_ON);
  expect((await t.query(api.views.getRoundState, r.as(r.host)))!.actions).toEqual([]);
});

test('dead actors and targets are rejected; abstention and doctor self-protection are allowed', async () => {
  const { t, r, args, submit } = await nightRoom();
  const setAlive = (i: number, is_alive: boolean) => t.run(async ctx => {
    const row = await ctx.db.query('session_players').filter(q => q.eq(q.field('id'), r.humans[i].id)).unique();
    await ctx.db.patch(row!._id, { is_alive });
  });
  await setAlive(1, false);
  await expect(submit(args(1, 'mafia_target', 2))).rejects.toThrow(E.ACTOR_DEAD);
  await setAlive(1, true); await setAlive(4, false);
  await expect(submit(args(1, 'mafia_target', 4))).rejects.toThrow(E.TARGET_DEAD);
  expect(await submit(args(1, 'mafia_target'))).toEqual({ success: true });
  expect(await submit(args(1, 'mafia_target', 2))).toEqual({ success: true });
  expect(await submit(args(2, 'doctor_protect', 2))).toEqual({ success: true });
  const actions = (await t.query(api.views.getRoundState, r.as(r.host)))!.actions;
  expect(actions.map(a => [a.action_type, a.target_player_id])).toEqual([
    ['mafia_target', r.humans[2].player_id], ['doctor_protect', r.humans[2].player_id],
  ]);
});

test('inspector gets one check per round; a retry returns the stored result', async () => {
  const { t, r, args, submit } = await nightRoom();
  expect(await submit(args(3, 'inspector_check', 5))).toEqual({ success: true, result: 'mafia' });
  expect(await submit(args(3, 'inspector_check', 5))).toEqual({ success: true, result: 'mafia' });
  await expect(submit(args(3, 'inspector_check', 4))).rejects.toThrow(E.ALREADY_INSPECTED);
  await expect(submit(args(3, 'inspector_check'))).rejects.toThrow(E.ALREADY_INSPECTED);
  const rows = (await t.query(api.views.getRoundState, r.as(r.users[3])))!.actions;
  expect(rows).toHaveLength(1);
  expect(rows[0]).toMatchObject({ target_player_id: r.humans[5].player_id, action_data: { inspector_result: 'mafia' } });
});

test('inspector results: another inspector is blocked, citizens are not mafia, abstaining has no result', async () => {
  for (const [target, expected] of [[4, 'not_mafia'], [2, 'blocked'], [undefined, undefined]] as const) {
    const { t, r, args, submit } = await nightRoom();
    await t.run(async ctx => {
      const row = await ctx.db.query('session_players').filter(q => q.eq(q.field('id'), r.humans[2].id)).unique();
      await ctx.db.patch(row!._id, { role: 'inspector' });
    });
    expect(await submit(args(3, 'inspector_check', target))).toEqual(expected ? { success: true, result: expected } : { success: true });
  }
});

test('bots are driven only by the host; finished games reject actions', async () => {
  const t = backend(); const r = await room(t, 2, 2);
  const state = await start(t, r, ['citizen', 'citizen'], ['mafia', 'inspector']);
  const bot = r.bots[0];
  const action = { session_id: r.sessionId, round_id: state.round_id!, action_type: 'mafia_target' as const, phase_index: 0,
    actor_player_id: bot.player_id, target_player_id: r.humans[1].player_id };
  await expect(t.mutation(api.play.submitAction, { ...action, guest_secret_hash: r.users[1].hash })).rejects.toThrow(E.HOST_ONLY);
  expect(await t.mutation(api.play.submitAction, { ...action, guest_secret_hash: r.host.hash })).toEqual({ success: true });
  await t.run(async ctx => {
    const s = await ctx.db.query('game_sessions').withIndex('by_app_id', q => q.eq('id', r.sessionId)).unique();
    await ctx.db.patch(s!._id, { is_game_over: true });
  });
  await expect(t.mutation(api.play.submitAction, { ...action, guest_secret_hash: r.host.hash })).rejects.toThrow(E.NOT_ACTIVE);
  expect((await seatRow(t, bot.player_id))!.is_alive).toBe(true);
});

test('re-sending the current target writes nothing; a new target is written', async () => {
  vi.useFakeTimers({ toFake: ['Date'] });
  const { t, r, args, submit, draft } = await nightRoom();
  const rows = () => t.run(async ctx => [await ctx.db.query('game_actions').collect(), await ctx.db.query('tentative_selections').collect()] as const);
  await submit(args(1, 'mafia_target', 2)); await draft(args(1, 'mafia_target', 2));
  await submit(args(2, 'doctor_protect')); await draft(args(2, 'doctor_protect'));
  const first = await rows();
  advance(5);
  expect(await submit(args(1, 'mafia_target', 2))).toEqual({ success: true });
  expect(await draft(args(1, 'mafia_target', 2))).toBeNull();
  expect(await submit(args(2, 'doctor_protect'))).toEqual({ success: true });
  expect(await draft(args(2, 'doctor_protect'))).toBeNull();
  expect(await rows()).toEqual(first);

  advance(5);
  await submit(args(1, 'mafia_target', 4)); await draft(args(1, 'mafia_target', 4));
  const [[action], [tentative]] = await rows();
  expect(action).toMatchObject({ target_player_id: r.humans[4].player_id, created_at: first[0][0].created_at + 10 });
  expect(tentative).toMatchObject({ target_player_id: r.humans[4].player_id, updated_at: first[1][0].updated_at + 10 });
  // Validation still runs first: the same target, now dead, is rejected.
  await t.run(async ctx => {
    const row = await ctx.db.query('session_players').filter(q => q.eq(q.field('id'), r.humans[4].id)).unique();
    await ctx.db.patch(row!._id, { is_alive: false });
  });
  await expect(submit(args(1, 'mafia_target', 4))).rejects.toThrow(E.TARGET_DEAD);
  await expect(draft(args(1, 'mafia_target', 4))).rejects.toThrow(E.TARGET_DEAD);
});

// humans: host citizen, 1 mafia; bots: mafia, doctor, inspector, citizen.
async function botRoom() {
  const t = backend(); const r = await room(t, 2, 4);
  const state = await start(t, r, ['citizen', 'mafia'], ['mafia', 'doctor', 'inspector', 'citizen']);
  const item = (actor: { player_id: string }, action_type: any, target?: { player_id: string }) =>
    ({ actor_player_id: actor.player_id, action_type, target_player_id: target?.player_id });
  const batch = (actions: ReturnType<typeof item>[], user = r.host, extra: Record<string, unknown> = {}) =>
    t.mutation(api.play.submitBotActions, { ...r.as(user), round_id: state.round_id!, phase_index: 0, actions, ...extra });
  return { t, r, state, item, batch };
}

test('submitBotActions stores every bot action in one call and reports each item', async () => {
  const { t, r, item, batch } = await botRoom();
  const [host, humanMafia] = r.humans; const [botMafia, doctor, insp, citizen] = r.bots;
  const ghost = { player_id: crypto.randomUUID() };
  const ok = (actor: { player_id: string }, extra = {}) => ({ actor_player_id: actor.player_id, ok: true, ...extra });
  const no = (actor: { player_id: string }, error: string) => ({ actor_player_id: actor.player_id, ok: false, error });
  expect(await batch([
    item(botMafia, 'mafia_target', citizen),
    item(botMafia, 'mafia_target', humanMafia),
    item(doctor, 'doctor_protect', host),
    item(insp, 'inspector_check', botMafia),
    item(insp, 'inspector_check', botMafia),
    item(insp, 'inspector_check', host),
    item(humanMafia, 'mafia_target', citizen),
    item(host, 'mafia_target', citizen),
    item(ghost, 'mafia_target', citizen),
    item(citizen, 'mafia_target', host),
    item(citizen, 'vote', host),
    item(doctor, 'doctor_protect', ghost),
  ])).toEqual({ results: [
    ok(botMafia),
    no(botMafia, E.MAFIA_TEAMMATE),
    ok(doctor),
    ok(insp, { result: 'mafia' }),
    ok(insp, { result: 'mafia' }),
    no(insp, E.ALREADY_INSPECTED),
    no(humanMafia, E.NOT_YOUR_PLAYER),
    no(host, E.NOT_YOUR_PLAYER),
    no(ghost, E.PLAYER_NOT_FOUND),
    no(citizen, E.WRONG_ROLE),
    no(citizen, E.WRONG_PHASE),
    no(doctor, E.TARGET_DEAD),
  ] });
  // A failed item never touched the stored rows.
  const actions = (await round(t, r)).actions;
  expect(actions.map(a => [a.actor_player_id, a.action_type, a.target_player_id])).toEqual([
    [botMafia.player_id, 'mafia_target', citizen.player_id],
    [doctor.player_id, 'doctor_protect', host.player_id],
    [insp.player_id, 'inspector_check', botMafia.player_id],
  ]);
  expect(actions[2].action_data).toEqual({ inspector_result: 'mafia' });
  expect(await batch([])).toEqual({ results: [] });
  await act(t, r, humanMafia, 'mafia_target', citizen);
  expect((await finishNight(t, r)).resulting_deaths).toEqual([citizen.player_id]);
  expect(await batch([item(doctor, 'doctor_protect', host)])).toEqual({ results: [no(doctor, E.WRONG_PHASE)] });
});

test('submitBotActions is host only and checks the round for every item', async () => {
  const { t, r, item, batch } = await botRoom();
  const [, humanMafia] = r.humans; const [botMafia, doctor, insp, citizen] = r.bots;
  await expect(batch([item(botMafia, 'mafia_target', citizen)], r.users[1])).rejects.toThrow(E.HOST_ONLY);
  await expect(batch([item(botMafia, 'mafia_target', citizen)], r.host, { guest_secret_hash: undefined })).rejects.toThrow(E.AUTH);
  expect(await batch([item(doctor, 'doctor_protect', doctor)], r.host, { round_id: crypto.randomUUID() }))
    .toEqual({ results: [{ actor_player_id: doctor.player_id, ok: false, error: E.MOVED_ON }] });
  expect(await batch([item(doctor, 'doctor_protect', doctor)], r.host, { phase_index: 1 }))
    .toEqual({ results: [{ actor_player_id: doctor.player_id, ok: false, error: E.MOVED_ON }] });
  // Same-target re-sends are no-ops, and a closed night rejects every item.
  await batch([item(botMafia, 'mafia_target', citizen), item(doctor, 'doctor_protect', doctor), item(insp, 'inspector_check', humanMafia)]);
  const before = (await round(t, r)).actions;
  expect((await batch([item(botMafia, 'mafia_target', citizen)])).results).toEqual([{ actor_player_id: botMafia.player_id, ok: true }]);
  expect((await round(t, r)).actions).toEqual(before);
  await act(t, r, humanMafia, 'mafia_target', citizen);
  await t.mutation(api.night.recordNightActions, { ...r.as(r.host), round_id: before[0].round_id });
  expect(await batch([item(botMafia, 'mafia_target', citizen)]))
    .toEqual({ results: [{ actor_player_id: botMafia.player_id, ok: false, error: E.NIGHT_CLOSED }] });
});
