import { MutationCtx } from "../_generated/server";

// stats:recordGame remembers a game only so that a retry is not counted twice.
// A retry comes from a device's outbox, which holds at most 50 games
// (StatsOutbox.maxEntries), so each user keeps that many rows and no more.
export const RECORDED_GAMES_KEPT = 50;

// Deletes all but the user's newest RECORDED_GAMES_KEPT rows. Run after every
// write of that user's rows, so it never reads many more than it keeps.
export async function trimRecordedGames(ctx: MutationCtx, userId: string) {
  const rows = await ctx.db
    .query("recorded_games")
    .withIndex("by_user", (q) => q.eq("user_id", userId))
    .order("desc")
    .collect();
  for (const row of rows.slice(RECORDED_GAMES_KEPT)) await ctx.db.delete(row._id);
}
