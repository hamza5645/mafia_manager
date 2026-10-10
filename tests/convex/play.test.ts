import { expect, test } from 'vitest';
import { api } from '../../convex/_generated/api';
import { E } from '../../convex/lib/errors';
import { backend, room, seatRow, start } from './helpers';

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
    const row = await ctx.db.query('session_players').withIndex('by_app_id', q => q.eq('id', r.humans[i].id)).unique();
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
      const row = await ctx.db.query('session_players').withIndex('by_app_id', q => q.eq('id', r.humans[2].id)).unique();
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
