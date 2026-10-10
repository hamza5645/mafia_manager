import { v } from "convex/values";
import { internal } from "./_generated/api";
import { internalMutation, internalQuery } from "./_generated/server";
import { sha256Hex } from "./lib/util";

// Deploy-1 data migrations (internal only). Run with `npx convex run`, then
// confirm with auditLegacyFields before deploy 2 drops the transitional fields.

type Page = { updated: number; is_done: boolean; continue_cursor: string };
const pageArgs = { cursor: v.optional(v.union(v.string(), v.null())), batch_size: v.optional(v.number()) };

export const backfillGuestSecretDigests = internalMutation({
  args: pageArgs,
  handler: async (ctx, args): Promise<Page> => {
    const page = await ctx.db.query("users").paginate({ cursor: args.cursor ?? null, numItems: args.batch_size ?? 200 });
    let updated = 0;
    for (const row of page.page) {
      if (row.guest_secret_hash === undefined) continue;
      await ctx.db.patch(row._id, {
        guest_secret_digest: row.guest_secret_digest ?? (await sha256Hex(row.guest_secret_hash)),
        guest_secret_hash: undefined,
      });
      updated += 1;
    }
    if (!page.isDone) {
      await ctx.scheduler.runAfter(0, internal.migrations.backfillGuestSecretDigests, {
        cursor: page.continueCursor,
        batch_size: args.batch_size,
      });
    }
    return { updated, is_done: page.isDone, continue_cursor: page.continueCursor };
  },
});

export const cleanupSessionFields = internalMutation({
  args: pageArgs,
  handler: async (ctx, args): Promise<Page> => {
    const page = await ctx.db
      .query("game_sessions")
      .paginate({ cursor: args.cursor ?? null, numItems: args.batch_size ?? 200 });
    let updated = 0;
    for (const row of page.page) {
      if (row.phase_sequence === undefined && row.night_resolution === undefined) continue;
      await ctx.db.patch(row._id, { phase_sequence: undefined, night_resolution: undefined });
      updated += 1;
    }
    if (!page.isDone) {
      await ctx.scheduler.runAfter(0, internal.migrations.cleanupSessionFields, {
        cursor: page.continueCursor,
        batch_size: args.batch_size,
      });
    }
    return { updated, is_done: page.isDone, continue_cursor: page.continueCursor };
  },
});

export const auditLegacyFields = internalQuery({
  args: {
    table: v.union(v.literal("users"), v.literal("game_sessions")),
    cursor: v.optional(v.union(v.string(), v.null())),
  },
  handler: async (ctx, args) => {
    const options = { cursor: args.cursor ?? null, numItems: 500 };
    let scanned: number;
    let remaining: number;
    let page: { isDone: boolean; continueCursor: string };
    if (args.table === "users") {
      const users = await ctx.db.query("users").paginate(options);
      scanned = users.page.length;
      remaining = users.page.filter((row) => row.guest_secret_hash !== undefined).length;
      page = users;
    } else {
      const sessions = await ctx.db.query("game_sessions").paginate(options);
      scanned = sessions.page.length;
      remaining = sessions.page.filter(
        (row) => row.phase_sequence !== undefined || row.night_resolution !== undefined,
      ).length;
      page = sessions;
    }
    return { scanned, remaining_legacy: remaining, is_done: page.isDone, continue_cursor: page.continueCursor };
  },
});
