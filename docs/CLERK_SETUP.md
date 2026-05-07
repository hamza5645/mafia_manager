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

Sync Convex with the Clerk Frontend API URL. **This step is required.** When `CLERK_FRONTEND_API_URL` is not set in the deployment env, `convex/auth.config.ts` silently degrades to `providers: []` and every Clerk-authenticated mutation fails with "Authentication required". To verify or set:

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
