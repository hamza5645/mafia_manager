import { v } from "convex/values";
import { Doc } from "./_generated/dataModel";
import { MutationCtx, mutation } from "./_generated/server";
import { E, fail } from "./lib/errors";
import { getSession, listSeats, requireHost, requireRoster, requireSeat, seatOf } from "./lib/guards";
import { requireCaller } from "./lib/identity";
import { ONLINE_SECONDS, heartbeatsOf, touchPresence } from "./lib/presence";
import { hostStaleAfter, nextHostAfterDeath, roleDistribution } from "./lib/rules";
import { cancelSessionAndRemovePlayers, removeSeatAndTransferHost, resetToLobby } from "./lib/transitions";
import { cleanText, nowAppleEpochSeconds, uuid } from "./lib/util";
import { guestArg, roleValidator } from "./validators";

// Lobby, membership and host management.

// `rejoined` tells the app the seat existed before this call, so a cancelled
// entry must not give it back (only a seat the entry created is left).
function enterResult(
  session: { id: string; room_code: string },
  seat: { id: string; player_id: string },
  rejoined: boolean,
) {
  return {
    session_id: session.id,
    room_code: session.room_code,
    player_record_id: seat.id,
    player_id: seat.player_id,
    rejoined,
  };
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
    joined_at: timestamp,
  };
  await ctx.db.insert("session_players", doc);
  if (seat.user_id) await touchPresence(ctx, sessionId, seat.user_id, timestamp);
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
    return enterResult(session, hostSeat, false);
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
      await touchPresence(ctx, session.id, caller.id, nowAppleEpochSeconds());
      if (!existing.is_online) await ctx.db.patch(existing._id, { is_online: true });
      return enterResult(session, existing, true);
    }
    if (session.status !== "waiting") fail(E.GAME_STARTED);
    if (seats.length >= session.max_players) fail(E.GAME_FULL);
    const playerName = cleanText(args.player_name, 1, 50, E.PLAYER_NAME);
    const seat = await insertSeat(ctx, session.id, { user_id: caller.id, player_name: playerName, is_bot: false });
    return enterResult(session, seat, false);
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

// Any member may report a stale host; the server, by its own clock, installs
// its own successor (who may not be the caller).
export const claimHost = mutation({
  args: { session_id: v.string(), ...guestArg },
  handler: async (ctx, args) => {
    const { caller, session, seats } = await requireRoster(ctx, args);
    if (session.host_user_id === caller.id) return null;
    const heartbeats = await heartbeatsOf(ctx, session.id);
    const hostBeat = heartbeats.get(session.host_user_id);
    if (hostBeat !== undefined && nowAppleEpochSeconds() - hostBeat < hostStaleAfter(session)) fail(E.HOST_ACTIVE);
    const successor = nextHostAfterDeath(seats, session.host_user_id, heartbeats) ?? fail(E.HOST_SUCCESSOR);
    await ctx.db.patch(session._id, { host_user_id: successor.user_id!, updated_at: nowAppleEpochSeconds() });
    return null;
  },
});

// Writes only the caller's presence row. The host's beat also refreshes every
// human seat's is_online, patching only the seats whose value changes.
export const heartbeat = mutation({
  args: { session_id: v.string(), ...guestArg },
  handler: async (ctx, args) => {
    const caller = await requireCaller(ctx, args.guest_secret_hash);
    const session = await getSession(ctx, args.session_id);
    if (!session || !(await seatOf(ctx, session.id, caller.id))) return null;
    const now = nowAppleEpochSeconds();
    await touchPresence(ctx, session.id, caller.id, now);
    if (session.host_user_id !== caller.id) return null;
    const heartbeats = await heartbeatsOf(ctx, session.id);
    for (const seat of await listSeats(ctx, session.id)) {
      if (seat.is_bot || !seat.user_id) continue;
      const beat = heartbeats.get(seat.user_id);
      const online = beat !== undefined && now - beat <= ONLINE_SECONDS;
      if (seat.is_online !== online) await ctx.db.patch(seat._id, { is_online: online });
    }
    return null;
  },
});

// `phase` is the phase the tap was made in. The Convex client resends a queued
// mutation after a reconnect, so a setReady can land in a later phase; it is
// then dropped instead of marking ready a seat that never confirmed there.
export const setReady = mutation({
  args: { session_id: v.string(), is_ready: v.boolean(), phase: v.optional(v.string()), ...guestArg },
  handler: async (ctx, args) => {
    const { session, seat } = await requireSeat(ctx, args);
    if (args.phase !== undefined && args.phase !== session.current_phase) return null;
    if (seat.is_ready !== args.is_ready) await ctx.db.patch(seat._id, { is_ready: args.is_ready });
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
