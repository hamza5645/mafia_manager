# Deployment compatibility check

`verify-deployment.mjs` queries `health:check` on a Convex deployment and fails
unless the deployment accepts the app's API contract
(`ConvexConfig.apiContractVersion`): its `api_contract` must be at least the
app's, and its `min_client_contract` at most the app's. It prints the URL it
checks, is read-only and deploys nothing. `tests/convex/deployment.test.ts`
covers the rule and the choice of deployment.

```sh
node scripts/e2e/verify-deployment.mjs              # app's development deployment
node scripts/e2e/verify-deployment.mjs --prod       # app's production deployment (Configuration/Production.xcconfig)
CONVEX_AUDIT_URL=https://<deployment>.convex.cloud node scripts/e2e/verify-deployment.mjs
```

`npm run convex:deploy` runs the backend tests (`npm run test:backend`), then
`convex deploy`, then this check with `--prod`. On a mismatch, deploy the
matching backend and re-run the check.
