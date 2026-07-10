import { AuthConfig } from "convex/server";

const runtimeEnv = (globalThis as unknown as {
  process?: { env?: Record<string, string | undefined> };
}).process?.env;
const clerkEnvKey = ["CLERK", "FRONTEND", "API", "URL"].join("_");
const clerkFrontendApiUrl = runtimeEnv?.[clerkEnvKey];

// Fail the deploy instead of silently disabling Clerk sign-in: with an empty
// providers list every Clerk-authenticated call becomes anonymous, which is
// invisible until users report that sign-in "works" but nothing syncs.
if (!clerkFrontendApiUrl) {
  throw new Error(
    `${clerkEnvKey} is not set on this Convex deployment. ` +
      "Set it to the Clerk Frontend API URL (Clerk dashboard -> API keys) " +
      "with `npx convex env set` before deploying.",
  );
}

export default {
  providers: [
    {
      domain: clerkFrontendApiUrl,
      applicationID: "convex",
    },
  ],
} satisfies AuthConfig;
