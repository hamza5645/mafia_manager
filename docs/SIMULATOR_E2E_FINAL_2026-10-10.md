# Simulator migration E2E — 10 October 2026

The tested core flows pass after ten separately committed and pushed simulator follow-ups. Final native suite: **64/64 passed, zero skipped**. Backend: **45/45 passed**. TypeScript and the three production-configuration checks pass. This is evidence for the scenarios below, not a guarantee that every device, network condition, or possible game combination is defect-free.

## Environment and scope

- Branch `AWS`, PR [#4](https://github.com/hamza5645/mafia_manager/pull/4).
- Two iPhone 17 Pro simulators on iOS 27.0; app deployment target remains iOS 18.0.
- Debug automated integration runs use development Clerk/Convex with both live-test opt-in flags. Manual Release UI runs use production Clerk and `handsome-tiger-460.eu-west-1.convex.cloud`, contract 3.
- A fresh production QA account was created through the app with real signup and password-reset email codes. Credentials and codes were not committed.
- Changes to QA rooms and saved data were restricted to these test identities. Existing imported customer data was not edited by this campaign.

## Issues found and fixed

| Issue | Result | Commit |
|---|---|---|
| Cached Clerk identity restored before Convex authentication was installed | Token restoration precedes profile loading; repeated cold launches restore the account | `45e45ca` |
| Solo vote target retained at voter handoff; invalid votes accepted | Selection clears and store rejects self/dead/unknown/replacement votes | `05e2863` |
| Role-reveal ready flags permitted finishing an incomplete multiplayer night | Client and atomic backend require every living active role's current-round action | `4a52c54` |
| Password reset discarded pending guest-merge proof | Successful merge clears proof; failed merge retains it for retry | `3d6d101` |
| Rapid Online selection opened guest signup during account restoration | Online entry waits for restoration | `d52c097` |
| Empty roster treated as night-ready; live fixture omitted Police action | Absent roster fails closed; fixture includes all required role actions | `367c5f2` |
| Saved-group/custom-role request errors captured but never displayed | Both libraries show mapped errors and offer Reload | `671d51c` |
| Bots processed before assigned roles arrived and never retried | Refresh roster, recover missing round actions, preserve completed submissions | `1ca0733` |
| Partial Mafia-bot retry could choose a different cohort target | Missing teammate reuses the submitted Mafia target | `e83955e` |
| Lobby/active room re-entry rejected an existing member after restart | Verified identity restores the same seat and round; new mid-game entrants remain blocked | `0561247` |

Rollback and per-step validation are in [SESSION_CHANGES.md](SESSION_CHANGES.md). Earlier migration audit/fixes remain documented in [CONVEX_MIGRATION_FIXES_AND_RETEST.md](CONVEX_MIGRATION_FIXES_AND_RETEST.md).

## Coverage and observed outcomes

| Area | Simulator / automated evidence |
|---|---|
| Account lifecycle | Fresh production guest-to-account signup, real email verification, form dismissal, profile editing, repeated cold restoration, sign-out, wrong-password rejection, password sign-in, real reset code, automatic post-reset sign-in, old-password rejection, and reset-password sign-in passed. Pending-merge success/failure/retry paths have store regressions. |
| Guest identity and ownership | Creation/restoration, caller proofs, Clerk UUID restoration, guest/account merge ownership and active-room transfers are covered by live/native and isolated backend checks. |
| Solo gameplay | Saved four-player group and four-role preset loaded into a full local game. Role reveal, Mafia/Police/Doctor actions, morning reload persistence, death reveal, vote handoff, elimination, expected Citizen win, event log, Play Again, and cloud stats for all four names were checked. Invalid votes and winner/phase transitions are covered by store tests. |
| Multiplayer membership | Production create/join, invalid code, roster sync, kick/rejoin, host takeover during the long pause, cancellation, rematch, and lobby/active re-entry after force-quit were checked. The active re-entry kept the same Police role and round without another seat. Backend regressions cover full lobby, eliminated/readied member preservation, wrong proof, Clerk identity, late non-member rejection, and cancelled rooms. |
| Multiplayer night and privacy | Two-device role confirmation and human action gates, current-round completion, private peer projections, bot role processing, two-phase/atomic resolution, elimination, and shared morning state passed. Host retains its documented moderation visibility; non-host privacy is enforced by backend projections. |
| Bot match across rounds | Room 934779 completed three nights, voting/elimination, Doctor self-protection and a successful save in Night 2, game-over, and rematch. The Mafia result followed the existing bot-mode rule when all humans were eliminated. The rematch exercised a Police host with Doctor/Mafia bots. |
| Original stalled round | Room 315742 was not gone: the old active-join restriction had produced the earlier "not found" response. After re-entry was fixed, the original Citizen host returned, all independent Mafia/Doctor/Police bots completed, Finish Night enabled without a human action, and the same round resolved to Morning. Before/after images are saved. |
| Bot retry cases | Live Swift Testing cases verify stale role-less roster, existing Doctor action, missed human Mafia event, and partial Mafia-bot submission. Completed action targets/timestamps survive repeated readiness checks. |
| Saved data | Production group create/read/rename/delete passed. Custom preset create/read/count edit/delete passed (seven players changed to six). Disposable fixtures were deleted and empty libraries reloaded. Saved-library failure presentation was verified by source review, compilation, and existing error mapping tests; an OS-level outage was not forced. |
| Migration/configuration | Imported data parity and synthetic legacy profile claim remain verified by the earlier audit/backend tests. Current production values, release fail-fast guards, Date encoding, raw JSON arguments, authorization, projections, cancellation, merge/rematch, and compatibility are covered by the automated suites. |
| Production branding | After the user renamed the application, Clerk's public production environment reports `application_name: Mafia`. The default-name finding is resolved. A fresh email was not sent after the rename. |

## Evidence and artifacts

- [Final native summary](e2e-evidence/2026-10-10-simulator/final-swift-test-summary.json): 64 passed, 0 failed, 0 skipped.
- Native result bundle: `/tmp/mafia-final-reentry-full.xcresult`.
- Backend result log: `/tmp/mafia-reentry-backend-after.log` (45/45).
- [Simulator evidence](e2e-evidence/2026-10-10-simulator/) and [earlier solo/two-device evidence](e2e-evidence/2026-10-09-simulator/).
- Final signed archive: `/tmp/mafia-manager-release-final-20261010.xcarchive`.
- Final exported IPA: `/tmp/mafia-manager-release-final-export-20261010/mafia_manager.ipa`.
- Distribution signature, exact production configuration, team/application ID, Associated Domain, disabled debugging, and profile without device restrictions are verified in the artifact JSON saved alongside this report's evidence.
- [Production branding verification](e2e-evidence/2026-10-10-simulator/clerk-production-branding.json): Clerk reports the production application name as `Mafia`.
- No PR merge, App Store upload, or release submission was performed.

## Practical limits and remaining release checks

- A real existing migrated user's Clerk sign-in/restoration was not supplied. Synthetic legacy claiming and imported-row parity are verified; that real-user path remains unverified, as agreed when using a new QA account.
- Physical devices/TestFlight, iOS 18 runtime, iPad/landscape, and an OS-level network-disconnect campaign were not run. Simulator passes do not prove those environments.
- The reviewable code has passing local tests and the PR is mergeable. Production rollout confidence should include the remaining real-user/device checks above.

## QA cleanup

Rooms 934779 and 315742 were ended through the host UI; room cancellation/removal behavior is covered by backend tests. Disposable final CRUD group/preset fixtures were removed. QA profiles and the earlier QA saved-data fixtures remain available for retesting. Private test credentials stay only in mode-0600 temporary files/Keychain; no passwords, JWTs, or email codes were added to Git.
