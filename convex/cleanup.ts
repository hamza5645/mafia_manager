import { v } from "convex/values";
import { internal } from "./_generated/api";
import { Doc } from "./_generated/dataModel";
import { MutationCtx, internalMutation } from "./_generated/server";
import { listSeats } from "./lib/guards";
import { heartbeatsOf } from "./lib/presence";
import { cancelSessionAndRemovePlayers, deleteRoomRows } from "./lib/transitions";
import { nowAppleEpochSeconds } from "./lib/util";
import { sessionStatusValidator } from "./validators";

// Data lifecycle, run hourly by crons.ts. Rooms are swept one status at a time,
// one page per transaction; a full page schedules the next one.
// - A lobby or game nobody has been seen in for 6 h is cancelled. "Seen" is the
//   players' presence heartbeats, never session.updated_at, which a quiet
//   lobby does not move.
// - A finished game keeps its seats for a day (game over screen, Play Again),
//   then loses them.
// - Cancelled and finished rooms are deleted after 30 days, freeing the code.
const HOUR = 3600;
export const STALE_ROOM_SECONDS = 6 * HOUR;
export const FINISHED_ROOM_SECONDS = 24 * HOUR;
export const DEAD_ROOM_SECONDS = 30 * 24 * HOUR;
// A room can own a few hundred rows (seats, presence, every round's actions),
// so a page stays far below Convex's per-transaction write limit.
const PAGE_SIZE = 20;

type Room = Doc<"game_sessions">;

// When anyone in the room was last seen: the newest presence heartbeat, else
// (rooms from before session_presence) the newest seat heartbeat or join time.
async function lastActivity(ctx: MutationCtx, sessionId: string): Promise<number | undefined> {
  const beats = [...(await heartbeatsOf(ctx, sessionId)).values()];
  if (beats.length > 0) return Math.max(...beats);
  const humans = (await listSeats(ctx, sessionId)).filter((s) => !s.is_bot);
  return humans.length > 0 ? Math.max(...humans.map((s) => s.last_heartbeat ?? s.joined_at)) : undefined;
}

async function cleanRoom(ctx: MutationCtx, room: Room, now: number): Promise<"cancelled" | "cleared" | "deleted" | null> {
  if (room.status === "waiting" || room.status === "in_progress") {
    const seen = await lastActivity(ctx, room.id);
    if (seen !== undefined && now - seen <= STALE_ROOM_SECONDS) return null;
    await cancelSessionAndRemovePlayers(ctx, room);
    return "cancelled";
  }
  const age = now - (room.completed_at ?? room.created_at);
  if (age > DEAD_ROOM_SECONDS) {
    await deleteRoomRows(ctx, room.id);
    await ctx.db.delete(room._id);
    return "deleted";
  }
  if (room.status === "completed" && age > FINISHED_ROOM_SECONDS && (await deleteRoomRows(ctx, room.id)) > 0) {
    return "cleared";
  }
  return null;
}

export const sweep = internalMutation({
  args: {},
  handler: async (ctx): Promise<null> => {
    for (const status of ["waiting", "in_progress", "completed", "cancelled"] as const) {
      await ctx.scheduler.runAfter(0, internal.cleanup.sweepRooms, { status, cursor: null });
    }
    return null;
  },
});

export const sweepRooms = internalMutation({
  args: { status: sessionStatusValidator, cursor: v.union(v.string(), v.null()) },
  handler: async (ctx, args): Promise<{ checked: number; cancelled: number; cleared: number; deleted: number }> => {
    const now = nowAppleEpochSeconds();
    const page = await ctx.db
      .query("game_sessions")
      .withIndex("by_status", (q) => q.eq("status", args.status))
      .paginate({ numItems: PAGE_SIZE, cursor: args.cursor });
    const counts = { checked: page.page.length, cancelled: 0, cleared: 0, deleted: 0 };
    for (const room of page.page) {
      const outcome = await cleanRoom(ctx, room, now);
      if (outcome) counts[outcome] += 1;
    }
    if (!page.isDone) {
      await ctx.scheduler.runAfter(0, internal.cleanup.sweepRooms, { status: args.status, cursor: page.continueCursor });
    }
    return counts;
  },
});
