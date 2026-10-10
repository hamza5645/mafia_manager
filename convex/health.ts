import { query } from "./_generated/server";
import { guestArg } from "./validators";

export const check = query({
  args: { ...guestArg },
  handler: async () => ({
    ok: true,
    backend: "convex",
    version: "convex-clerk-v4",
    api_contract: 4,
    checked_at: new Date().toISOString(),
  }),
});
