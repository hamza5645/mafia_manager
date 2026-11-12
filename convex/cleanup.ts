import { v } from "convex/values";
import { internal } from "./_generated/api";
import { Doc } from "./_generated/dataModel";
import { MutationCtx, internalMutation } from "./_generated/server";
import { listSeats } from "./lib/guards";
import { heartbeatsOf } from "./lib/presence";
import {
  DEAD_ROOM_SECONDS,
  FINISHED_ROOM_SECONDS,
  cancelSessionAndRemovePlayers,
  deleteRoomRows,
} from "./lib/transitions";
import { APPLE_EPOCH_UNIX_SECONDS, nowAppleEpochSeconds } from "./lib/util";
import { sessionStatusValidator } from "./validators";

// Data lifecycle, run hourly by crons.ts.
// - A lobby or game nobody has been seen in for 6 h is cancelled. "Seen" is the
//   players' presence heartbeats, never session.updated_at, which a quiet
//   lobby does not move.
// - A finished game keeps its seats for a day (game over screen, Play Again),
//   then loses them.
// - Cancelled and finished rooms are deleted after 30 days, freeing the code.
//
// A sweep lists only rooms that can be due, so it costs what there is to do,
// not what the history holds:
// - open rooms (waiting, in_progress) created more than 6 h ago;
// - ended rooms (completed, cancelled) whose next_cleanup_at has passed;
// - ended rooms with no next_cleanup_at yet (from before the field), which
//   get one, so each is listed this way once.
// Listing and cleaning are separate transactions, one per room, so a room that
// cannot be cleaned holds up nothing else.
export const STALE_ROOM_SECONDS = 6 * 3600;
// A page only reads the rooms and schedules one cleanRoom each.
const PAGE_SIZE = 100;

type Room = Doc<"game_sessions">;
type Outcome = "cancelled" | "cleared" | "deleted" | null;

// When anyone in the room was last seen: the newest presence heartbeat, else
// (rooms from before session_presence) the newest seat heartbeat or join time.
async function lastActivity(ctx: MutationCtx, sessionId: string): Promise<number | undefined> {
  const beats = [...(await heartbeatsOf(ctx, sessionId)).values()];
  if (beats.length > 0) return Math.max(...beats);
  const humans = (await listSeats(ctx, sessionId)).filter((s) => !s.is_bot);
  return humans.length > 0 ? Math.max(...humans.map((s) => s.last_heartbeat ?? s.joined_at)) : undefined;
}

// An ended room is left either deleted or with the date of its next step.
async function clean(ctx: MutationCtx, room: Room, now: number): Promise<Outcome> {
  if (room.status === "waiting" || room.status === "in_progress") {
    const seen = await lastActivity(ctx, room.id);
    if (seen !== undefined && now - seen <= STALE_ROOM_SECONDS) return null;
    await cancelSessionAndRemovePlayers(ctx, room);
    return "cancelled";
  }
  const endedAt = room.completed_at ?? room.created_at;
  if (now - endedAt > DEAD_ROOM_SECONDS) {
    await deleteRoomRows(ctx, room.id);
    await ctx.db.delete(room._id);
    return "deleted";
  }
  if (room.status === "completed" && now - endedAt <= FINISHED_ROOM_SECONDS) {
    await ctx.db.patch(room._id, { next_cleanup_at: endedAt + FINISHED_ROOM_SECONDS });
    return null;
  }
  // A cancelled room lost its rows when it was cancelled.
  const seats = room.status === "completed" ? await deleteRoomRows(ctx, room.id) : 0;
  await ctx.db.patch(room._id, { next_cleanup_at: endedAt + DEAD_ROOM_SECONDS });
  return seats > 0 ? "cleared" : null;
}

export const sweep = internalMutation({
  args: {},
  handler: async (ctx): Promise<null> => {
    const now = nowAppleEpochSeconds();
    for (const status of ["waiting", "in_progress", "completed", "cancelled"] as const) {
      await ctx.scheduler.runAfter(0, internal.cleanup.sweepRooms, { status, now, cursor: null });
    }
    for (const status of ["completed", "cancelled"] as const) {
      await ctx.scheduler.runAfter(0, internal.cleanup.sweepRooms, { status, undated: true, now, cursor: null });
    }
    return null;
  },
});

// Lists one page of the rooms that can be due and schedules cleanRoom for
// each; returns how many it listed. `now` is when the sweep started, so every
// page of a pass runs the same query. `undated` lists the ended rooms that
// have no next_cleanup_at.
export const sweepRooms = internalMutation({
  args: {
    status: sessionStatusValidator,
    undated: v.optional(v.boolean()),
    now: v.number(),
    cursor: v.union(v.string(), v.null()),
  },
  handler: async (ctx, args): Promise<number> => {
    const { status, now } = args;
    const rooms =
      status === "waiting" || status === "in_progress"
        ? ctx.db.query("game_sessions").withIndex("by_status", (q) =>
            // _creationTime is in Unix milliseconds.
            q.eq("status", status).lt("_creationTime", (now - STALE_ROOM_SECONDS + APPLE_EPOCH_UNIX_SECONDS) * 1000),
          )
        : ctx.db.query("game_sessions").withIndex("by_status_cleanup", (q) =>
            args.undated
              ? q.eq("status", status).eq("next_cleanup_at", undefined)
              : q.eq("status", status).gt("next_cleanup_at", 0).lt("next_cleanup_at", now),
          );
    const page = await rooms.paginate({ numItems: PAGE_SIZE, cursor: args.cursor });
    for (const room of page.page) await ctx.scheduler.runAfter(0, internal.cleanup.cleanRoom, { id: room._id });
    if (!page.isDone) {
      await ctx.scheduler.runAfter(0, internal.cleanup.sweepRooms, { ...args, cursor: page.continueCursor });
    }
    return page.page.length;
  },
});

// One room in its own transaction. It is read again here, so a room that
// changed after it was listed is judged as it is now.
export const cleanRoom = internalMutation({
  args: { id: v.id("game_sessions") },
  handler: async (ctx, args): Promise<Outcome> => {
    const room = await ctx.db.get(args.id);
    return room ? await clean(ctx, room, nowAppleEpochSeconds()) : null;
  },
});
