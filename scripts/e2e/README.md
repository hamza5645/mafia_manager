# Deployment compatibility check

`verify-deployment.mjs` queries `health:check` on a Convex deployment and fails
unless it reports the API contract the app expects
(`ConvexConfig.apiContractVersion`). It is read-only and deploys nothing.

```sh
node scripts/e2e/verify-deployment.mjs              # app's development deployment
CONVEX_AUDIT_URL=https://<deployment>.convex.cloud node scripts/e2e/verify-deployment.mjs
```

Run it against the target deployment before shipping the matching app. On a
mismatch, deploy the matching backend and re-run the check.
