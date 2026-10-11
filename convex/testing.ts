import { v } from "convex/values";
import { Doc } from "./_generated/dataModel";
import { MutationCtx, internalMutation } from "./_generated/server";
import { getSession } from "./lib/guards";
import { deleteRoomRows, removeSeatAndTransferHost } from "./lib/transitions";

// Dev only: deletes what the live test suites leave behind. It refuses to run
// unless the deployment sets MAFIA_ALLOW_QA_PURGE=1, which production must
// never set (`npx convex env set MAFIA_ALLOW_QA_PURGE 1` on dev). Run it with
// `npx convex run testing:purgeQa '{}'`, then again with
// `'{"cursor": "<returned cursor>"}'` until the returned cursor is null.
// Only QA users are touched: guests named "QA ..." (ConvexIntegrationTests)
// and Clerk test accounts (ClerkAccountIntegrationTests).
// The Convex runtime provides process.env; convex/tsconfig.json loads no Node types.
declare const process: { env: Record<string, string | undefined> };

const QA_EMAIL = /^mafia-native-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\+clerk_test@example\.com$/;

const isQaUser = (u: Doc<"users">) =>
  (u.is_anonymous && u.auth_subject === undefined && u.display_name.startsWith("QA ")) ||
  (!u.is_anonymous && u.email !== undefined && QA_EMAIL.test(u.email));

type Counts = { users: number; seats: number; rooms: number; library_rows: number };

async function purgeUser(ctx: MutationCtx, user: Doc<"users">, counts: Counts) {
  // Leaving each seat hands host over, or cancels the room when no human is left.
  const seats = await ctx.db
    .query("session_players")
    .withIndex("by_user", (q) => q.eq("user_id", user.id))
    .collect();
  for (const seat of seats) {
    const room = await getSession(ctx, seat.session_id);
    if (room) await removeSeatAndTransferHost(ctx, room, seat, user.id);
    else await ctx.db.delete(seat._id);
    counts.seats += 1;
  }
  // Their cancelled rooms go entirely. A room still hosted without a seat is
  // left first; rooms that live on under another host are kept.
  const hosted = await ctx.db
    .query("game_sessions")
    .withIndex("by_host", (q) => q.eq("host_user_id", user.id))
    .collect();
  const original = await ctx.db
    .query("game_sessions")
    .withIndex("by_original_host", (q) => q.eq("original_host_user_id", user.id))
    .collect();
  for (const found of new Map([...hosted, ...original].map((room) => [room._id, room])).values()) {
    if (found.status !== "cancelled" && found.host_user_id === user.id) {
      await removeSeatAndTransferHost(ctx, found, null, user.id);
    }
    const room = await getSession(ctx, found.id);
    if (room?.status !== "cancelled") continue;
    await deleteRoomRows(ctx, room.id);
    await ctx.db.delete(room._id);
    counts.rooms += 1;
  }
  const owned = await Promise.all([
    ctx.db.query("player_stats").withIndex("by_user_player", (q) => q.eq("user_id", user.id)).collect(),
    ctx.db.query("recorded_games").withIndex("by_user_game", (q) => q.eq("user_id", user.id)).collect(),
    ctx.db.query("custom_roles_configs").withIndex("by_user_config_name", (q) => q.eq("user_id", user.id)).collect(),
    ctx.db.query("player_groups").withIndex("by_user_group_name", (q) => q.eq("user_id", user.id)).collect(),
  ]);
  for (const row of owned.flat()) await ctx.db.delete(row._id);
  counts.library_rows += owned.flat().length;
  await ctx.db.delete(user._id);
  counts.users += 1;
}

export const purgeQa = internalMutation({
  args: { cursor: v.optional(v.union(v.string(), v.null())), batch: v.optional(v.number()) },
  handler: async (ctx, args): Promise<Counts & { checked: number; cursor: string | null }> => {
    if (process.env.MAFIA_ALLOW_QA_PURGE !== "1") {
      throw new Error("purgeQa is disabled. Set MAFIA_ALLOW_QA_PURGE=1 on a development deployment only.");
    }
    const page = await ctx.db.query("users").paginate({ numItems: args.batch ?? 50, cursor: args.cursor ?? null });
    const counts: Counts = { users: 0, seats: 0, rooms: 0, library_rows: 0 };
    for (const user of page.page) if (isQaUser(user)) await purgeUser(ctx, user, counts);
    return { ...counts, checked: page.page.length, cursor: page.isDone ? null : page.continueCursor };
  },
});
