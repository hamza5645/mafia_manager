import { query } from "./_generated/server";
import { guestArg } from "./validators";

// The app blocks online features only when its own contract is below
// min_client_contract, so the backend can move ahead of installed builds.
export const check = query({
  args: { ...guestArg },
  handler: async () => ({
    ok: true,
    backend: "convex",
    version: "convex-clerk-v5",
    api_contract: 5,
    min_client_contract: 5,
    checked_at: new Date().toISOString(),
  }),
});
