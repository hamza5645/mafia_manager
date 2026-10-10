# Backend Decisions

Why the backend looks the way it does. The full migration plan, audits and QA
evidence were removed on 2026-10-10; read them with
`git log -- docs/SUPABASE_TO_CONVEX_MIGRATION_PLAN.md docs/e2e-evidence`.

## Convex + Clerk (replaced Supabase)

- Convex reactive queries replace table change feeds, and transactional
  TypeScript mutations replace the scattered Postgres RPCs, including atomic
  night resolution. Role privacy is enforced in query results, not in SwiftUI.
- Clerk provides email/password sign-up, sign-in and reset, a native iOS SDK, and
  a Convex bridge (`clerk-convex-swift`, vendored; see
  `Vendor/clerk-convex-swift/VENDORED.md`). Convex accepts JWTs minted from the
  Clerk `convex` template (audience `convex`); the issuer comes from the Convex
  `CLERK_FRONTEND_API_URL` environment variable.
- Auth0, Sign in with Apple alone, and guest-only Convex were considered and rejected.

## Guest proof

- Guests have no Clerk identity. The app creates a random secret once and keeps
  it in the Keychain; the raw secret never leaves the device.
- The client sends `sha256(secret)` as `guest_secret_hash` with guest requests.
- The server stores only a sha256 digest of that value and compares digests, so a
  leaked `users` row cannot be replayed as a guest proof.

## Legacy accounts

- Legacy users were imported as unclaimed `users` rows (no `auth_subject`) that
  keep their email and legacy IDs; child rows keep their legacy owner IDs.
- On Clerk sign-in, `users:ensureUser` claims the unclaimed legacy row whose email
  matches the Clerk identity's verified email. Unverified emails never claim.

## One-shot migration

- Ran once against production on 2026-10-09 from the saved export: 86 users,
  48 stats, 6 role configs, 2 groups, checked field by field with zero orphans.
- The original database is no longer reachable. Do not rerun the import after
  users have claimed or edited data.
