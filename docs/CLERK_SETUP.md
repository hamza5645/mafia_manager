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

Production Convex `handsome-tiger-460` exists, but the 2026-10-08 inspection found
no functions deployed and no Clerk issuer environment variable. The Clerk
production instance could not be inspected because the shared dashboard was
signed out. A production key is intentionally not fabricated or copied from dev.
Release builds remain blocked until this setup is completed:

1. In Clerk, create/open the production instance, complete its domain/DNS setup,
   enable Native API, and register the iOS App ID Prefix and bundle
   `com.hamza5645.mafia`. Configure its Convex JWT integration/template with
   audience `convex` and verified email claims for legacy account restoration.
2. Fill the production `pk_live_` key and its frontend hostname in
   `Configuration/Production.xcconfig`. Clerk publishable keys are safe client
   configuration; secret keys must never go in the app or this file.
3. Set `CLERK_FRONTEND_API_URL` on **production** Convex to that Clerk issuer,
   deploy this branch's backend to production, and ingest/verify the durable
   legacy data using the migration scripts configured for the production URL.
4. Run `tuist generate --no-open` and verify the selected production API contract
   with `CONVEX_AUDIT_URL=https://handsome-tiger-460.eu-west-1.convex.cloud npm run convex:verify-deployment`.
   Then build/archive Release and test signup, sign-in, reset, migrated-account
   restoration, and multiplayer on a physical device with production services.

Do not run the development fixture campaigns against production. See
[Clerk's production guide](https://clerk.com/docs/guides/development/deployment/production)
for the dashboard prerequisites. A Release compilation with a synthetic test
key only verifies configuration plumbing; it does not prove production auth works.
