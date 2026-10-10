import { v } from "convex/values";
import { mutation } from "./_generated/server";
import { E, fail } from "./lib/errors";
import { requireHost } from "./lib/guards";
import { NIGHT_TYPES, NightRecord, buildNightRecord, evaluateWinners, nightActionsReady, sessionData } from "./lib/rules";
import { finishGame, transferHostAfterDeath } from "./lib/transitions";
import { nowAppleEpochSeconds } from "./lib/util";
import { guestArg } from "./validators";

// Two-phase night: recordNightActions stores an unresolved record and closes
// the night's actions; resolveNightAtomic applies it. Both are idempotent per round.
const byNightIndex = (a: NightRecord, b: NightRecord) => a.night_index - b.night_index;

export const recordNightActions = mutation({
  args: { session_id: v.string(), round_id: v.string(), ...guestArg },
  handler: async (ctx, args) => {
    const { session, seats } = await requireHost(ctx, args);
    const { phase, nights } = sessionData(session);
    const existing = nights.find((e) => e.round_id === args.round_id);
    if (existing) return existing;
    if (session.status !== "in_progress" || session.is_game_over) fail(E.NOT_ACTIVE);
    if (session.current_phase !== "night" || session.current_round_id !== args.round_id) fail(E.MOVED_ON);
    const n = phase?.nightIndex;
    if (n === undefined || !Number.isInteger(n)) fail(E.MOVED_ON);

    const actions = (
      await Promise.all(
        NIGHT_TYPES.map((type) =>
          ctx.db
            .query("game_actions")
            .withIndex("by_session_round_type_phase", (q) =>
              q.eq("session_id", session.id).eq("round_id", args.round_id).eq("action_type", type).eq("phase_index", n),
            )
            .collect(),
        ),
      )
    ).flat();
    if (!nightActionsReady(seats, actions, args.round_id, n)) fail(E.NIGHT_INCOMPLETE);

    const record = buildNightRecord(seats, actions, n, args.round_id);
    const nightHistory = [...nights.filter((e) => e.night_index !== n), record].sort(byNightIndex);
    await ctx.db.patch(session._id, { night_history: nightHistory, updated_at: nowAppleEpochSeconds() });
    return record;
  },
});

export const resolveNightAtomic = mutation({
  args: { session_id: v.string(), round_id: v.string(), ...guestArg },
  handler: async (ctx, args) => {
    const { session, seats } = await requireHost(ctx, args);
    const { nights } = sessionData(session);
    const rec = nights.find((e) => e.round_id === args.round_id);
    if (rec?.is_resolved) {
      return {
        night_index: rec.night_index,
        resulting_deaths: rec.resulting_deaths,
        next_phase: rec.next_phase,
        winner: rec.next_phase === "game_over" ? (session.winner ?? null) : null,
      };
    }
    if (!rec) {
      const recordable = session.current_round_id === args.round_id && session.current_phase === "night";
      fail(recordable ? E.NIGHT_NOT_RECORDED : E.MOVED_ON);
    }
    if (session.status !== "in_progress" || session.is_game_over) fail(E.NOT_ACTIVE);
    if (session.current_phase !== "night" || session.current_round_id !== args.round_id) fail(E.MOVED_ON);

    const victim = seats.find((s) => s.is_alive && s.player_id === rec.mafia_target_id);
    const deaths: string[] = victim && !rec.target_was_saved ? [victim.player_id] : [];
    const revealed: NightRecord["revealed_death_roles"] = {};
    for (const seat of seats) {
      if (!deaths.includes(seat.player_id)) continue;
      await ctx.db.patch(seat._id, { is_alive: false, removal_note: "night" });
      if (seat.role) revealed[seat.player_id] = seat.role;
    }
    const seatsAfter = seats.map((s) => (deaths.includes(s.player_id) ? { ...s, is_alive: false } : s));
    const win = evaluateWinners(seatsAfter.filter((s) => s.is_alive), true);
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
  },
});
