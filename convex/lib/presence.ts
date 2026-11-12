import { MutationCtx, QueryCtx } from "../_generated/server";

// Heartbeats write only session_presence, never session_players, so a
// heartbeat does not re-run the roster and round queries of every member.
type Ctx = QueryCtx | MutationCtx;

// A human seat counts as online while its last heartbeat is this recent.
export const ONLINE_SECONDS = 20;

export async function presenceOf(ctx: Ctx, sessionId: string, userId: string) {
  return await ctx.db
    .query("session_presence")
    .withIndex("by_session_user", (q) => q.eq("session_id", sessionId).eq("user_id", userId))
    .first();
}

// user_id → last heartbeat (server Apple-epoch seconds) for every human in the room.
export async function heartbeatsOf(ctx: Ctx, sessionId: string): Promise<Map<string, number>> {
  const rows = await ctx.db
    .query("session_presence")
    .withIndex("by_session", (q) => q.eq("session_id", sessionId))
    .collect();
  return new Map(rows.map((row) => [row.user_id, row.last_heartbeat]));
}

export async function touchPresence(ctx: MutationCtx, sessionId: string, userId: string, now: number) {
  const row = await presenceOf(ctx, sessionId, userId);
  if (row) await ctx.db.patch(row._id, { last_heartbeat: now });
  else await ctx.db.insert("session_presence", { session_id: sessionId, user_id: userId, last_heartbeat: now });
}

export async function deletePresence(ctx: MutationCtx, sessionId: string, userId: string) {
  const row = await presenceOf(ctx, sessionId, userId);
  if (row) await ctx.db.delete(row._id);
}

export async function deleteSessionPresence(ctx: MutationCtx, sessionId: string) {
  const rows = await ctx.db
    .query("session_presence")
    .withIndex("by_session", (q) => q.eq("session_id", sessionId))
    .collect();
  for (const row of rows) await ctx.db.delete(row._id);
}
