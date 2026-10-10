## 2026-10-10 — final simulator campaign results

- Ten simulator follow-ups were fixed, reviewed, committed, and pushed separately (FOLLOWUP-10 through FOLLOWUP-19). Final native suite is 64/64 with zero skips; backend suite 45/45; TypeScript and three production configuration checks pass.
- Production UI covered real-email account lifecycle, cold account/active-room restoration, full solo play and stats, two-device gameplay, saved-data CRUD, and a multi-round bot match with a Doctor save, elimination, game-over/rematch. The original stalled Citizen-host round recovered all independent bot role actions and resolved successfully after the bot/reentry fixes.
- Development and production backends include the reentry fix. The final signed archive/IPA were built locally (not committed) from code commit 0561247. Distribution signature, production configuration, team/application ID and Associated Domain are verified. No merge or App Store upload occurred.
- The user renamed Clerk's production application to "Mafia". Its public native environment confirms that name and the production instance type, resolving the default-name finding. A fresh email was not sent after the rename.
- The campaign report and evidence were removed on 2026-10-10 (see git history). Do not treat simulator passes as proof for untested environments or real legacy account restoration.
- Rollback: revert individual fix commits in reverse order; regenerate with Tuist; deploy reverted Convex code for backend changes. No data/schema rollback is required for these follow-ups.

## 2026-10-10 — FOLLOWUP-19: restore an existing multiplayer seat after restart

- Production E2E reproduced rejected reentry in a lobby ("already in this game") and active games ("not found"). The latter was a status restriction, not proof the room had expired.
- The authenticated join mutation now returns the same verified member's seat before applying lobby/capacity checks. It preserves role, elimination, readiness, actor IDs, and current round while renewing online/heartbeat state. Non-members still cannot enter active/completed games, and cancelled rooms remain closed.
- Reentry responses use the existing server privacy projection. Added four backend regressions covering full lobby, active/dead member and private history, Clerk identity, and cancellation; three cases fail before the fix. Added a native Swift Testing guest reentry round-trip.
- Validation: backend 45/45, TypeScript check passes, full native suite 64/64 with zero skips. Deployed to development and production. Production QA room 934779 restored the seven-player lobby without duplicates; after another restart it restored the same Police role in Night 1, then resolved bot actions normally. Before/after role screenshots are saved with the campaign evidence.
- Rollback: revert this commit, regenerate Tuist, and deploy the reverted backend. No schema or request-shape change; reverting restores rejected reentry.
- Gotcha: rejoining restores a seat, not an extra player. It does not rename or revive the member. Automatic room navigation on app launch is not added; use the room code to re-enter.

## 2026-10-10 — FOLLOWUP-18: preserve the Mafia cohort target during partial retries

- Review of bot recovery found that a missing Mafia bot could choose a new target even when its teammate had already submitted. Recovery now reuses the submitted Mafia target while preserving completed actions.
- Added a fourth live bot scenario for partial Mafia submission. It asserts that the missing teammate follows the existing target and that readiness retries do not rewrite action timestamps.
- Validation: full simulator suite passes 63/63, zero skips; Release builds successfully. The preceding production bot match completed through three nights, a Doctor save, voting/elimination, game-over, and rematch.
- Rollback: revert this commit. No backend/schema changes or deployment required.
- Final steps: complete the final-build rematch check, regenerate distribution artifacts, and finalize campaign evidence.

## 2026-10-10 — FOLLOWUP-17: refresh bot roles and recover missing night actions

- Production simulator room 315742 with a Citizen host and six bots stalled on Night 1. A phase snapshot could arrive before assigned roles, allowing a role-less bot pass to be marked processed permanently.
- Night readiness now refreshes assigned players and recovers missing current-round bot actions. Completed targets/timestamps are preserved. Bot responses can follow an existing human action after a missed realtime event, and tracking resets by round rather than by retry.
- Added three live Swift Testing scenarios: stale roster, pre-submitted Doctor action, and pre-submitted human Mafia action without its realtime event. Both original cases fail before the fix; the final full suite passes 62/62 with zero skips. Tuist regenerated the project to add the test source; Release builds successfully.
- Production UI retest: the old room became unavailable during the pause. A fresh seven-player room (934779) with a Doctor host and six bots blocks Finish Night until the human action, then resolves to Morning with two Mafia bot actions, the Police bot check, and Doctor self-protection.
- Rollback: revert this commit and regenerate Tuist. No backend/schema changes or deployment required; reverting restores the bot-night stall.
- Final campaign steps still pending: complete the bot match, rebuild/export distribution artifacts from this fix, and finalize the PR report. Earlier IPAs predate this fix. The temporary approval-service usage failure was resolved before this retest.

## 2026-10-10 — FOLLOWUP-16: display saved-library request failures

- Source review found that Player Groups and Custom Roles captured load/delete failures in state but never rendered them, allowing a failed load to appear as an empty library.
- Both screens now display the mapped request error in an alert with Reload and OK actions. Existing data stays intact after failed deletes.
- Validation: full simulator suite with live Clerk/Convex integration flags passes 59/59, zero skips. Release rebuild and final artifact verification follow this commit. Production saved-group create/read UI passes; edit/delete checks are continuing.
- Rollback: revert this commit. No backend/schema or migration changes.
- Gotcha: alerts use the existing sanitized backend error mapping. An OS-level network-disconnect test has not been forced; the previously unreachable error presentation path is verified by code review and compilation.

## 2026-10-10 — FOLLOWUP-15: fail closed before the night roster loads

- Full-suite retest exposed a manual-night fixture that omitted its living Police bot action. Updated it to submit every required role action and seed the last known roster before exercising the delayed snapshot race.
- Readiness now rejects an absent/all-dead roster rather than treating an empty list as complete; Convex continues independently validating the real roster/actions.
- Validation: live manual-night integration and four Swift Testing readiness regressions pass (5/5). The initial full run was 57/58; a complete rerun is required after this correction.
- Rollback: revert this commit. No deployment or schema change; the guard is client-only.
- Gotcha: missing or failed roster reads must not enable Finish Night. The retained delayed-read test still asserts resolved atomic history and actual player death after all role actions exist.

## 2026-10-10 — FOLLOWUP-14: wait for account restoration before online entry

- A quick Online Game selection could open guest signup while the cached Clerk account was still restoring.
- Online entry now stays disabled with a progress indicator until restoration finishes; the action also guards the same boundary. Offline local play remains available during restoration.
- Validation: Release build succeeds; cold-launch production account is shown in Settings and online selection reaches Continue without the guest form. Full Swift run compiled this change and passed auth/restoration regressions; one unrelated manual-night fixture failure remains under investigation (57/58 passed).
- Rollback: revert this commit. No backend or migration changes.
- Gotcha: this uses the existing bounded restoration flow; users may briefly see a spinner before online play becomes available.

## 2026-10-10 — FOLLOWUP-13: preserve guest progress through password reset

- Password reset authenticated the account but unconditionally deleted the guest merge proof, leaving pending progress permanently unable to merge.
- Reset now retries a pending merge, matching sign-in behavior. A failed merge retains its Keychain proof for retry; a successful merge clears both pending state and proof.
- Validation: both new Swift Testing regressions fail before the fix and pass after it; existing auth regressions also pass (9 total). Backend suite 41/41 passes. Two-device production UI completed voting, citizen win, rematch, and cancellation before this change.
- Rollback: revert this commit. No schema or Clerk configuration changes.
- Gotcha: this prevents future proof loss; it cannot reconstruct a guest secret already discarded by an older build. Rebuild distribution artifacts after the final retest.

## 2026-10-10 — FOLLOWUP-12: require submitted actions before multiplayer night resolution

- Two-device production E2E reproduced a Finish Night button enabled while a live police guest had not submitted. Role-reveal ready flags were accepted as night completion evidence.
- Night readiness now requires matching current-round actions from every living active role, including the host and bots. Completion rechecks readiness; Convex independently rejects incomplete atomic resolution. New night/voting rounds clear human ready flags in the phase transaction, replacing delayed per-player resets.
- Validation: backend 41/41; TypeScript check passes; focused Swift readiness/realtime tests 7/7; Release simulator build succeeds; backend deployed to development and production and production contract 3 verified. Two-device retest with police host/Mafia guest keeps Finish Night disabled after only the host action, enables it after the guest action, and publishes the correct death/investigation. Evidence: `night-waits-for-guest-fixed.png` and `night-ready-after-all-actions.png`.
- Rollback: revert this commit, regenerate Tuist, and deploy the reverted backend together; this restores the premature-resolution defect. No schema or argument-shape change.
- Gotcha: signed archive/IPA must be rebuilt from the final tested code. Full simulator campaign is still in progress.

## 2026-10-09 — FOLLOWUP-11: reset and validate solo votes at each handoff

- Simulator E2E reproduced a retained target when moving from one solo voter to the next. The next player could confirm the previous target without selecting a card, including a self-vote.
- Voting now clears its local selection at handoff, enables confirmation only for a live eligible target, and advances only after an accepted store vote. `GameStore` rejects self-votes, unknown/dead participants, and attempts to replace locked votes.
- Validation: focused gameplay tests 24/24; full Swift suite with live integration flags 53/53, zero skips; Release simulator build succeeds. The real UI handoff shows Lock Vote disabled until selection; the four-role game completes with the expected citizen win and event log.
- Rollback: revert this commit and regenerate through Tuist. No backend/schema change; reverting restores the solo vote handoff defect.
- Gotcha: rebuild the signed distribution artifact after this fix. Full production multiplayer UI testing remains in progress.

## 2026-10-09 — FOLLOWUP-10: restore production account after cold launch

- Simulator E2E reproduced a production account mismatch: Clerk retained an active session after relaunch, but Settings displayed Login / Sign Up and another login returned “You’re already signed in.”
- `AuthService.currentUser` now installs cached Clerk authentication in Convex before loading the account profile. The bounded auth wait also checks Clerk environment/client readiness.
- Added three Swift Testing regressions for token-before-profile ordering, failed-token short circuit, and signed-out launch.
- Validation: focused auth tests 10/10, no skips; backend 39/39; production contract 3; Release simulator build succeeds; production account restored on two consecutive cold launches.
- Rollback: revert this commit and regenerate through Tuist; doing so reintroduces the observed startup race. No backend/schema change.
- Gotcha: the earlier signed archive/IPA predates this fix and must be rebuilt before distribution. Full simulator E2E remains in progress.

# Session Changes

## Convex audit fixes — 2026-10-08

Fixes are committed and pushed separately, in report order. The audit and retest
reports were removed on 2026-10-10 (see git history).

### Production real-email account and room checks — 2026-10-09

- Used the user-approved temporary inbox for one real production QA account.
  Actual signup/reset emails were delivered by the configured production domain.
  Browser access recovered and the reset OTP was read directly; no test mode or
  fabricated OTP was used. Expired signup verification was rejected correctly.
- Passed production native Frontend API signup, Convex JWT audience/email claims,
  authenticated profile creation, edited-name persistence, wrong-password rejection,
  sign-in/UUID restoration, password reset, old-password rejection, new-password
  sign-in and fresh-native-client login. These are API checks, not Swift UI passes.
- Production account/guest public-client smoke passed create/join, host permissions,
  kick/empty roster/rejoin, actual cancelSession, and membership cleanup. Two initial
  smoke probes had test-payload errors (missing caller ID, wrong cancellation
  endpoint); corrected to mirror the app's real calls, with no backend change.
- Cleaned all three own probe/smoke rooms; each is cancelled with zero memberships.
  All API sessions were revoked. The QA account and anonymous QA profiles remain.
  Private credentials/session files were removed; sanitized results are committed.
- Native UI signup reached email verification. Browser and simulator control then
  failed; restarting the stalled control daemon did not restore device automation.
  UI signup verification/sign-in/reset, full production gameplay and physical-device
  validation remain unverified. A real legacy account was not supplied.
- Production emails still identify the application as "My Application". Update
  Clerk branding to Mafia Manager before inviting users; this is a dashboard item.
- Rollback: these tests changed only their own QA profile/rooms, never the 142 legacy rows.

### Signed production archive and App Store export — 2026-10-09

- Account holder access is now available. Signed Release archive passed for team
  5GH22BAXAU, version 5.0/build 11. Exported the App Store IPA successfully.
- Verified archive and IPA signatures, exact production Convex host/key,
  application identifier, and `webcredentials:clerk.mafia.monitorthesituations.com`.
  The exported IPA uses Apple Distribution, disables get-task-allow, has an App
  Store profile without device restrictions, and includes Associated Domains.
- The archive and IPA stayed local (not committed). No upload or
  App Store submission was performed.
- Production Release UI signup reached real email verification and delivery was
  confirmed by the user. Browser and simulator automation services then became
  unavailable; the Verify tap could not be confirmed. API account checks are
  continuing with real OTPs. Do not count the incomplete UI flow as a pass.
- Rollback: remove local artifacts if superseded. No new application code or
  production data changes were required for signing. Keep the required domain
  entitlement and publishing team; historical signing blockers are resolved.

### FOLLOWUP-09: Release simulator architecture compatibility

- A real-production Release simulator build tried to link x86_64 and failed on
  ConvexMobile Rust symbols. Inspection confirms the installed Convex XCFramework
  provides only arm64 simulator/device/macOS slices. Exclude x86_64 for simulator
  builds through Project.swift, then regenerate with Tuist.
- Validation: the same Release simulator build failed before the setting and
  passed afterward. Production device archive/export already passed; the setting
  applies only to iphonesimulator. Apple Silicon simulator support is explicit;
  this SDK version does not provide Intel simulator support.
- User's signing selection remains 5GH22BAXAU through the manifest. Tuist
  regenerated the project; no direct .pbxproj edits were made by the agent.
- Rollback: revert the simulator exclusion and regenerate, restoring the Release
  simulator linker failure. No backend or durable data changes.

### Signing access diagnosis — 2026-10-09

- User confirmed team 5GH22BAXAU is an Individual membership. Their App Store
  Connect Admin role does not provide Apple Developer signing-resource access;
  Xcode therefore lists only their Personal Team for signing.
- Read-only Keychain check found two valid Apple Development identities and no
  Apple Distribution identity. Cached development/store profiles for 5GH22BAXAU
  lack Associated Domains. Correct-team archive retry still reports No Account
  for Team and missing Associated Domains in the profile.
- Resolution: account holder personally signs into Xcode on this Mac, or supplies
  an Apple Distribution identity with private key and an updated App Store
  provisioning profile for com.hamza5645.mafia with Associated Domains enabled.
  Keep the publishing team and Clerk App ID Prefix at 5GH22BAXAU.
- No certificates were created/revoked, no account permissions were changed,
  and no generated project edits were made by the agent. User's Xcode changes
  selecting Personal Team remain uncommitted. Backend/data setup is unaffected.

### Production Clerk/Convex configuration and data import — 2026-10-09

- Configured the user-provided `pk_live_` key and matching Clerk frontend host in
  Release settings. HTTPS issuer discovery now succeeds. User enabled Native API
  and registered the iOS application; published AASA lists
  `5GH22BAXAU.com.hamza5645.mafia`, matching the local provisioning prefix.
- Set production Convex `CLERK_FRONTEND_API_URL`, reviewed a dry-run, then deployed
  the backend to `handsome-tiger-460.eu-west-1.convex.cloud` with typecheck enabled.
  Production health passes API contract 3.
- Production was empty. Imported the validated saved export through internal
  migration mutations: 86 users, 48 stats, 6 configs and 2 groups. Preflight checked
  unique IDs/emails and owner references; insertion reported zero orphaned rows.
  Fresh production snapshots match every exported field and owner mapping.
- Validation: Tuist generation, actual-key configuration guard and all 3 guard
  regressions passed; unsigned Release device compilation passed. Generated app
  plist contains the exact production host/key. Signed archive failed because
  Xcode has no Apple account for team 5GH22BAXAU and the cached wildcard profile
  lacks Associated Domains. Requires Xcode Settings → Accounts sign-in and fresh
  provisioning; do not remove the required entitlement to bypass the failure.
- Remaining: signed archive, real production account/JWT/legacy-account checks,
  and physical-device E2E. Live legacy source is unavailable; parity establishes
  the saved export only. No development test fixture campaign ran on production.
- Raw production snapshots were kept private and never committed.
- Rollback: revert the production config commit to block Release again. Backend
  rollback must coordinate API contract 3 with the app. Restore the prior issuer
  only with a matching backend/client. Imported rows are new; remove only verified
  unclaimed/unmodified legacy rows if a data rollback is required, preserving any
  subsequent account claims and edits. Avoid rerunning imports after user edits.

### Clerk production DNS — 2026-10-09

- Directly accessed the authenticated Cloudflare zone for
  `monitorthesituations.com`. All five supplied Clerk CNAMEs were absent;
  none existed with a conflicting target. Added these DNS-only, TTL Auto:
  - `accounts.mafia` → `accounts.clerk.services`
  - `clerk.mafia` → `frontend-api.clerk.services`
  - `clk._domainkey.mafia` → `dkim1.dqnbqbamj40d.clerk.services`
  - `clk2._domainkey.mafia` → `dkim2.dqnbqbamj40d.clerk.services`
  - `clkmail.mafia` → `mail.dqnbqbamj40d.clerk.services`
- Validation: all five match exactly on both authoritative Cloudflare
  nameservers, and Cloudflare shows DNS-only for each.
- No existing DMARC TXT policy was found at the root or Mafia subdomain;
  no TXT value was supplied, so DMARC was not changed. Existing root/tunnel
  records were preserved. Clerk verification/certificates still need to be
  rerun in the dashboard; its shared-browser session is signed out.
- Rollback: remove only the five new CNAMEs above from the Cloudflare zone.
  App production key, native registration and Convex deployment remain pending.

### Production URL correction — 2026-10-09

- The production dashboard screenshot confirms the deployment's Cloud URL is
  `https://handsome-tiger-460.eu-west-1.convex.cloud`. Corrected the previously
  shortened host in Release configuration, setup docs and the guard fixture.
- Validation: release guard 3/3 passed; Tuist generation and diff review passed.
  Clerk production values remain empty; no production deployment was performed.
- Rollback: revert this host correction, restoring the incorrect shortened URL.

### Final retest and cleanup — 2026-10-09

- All final checks passed: Swift 48/48 (live Convex/Clerk, no skips), backend 39/39,
  fresh guest API 50/50, fresh account API 27/27, release guard 3/3, contract 3.
  Fresh private snapshots match all 142 saved-export rows and owners.
- Visible final pass verified first-tap night completion, Game Over, Play Again,
  sign-in/form dismissal/name restoration and sign-out. Two-device kick/cancel
  and voting/results/winner were verified earlier in the post-fix campaign.
- Ended final room 588567 and prior room 265275. Removed temporary credentials;
  sanitized evidence/report committed. QA development profiles remain.
- Known limits: production Clerk/Convex setup, real legacy account restoration,
  today's live legacy parity (DNS unavailable), physical iOS 26/iPad and extended
  disruption checks remain unverified. No production data was changed.
- Rollback: docs/evidence can be reverted independently. Revert issue commits
  with their tests; coordinate backend/client contract changes when rolling back.

### FOLLOWUP-08: Idempotent account sign-out

- Repeated native cleanup exposed Clerk's `signed_out` error. Treat that exact
  response as success and clear Convex authentication; other failures propagate.
  The native lifecycle regression now signs out twice before creating a guest.
- Validation: repeated sign-out failed before correction; full signed Swift
  suite passed 48/48 afterward with live Convex and Clerk flags and no skips.
  Signup, verification, restoration, reset, old-password rejection, guest upgrade,
  continuous subscriptions, concurrent night completion and solo tests passed.
- Rollback: revert the narrow error handling/regression. No data changes.

### FOLLOWUP-07: Retain the recorded night through reactive cache replacement

- Pass the phase-one record directly to atomic resolution. An older session
  snapshot can replace local night history after the record mutation completes;
  previously phase two could silently return with no outcome. Missing records
  now report a readable completion error. Test hooks are DEBUG-only.
- Validation: targeted live regression passed with history removed between the
  two phases; the full live Convex suite passed 10/10 with the new regression.
  The first full run exposed a separate repeated-sign-out setup failure; Clerk
  lifecycle is being corrected and the complete suite will be rerun.
- Rollback: revert direct record handoff and regression, restoring the cache race.
  No backend/schema or durable data changes.

### FOLLOWUP-06: Independent Settings authentication buttons

- Login and Sign Up inside a Settings List row could both fire, opening Sign Up
  when Login was tapped. Give the buttons explicit plain styling.
- Validation: signed simulator build passed; visible Login opened Sign In after
  reinstall. This is a UI routing correction with no backend/data change.
- Rollback: revert the button style, restoring ambiguous List button handling.

### FOLLOWUP-05: Readiness checks must not suppress night completion

- Final visible retest exposed a silent no-op: background readiness evaluation
  shared the night-completion lock. Split the locks, so an in-flight read cannot
  discard the host's Finish Night action. New readiness/resync work pauses during
  actual completion; duplicate completion remains serialized.
- Validation: live regression holds a background player read in progress.
  Before the fix it stayed in night with no outcome/death (3 failed assertions).
  After correction the same test passed (1/1), with atomic morning/death/history.
  Signed build and diff review passed. Room `457140` was ended in the UI.
- Rollback: revert the separate completion flag and concurrent regression,
  restoring the discarded-button race. No backend or durable data changes.

### FOLLOWUP-04: Private voting contract

- The visible voting screen promises private votes until everyone has voted;
  member queries previously returned peer actors/targets immediately. Confirmed
  votes now stay private until every living player submits, or results publish.
  Draft selections stay private to the actor/host. Host bot coordination and own
  vote confirmation remain available. Added a live API assertion.
- Validation: privacy regression failed before correction; 39/39 backend tests
  passed afterward across all four read paths, own/host access, and publication.
  Expanded real guest API campaign passed 50/50. Development typecheck passed.
- Rollback: revert filters/test expectations together, restoring the vote leak.
  No production or legacy data was changed.

### FOLLOWUP-03: Consolidate manual night completion

- Live store regression exposed the legacy `completeNightPhase` entry point:
  it wrote deaths/session state separately and left the record unresolved.
  Removed that path. Both the UI and manual entry point now use record-then-
  atomic-resolution, serialize concurrent completion, and show completion errors.
- Validation: regression failed before the fix and passed after it (1/1), with
  resolved history, the expected death, and morning transition. Signed build and
  source review passed. Visible voting/results/game-over/Play Again also passed.
- The earlier first UI tap stayed in night; retry advanced. Current UI source
  already used two-phase methods, so the specific first-tap cause was not proven
  by logs. Consolidation/error presentation improves verification and diagnosis.
- Rollback: revert the unified entry point/UI delegation. This restores the
  unsafe legacy path. Completed room `912498` was ended and cleaned in the UI.

### Retest tooling and fresh automated pass

- Audit campaigns now exit nonzero on failed assertions, use valid Swift
  phase/history fixtures, and clean account rooms/revoke API sessions. Added
  a private account-output directory override for UI follow-up.
- Validation: fresh account campaign passed 27/27 checks. The repeated full
  signed Swift suite passed 47/47 with all live/native flags enabled (no skips),
  including the guest auth-handoff monitor. Guest API campaign passed 49/49;
  it is rerunning after the final handoff change. Visible E2E follows.
- Rollback: revert audit-script changes; this only affects validation tooling.

### FOLLOWUP-02: Realtime auth handoff during guest upgrade

- The first full retest exposed a live handoff failure: Clerk profile creation
  made the guest roster disappear before merge and terminated action/selection
  subscriptions. Read viewers now retain proven guest authority through that
  window, then use the actual authenticated account after seat transfer. Mutation
  caller assertions remain strict; guessed viewer IDs/proofs cannot reveal roles.
- Validation: first full Swift run had 46 passed / 1 failed test (3 assertions)
  in the new native subscription monitor. After correction, that actual Clerk
  signup/merge subscription test passed (1/1), and 38/38 backend regressions passed.
  All 49 guest API checks passed before the handoff fix. Dev typecheck passed.
- The failed Xcode run completed assertions but hung collecting diagnostics;
  its own process was interrupted. Subsequent runs disable diagnostics collection.
- Rollback: revert viewer handoff and regressions; this restores false kicks
  during upgrade. No production or legacy data was changed.

### FOLLOWUP-01: Missing migration timestamps

- New regression fixtures exposed a preexisting valid-input failure: optional
  child timestamps were spread over required defaults; retries could also delete
  an existing creation timestamp. Insert defaults now take precedence and
  updates preserve the original creation date when it is omitted.
- Validation: all 6 timestamp regressions failed before the fix, then 36/36
  backend/migration regressions passed after it. Development typecheck passed.
  Tests cover stats, role configs, and groups, including idempotent retry identity.
- Rollback: revert timestamp ordering; missing-date imports will fail again.
  No production or legacy data was changed by these isolated tests.

### REVIEW-03: Guest-to-account form dismissal

- Login/password-reset forms observe authenticated account identity instead of
  the guest-inclusive authentication Boolean. Guest auth does not dismiss an
  account form; completing account auth does. Failed login keeps the form open.
- Validation: 7/7 Swift auth regressions passed, including guest/account signal
  transition and failed sign-in. Signed build and source/navigation review passed.
  The final visible E2E pass will verify actual sheet behavior separately.
- Rollback: revert the derived identity and observers, restoring the guest
  transition dismissal defect. No stored data or backend API changes.

### REVIEW-02: Migration parity and orphan verification

- Verification compares all source legacy IDs, every child owner mapping, and
  per-user legacy counts, while allowing fresh Convex rows. All child references
  are checked for missing users. An admin-only snapshot returns no personal
  fields. Added explicit saved-export mode and legacy-only table counts.
- Validation: 30/30 backend/migration regressions passed, including equal-count
  corruption, missing/duplicate IDs, claimed users, fresh data, and child orphans.
  Development typecheck passed. Export verification matched 86 users / 48 stats /
  6 configs / 2 groups. Live source remained unreachable and exited nonzero.
- A valid optional-timestamp ingestion input exposed a separate preexisting
  defect; tracked as FOLLOWUP-01 for a separate fix/regression.
- Rollback: revert verifier/audit query together. No durable data was changed.

### REVIEW-01: Separate production configuration

- Release reads a production xcconfig/Info.plist and has no dev fallback. A
  Tuist pre-build guard rejects missing/test keys, dev backend, and mismatched
  Clerk domains. Tuist generates associated-domain entitlements. Updated setup
  docs with the remaining production provisioning/deployment/data steps.
- Validation: 3/3 configuration regressions passed. An unconfigured Release
  build failed at the intended guard. Release device compilation passed with a
  synthetic key fixture (no production auth claims); signed Debug/native account
  lifecycle passed (1/1). One concurrent build attempt hit Xcode's DB lock;
  sequential validation succeeded.
- Production readiness: `handsome-tiger-460` has no deployed functions or Clerk
  issuer. Clerk dashboard was signed out; real production key/domain/registration
  remain required. No production configuration/deployment/data were changed.
- Rollback: revert manifest/config/scripts and regenerate with Tuist. This
  removes the release protection; never ship with the previous development key.

### E2E-14: End Game and empty-room cancellation

- Host End Game cancels the entire room and removes seats/actions/selections.
  Nonhosts leave their own seat. Last-human departure cancels bot-only/empty
  rooms, including creators whose seat creation failed. Completed outcomes are
  retained. Failed leave requests keep local connections intact for retry.
- Validation: 25/25 backend regressions and all 9 live Swift integration tests
  passed, including store-level End Game, empty roster, lifecycle, and kicking.
  Development typecheck and signed build passed; UI messages/actions reviewed.
- Rollback: revert cancellation mutation, auto-cancellation, and host UI action
  together. Deleted QA/game seats/actions cannot be restored by code rollback.

### E2E-13: Readable backend errors

- Convex query/mutation errors become safe localized messages at the service
  boundary. Known gameplay errors remain actionable; unknown validation/SDK
  payloads cannot leak into alerts. Realtime connection and voting errors use
  the same mapping. Added source/tests through Tuist generation.
- Validation: 5/5 Swift tests passed, including a real invalid-room SDK request
  and unknown-payload redaction. Signed build and diff review passed.
- Rollback: revert mapping and regenerated source registration through Tuist;
  this restores raw SDK errors in app alerts.

### E2E-12: Profile name persistence

- Routine Clerk synchronization preserves an existing Convex display name.
  Explicit names still update it. Legacy claims retain the saved name unless
  the caller explicitly supplies a replacement.
- Validation: 22/22 backend regressions passed; native Clerk lifecycle passed
  (1/1), proving edits survive refresh, password sign-in, and password reset.
  Development typecheck and signed build passed.
- Rollback: revert name selection. Previously overwritten names need manual
  restoration or a data backup; a code rollback cannot recover those values.

### E2E-11: Active room upgrade

- Guest merge transfers seat ownership, current host, and stored original host
  before deleting the guest. Player IDs/roles/actions stay intact. A conflicting
  account seat aborts the whole transaction with an actionable error. Snapshot
  comparison now propagates ownership-only changes into the local player.
- Validation: 20/20 backend regressions and 5/5 Swift tests passed, including
  native Clerk room upgrade/leave and ownership-only snapshot handling.
  Signed build and development typecheck passed. Audit reads now use account auth.
- Rollback: revert backend and client ownership handling together. Transferred
  references cannot be reversed after the guest is deleted without a data backup.

### E2E-10: Collision-safe guest stats merge

- Guest stats merge transactionally by account/player name, sum all eight
  counters, retain the stable account row (preferring legacy lineage), and delete
  source/duplicate rows. Earlier duplicate account rows are consolidated when
  that player is merged. Noncolliding rows transfer intact.
- Validation: 18/18 backend regressions passed, including preexisting duplicates
  and future upserts. Native Clerk/Convex account lifecycle passed (1/1) with
  real guest/account stats merge, combined counters, increment, and cleanup.
- Rollback: revert merge logic; already-combined counters cannot be separated
  by a code rollback. Keep pre-merge exports if a data rollback is needed.

### E2E-09: Rematch state guard

- Rematch requires `completed` status, the game-over phase, and a final game.
  Active games are rejected before any players, actions, or history are changed.
- Validation: 16/16 backend regressions passed, including unchanged active state
  on rejection and completed-game reset/cleanup. Development typecheck passed.
- Rollback: revert the guard, restoring the active-game reset vulnerability.

### E2E-08: Trusted original host ownership

- Convex stores the original host at room creation/game assignment. Play Again
  reclamation uses that stored identity and rejects spoofed legacy assertions.
  Swift no longer supplies or caches an authoritative original-host argument.
- Validation: 15/15 backend regressions passed; live Swift full lifecycle passed
  (1/1), including member-first lobby return and genuine host reclamation.
  Development typecheck and signed build passed.
- Rollback: optional stored ownership is backward compatible; revert server and
  Swift argument changes together. Old sessions safely default to their current
  host until the next game assigns the stored original host.

### E2E-07: Conditional atomic night resolution

- Atomic resolution requires the expected round, active night/index, valid
  elimination targets, and a final morning/game-over state. Identical retries
  are idempotent; changed or late requests cannot rewind phases or add deaths.
  Session reset clears resolution metadata. Client outcomes are applied only
  after the server succeeds; winner calculation uses projected deaths.
- Validation: 14/14 backend regressions and all 7 live Swift integration tests
  passed; signed build, development typecheck, and deployment check passed.
- Rollback: revert Swift arguments and backend validators/schema together.
  API contract is now 3; deploy matching clients/backend as a coordinated rollout.

### E2E-06: Server-side game action rules

- Submitted actions and tentative selections validate game status, current
  phase/index, actor life/role, and live session targets. Mafia cannot target
  teammates and inspectors cannot inspect themselves. Doctor self-protection,
  abstention/no-target actions, and current-round upserts remain supported.
  Role-readiness queries now count only the active round.
- Validation: 12/12 backend regressions and all 7 live Swift integration tests
  passed; development typecheck passed. Reviewed host/bot and human action paths.
- Rollback: revert action checks, restoring acceptance of invalid role/phase/
  target requests. Do not revert solely to work around a stale client snapshot.

### E2E-05: Private session history

- Room discovery returns a safe projection with no history, phase payload,
  role assignments, or round ID. Authenticated member snapshots retain published
  outcomes and typed public phase data; hosts and final-game members retain full
  records. Swift snapshot queries/subscriptions now send guest viewer proof.
- Validation: 4/4 backend regressions passed; all 7 live Swift integration tests
  passed, including model decoding, full lifecycle history, voting, and kicking.
  Development backend typecheck passed. Source review checked every Swift read.
- Rollback: revert client query arguments and backend projection together.
  Reverting only the client would deprive guest hosts of private resolution data.

### E2E-04: Action and selection privacy

- All four action/selection queries omit rows that would reveal another role.
  Own-role coordination, host resolution, public votes, and completed-game
  results remain available. Other inspectors cannot read an actor's result.
- Validation: 3/3 isolated regressions passed across all four query paths and
  host/actor/teammate/citizen visibility. Live Swift authorization test passed
  (1/1), updated to require citizens receive no Mafia actions. Dev typecheck passed.
- Rollback: revert backend filters and test expectation together; rollback
  restores the role-disclosure vulnerability.

### E2E-03: Kicked-player subscriptions

- Proven former members receive an empty roster, so the existing snapshot diff
  clears membership and dismisses the lobby. Outsiders receive no roster; invalid
  guest proofs still fail. Convex CLI regenerated server helpers for the SDK.
- Validation: 2/2 isolated backend regressions and the live Swift subscription
  removal test passed (1/1), including `wasKicked` and cleared player state.
- Rollback: revert the roster behavior; this restores the kick-detection defect.

### E2E-02: Voting advancement

- `showVotingResults` passes the viewer ID and guest proof. The voting alert now
  describes failure to finish voting accurately. The API audit uses the corrected
  call contract. Added a live store-level regression with a real guest room.
- Validation: signed simulator build and store-level live test passed (1/1),
  including the transition to `voting_results`; diff review passed.
- Rollback: revert this commit. No backend contract change is required.

### E2E-01: Deployment compatibility

- Added API contract 2 to the backend health response and the app configuration.
  Live Swift health coverage and `convex:verify-deployment` now fail when the
  selected backend is incompatible. Added isolated Convex regression tooling.
- Validation: backend compatibility regression, development deployment typecheck,
  and live deployment contract check.
- Rollback: revert the contract/check together. Guest-proof API rollout still
  requires coordinated client/backend deployment. Production is unchanged.

## Extensive Convex migration E2E audit — 2026-10-08

### What Changed

- Added a migration E2E report (removed 2026-10-10; see git history): 14 confirmed issues and 3
  source-review findings, with severity, reproductions, affected code, evidence,
  coverage limits, and test-data cleanup notes. No app/backend fixes were made.
- Added development-only public-client audit scripts for multiplayer/privacy/
  authorization/cloud data and Clerk account/merge/reset flows, plus a read-only
  saved-export parity checker (removed 2026-10-10).
- Added opt-in `ClerkAccountIntegrationTests.swift` for the actual native
  ClerkKit → ConvexMobile account lifecycle. `tuist generate --no-open`
  regenerated the project to include the source; the project file was not
  edited manually.
- Synchronized the existing branch's Convex functions to the configured
  development deployment. Initially its older API rejected the app's guest
  proof arguments. Production was not deployed or modified.

### Validation

- Normal signed Debug simulator build passed. Existing Swift tests passed
  35/35 after backend sync, including all 5 live Convex tests. The added native
  Clerk signup/verification/sign-in/restoration/reset test passed 1/1.
- Expanded backend audit: 49 assertions, 35 passed and 14 failed. Account/merge
  audit: 20 assertions, 15 passed and 5 failed. Password-reset audit: 5/5 passed.
  Failures are intentionally reported as unresolved product issues.
- Two-device guest UI covered creation, joining, realtime roster changes,
  kicking, roles, bot night actions, morning/death reveal, and voting. Kicking
  left the removed device stale; voting could not advance to results.
- Completed a full solo game, restored its completed state after relaunch,
  used Play Again, and verified cloud stats. Created/restored a guest player
  group.
- Every row in the saved legacy export matched current Convex legacy data:
  86 users / 48 stats / 6 role configs / 2 groups, including owner mappings.
  Live Supabase parity was blocked by `ENOTFOUND` for the configured source.

### Rollback

- Remove the new report/evidence, `scripts/e2e`, and the new Clerk test source,
  then run `tuist generate --no-open` to regenerate the project.
- Development backend sync deployed existing branch code, not a new fix.
  Reverting that deployment independently restores the app/API mismatch;
  coordinate any backend rollback with its client version.
- QA rooms and saved-data fixtures were cleaned as documented in the report.
  Guest profiles and two development Clerk accounts remain. The intentionally
  orphaned merge fixture was removed with a temporary internal mutation scoped
  to that exact QA fixture; the function was then removed and undeployed.

### Known Gotchas

- Full multiplayer UI game-over/rematch validation is blocked by the voting
  issue. Production configuration and a real legacy account claim remain
  unverified. The report separates API/native-service tests from visible UI
  journeys and lists other runtime/network/device limits.
- Xcode 27 beta AutoFill/system sheets interfered with UI account automation.
  The native Swift SDK test completed all account stages successfully.
- `CODE_SIGNING_ALLOWED=NO` builds could not store Keychain data on this
  runtime (`-34018`). Use a normal signed simulator build for guest/account UI.
- Audit scripts create isolated development data. Raw snapshots, credentials,
  and session tokens stay outside the repository; committed evidence is
  sanitized. Do not run fixture campaigns against production.

## Authentication, realtime, and migration regression fixes

### What Changed

- Protected Convex profile, stats, setup-data, player, session, action, and
  tentative-selection APIs now require either a matching Clerk identity or the
  anonymous row's `guest_secret_hash`. Human actions require player ownership;
  bot actions require the proven session host. Sensitive action/readiness data
  requires proven session membership, while room-code discovery stays public.
- Clerk token refresh events now fetch the `convex` JWT template and retain the
  last valid Convex token if refresh fails. Verification-free signup performs
  the same Clerk/Convex synchronization as verified signup, and Clerk's typed
  existing-email error routes into the existing-account merge flow.
- Guest upgrades persist pending merge work and Keychain proof until the merge
  succeeds. Failed merges expose Retry saving progress and Finish later, and an
  active account retries pending work during session restoration.
- Realtime player snapshots emit removals before replacing their cache. Other
  players disappear immediately; local removal clears player/role/number state,
  stops the session connection, sets `isInSession = false`, and marks the kick.
- Migration parity now counts every row with `legacy_supabase_user_id`, including
  Clerk-claimed rows. `listLegacyOrphans` remains the unclaimed-user report only.

### Validation

- Added XCTest coverage for Clerk error/token handling, verification-free auth
  synchronization, pending merge persistence/retry/cleanup, snapshot insertion,
  update and one-shot deletion, and local/remote player removal behavior.
- `node --check scripts/migration/verify.mjs` passed.
- `npx convex codegen --dry-run --typecheck enable` passed after adding the
  standard Convex TypeScript configuration and development compiler dependency.
- `tuist generate` and `tuist build mafia_manager` passed.
- `tuist test mafia_manager` passed 30 local tests; 5 live Convex security and
  integration scenarios were skipped behind `CONVEX_INTEGRATION=1` as intended.

### Rollback

- Roll back the fixed app and Convex functions together. Revert the guest-proof
  arguments and strict guards only with the matching Swift service/realtime
  changes; reverting one side alone breaks guest multiplayer and cloud data.
- Pending merge state is backward-compatible local data. A rollback may leave
  the Keychain secret and pending anonymous ID in place; do not delete them
  unless guest data has been merged or intentionally abandoned.

### Guest API Compatibility

- Existing account clients remain compatible because Clerk calls omit the
  optional guest hash. Older guest clients do not send proof and cannot use the
  newly protected endpoints. Production Convex and the fixed app must therefore
  ship as a coordinated rollout; do not deploy this backend ahead of the app.

## Final pre-App-Store revision: auth-config hardening, build bump, ETL verification

### What Changed

- `convex/auth.config.ts` now throws at deploy time when `CLERK_FRONTEND_API_URL`
  is unset instead of silently degrading to `providers: []`. Previously a prod
  deploy without the env var would ship a backend where Clerk sign-in silently
  authenticates nobody; now `npx convex deploy` fails with instructions.
- Bumped `CURRENT_PROJECT_VERSION` 10 → 11 in `Project.swift`. Both branches sat
  at 5.0 (10); App Store Connect rejects an upload reusing the live build number.
  Bumping `MARKETING_VERSION` (5.0 → 5.1?) is a product call left to the owner.

### Validation

- `npx convex dev --once` green after the auth.config change (dev has the var set).
- Post-regenerate: 26 unit tests (4 gated skips) 0 failures; live integration
  tests 4/4 against dev; Release **device** build (`-destination generic/platform=iOS`,
  the archive path) succeeds.
- Release build for `generic/platform=iOS Simulator` fails to link **x86_64**:
  upstream `convex-swift` ships `libconvexmobile.a` with an arm64-only simulator
  slice. Irrelevant to App Store archives (device arm64) and Apple-Silicon
  simulators; only Release-config runs on Intel-Mac simulators are affected.
- ETL verified complete against the live legacy database: restored the paused
  Supabase project `mafia-manager` (it was INACTIVE — the shipped app's backend
  was down) and compared counts: 86 auth users / 48 player_stats / 6
  custom_roles_configs / 2 player_groups exactly match the
  `legacy_supabase_user_id`-tagged rows already ingested in the dev deployment;
  row-level spot check of the heaviest user matched field-for-field. The
  Supabase project was left ACTIVE so the legacy app keeps working during rollout.

### Known Gotchas

- `tuist test` uses selective testing: with unchanged inputs it regenerates a
  pruned "for testing" project whose scheme has **no test action**, breaking
  subsequent `xcodebuild test` until `tuist generate` runs again. Drive tests via
  `xcodebuild test` after a plain `tuist generate` when you need a real run.

## Migration production-readiness review: build fix, backend fixes, live integration tests

### What Changed

- Fixed the broken build under Xcode 27 beta: Tuist maps the `convex-swift` package's
  `ConvexMobile` target to a product named `ConvexMobileWrapper.framework` while the
  module inside stays `ConvexMobile`, so `import ConvexMobile` failed module resolution.
  Added a `PackageSettings.targetSettings` override in `Tuist/Package.swift` forcing
  `PRODUCT_NAME=ConvexMobile`.
- Restored host role visibility in `convex/lib.ts` (`visiblePlayerForViewer`). The
  prior authorization-hardening pass hid all roles from the host, but the host client
  is the authoritative game master: it drives bot actions (`processBotActions`),
  evaluates win conditions (`evaluateWinners` counts alive mafia), and records
  revealed death roles. With roles hidden, a non-mafia host ended every game as
  "citizens win" after the first night and role-holding bots never acted. This
  matches the Supabase `get_visible_role` contract on main.
- `sessions:returnToLobby` now deletes the previous game's `game_actions` and
  `tentative_selections` (parity with Supabase `reset_session_to_lobby`). Without
  this, a Play Again game shared `phase_index` values with stale rows, which leak
  into `checkNightPhaseReadiness` (loads actions without `round_id`) and bot
  coordination.
- `migration:countByTable` and `migration:listLegacyOrphans` are now
  `internalQuery`. `listLegacyOrphans` returned legacy users' emails to any
  unauthenticated client. The migration scripts use `setAdminAuth`, so they can
  still call internal functions.
- Added `mafia_managerTests/ConvexIntegrationTests.swift`: live integration tests
  against the dev deployment through the real client stack (ConvexMobile FFI,
  arg encoding, model/date decoding, reactive subscriptions). Skipped unless the
  runner env sets `CONVEX_INTEGRATION=1`
  (`TEST_RUNNER_CONVEX_INTEGRATION=1 xcodebuild test ...`).

### Validation

- `tuist build mafia_manager` succeeded (Xcode 27 beta).
- `tuist test mafia_manager`: 22 unit tests passed, 4 integration tests skipped by default.
- `TEST_RUNNER_CONVEX_INTEGRATION=1 xcodebuild test -only-testing:mafia_managerTests/ConvexIntegrationTests`:
  4/4 passed against dev (health, guest restore idempotency, full multiplayer
  lifecycle incl. stale-round rejection and `resolveNightAtomic`, live subscription
  delivering phase updates).
- Backend functional campaign over `mcp__convex__run` (15 scenario groups): role
  privacy per viewer, save-beats-kill, inspector mafia/not_mafia/blocked, stale
  round rejection, non-host resolve/kick/life-status rejections, host transfer on
  leave + heartbeat-guarded host claim, voting upsert + game over, returnToLobby
  reset with action cleanup, executeRematch, stats upsert increments, health checks.
- `npx convex dev --once` pushed all changes to the dev deployment.

### Rollback

- Revert `Tuist/Package.swift` (build fix), `convex/lib.ts`, `convex/sessions.ts`,
  `convex/migration.ts`, and delete `mafia_managerTests/ConvexIntegrationTests.swift`.

### Known Gotchas

- Xcode 27 beta replaced Simulator.app with DeviceHub and moved SimulatorKit to
  `Contents/SharedFrameworks`; simulator HID automation (idb/XcodeBuildMCP/Xcode
  device interaction) is currently broken, so UI-level E2E remains manual. A
  symlink was added at
  `Xcode-beta.app/Contents/Developer/Library/PrivateFrameworks/SimulatorKit.framework`
  to restore idb screenshots/accessibility (taps still no-op on this beta).
- The prod Convex deployment (`handsome-tiger-460`) has never been pushed and the
  app still hardcodes the dev URL + `pk_test_` Clerk key in `ConvexConfig.swift`.

## Multiplayer Convex authorization hardening

### What Changed

- Restricted exported Convex player insertion so direct human adds require the session host to add only themselves while the session is waiting, with duplicate and capacity checks preserved.
- Routed host kicks through the host-only `sessions:removePlayer` mutation for both human players and bots.
- Tightened lobby reset so `sessions:returnToLobby` verifies the caller owns the player record in the session and only resets after game over.
- Removed host status as a role/action visibility override so active host players do not receive secret roles or other inspectors' results before game over.

### Validation

- `tuist build mafia_manager` succeeded after the security fixes.
- `tuist test mafia_manager` succeeded with 22 tests and 0 failures.
- `npx convex dev --once` and local `convex codegen --dry-run --typecheck enable` could not run here because the Convex CLI attempted external network authorization/telemetry and network access was blocked.

### Rollback

- Revert the `convex/sessions.ts`, `convex/lib.ts`, and `Core/Multiplayer/Store/MultiplayerGameStore.swift` changes if this hardening must be backed out.

### Known Gotchas

- Guest quick-play still uses the existing asserted app user ID model; these fixes prevent the reviewed regressions without replacing guest identity verification.

## Backend migration: Convex + Clerk

### What Changed

- Replaced the active backend dependency and service layer with Convex + Clerk.
- Added Convex schema/functions for users, stats, saved setup data, multiplayer sessions, players, actions, tentative selections, and atomic night resolution.
- Replaced account auth with Clerk-backed `AuthService` while preserving guest quick-play through Convex guest profiles.
- Replaced multiplayer realtime with Convex reactive query subscriptions.
- Removed legacy backend setup SQL, obsolete auth workaround docs, and old Xcode mutation scripts.
- Updated active docs and privacy copy to describe Convex + Clerk.
- Configured Clerk with the real publishable key and Convex Frontend API URL for the dev deployment.

### Validation

- `npx convex env list` shows `CLERK_FRONTEND_API_URL=https://striking-elf-22.clerk.accounts.dev` on the dev deployment.
- `npx convex dev --once` succeeded with Clerk auth config.
- Convex MCP `health.js:check` returned `{ ok: true, backend: "convex", version: "convex-clerk-v1" }`.
- `tuist generate` succeeded after the Tuist dependency/project changes.
- `tuist build mafia_manager` succeeded.
- `tuist xcodebuild test -workspace mafia_manager.xcworkspace -scheme mafia_manager -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` succeeded with 22 tests and 0 failures.

### Rollback

- Reverting this migration requires restoring the deleted legacy backend files, the previous Swift service implementations, and the previous Tuist dependency graph.
- Do not attempt rollback by hand-editing `.pbxproj`; use Tuist manifests and regenerate.

### Known Gotchas

- Account auth now initializes against Clerk project `striking-elf-22`.
- Guest multiplayer role visibility depends on passing the current Convex app user ID to `sessions:getSessionPlayers`.

## MM-17: Solo vote elimination reveal

### What Changed

- Added a new solo `voteDeathReveal` phase so daytime eliminations pause on a reveal screen instead of jumping straight from vote results into the next night.
- Updated `GameStore.applyVotingResult()` to route actual vote eliminations through that reveal phase while keeping tie/no-elimination days on the existing direct-to-night path.
- Reused `DeathRevealView` for both night kills and vote eliminations with context-specific copy and continue behavior.
- Updated `VoteResultsView` so the primary button reflects the new reveal step when a player was actually eliminated.
- Added `GameStore` regression tests for:
  - vote elimination entering the reveal phase,
  - continuing from that reveal into the next night,
  - continuing from that reveal into game over when the final mafia is voted out.

### Validation

- Xcode project build succeeded after the phase-routing and UI changes.
- CLI `xcodebuild test` and Xcode-hosted targeted test execution both stalled in this session before producing a usable XCTest summary, so the new tests were added but not fully observed completing here.

### Rollback

- Revert the `voteDeathReveal` phase and restore the old `applyVotingResult()` behavior if you want vote results to advance directly into the next night again.

### Known Gotchas

- `DeathRevealView` now serves two solo contexts. If you change its copy or continue action later, verify both night deaths and vote eliminations still route correctly.

## MM-02: Persist multiplayer doctor saves across two-phase resolution

### What Changed

- Added `target_was_saved` to multiplayer `night_history` records so phase 1 persists the authoritative doctor-save verdict.
- Updated `MultiplayerGameStore.recordNightActions()` to store that verdict and bias `doctorProtectedId` toward the mafia target whenever any doctor actually saved them.
- Updated `MultiplayerGameStore.resolveNightOutcome()` so phase 2 resolves from the stored verdict instead of recomputing from `doctorProtectedId`.
- Added a compatibility fallback for unresolved legacy records: if `target_was_saved` is missing and the session is still on that active night, the host re-reads doctor actions for the current round before falling back to `doctorProtectedId == mafiaTargetId`.
- Updated multiplayer summaries to use `target_was_saved` when available so saved nights are reported consistently.

### Validation

- Built the multiplayer resolution path around the persisted phase-1 verdict to remove the split-doctor mismatch identified in MM-02.
- Planned manual verification for split protections, no-save nights, unanimous-save nights, and unresolved legacy records that predate `target_was_saved`.

### Rollback

- Revert the `NightActionRecord` schema addition and restore the old `resolveNightOutcome(nightIndex:targetWasSaved:)` call path if you intentionally want phase 2 to recompute saves from the summarized doctor target again.

### Known Gotchas

- This is fix-forward for new records plus unresolved legacy nights. Already-resolved historical rows that only stored a non-saving `doctorProtectedId` cannot be reconstructed after the fact.

## MM-01: `resolve_night_atomic()` snake_case fix

### What Changed

- Patched `public.resolve_night_atomic()` in `supabase/multiplayer_schema.sql` to read `night_index` first and tolerate legacy `nightIndex` only as a fallback.
- Added migration `supabase/migrations/20260321110000_fix_resolve_night_atomic_json_keys.sql` so existing Supabase projects can deploy the RPC fix without re-running the full schema.
- Hardened the RPC so malformed night payloads raise an error instead of silently nulling `night_index` and collapsing `night_history`.

### Validation

- Confirmed the Swift multiplayer payload already encodes snake_case keys, so no app-facing contract changes were required.
- Verified against the connected Supabase project that the pre-fix live RPC still used camelCase lookups and matched the audit's live data anomaly counts.
- Planned SQL verification after migration application to confirm prior `night_history` rows are preserved and `removal_note` receives a real night number.

### Rollback

- Re-apply the previous function body if you intentionally need the old behavior, though it will reintroduce history corruption for snake_case payloads.

### Known Gotchas

- MM-01 is fix-forward only. Sessions whose `night_history` was already collapsed before this patch are not reconstructed by this change.

## What Changed

- Reorganized the app entry point into `App/mafia_managerApp.swift`.
- Reworked `Core/` into domain folders:
  - `Core/Auth/`
  - `Core/Backend/`
  - `Core/Gameplay/`
  - `Core/Multiplayer/`
  - `Core/Stats/`
  - `Core/Support/`
- Split multiplayer views into clearer flow buckets:
  - `Features/Multiplayer/Entry/`
  - `Features/Multiplayer/Flow/`
- Moved the non-project `SupabaseConfig.swift.template` into `Core/Backend/`.
- Updated `AGENTS.md`, `docs/CLAUDE_PRIMER.md`, and `docs/ARCHITECTURE_NOTES.md` to match the new paths.

## Why

- The previous layout mixed technical buckets (`Models`, `Services`, `Store`) with feature-specific code, which made multiplayer/auth/stats ownership harder to follow.
- Several Xcode navigator entries were effectively stale or duplicated after earlier iterations. Moving files through Xcode-safe project operations normalized the navigator and kept the project buildable.
- Multiplayer screens were all flat in one folder; splitting entry vs in-game flow makes future changes less error-prone.

## Validation

- Rebuilt the project through Xcode after the moves.
- Result: successful build with the reorganized structure.

## Rollback

- To revert the structure, move files back to their previous paths using Xcode project moves, not raw `.pbxproj` edits.
- If you want a full rollback with Git, revert this changeset rather than manually dragging files around in Finder.
- If a future move affects target membership or file references, validate with an Xcode build immediately after the move batch.

## Known Gotchas

- This project’s Xcode navigator had path drift before the cleanup. Use Xcode-aware moves for source files so the project file stays consistent.
- The repo still contains a duplicate on-disk `mafia_manager/Assets.xcassets` folder that was not touched in this session because the active target is already building successfully and that asset cleanup should be done as a separate verification pass.

## Audio preloading via SoundManager

### What Changed

- Created `Core/Gameplay/Services/SoundManager.swift` — a `@MainActor` singleton that preloads all 4 `.wav` sound files (`mafia_gunshot`, `police_siren`, `doctor_ecg`, `wakeup_rooster`) at startup via an explicit `warmUp()` call.
- `warmUp()` is called from `App/mafia_managerApp.swift` `.onAppear`, well before any sound is needed. Guarded by `hasWarmedUp` flag so repeat calls are free.
- Audio session is re-configured defensively before each playback (`ensureAudioSession()`), with a cheap early-return when already active. Handles session deactivation after backgrounding.
- Each sound file is preloaded independently — one missing/corrupt file does not break the others.
- Removed all inline audio code from `NightWakeUpView.swift` (~45 lines) and `MorningSummaryView.swift` (~30 lines). Both now delegate to `SoundManager.shared`.
- Removed duplicate `configureAudioSessionIfNeeded()` implementations from both views.
- Added `SoundManager.shared.handleBackgrounding()` to the app's background lifecycle handler.

### Why

- Instruments Time Profiler showed `AVAudioPlayer.__allocating_init(contentsOf:)` costing 84ms+ on the main thread at each play site. Preloading eliminates this hitch entirely.
- Audio code was duplicated across two views with no shared service.

### Validation

- Build succeeds (`Cmd+B`).
- Solo night flow: mafia gunshot plays after 2s "Start Night" delay, inspector siren on inspector wake, doctor ECG on doctor wake — no perceptible delay.
- Morning summary: rooster plays on appear.
- Background/foreground: sounds still play after returning from background.

### Rollback

- Delete `Core/Gameplay/Services/SoundManager.swift`, revert `NightWakeUpView.swift`, `MorningSummaryView.swift`, and `App/mafia_managerApp.swift` to restore inline audio code.

### Known Gotchas

- `SoundManager.swift` must be added to the Xcode project manually (not auto-added via .pbxproj edit).
- `MultiplayerVoteDeathRevealView.swift` uses `AudioServicesPlaySystemSound(1057)` — different mechanism, intentionally not touched.
- Persistence main-thread work (`GameStore` → `Persistence.save`) is a separate perf concern for a future pass.

## MM-04 through MM-16 remediation pass

### What Changed

- Fixed solo rules regressions:
  - Mafia now wins at parity after night resolution.
  - Tied day votes now record a no-elimination day, increment `dayIndex`, and re-run winner evaluation.
  - Solo inspector-on-inspector checks no longer leak a role through the UI.
  - Morning summary no longer labels the first night as “Night 2”.
- Fixed multiplayer app-side issues:
  - Voting readiness now keys off actual submitted votes instead of `isReady`.
  - Night death reveal now stores explicit revealed death roles instead of inferring from who submitted actions.
  - Game-over UI now falls back to `currentPhaseData` for winner rendering.
  - Entering `game_over` now forces a player snapshot refresh so newly visible roles can appear once the backend allows them.
  - Inspector UI now only shows `mafia`, `not_mafia`, or `blocked`.
- Fixed schema/migration drift in repo:
  - Added checked-in definitions/migrations for `add_session_player` and `reset_players_ready`.
  - Normalized `submit_game_action` inspector results.
  - Extended `resolve_night_atomic` so game-over winner fields are written atomically with the phase transition.
  - Fixed optional performance RPCs so `batch_assign_roles` accepts real JSONB payloads and no longer writes a nonexistent `updated_at` column.
- Re-enabled the automated test path:
  - Added a real `mafia_managerTests` target to the Xcode project.
  - Added the test target to the shared scheme.
  - Added a regression test covering tied-vote day advancement.
- Updated docs:
  - Multiplayer guide no longer claims `phase_timers` exists.
  - Architecture notes now describe the corrected inspector behavior.
  - Audit statuses now distinguish repo fixes from still-pending live Supabase deployment.

### Validation

- Xcode build succeeded after the changes.
- `xcodebuild -project mafia_manager.xcodeproj -scheme mafia_manager -destination "platform=iOS Simulator,name=iPhone 17 Pro" test` now succeeds with 17 passing tests.
- Live Supabase inspection confirmed the deployed DB is still on the old function bodies for `get_visible_role`, round-aware `submit_game_action`, `resolve_night_atomic`, and `batch_assign_roles`.
- Attempting to apply the new DB migrations through the Supabase MCP failed because the connected project is exposed in read-only mode in this session.

### Rollback

- Revert the app/code changes if you want to restore the audited behavior, though that will reintroduce the bugs documented in `docs/AUDIT_2026-03-20.md`.
- Revert the Xcode project changes if you intentionally want to disable the test target again.
- Revert the new Supabase migration files if you do not want the backend contract upgrades queued for deployment.

### Known Gotchas

- The repo is fixed; the deployed Supabase project is not fully fixed until the new migrations are applied with write access.
- `submit_game_action` is overloaded in the live DB, and the round-aware overload used by the app is still the old leaking version until deployment happens.
