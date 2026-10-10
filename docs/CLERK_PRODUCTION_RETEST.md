# Production configuration and retest — 2026-10-09

Production configuration, deployment, data import, signed archive and App Store
IPA export are complete. Production API checks passed. Native UI/physical-device
release validation is still incomplete; this report does not declare the app
fully validated for publication.

## Verified

- Clerk production HTTPS issuer and native association file are correct for
  `5GH22BAXAU.com.hamza5645.mafia`.
- Convex production deployment passes API contract 3.
- Signed version 5.0/build 11 archive and IPA use the real production key/host.
  IPA signature verifies as Apple Distribution; Associated Domains is correct,
  get-task-allow is disabled, and its App Store profile has no device restrictions.
- Production Release simulator build passed after correcting unsupported Intel
  simulator linking through Tuist (FOLLOWUP-09). The installed Convex binary
  supplies arm64 slices only.
- 26 distinct production API checks passed using the user-approved temporary
  inbox and real email OTPs. These cover signup, expired-code rejection, Convex
  audience/email claims, authenticated profile creation, edited-name persistence,
  UUID restoration, wrong/old-password rejection, password reset, fresh-client
  sign-in and session revocation.
- Account-host/guest room smoke passed create/join, host authorization, kick,
  empty roster after removal, rejoin, cancellation and membership cleanup.
- Final snapshots still match all 142 saved-export legacy rows: 86 users, 48
  stats, 6 role configs and 2 groups; no mismatches or owner errors.

## Coverage limits and cleanup

The Release app initiated native signup and delivered a real verification email.
Browser and simulator controls then failed before native verification could be
confirmed. API checks subsequently completed successfully. Native UI signup,
sign-in/reset, full production gameplay and physical-device/iPad checks remain
unverified. A real legacy account was not supplied; parity uses the saved export
because the old live database is unavailable.

The first two room probes used incorrect test payloads; these were corrected to
match the actual app calls (caller_user_id and cancelSession). No backend change
was needed. All three own QA rooms are cancelled with zero memberships. QA API
sessions are revoked; temporary credential/session files were removed. Six QA
profiles (one account and five guests) remain; legacy rows are unchanged.

Production emails currently use the Clerk application name "My Application".
Update Clerk branding to Mafia Manager before inviting users.

## Artifacts and evidence

- Archive: `/tmp/mafia-manager-production-ready-20261009.xcarchive`
- IPA: `/tmp/mafia-manager-production-export-20261009/mafia_manager.ipa`
- [Sanitized evidence](e2e-evidence/2026-10-09-production): signature/hash checks,
  account/room assertions, cleanup and legacy parity.
- [Setup status](CLERK_SETUP.md) and [rollback notes](SESSION_CHANGES.md).

The artifacts have not been uploaded or submitted to App Store Connect.
