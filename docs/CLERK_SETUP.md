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
4. Confirm the `convex` JWT template has audience/application ID `convex` and includes the `email_verified` claim. Without that claim no legacy account can be claimed: sign-in creates a new, empty account instead.

## App Configuration

Update the Clerk values in [Debug.xcconfig](../Configuration/Debug.xcconfig) (development) or [Production.xcconfig](../Configuration/Production.xcconfig) (release) if the Clerk project changes, then regenerate with Tuist. Clerk publishable keys are client-side keys and are safe to include in the iOS app.

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

Debug reads development values from [Debug.xcconfig](../Configuration/Debug.xcconfig)
and Release reads production values from
[Production.xcconfig](../Configuration/Production.xcconfig), both through generated
build settings/Info.plist; there is no fallback. `ConvexConfig` stops the app at
launch if a value is missing, and Release also requires a `pk_live_` Clerk key. Tuist generates the matching
`webcredentials` associated-domain entitlement, following
[Clerk's iOS quickstart](https://clerk.com/docs/ios/getting-started/quickstart).

## Production

`Configuration/Production.xcconfig` targets:

- Convex: `https://handsome-tiger-460.eu-west-1.convex.cloud`, with `CLERK_FRONTEND_API_URL` set.
- Clerk Frontend API/issuer: `https://clerk.mafia.monitorthesituations.com`. Its five
  Clerk CNAMEs are DNS-only.
- Native API is enabled. The published association file lists
  `5GH22BAXAU.com.hamza5645.mafia`.

Before shipping an app build, check that the deployment reports API contract 4:

```bash
CONVEX_AUDIT_URL=https://handsome-tiger-460.eu-west-1.convex.cloud node scripts/e2e/verify-deployment.mjs
```

Never run test fixtures against production.

For a future production instance change:

1. Enable Native API and register the App ID Prefix and bundle ID again.
2. Activate the Convex integration/JWT template with audience `convex` and the
   `email_verified` claim. A copied development instance does not copy integrations.
3. Update the production key/hostname in `Configuration/Production.xcconfig` and
   set `CLERK_FRONTEND_API_URL` on production Convex to the same issuer.
4. Regenerate through Tuist and redeploy the matching backend. Verify contract 4
   and real native account flows, including a legacy-account claim, before releasing.

See [Clerk's production guide](https://clerk.com/docs/guides/development/deployment/production)
for dashboard prerequisites and native registration.
