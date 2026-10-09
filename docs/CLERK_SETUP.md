# Clerk + Convex Setup

The Swift and Convex code is wired for Clerk. The current dev project is configured; use this guide when changing Clerk projects or reproducing setup on another deployment.

## Required Values

From the Clerk dashboard:
- **Publishable key**: starts with `pk_test_` or `pk_live_`.
- **Frontend API URL / issuer domain**: development format is usually `https://verb-noun-00.clerk.accounts.dev`; production format is usually `https://clerk.<your-domain>.com`.

## Clerk Dashboard

1. Create or open the Clerk application for Mafia Manager.
2. Activate the Convex integration.
3. Copy the Frontend API URL shown by the integration.
4. Confirm the Convex audience/application ID is `convex`.

## App Configuration

Update [ConvexConfig.swift](/Users/hamzaosama/Documents/Developer/SwiftUI/mafia_manager/Core/Backend/ConvexConfig.swift) if the Clerk project changes. Clerk publishable keys are client-side keys and are safe to include in the iOS app.

Sync Convex with the Clerk Frontend API URL. **This step is required.** The backend refuses deployment when `CLERK_FRONTEND_API_URL` is missing. To verify or set:

```bash
npx convex env list                       # confirm CLERK_FRONTEND_API_URL is present
npx convex env set CLERK_FRONTEND_API_URL https://your-clerk-frontend-api-url.clerk.accounts.dev
npx convex dev --once
```

## Verification

After both values are real:

```bash
npx convex dev --once
tuist generate
tuist build mafia_manager
tuist test mafia_manager
```

Then run the app and verify:
- email/password sign-up creates a Clerk user and Convex `users` document;
- sign-in restores the same Convex profile;
- password reset starts the Clerk reset flow;
- multiplayer rooms still work for account users and guest users.


## Release configuration and publishing

Debug uses the development services. Release reads production values from
[Production.xcconfig](../Configuration/Production.xcconfig) through generated
build settings/Info.plist; it has no development fallback. The pre-build guard
rejects missing/test Clerk keys, the known development Convex host, and a Clerk
frontend domain that does not match the key. Tuist generates the matching
`webcredentials` associated-domain entitlement, following
[Clerk's iOS quickstart](https://clerk.com/docs/ios/getting-started/quickstart).

## Production setup status — 2026-10-09

Production is now configured in `Configuration/Production.xcconfig`:

- Convex Cloud URL: `https://handsome-tiger-460.eu-west-1.convex.cloud`.
- Clerk Frontend API/issuer: `https://clerk.mafia.monitorthesituations.com`.
- The real production publishable key is configured; it matches that hostname.
- All five Clerk CNAMEs are DNS-only and verified. HTTPS/OpenID discovery works.
- Native API is enabled (dashboard evidence). The published association file
  lists `5GH22BAXAU.com.hamza5645.mafia`, matching the actual provisioning prefix.
- Production Convex has `CLERK_FRONTEND_API_URL` set and the branch backend
  deployed. The read-only deployment check passes with API contract 3.
- Imported and verified the saved export: 86 users, 48 stats, 6 role configs,
  2 groups. All fields/legacy IDs/owner mappings match; zero orphaned rows.
- Tuist generation, configuration guard, Release device compilation, signed
  production archive and App Store IPA export all passed. IPA signature verifies
  as Apple Distribution for 5GH22BAXAU, with production associated domain,
  get-task-allow disabled, and an App Store provisioning profile.
- Version 5.0, build 11. Artifacts remain local; no upload was performed.
- Production Release simulator build passes on Apple Silicon. Convex's installed
  binary omits Intel simulator support; Tuist excludes x86_64 for that SDK.

The original live database hostname is unavailable. Import verification compares
against the saved export, not a fresh live source. A real legacy account claim,
production signup/sign-in/reset JWT exchange, and physical-device gameplay still
need end-to-end validation before publishing. Do not run the development fixture
campaigns against production.

For a future production instance change:

1. Enable Native API and register the App ID Prefix and bundle ID again.
2. Activate the Convex integration/JWT template with audience `convex` and
   verified email claims. A copied development instance does not copy integrations.
3. Update the production key/hostname in `Configuration/Production.xcconfig` and
   set `CLERK_FRONTEND_API_URL` on production Convex to the same issuer.
4. Regenerate through Tuist and redeploy the matching backend. Verify contract 3,
   migration ownership and real native account flows before releasing.

See [Clerk's production guide](https://clerk.com/docs/guides/development/deployment/production)
for dashboard prerequisites and native registration.
