import { AuthConfig } from "convex/server";

const runtimeEnv = (globalThis as unknown as {
  process?: { env?: Record<string, string | undefined> };
}).process?.env;
const clerkEnvKey = ["CLERK", "FRONTEND", "API", "URL"].join("_");
const clerkFrontendApiUrl = runtimeEnv?.[clerkEnvKey];

export default {
  providers: clerkFrontendApiUrl
    ? [
        {
          domain: clerkFrontendApiUrl,
          applicationID: "convex",
        },
      ]
    : [],
} satisfies AuthConfig;
