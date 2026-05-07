import { query } from "./_generated/server";

export const check = query({
  args: {},
  handler: async () => ({
    ok: true,
    backend: "convex",
    version: "convex-clerk-v1",
    checked_at: new Date().toISOString(),
  }),
});
