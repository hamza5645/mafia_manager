# Convex migration fixes and retest — 2026-10-09

> Later production setup is recorded in [Clerk setup status](CLERK_SETUP.md#production-setup-status--2026-10-09)
> and [Session changes](SESSION_CHANGES.md). The audit below reflects tested code
> `76e84bb` and its environment at the time; production configuration/deployment
> and saved-export import have since been completed.

The 14 confirmed audit issues and three source-review findings have code fixes,
committed and pushed individually to `origin/AWS`. Retesting found eight further
issues; those were also fixed in separate commits. All final automated development
checks passed. Production configuration and genuine legacy-account restoration
remain prerequisites for publishing, as described below.

The [original audit](CONVEX_MIGRATION_E2E_REPORT.md) is the before-fix record.
[Session changes](SESSION_CHANGES.md) contains per-fix validation, rollback notes,
and gotchas. This report describes the resulting behavior, not a guarantee that
no undiscovered issue exists.

## Final verification

Code tested: `76e84bb369b3684144eab7331f7062403fcea44b`. Development backend:
`energized-herring-345`; Clerk development instance: `striking-elf-22`.
Two signed iOS 27 simulator installations were used. The installed Tuist version
uses `build`/`test` for inspection, so the project was generated with Tuist and
built/tested through Xcode. No `.pbxproj` was edited directly.

| Check | Final result | What it establishes |
| --- | --- | --- |
| Full signed Swift suite | **48/48 passed, no skips** | 22 solo tests, 10 real Convex integration tests, native Clerk lifecycle, auth/store/realtime/error regressions |
| Convex/migration regression suite | **39/39 passed, 17 files** | Authentication boundaries, role/vote privacy, eligibility, stale resolution, rematch, merge, ownership verification, migration timestamp defaults |
| Fresh public-client guest API campaign | **50/50 passed** | Guest restoration, room lifecycle, privacy/permissions, night/voting rules, saved data, cancellation and fixture cleanup |
| Fresh Clerk/account API campaign | **27/27 passed** | Signup verification, JWT email claim, restoration, edited name, merge/collision handling, active seat transfer, sign-in/reset and cleanup |
| Release configuration guard | **3/3 passed** | Reject missing/test keys and wrong/mismatched domains; accept valid fixture configuration |
| Development deployment compatibility | **Passed: contract 3** | Client and deployed backend agree on the API contract |
| Saved export against fresh Convex snapshots | **142/142 legacy rows match** | 86 users, 48 stats, 6 role configurations, 2 groups; zero missing/duplicate IDs, field mismatches or owner errors |

The Swift lifecycle uses the real ClerkKit and Convex Swift SDKs. It creates a new
Clerk development account, verifies email, restores/edits its profile, upgrades a
guest while live subscriptions remain active, transfers its active room, signs in,
resets the password, rejects the old password, accepts the new one and signs out.
The night regression holds a readiness read open and replaces local history with
an older snapshot between record and resolution; the final atomic outcome still
publishes the expected death, resolved record and morning phase.

Two intermediate retest failures were corrected before the final pass: repeated
Clerk sign-out returned `signed_out`, and the night path depended on mutable local
history. The final suite has neither failure. Earlier simulator verification was
kept separate from XCTest on the same device to avoid account-state interference.

## Visible simulator checks

- Two-device guest creation/join updated both rosters. Kicking the guest dismissed
  its stale lobby; rejoining worked. Host End Game dismissed both clients. Joining
  the cancelled room displayed a readable message.
- Host voting reached results, applied elimination, revealed the death, reached
  Citizens Win and returned to a reset lobby through Play Again.
- After the final night fix was installed, a single Finish Night tap completed the
  outcome in room `588567`. The last human died, so the existing bot-only completion
  rule produced Mafia Win. Play Again restored the five-player host lobby with
  cleared roles. A second night completion also advanced on its first tap.
- Settings Login opened Sign In after correcting the List button behavior. A newly
  created development account signed in through the visible form, dismissed it,
  restored `QA Edited Account`, and signed out through Profile.
- The final visible room was ended; its public snapshot reports `cancelled` and
  phase `cancelled`. Earlier room `265275` was also ended.

[Screenshots and sanitized assertion results](e2e-evidence/2026-10-09-retest)
include kick/cancellation, voting, game-over, first-tap night completion, rematch
reset and account restoration. Voting/kick screenshots are from the post-fix
campaign before the final two app-only fixes; first-tap/rematch/sign-in evidence
is from the final simulator pass. Password reset/signup are established by native
SDK and API E2E, not a new complete visible reset/signup walkthrough.

Solo gameplay was unchanged by these corrections. All 22 solo tests were rerun
and passed. The earlier visible complete solo game, persisted restoration,
rematch, statistics and saved-group restoration are recorded in the original
audit; that full solo UI journey was not repeated in this final pass.

## Issue-to-commit review

| Issue | Resulting behavior | Commit |
| --- | --- | --- |
| E2E-01 | Deployment health exposes the API contract; compatibility check fails on mismatch | `014845f` |
| E2E-02 | Voting-results reads carry authenticated viewer/proof | `e14d047` |
| E2E-03 | Valid kicked viewers receive removal snapshots; outsiders cannot spoof access | `8ba9787` |
| E2E-04 | Secret role actions/drafts are filtered server-side across all read paths | `cf529ad` |
| E2E-05 | Public discovery exposes room metadata; member history follows viewer permissions | `88535ff` |
| E2E-06 | Actions/drafts require the correct phase, round, living actor, role and legal target | `e78b66a` |
| E2E-07 | Atomic night resolution rejects stale/conflicting retries and retains idempotence | `749b8e7` |
| E2E-08 | Rematch host restoration trusts stored original-host identity | `f87e3f4` |
| E2E-09 | Rematch requires a completed game before resetting data | `19a657e` |
| E2E-10 | Guest/account stats consolidate into one readable, incrementable row per name | `342fcce` |
| E2E-11 | Guest upgrade transfers active membership and room ownership before deleting the guest | `df3d8d9` |
| E2E-12 | Refresh/sign-in preserve edited and migrated profile names | `2807d78` |
| E2E-13 | Backend errors become readable messages; unknown SDK payloads stay out of alerts | `f703988` |
| E2E-14 | Host End Game cancels the room; last-human departure cleans abandoned rooms | `dfba58e` |
| REVIEW-01 | Release has separate production settings and fails closed until valid configuration | `291981e` |
| REVIEW-02 | Migration verification checks legacy IDs/ownership without counting fresh rows as corruption | `5f0297b` |
| REVIEW-03 | Login/reset dismissal observes account identity rather than guest-inclusive auth Boolean | `77dd12e` |
| FOLLOWUP-01 | Migration child timestamp defaults survive optional inputs and retries | `2bb93a3` |
| FOLLOWUP-02 | Guest read subscriptions survive Clerk creation and atomic account upgrade | `d8b97e3` |
| FOLLOWUP-03 | Manual/UI night completion share record-then-atomic-resolution | `3043f8a` |
| FOLLOWUP-04 | Peer votes stay private until everyone votes/results publish; drafts remain private | `e08cd08` |
| FOLLOWUP-05 | Background readiness reads cannot silently discard Finish Night | `ffba45b` |
| FOLLOWUP-06 | Settings Login and Sign Up trigger independently | `9d2a9cf` |
| FOLLOWUP-07 | Phase two receives the recorded night directly despite reactive cache replacement | `d88ab0f` |
| FOLLOWUP-08 | Already-signed-out Clerk responses allow successful Convex logout | `76e84bb` |

Host access to roles/actions is intentional for authoritative bot coordination.
Other members receive only their permitted role information; the complete member
history is available after game completion. Solo state remains local and distinct
from multiplayer state. Active app code remains Convex + Clerk.

## Publishing and remaining verification

**Development verification does not make production ready.** The read-only
production inspection found Convex deployment `handsome-tiger-460` with no functions
and no `CLERK_FRONTEND_API_URL`. The shared Clerk dashboard was signed out, so its
production instance/key/domain and iOS registration could not be verified.

Before publishing, complete [the production setup checklist](CLERK_SETUP.md#release-configuration-and-publishing):

1. Configure the real Clerk production instance/domain, Native API, iOS registration
   and Convex JWT integration with verified email claims.
2. Fill the real `pk_live_` publishable key and matching Clerk frontend hostname in
   `Configuration/Production.xcconfig`.
3. Configure the production Convex Clerk issuer, deploy this backend, ingest/verify
   the durable legacy data, then verify contract 3 against production.
4. Archive Release and test production account restoration and multiplayer on a
   physical device. The guard intentionally prevents the currently unconfigured
   Release build. A synthetic-key Release compilation verified plumbing only.

No production functions, environment, users or data were changed. Real legacy
Clerk-account restoration remains unverified because no legacy account was
provided. The live legacy source hostname returned `ENOTFOUND`; saved-export
parity does not establish parity with today's source database. Physical-device,
iOS 26, iPad and prolonged network-disruption testing were not performed. Android
was unavailable because the SDK is absent; this repository targets iOS.

## Evidence, cleanup and rollback

Sanitized evidence excludes credentials, JWTs, guest proofs and legacy personal
data. Private Xcode results are `/tmp/mafia-fix-final-complete.xcresult`; native and
API logs remain local. Temporary credential/session files were removed after
visible sign-out. Development QA account/guest profiles and cancelled room records
remain; campaigns delete their saved-data fixtures and revoke API sessions.

Revert the appropriate issue commit for a narrow rollback; refer to
`SESSION_CHANGES.md` for risks. Backend contract/schema/auth changes require a
coordinated backend/client rollback. Do not deploy an old validator against a
new client or run development fixture campaigns against production. Production
setup remains intentionally incomplete until real values are supplied.
