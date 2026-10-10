import { v } from "convex/values";
import { Doc } from "./_generated/dataModel";
import { MutationCtx, mutation } from "./_generated/server";
import { E, fail } from "./lib/errors";
import { getSession, listSeats, requireHost, requireRoster, requireSeat } from "./lib/guards";
import { requireCaller } from "./lib/identity";
import { HOST_STALE_SECONDS, nextHostAfterDeath, roleDistribution } from "./lib/rules";
import { cancelSessionAndRemovePlayers, removeSeatAndTransferHost, resetToLobby } from "./lib/transitions";
import { cleanText, nowAppleEpochSeconds, uuid } from "./lib/util";
import { guestArg, roleValidator } from "./validators";

// Lobby, membership and host management.

function enterResult(session: { id: string; room_code: string }, seat: { id: string; player_id: string }) {
  return { session_id: session.id, room_code: session.room_code, player_record_id: seat.id, player_id: seat.player_id };
}

async function generateRoomCode(ctx: MutationCtx) {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    const code = String(Math.floor(100000 + Math.random() * 900000));
    const existing = await ctx.db
      .query("game_sessions")
      .withIndex("by_room_code", (q) => q.eq("room_code", code))
      .first();
    if (!existing) return code;
  }
  return fail(E.ROOM_CODE);
}

async function insertSeat(
  ctx: MutationCtx,
  sessionId: string,
  seat: { user_id?: string; player_name: string; is_bot: boolean },
) {
  const timestamp = nowAppleEpochSeconds();
  const doc = {
    id: uuid(),
    session_id: sessionId,
    user_id: seat.user_id,
    player_id: uuid(),
    player_name: seat.player_name,
    is_bot: seat.is_bot,
    is_alive: true,
    is_online: !seat.is_bot,
    is_ready: true,
    last_heartbeat: timestamp,
    joined_at: timestamp,
  };
  await ctx.db.insert("session_players", doc);
  return doc;
}

export const createSession = mutation({
  args: { player_name: v.string(), max_players: v.number(), bot_count: v.number(), ...guestArg },
  handler: async (ctx, args) => {
    const caller = await requireCaller(ctx, args.guest_secret_hash);
    const playerName = cleanText(args.player_name, 1, 50, E.PLAYER_NAME);
    if (!Number.isInteger(args.max_players) || args.max_players < 4 || args.max_players > 19) fail(E.MAX_PLAYERS);
    if (!Number.isInteger(args.bot_count) || args.bot_count < 0 || args.bot_count > args.max_players - 1) {
      fail(E.BOT_COUNT);
    }
    const timestamp = nowAppleEpochSeconds();
    const session = {
      id: uuid(),
      room_code: await generateRoomCode(ctx),
      host_user_id: caller.id,
      original_host_user_id: caller.id,
      status: "waiting" as const,
      created_at: timestamp,
      max_players: args.max_players,
      bot_count: args.bot_count,
      current_phase: "lobby",
      current_phase_data: { type: "lobby" },
      day_index: 0,
      is_game_over: false,
      assigned_numbers: [],
      night_history: [],
      day_history: [],
      updated_at: timestamp,
    };
    await ctx.db.insert("game_sessions", session);
    const hostSeat = await insertSeat(ctx, session.id, { user_id: caller.id, player_name: playerName, is_bot: false });
    for (let i = 1; i <= args.bot_count; i += 1) {
      await insertSeat(ctx, session.id, { player_name: `Bot ${i}`, is_bot: true });
    }
    return enterResult(session, hostSeat);
  },
});

export const joinSession = mutation({
  args: { room_code: v.string(), player_name: v.string(), ...guestArg },
  handler: async (ctx, args) => {
    const caller = await requireCaller(ctx, args.guest_secret_hash);
    const code = args.room_code.trim();
    const session = /^\d{6}$/.test(code)
      ? await ctx.db
          .query("game_sessions")
          .withIndex("by_room_code", (q) => q.eq("room_code", code))
          .first()
      : null;
    if (!session || session.status === "cancelled") fail(E.GAME_NOT_FOUND);
    const seats = await listSeats(ctx, session.id);
    const existing = seats.find((s) => s.user_id === caller.id);
    if (existing) {
      // Re-entry restores this identity's seat, including its role and death state.
      await ctx.db.patch(existing._id, { is_online: true, last_heartbeat: nowAppleEpochSeconds() });
      return enterResult(session, existing);
    }
    if (session.status !== "waiting") fail(E.GAME_STARTED);
    if (seats.length >= session.max_players) fail(E.GAME_FULL);
    const playerName = cleanText(args.player_name, 1, 50, E.PLAYER_NAME);
    const seat = await insertSeat(ctx, session.id, { user_id: caller.id, player_name: playerName, is_bot: false });
    return enterResult(session, seat);
  },
});

export const leaveSession = mutation({
  args: { session_id: v.string(), ...guestArg },
  handler: async (ctx, args) => {
    const caller = await requireCaller(ctx, args.guest_secret_hash);
    const session = await getSession(ctx, args.session_id);
    if (!session) return null;
    const seat = await ctx.db
      .query("session_players")
      .withIndex("by_session_user", (q) => q.eq("session_id", session.id).eq("user_id", caller.id))
      .first();
    await removeSeatAndTransferHost(ctx, session, seat, caller.id);
    return null;
  },
});

export const cancelSession = mutation({
  args: { session_id: v.string(), ...guestArg },
  handler: async (ctx, args) => {
    const { session } = await requireHost(ctx, args);
    await cancelSessionAndRemovePlayers(ctx, session);
    return null;
  },
});

export const removePlayer = mutation({
  args: { session_id: v.string(), player_record_id: v.string(), ...guestArg },
  handler: async (ctx, args) => {
    const { caller, session, seats } = await requireHost(ctx, args);
    const target = seats.find((s) => s.id === args.player_record_id) ?? fail(E.PLAYER_NOT_FOUND);
    if (target.user_id === caller.id) fail(E.REMOVE_SELF);
    await removeSeatAndTransferHost(ctx, session, target, target.user_id);
    return null;
  },
});

// Only the server-computed successor may take over, and only from a stale host.
export const claimHost = mutation({
  args: { session_id: v.string(), ...guestArg },
  handler: async (ctx, args) => {
    const { caller, session, seats } = await requireRoster(ctx, args);
    if (session.host_user_id === caller.id) return null;
    const hostSeat = seats.find((s) => s.user_id === session.host_user_id);
    if (hostSeat && nowAppleEpochSeconds() - hostSeat.last_heartbeat < HOST_STALE_SECONDS) fail(E.HOST_ACTIVE);
    const successor = nextHostAfterDeath(seats, session.host_user_id, true);
    if (successor?.user_id !== caller.id) fail(E.HOST_SUCCESSOR);
    await ctx.db.patch(session._id, { host_user_id: caller.id, updated_at: nowAppleEpochSeconds() });
    return null;
  },
});

export const heartbeat = mutation({
  args: { session_id: v.string(), ...guestArg },
  handler: async (ctx, args) => {
    const caller = await requireCaller(ctx, args.guest_secret_hash);
    const seat = await ctx.db
      .query("session_players")
      .withIndex("by_session_user", (q) => q.eq("session_id", args.session_id).eq("user_id", caller.id))
      .first();
    if (seat) await ctx.db.patch(seat._id, { last_heartbeat: nowAppleEpochSeconds(), is_online: true });
    return null;
  },
});

export const setReady = mutation({
  args: { session_id: v.string(), is_ready: v.boolean(), ...guestArg },
  handler: async (ctx, args) => {
    const { seat } = await requireSeat(ctx, args);
    await ctx.db.patch(seat._id, { is_ready: args.is_ready });
    return null;
  },
});

function assignmentsCoverSeats(
  seats: Doc<"session_players">[],
  assignments: { player_id: string; number: number }[],
) {
  const n = seats.length;
  const seatIds = new Set(seats.map((s) => s.player_id));
  const ids = new Set(assignments.map((a) => a.player_id));
  const numbers = new Set(assignments.map((a) => a.number));
  return (
    assignments.length === n &&
    ids.size === n &&
    [...ids].every((id) => seatIds.has(id)) &&
    numbers.size === n &&
    assignments.every((a) => Number.isInteger(a.number) && a.number >= 1 && a.number <= 2 * n)
  );
}

// One transaction: roles, numbers, in_progress, humans not ready, role_reveal.
export const startGame = mutation({
  args: {
    session_id: v.string(),
    assignments: v.array(v.object({ player_id: v.string(), role: roleValidator, number: v.number() })),
    ...guestArg,
  },
  handler: async (ctx, args) => {
    const { session, seats } = await requireHost(ctx, args);
    if (session.status !== "waiting" || session.current_phase !== "lobby") fail(E.GAME_STARTED);
    const n = seats.length;
    if (n < 4 || n > 19 || n > session.max_players) fail(E.PLAYER_COUNT);
    if (!assignmentsCoverSeats(seats, args.assignments)) fail(E.ASSIGNMENT_COVERAGE);
    const expected = roleDistribution(n);
    const count = (role: string) => args.assignments.filter((a) => a.role === role).length;
    if (
      count("mafia") !== expected.mafia ||
      count("doctor") !== expected.doctor ||
      count("inspector") !== expected.inspector ||
      count("citizen") !== expected.citizen
    ) {
      fail(E.ASSIGNMENT_ROLES);
    }
    for (const a of args.assignments) {
      const seat = seats.find((s) => s.player_id === a.player_id)!;
      await ctx.db.patch(seat._id, {
        role: a.role,
        player_number: a.number,
        is_alive: true,
        removal_note: undefined,
        ...(seat.is_bot ? {} : { is_ready: false }),
      });
    }
    const timestamp = nowAppleEpochSeconds();
    await ctx.db.patch(session._id, {
      status: "in_progress",
      started_at: timestamp,
      original_host_user_id: session.host_user_id,
      assigned_numbers: args.assignments.map((a) => ({ player_id: a.player_id, number: a.number })),
      current_phase: "role_reveal",
      current_phase_data: { type: "roleReveal", currentPlayerIndex: 0 },
      day_index: 0,
      is_game_over: false,
      winner: undefined,
      night_history: [],
      day_history: [],
      updated_at: timestamp,
    });
    return null;
  },
});

// Play Again. Any member may reset a finished game; the caller becomes host.
export const returnToLobby = mutation({
  args: { session_id: v.string(), ...guestArg },
  handler: async (ctx, args) => {
    const { caller, session, seats, seat } = await requireRoster(ctx, args);
    const over = session.is_game_over || session.current_phase === "game_over";
    if (session.current_phase !== "lobby" && !over) fail(E.NOT_GAME_OVER);
    const originalHostId = session.original_host_user_id ?? session.host_user_id;
    if (session.current_phase !== "lobby") {
      await resetToLobby(ctx, session, seats, caller.id);
    } else if (caller.id === originalHostId && session.host_user_id !== originalHostId) {
      await ctx.db.patch(session._id, { host_user_id: originalHostId, updated_at: nowAppleEpochSeconds() });
    }
    await ctx.db.patch(seat._id, { is_ready: true });
    return null;
  },
});
