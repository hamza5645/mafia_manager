# Convex migration audit tooling

These scripts exercise the configured **development** Clerk/Convex services and create isolated QA data. They deliberately assert safe/expected behavior, so failures expose unresolved branch issues. They do not fix app/backend code. Read the [final fixes/retest report](../../docs/CONVEX_MIGRATION_FIXES_AND_RETEST.md) and [original audit](../../docs/CONVEX_MIGRATION_E2E_REPORT.md) before rerunning.

## Backend campaign

```sh
mkdir -p /tmp/mafia-e2e-20261008
node scripts/e2e/convex-migration-audit.mjs
```

Defaults to the app's development URL. Optional `CONVEX_AUDIT_URL` and `CONVEX_AUDIT_OUTPUT` override the URL/output. Do not point a test campaign at production. Outputs an assertion report with QA guest proofs redacted. Cancels test rooms, removes human memberships, and deletes saved-data fixtures. Guest profiles and cancelled room records remain.

## Account and merge campaign

```sh
node scripts/e2e/clerk-convex-audit.mjs
```

Uses the installed ClerkKit native API paths and Clerk's development test-email convention, verified by [Clerk's test-email documentation](https://clerk.com/docs/guides/development/testing/test-emails-and-phones). Creates a new test account, verifies signup/sign-in/reset, and probes merge collisions and active-room ownership. Saved-data fixtures are removed, QA rooms are cancelled, and the API session is revoked. Development test accounts and guest profiles remain.

Results go to `/tmp/mafia-e2e-20261008/account-results.json`. Private credentials/device-session state go to `api-test-account.json` and `api-test-session.json` with mode `0600`, for follow-up native sign-in; never commit them. `CLERK_AUDIT_RESUME=1` resumes password-reset checks for that account and writes `password-reset-results.json`.

## Actual Swift SDK account lifecycle

Use a normal signed simulator build: unsigned builds on this runtime cannot access Keychain. Generate with Tuist, then run Xcode's test action directly because the installed Tuist CLI's `test` command is for inspecting test runs.

```sh
tuist generate --no-open
TEST_RUNNER_CONVEX_INTEGRATION=1 TEST_RUNNER_CLERK_ACCOUNT_E2E=1 \
  xcodebuild test -workspace mafia_manager.xcworkspace -scheme mafia_manager \
  -destination 'platform=iOS Simulator,name=Mafia QA Guest' \
  -only-testing:mafia_managerTests/ClerkAccountIntegrationTests \
  -parallel-testing-enabled NO -collect-test-diagnostics never
```

This creates a development test account using `+clerk_test@example.com` and `424242`, exercises native signup, verification, sign-in, restoration, reset, and changed-password behavior, then signs out. Passwords are randomly generated and not printed. Without both opt-in flags, the new test skips.

## Saved-export parity

Collect private snapshots with the authenticated Convex CLI, then compare every exported row and foreign-key mapping:

```sh
umask 077
for table in users player_stats custom_roles_configs player_groups; do
  npx convex data "$table" --limit 10000 --format json \
    > "/tmp/mafia-e2e-20261008/$table-snapshot.json"
done
python3 scripts/e2e/legacy-export-parity.py \
  /tmp/mafia-e2e-20261008 /tmp/mafia-e2e-20261008/legacy-export-parity.json
```

Keep raw snapshots private: users contain legacy personal data and guest proof. Only the sanitized count/mismatch report should be shared. Verify the CLI limit exceeds the table size. The comparison uses the saved export, excludes expected updated-timestamp changes, and checks legacy IDs, data fields, and mapped user ownership. It does not prove parity with the current live Supabase database.

## Deployment compatibility and regression tests

Run `npm run test:backend` for isolated Convex function regressions using the
[official convex-test harness](https://docs.convex.dev/testing/convex-test).
Run `npm run convex:verify-deployment` against the selected deployment before
shipping the corresponding app. A missing or mismatched API contract fails the
check. Deploy the matching backend and re-run the check; coordinate guest-proof
API changes with the client rollout. This check does not deploy any functions.

The campaigns now exit nonzero on any failed/error assertion. Backend fixtures
use Swift-compatible phase/history payloads. `CLERK_AUDIT_DIR` selects a private
output directory for the account campaign; it cancels QA rooms and revokes its
API session at completion. Its development account/password file remains for
visible UI follow-up; delete private credential/session files when finished.
