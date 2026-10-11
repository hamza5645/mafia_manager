import { v } from "convex/values";
import { Doc } from "./_generated/dataModel";
import { MutationCtx, mutation } from "./_generated/server";
import { E, fail } from "./lib/errors";
import { getSession, requireHost } from "./lib/guards";
import { NIGHT_TYPES, NightRecord, buildNightRecord, evaluateWinners, nightActionsReady, sessionData } from "./lib/rules";
import { finishGame, transferHostAfterDeath } from "./lib/transitions";
import { nowAppleEpochSeconds } from "./lib/util";
import { guestArg } from "./validators";

// Two-phase night: the record step stores an unresolved record and closes the
// night's actions; the resolve step applies it. Both are idempotent per round.
// finishNight runs both in one transaction; the separate endpoints remain.
const byNightIndex = (a: NightRecord, b: NightRecord) => a.night_index - b.night_index;
type Session = Doc<"game_sessions">;
type Seat = Doc<"session_players">;

async function recordNight(ctx: MutationCtx, session: Session, seats: Seat[], roundId: string): Promise<NightRecord> {
  const { phase, nights } = sessionData(session);
  const existing = nights.find((e) => e.round_id === roundId);
  if (existing) return existing;
  if (session.status !== "in_progress" || session.is_game_over) fail(E.NOT_ACTIVE);
  if (session.current_phase !== "night" || session.current_round_id !== roundId) fail(E.MOVED_ON);
  const n = phase?.nightIndex;
  if (n === undefined || !Number.isInteger(n)) fail(E.MOVED_ON);

  const actions = (
    await Promise.all(
      NIGHT_TYPES.map((type) =>
        ctx.db
          .query("game_actions")
          .withIndex("by_unique_action", (q) =>
            q.eq("session_id", session.id).eq("round_id", roundId).eq("action_type", type).eq("phase_index", n),
          )
          .collect(),
      ),
    )
  ).flat();
  if (!nightActionsReady(seats, actions, roundId, n)) fail(E.NIGHT_INCOMPLETE);

  const record = buildNightRecord(seats, actions, n, roundId);
  const nightHistory = [...nights.filter((e) => e.night_index !== n), record].sort(byNightIndex);
  await ctx.db.patch(session._id, { night_history: nightHistory, updated_at: nowAppleEpochSeconds() });
  return record;
}

async function resolveNight(ctx: MutationCtx, session: Session, seats: Seat[], roundId: string) {
  const { nights } = sessionData(session);
  const rec = nights.find((e) => e.round_id === roundId);
  if (rec?.is_resolved) {
    return {
      night_index: rec.night_index,
      resulting_deaths: rec.resulting_deaths,
      next_phase: rec.next_phase,
      winner: rec.next_phase === "game_over" ? (session.winner ?? null) : null,
    };
  }
  if (!rec) {
    const recordable = session.current_round_id === roundId && session.current_phase === "night";
    fail(recordable ? E.NIGHT_NOT_RECORDED : E.MOVED_ON);
  }
  if (session.status !== "in_progress" || session.is_game_over) fail(E.NOT_ACTIVE);
  if (session.current_phase !== "night" || session.current_round_id !== roundId) fail(E.MOVED_ON);

  const victim = seats.find((s) => s.is_alive && s.player_id === rec.mafia_target_id);
  const deaths: string[] = victim && !rec.target_was_saved ? [victim.player_id] : [];
  const revealed: NightRecord["revealed_death_roles"] = {};
  for (const seat of seats) {
    if (!deaths.includes(seat.player_id)) continue;
    await ctx.db.patch(seat._id, { is_alive: false, removal_note: "night" });
    if (seat.role) revealed[seat.player_id] = seat.role;
  }
  const seatsAfter = seats.map((s) => (deaths.includes(s.player_id) ? { ...s, is_alive: false } : s));
  const win = evaluateWinners(seatsAfter.filter((s) => s.is_alive));
  const next = win.over ? "game_over" : "morning";
  const resolved: NightRecord = {
    ...rec,
    is_resolved: true,
    resulting_deaths: deaths,
    revealed_death_roles: revealed,
    next_phase: next,
  };

  if (win.over) {
    await finishGame(ctx, session, seats, win.winner);
  } else {
    await ctx.db.patch(session._id, {
      current_phase: "morning",
      current_phase_data: { type: "morning", nightIndex: rec.night_index },
    });
  }
  const hostSeat = seats.find((s) => s.user_id === session.host_user_id);
  if (hostSeat && deaths.includes(hostSeat.player_id)) await transferHostAfterDeath(ctx, session, seatsAfter);
  await ctx.db.patch(session._id, {
    night_history: nights.map((e) => (e.night_index === rec.night_index ? resolved : e)).sort(byNightIndex),
    updated_at: nowAppleEpochSeconds(),
  });
  return {
    night_index: rec.night_index,
    resulting_deaths: deaths,
    next_phase: next,
    winner: win.over ? (win.winner ?? null) : null,
  };
}

export const recordNightActions = mutation({
  args: { session_id: v.string(), round_id: v.string(), ...guestArg },
  handler: async (ctx, args) => {
    const { session, seats } = await requireHost(ctx, args);
    return await recordNight(ctx, session, seats, args.round_id);
  },
});

export const resolveNightAtomic = mutation({
  args: { session_id: v.string(), round_id: v.string(), ...guestArg },
  handler: async (ctx, args) => {
    const { session, seats } = await requireHost(ctx, args);
    return await resolveNight(ctx, session, seats, args.round_id);
  },
});

// Finish Night in one host call: the record step, then the resolve step, in one
// transaction, so every phone sees a single transition. Same result as
// resolveNightAtomic, and idempotent per round.
export const finishNight = mutation({
  args: { session_id: v.string(), round_id: v.string(), ...guestArg },
  handler: async (ctx, args) => {
    const { session, seats } = await requireHost(ctx, args);
    await recordNight(ctx, session, seats, args.round_id);
    const recorded = (await getSession(ctx, session.id)) ?? fail(E.GAME_NOT_FOUND);
    return await resolveNight(ctx, recorded, seats, args.round_id);
  },
});
