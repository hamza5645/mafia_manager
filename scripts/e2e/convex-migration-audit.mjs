import { ConvexHttpClient } from 'convex/browser';
import { randomUUID, createHash } from 'node:crypto';
import { writeFileSync } from 'node:fs';

// Public-client audit: creates only QA data; cancels rooms and removes their
// memberships and saved data. Guest profiles remain because no delete API exists.
const client = new ConvexHttpClient(process.env.CONVEX_AUDIT_URL ?? 'https://energized-herring-345.eu-west-1.convex.cloud');
const results = [];
const users = [];
const rooms = [];
const saved = [];
const runId = randomUUID();
const q = (name, args) => client.query(name, args);
const m = (name, args) => client.mutation(name, args);
const proof = (u) => ({ guest_secret_hash: u.hash });
const hostArgs = (s, u) => ({ session_id: s.id, caller_user_id: u.id, ...proof(u) });
const viewerArgs = (s, u) => ({ session_id: s.id, viewer_user_id: u.id, ...proof(u) });
async function check(name, work) {
  try { const evidence = await work(); results.push({ name, status: 'PASS', evidence }); }
  catch (e) { results.push({ name, status: 'FAIL', evidence: String(e.message ?? e) }); }
  console.log(`${results.at(-1).status} ${name}`);
}
function expect(condition, evidence) { if (!condition) throw new Error(JSON.stringify(evidence)); return evidence; }
async function rejects(work) { try { await work(); } catch (e) { return String(e.message ?? e); } throw new Error('Request was accepted'); }
async function guest(name) {
  const hash = createHash('sha256').update(randomUUID()).digest('hex');
  const u = await m('users:createOrRestoreGuest', { display_name: `QA audit ${name}`, guest_secret_hash: hash });
  const value = { ...u, hash }; users.push(value); return value;
}
async function room(host, members, max = 8) {
  const s = await m('sessions:createSession', { host_user_id: host.id, max_players: max, bot_count: 0, ...proof(host) });
  rooms.push({ s, host, members: [host, ...members] });
  const ps = [];
  ps.push(await m('sessions:addPlayer', { ...hostArgs(s, host), user_id: host.id, player_name: 'QA host', is_bot: false }));
  for (const u of members) ps.push((await m('sessions:joinSession', { room_code: s.room_code, user_id: u.id, player_name: u.display_name, ...proof(u) })).player);
  return { s, ps };
}
async function phase(s, host, name, index = 0) {
  await m('sessions:updateSessionPhase', { ...hostArgs(s, host), current_phase: name, current_phase_data: { type: name, [name === 'night' ? 'nightIndex' : 'dayIndex']: index } });
  return q('sessions:getSessionById', viewerArgs(s, host));
}
try {
  await check('Health', async () => expect((await q('health:check', {})).ok, 'health:check'));
  const host = await guest('host'), mafia = await guest('mafia'), doctor = await guest('doctor'), inspector = await guest('inspector'), citizen = await guest('citizen'), outsider = await guest('outsider');
  await check('Guest restore preserves identity', async () => expect((await m('users:createOrRestoreGuest', { display_name: host.display_name, ...proof(host) })).id === host.id, 'same UUID'));
  await check('Profile denies wrong guest proof', () => rejects(() => q('users:getUserProfile', { user_id: host.id, ...proof(outsider) })));
  await check('Profile denies missing proof', () => rejects(() => q('users:getUserProfile', { user_id: host.id })));
  const { s, ps } = await room(host, [mafia, doctor, inspector, citizen]);
  const roles = ['citizen', 'mafia', 'doctor', 'inspector', 'citizen'];
  await m('sessions:assignRolesAndNumbers', { ...hostArgs(s, host), assignments: ps.map((p, i) => ({ player_id: p.player_id, role: roles[i], number: i + 1 })) });
  await check('Host sees all assigned roles', async () => expect((await q('sessions:getSessionPlayers', viewerArgs(s, host))).every(p => p.role), 'all roles present'));
  await check('Citizen sees only own role', async () => expect((await q('sessions:getSessionPlayers', viewerArgs(s, citizen))).filter(p => p.role).length === 1, 'one visible role'));
  await check('Outsider cannot spoof host role query', () => rejects(() => q('sessions:getSessionPlayers', { session_id: s.id, viewer_user_id: host.id, ...proof(outsider) })));
  await check('Nonhost cannot kick', () => rejects(() => m('sessions:removePlayer', { player_id: ps[0].id, caller_user_id: citizen.id, ...proof(citizen) })));
  await check('Member cannot mutate another readiness', () => rejects(() => m('sessions:updatePlayerReady', { player_id: ps[0].id, is_ready: false, ...proof(citizen) })));
  await check('Fresh host cannot be claimed', () => rejects(() => m('sessions:updateSessionHost', { ...hostArgs(s, citizen), new_host_user_id: citizen.id })));
  await m('sessions:updateSessionStatus', { ...hostArgs(s, host), status: 'in_progress' });
  await check('Cannot join in-progress room', () => rejects(() => m('sessions:joinSession', { room_code: s.room_code, user_id: outsider.id, player_name: outsider.display_name, ...proof(outsider) })));
  let active = await phase(s, host, 'night');
  const action = (i, type, target = ps[4].player_id, overrides = {}) => ({ session_id: s.id, round_id: active.current_round_id, action_type: type, phase_index: 0, actor_player_id: ps[i].player_id, target_player_id: target, ...proof([host, mafia, doctor, inspector, citizen][i]), ...overrides });
  await check('Reject stale action round', () => rejects(() => m('sessions:submitAction', action(1, 'mafia_target', undefined, { round_id: randomUUID() }))));
  await check('Reject action actor impersonation', () => rejects(() => m('sessions:submitAction', action(1, 'mafia_target', undefined, proof(citizen)))));
  await m('sessions:submitAction', action(1, 'mafia_target'));
  await m('sessions:submitAction', action(2, 'doctor_protect'));
  const inspected = await m('sessions:submitAction', action(3, 'inspector_check', ps[1].player_id));
  await check('Inspector receives mafia result', () => expect(inspected.result === 'mafia', inspected));
  await check('Citizen cannot infer secret role actors/targets from actions', async () => {
    const rows = await q('sessions:getAllActions', viewerArgs(s, citizen));
    return expect(!rows.some(r => r.actor_player_id !== ps[4].player_id && r.action_type !== 'vote' && (r.actor_player_id || r.target_player_id)), rows);
  });
  await check('Citizen cannot see inspector result', async () => expect(!(await q('sessions:getAllActions', viewerArgs(s, citizen))).some(r => r.action_data?.inspector_result), 'result omitted'));
  await m('sessions:setTentativeSelection', { session_id: s.id, actor_player_id: ps[1].player_id, target_player_id: ps[4].player_id, action_type: 'mafia_target', phase_index: 0, ...proof(mafia) });
  await check('Citizen cannot read Mafia tentative targets', async () => { const rows = await q('sessions:listTentativeSelectionsForSession', viewerArgs(s, citizen)); return expect(!rows.some(r => r.action_type === 'mafia_target'), rows); });
  await check('Reject wrong-role action (citizen inspector)', () => rejects(() => m('sessions:submitAction', action(4, 'inspector_check', ps[1].player_id))));
  await check('Reject vote submitted during night', () => rejects(() => m('sessions:submitAction', action(4, 'vote', ps[1].player_id))));
  await check('Reject nonexistent action target', () => rejects(() => m('sessions:submitAction', action(1, 'mafia_target', randomUUID()))));
  await check('Reject wrong phase index', () => rejects(() => m('sessions:submitAction', action(1, 'mafia_target', undefined, { phase_index: 99 }))));
  await m('sessions:submitAction', action(1, 'mafia_target')); // restore valid upsert
  await check('Action upsert is idempotent', async () => expect((await q('sessions:getActionsForPhase', { ...viewerArgs(s, host), action_type: 'mafia_target', phase_index: 0, round_id: active.current_round_id })).length === 1, 'one row'));
  await m('sessions:updatePlayerLifeStatus', { record_id: ps[4].id, is_alive: false, ...{ caller_user_id: host.id }, ...proof(host) });
  await check('Dead player cannot submit vote', () => rejects(() => m('sessions:submitAction', action(4, 'vote', ps[1].player_id))));
  await m('sessions:updatePlayerLifeStatus', { record_id: ps[4].id, is_alive: true, caller_user_id: host.id, ...proof(host) });
  await check('Nonhost cannot resolve night', () => rejects(() => m('sessions:resolveNightAtomic', { ...hostArgs(s, citizen), expected_round_id: active.current_round_id, night_record: { night_index: 0 }, eliminated_player_ids: [], next_phase: 'morning', next_phase_data: { type: 'morning', nightIndex: 0 } })));
  await check('Atomic resolution saves protected target', async () => { await m('sessions:resolveNightAtomic', { ...hostArgs(s, host), expected_round_id: active.current_round_id, night_record: { night_index: 0, is_resolved: true, mafia_target_id: ps[4].player_id, doctor_protected_id: ps[4].player_id, resulting_deaths: [] }, eliminated_player_ids: [], next_phase: 'morning', next_phase_data: { type: 'morning', nightIndex: 0 } }); return expect((await q('sessions:getSessionPlayers', viewerArgs(s, host))).every(p => p.is_alive), 'all alive'); });
  await check('Public discovery does not expose secret night targets', async () => { const row = await q('sessions:getSessionByRoomCode', { room_code: s.room_code }); return expect(!row.night_history.some(n => n.mafia_target_id || n.doctor_protected_id), row.night_history); });
  active = await phase(s, host, 'voting');
  await check('Host voting-results request with app arguments succeeds', async () => q('sessions:getActionsForPhase', { ...viewerArgs(s, host), action_types: ['vote'], phase_index: 0, round_id: active.current_round_id }));
  await check('Reject stale atomic night resolution after voting starts', () => rejects(() => m('sessions:resolveNightAtomic', { ...hostArgs(s, host), expected_round_id: active.current_round_id, night_record: { night_index: 0, is_resolved: true, resulting_deaths: [] }, eliminated_player_ids: [], next_phase: 'morning', next_phase_data: { type: 'morning', nightIndex: 0 } })));
  active = await phase(s, host, 'voting');
  await check('Reject inspector action during voting', () => rejects(() => m('sessions:submitAction', action(3, 'inspector_check', ps[1].player_id))));
  await m('sessions:submitAction', action(0, 'vote', ps[1].player_id));
  await m('sessions:submitAction', action(0, 'vote', ps[2].player_id));
  await check('Vote change overwrites one row', async () => { const rows = await q('sessions:getActionsForPhase', { ...viewerArgs(s, host), action_type: 'vote', phase_index: 0, round_id: active.current_round_id }); return expect(rows.filter(r => r.actor_player_id === ps[0].player_id).length === 1 && rows.find(r => r.actor_player_id === ps[0].player_id).target_player_id === ps[2].player_id, 'one updated vote'); });
  await check('Cannot return to lobby midgame', () => rejects(() => m('sessions:returnToLobby', { session_id: s.id, player_id: ps[4].id, player_user_id: citizen.id, original_host_user_id: host.id, ...proof(citizen) })));
  const rematchRoom = await room(host, [mafia, doctor, inspector]);
  await m('sessions:updateSessionStatus', { ...hostArgs(rematchRoom.s, host), status: 'in_progress' });
  await phase(rematchRoom.s, host, 'night');
  await check('Rematch cannot reset an active game', () => rejects(() => m('sessions:executeRematch', hostArgs(rematchRoom.s, host))));
  await m('sessions:updateSessionState', { ...hostArgs(s, host), current_phase: 'game_over', current_phase_data: { type: 'game_over', winner: 'citizen' }, is_game_over: true, winner: 'citizen' });
  await check('Final roles visible to members', async () => expect((await q('sessions:getSessionPlayers', viewerArgs(s, citizen))).every(p => p.role), 'all final roles visible'));
  await m('sessions:returnToLobby', { session_id: s.id, player_id: ps[0].id, player_user_id: host.id, original_host_user_id: host.id, ...proof(host) });
  await check('Play again clears actions and selections', async () => expect((await q('sessions:getAllActions', viewerArgs(s, host))).length === 0 && (await q('sessions:listTentativeSelectionsForSession', viewerArgs(s, host))).length === 0, 'empty snapshots'));
  await check('Return-to-lobby cannot spoof original host to steal room', () => rejects(() => m('sessions:returnToLobby', { session_id: s.id, player_id: ps[4].id, player_user_id: citizen.id, original_host_user_id: citizen.id, ...proof(citizen) })));
  // Restore actual host if the preceding negative case exposed an issue.
  const actual = await q('sessions:getSessionById', { session_id: s.id });
  if (actual.host_user_id !== host.id) await m('sessions:updateSessionHost', { ...hostArgs(s, citizen), new_host_user_id: host.id });
  await check('Host departure transfers ownership', async () => { await m('sessions:leaveSession', { session_id: s.id, user_id: host.id, ...proof(host) }); return expect((await q('sessions:getSessionById', { session_id: s.id })).host_user_id === mafia.id, 'oldest member is host'); });
  const capped = await room(host, [], 1);
  await check('Room capacity enforced', () => rejects(() => m('sessions:joinSession', { room_code: capped.s.room_code, user_id: outsider.id, player_name: outsider.display_name, ...proof(outsider) })));
  const abandoned = await room(host, []);
  await m('sessions:addPlayer', { ...hostArgs(abandoned.s, host), player_name: 'QA abandoned bot', is_bot: true });
  await m('sessions:updateSessionStatus', { ...hostArgs(abandoned.s, host), status: 'in_progress' });
  await phase(abandoned.s, host, 'night');
  await m('sessions:leaveSession', { session_id: abandoned.s.id, user_id: host.id, ...proof(host) });
  await check('Last human departure cancels bot-only room', async () => { const row = await q('sessions:getSessionById', { session_id: abandoned.s.id }); return expect(row.status === 'cancelled' || row.status === 'completed', { status: row.status, phase: row.current_phase, hostId: row.host_user_id }); });
  const statName = `QA ${runId}`;
  const stat = await m('stats:upsertPlayerStat', { user_id: host.id, player_name: statName, role: 'mafia', won: true, kills: 2, ...proof(host) }); saved.push(['stats:deletePlayerStat', stat.id, host]);
  await check('Stats increment and restore', async () => { await m('stats:upsertPlayerStat', { user_id: host.id, player_name: statName, role: 'doctor', won: false, kills: 0, ...proof(host) }); const row = await q('stats:getPlayerStat', { user_id: host.id, player_name: statName, ...proof(host) }); return expect(row.games_played === 2 && row.games_won === 1 && row.games_lost === 1 && row.total_kills === 2 && row.times_doctor === 1, 'two games, one win, one loss, two kills'); });
  await check('Stats deny another guest', () => rejects(() => q('stats:listPlayerStats', { user_id: host.id, ...proof(outsider) })));
  const group = await m('stats:createPlayerGroup', { user_id: host.id, group_name: 'QA audit group', player_names: ['A', 'B', 'C', 'D'], ...proof(host) }); saved.push(['stats:deletePlayerGroup', group.id, host]);
  await check('Saved group CRUD', async () => { await m('stats:updatePlayerGroup', { id: group.id, group_name: 'QA edited', player_names: ['A', 'B'], ...proof(host) }); return expect((await q('stats:getPlayerGroup', { id: group.id, ...proof(host) })).player_names.length === 2, 'edited group restored'); });
  const config = await m('stats:createCustomRoleConfig', { user_id: host.id, config_name: 'QA audit roles', role_distribution: { mafia_count: 1, doctor_count: 1, inspector_count: 1, citizen_count: 2, total_players: 5 }, ...proof(host) }); saved.push(['stats:deleteCustomRoleConfig', config.id, host]);
  await check('Saved role configuration restore', async () => expect((await q('stats:getCustomRoleConfig', { id: config.id, ...proof(host) })).role_distribution.mafia_count === 1, 'restored distribution'));
} catch (e) { results.push({ name: 'Campaign fatal error', status: 'ERROR', evidence: String(e.stack ?? e) }); }
finally {
  for (const [endpoint, id, u] of saved) await check(`Cleanup ${endpoint}`, () => m(endpoint, { id, ...proof(u) }));
  for (const { s, members } of rooms) {
    const current = await q('sessions:getSessionById', { session_id: s.id }).catch(() => null);
    const currentHost = users.find(u => u.id === current?.host_user_id);
    if (currentHost) await check('Cleanup cancel QA room', () => m('sessions:updateSessionStatus', { ...hostArgs(s, currentHost), status: 'cancelled' }));
    for (const u of members) await m('sessions:leaveSession', { session_id: s.id, user_id: u.id, ...proof(u) }).catch(() => {});
  }
  const report = { runId, url: client.url, timestamp: new Date().toISOString(), results, leftoverGuestProfileIds: users.map(u => u.id) };
  let safeReport = JSON.stringify(report, null, 2);
  for (const u of users) safeReport = safeReport.replaceAll(u.hash, '[REDACTED QA GUEST PROOF]');
  writeFileSync(process.env.CONVEX_AUDIT_OUTPUT ?? '/tmp/mafia-e2e-20261008/backend-results.json', safeReport);
  console.log(JSON.stringify({ passed: results.filter(r => r.status === 'PASS').length, failed: results.filter(r => r.status !== 'PASS').length }));
}
