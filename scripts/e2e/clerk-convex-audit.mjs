import { ConvexHttpClient } from 'convex/browser';
import { randomUUID, createHash, randomBytes } from 'node:crypto';
import { writeFileSync, readFileSync, mkdirSync } from 'node:fs';

// Native Clerk Frontend API paths/params match the installed ClerkKit sources.
// Only Clerk development test emails are used; no real verification email is sent.
const base = 'https://striking-elf-22.clerk.accounts.dev';
const convex = new ConvexHttpClient('https://energized-herring-345.eu-west-1.convex.cloud');
const resume = process.env.CLERK_AUDIT_RESUME === '1';
const outputDir = process.env.CLERK_AUDIT_DIR ?? '/tmp/mafia-e2e-20261008';
mkdirSync(outputDir, { recursive: true });
const credentials = resume ? JSON.parse(readFileSync(`${outputDir}/api-test-account.json`, 'utf8')) : { email: `mafia-qa-${Date.now()}+clerk_test@example.com`, password: randomBytes(24).toString('base64url') };
const results = [];
let deviceToken, clientId, sessionId, account;
if (resume) {
  ({ deviceToken, clientId, sessionId } = JSON.parse(readFileSync(`${outputDir}/api-test-session.json`, 'utf8')));
  account = { id: JSON.parse(readFileSync(`${outputDir}/account-results.json`, 'utf8')).accountId };
}
const fixtures = { guests: [], rooms: [], stats: [] };
async function clerk(path, body, method = 'POST') {
  const headers = { 'x-bundle-id': 'com.hamza5645.mafia', 'x-is-sandbox': 'true' };
  if (deviceToken) headers.Authorization = deviceToken;
  if (clientId) headers['x-clerk-client-id'] = clientId;
  if (body) headers['Content-Type'] = 'application/x-www-form-urlencoded';
  const response = await fetch(`${base}${path}?_is_native=true`, { method, headers, body: body ? new URLSearchParams(body) : undefined });
  const freshToken = response.headers.get('authorization');
  if (freshToken) deviceToken = freshToken;
  const data = await response.json();
  if (data.client?.id) clientId = data.client.id;
  if (data.response?.object === 'client') clientId = data.response.id;
  if (!response.ok || data.errors) throw new Error(JSON.stringify(data.errors ?? { status: response.status }));
  return data.response ?? data;
}
async function check(name, work) {
  try { const evidence = await work(); results.push({ name, status: 'PASS', evidence }); }
  catch (e) { results.push({ name, status: 'FAIL', evidence: String(e.message ?? e) }); }
  console.log(`${results.at(-1).status} ${name}`);
}
function expect(c, evidence) { if (!c) throw new Error(JSON.stringify(evidence)); return evidence; }
async function rejects(work) { try { await work(); } catch (e) { return String(e.message ?? e); } throw new Error('Request was accepted'); }
async function authenticate(id) {
  sessionId = id;
  await clerk(`/v1/client/sessions/${id}/touch`, {});
  const token = await clerk(`/v1/client/sessions/${id}/tokens/convex`, {});
  convex.setAuth(token.jwt);
  return JSON.parse(Buffer.from(token.jwt.split('.')[1], 'base64url').toString());
}
try {
  if (!resume) {
  const signup = await clerk('/v1/client/sign_ups', { email_address: credentials.email, password: credentials.password, first_name: 'QA Clerk Audit' });
  await check('Signup requests email verification', () => expect(signup.status === 'missing_requirements', { status: signup.status }));
  await clerk(`/v1/client/sign_ups/${signup.id}/prepare_verification`, { strategy: 'email_code' });
  await check('Signup rejects invalid verification code', () => rejects(() => clerk(`/v1/client/sign_ups/${signup.id}/attempt_verification`, { strategy: 'email_code', code: '000000' })));
  const verified = await clerk(`/v1/client/sign_ups/${signup.id}/attempt_verification`, { strategy: 'email_code', code: '424242' });
  await check('Signup verification creates active session', () => expect(verified.status === 'complete' && !!verified.created_session_id, { status: verified.status }));
  const claims = await authenticate(verified.created_session_id);
  await check('Convex JWT includes verified account email', () => expect(claims.email === credentials.email, { audience: claims.aud, emailPresent: !!claims.email }));
  account = await convex.mutation('users:ensureUser', { display_name: 'QA Clerk Audit' });
  await check('Authenticated signup creates nonanonymous Convex profile', () => expect(!account.is_anonymous && !!account.auth_subject, { id: account.id, isAnonymous: account.is_anonymous }));
  await check('Account restoration preserves profile UUID', async () => expect((await convex.query('users:getMe', {})).id === account.id, 'same UUID'));
  await check('Account profile update persists', async () => { await convex.mutation('users:updateProfile', { user_id: account.id, display_name: 'QA Edited Account' }); return expect((await convex.query('users:getUserProfile', { user_id: account.id })).display_name === 'QA Edited Account', 'edited name restored'); });
  await check('Account refresh preserves edited profile name', async () => expect((await convex.mutation('users:ensureUser', {})).display_name === 'QA Edited Account', 'edited profile name retained'));
  const name = 'QA Merge Collision';
  const accountStat = await convex.mutation('stats:upsertPlayerStat', { user_id: account.id, player_name: name, role: 'mafia', won: true, kills: 2 }); fixtures.stats.push(accountStat.id);
  const anonymous = new ConvexHttpClient(convex.url);
  const hash = createHash('sha256').update(randomUUID()).digest('hex');
  const guest = await anonymous.mutation('users:createOrRestoreGuest', { display_name: 'QA Merge Guest', guest_secret_hash: hash });
  fixtures.guests.push(guest.id);
  const guestStat = await anonymous.mutation('stats:upsertPlayerStat', { user_id: guest.id, guest_secret_hash: hash, player_name: name, role: 'doctor', won: false, kills: 0 }); fixtures.stats.push(guestStat.id);
  const room = await anonymous.mutation('sessions:createSession', { host_user_id: guest.id, guest_secret_hash: hash, bot_count: 0, max_players: 4 }); fixtures.rooms.push(room.id);
  const player = await anonymous.mutation('sessions:addPlayer', { session_id: room.id, user_id: guest.id, caller_user_id: guest.id, guest_secret_hash: hash, player_name: 'QA Merge Guest', is_bot: false });
  await check('Merge rejects invalid guest proof', () => rejects(() => convex.mutation('users:mergeGuestIntoAccount', { guest_user_id: guest.id, target_user_id: account.id, guest_secret_hash: 'wrong-proof' })));
  const merged = await convex.mutation('users:mergeGuestIntoAccount', { guest_user_id: guest.id, target_user_id: account.id, guest_secret_hash: hash });
  await check('Guest merge succeeds', () => expect(merged.success && merged.transferred_count === 1, { transferred: merged.transferred_count }));
  await check('Merge combines same-name player stats into one row', async () => { const rows = await convex.query('stats:listPlayerStats', { user_id: account.id }); return expect(rows.filter(r => r.player_name === name).length === 1, rows.map(r => ({ id: r.id, name: r.player_name, played: r.games_played }))); });
  await check('Merged stats remain readable and incrementable', async () => { const row = await convex.query('stats:getPlayerStat', { user_id: account.id, player_name: name }); await convex.mutation('stats:upsertPlayerStat', { user_id: account.id, player_name: name, role: 'citizen', won: true, kills: 0 }); return expect(row.games_played === 2, { played: row.games_played }); });
  await check('Guest upgrade preserves active room membership and ownership', async () => { const current = await convex.query('sessions:getSessionById', { session_id: room.id, viewer_user_id: account.id }); const players = await convex.query('sessions:getSessionPlayers', { session_id: room.id, viewer_user_id: account.id }); return expect(current.host_user_id === account.id && players.find(p => p.id === player.id)?.user_id === account.id, { oldGuestId: guest.id, accountId: account.id, hostId: current.host_user_id, playerOwnerId: players.find(p => p.id === player.id)?.user_id }); });
  await check('Upgraded account can leave its guest room', () => convex.mutation('sessions:leaveSession', { session_id: room.id, user_id: account.id }));
  await check('Merged room has no orphaned membership', async () => expect((await convex.query('sessions:getSessionPlayers', { session_id: room.id, viewer_user_id: account.id })).length === 0, 'no players remain'));
  await clerk(`/v1/client/sessions/${sessionId}/remove`, {});
  convex.clearAuth();
  await check('Unauthenticated account reads fail', () => rejects(() => convex.query('users:getUserProfile', { user_id: account.id })));
  await check('Sign-in rejects wrong password', () => rejects(() => clerk('/v1/client/sign_ins', { identifier: credentials.email, strategy: 'password', password: 'IncorrectPassword-QA-2026' })));
  const signin = await clerk('/v1/client/sign_ins', { identifier: credentials.email, strategy: 'password', password: credentials.password });
  await authenticate(signin.created_session_id);
  await check('Password sign-in restores original Convex account', async () => expect((await convex.mutation('users:ensureUser', {})).id === account.id, 'same UUID'));
  await clerk(`/v1/client/sessions/${sessionId}/remove`, {});
  }
  const reset = await clerk('/v1/client/sign_ins', { identifier: credentials.email });
  const factor = reset.supported_first_factors.find(f => f.strategy === 'reset_password_email_code');
  await clerk(`/v1/client/sign_ins/${reset.id}/prepare_first_factor`, { strategy: 'reset_password_email_code', email_address_id: factor.email_address_id });
  await check('Reset rejects invalid code', () => rejects(() => clerk(`/v1/client/sign_ins/${reset.id}/attempt_first_factor`, { strategy: 'reset_password_email_code', code: '000000' })));
  const codeResult = await clerk(`/v1/client/sign_ins/${reset.id}/attempt_first_factor`, { strategy: 'reset_password_email_code', code: '424242' });
  await check('Reset code requests new password', () => expect(codeResult.status === 'needs_new_password', { status: codeResult.status }));
  const oldPassword = credentials.password;
  credentials.password = randomBytes(24).toString('base64url');
  const completed = await clerk(`/v1/client/sign_ins/${reset.id}/reset_password`, { password: credentials.password, sign_out_of_other_sessions: 'false' });
  await authenticate(completed.created_session_id);
  await check('Password reset restores same Convex profile', async () => expect((await convex.mutation('users:ensureUser', {})).id === account.id, 'same UUID'));
  await clerk(`/v1/client/sessions/${sessionId}/remove`, {});
  await check('Old password no longer authenticates', () => rejects(() => clerk('/v1/client/sign_ins', { identifier: credentials.email, strategy: 'password', password: oldPassword })));
  const renewed = await clerk('/v1/client/sign_ins', { identifier: credentials.email, strategy: 'password', password: credentials.password });
  await authenticate(renewed.created_session_id);
  await check('New password authenticates', () => expect(renewed.status === 'complete', { status: renewed.status }));
} catch (e) { results.push({ name: 'Campaign fatal error', status: 'ERROR', evidence: String(e.message ?? e) }); }
finally {
  for (const id of fixtures.stats) await check('Cleanup QA stats', () => convex.mutation('stats:deletePlayerStat', { id }));
  for (const id of fixtures.rooms) await check('Cleanup QA account room', () => convex.mutation('sessions:cancelSession', { session_id: id, caller_user_id: account.id }));
  if (sessionId) await check('Revoke QA API session', () => clerk(`/v1/client/sessions/${sessionId}/remove`, {}));
  // Keep only the isolated development account for follow-up UI sign-in.
  const safe = JSON.stringify({ email: credentials.email, accountId: account?.id, timestamp: new Date().toISOString(), results, fixtures }, null, 2).replaceAll(credentials.password, '[REDACTED]');
  writeFileSync(`${outputDir}/${resume ? 'password-reset-results' : 'account-results'}.json`, safe);
  writeFileSync(`${outputDir}/api-test-account.json`, JSON.stringify(credentials), { mode: 0o600 });
  writeFileSync(`${outputDir}/api-test-session.json`, JSON.stringify({ deviceToken, clientId, sessionId }), { mode: 0o600 });
  console.log(JSON.stringify({ passed: results.filter(r => r.status === 'PASS').length, failed: results.filter(r => r.status !== 'PASS').length }));
  process.exitCode = results.some(r => r.status !== 'PASS') ? 1 : 0;
}
