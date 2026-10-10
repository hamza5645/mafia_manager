import { v } from "convex/values";
import { mutation } from "./_generated/server";
import { E, fail } from "./lib/errors";
import { requireHost } from "./lib/guards";
import { DayRecord, evaluateWinners, readEliminatedId, sessionData, tallyVotes, votesReady } from "./lib/rules";
import { enterRound, finishGame, transferHostAfterDeath } from "./lib/transitions";
import { nowAppleEpochSeconds } from "./lib/util";
import { guestArg } from "./validators";

// Two-step day: closeVoting tallies into voting_results; after the reveal,
// resolveVoteAtomic applies the elimination. Both are idempotent per round.

export const closeVoting = mutation({
  args: { session_id: v.string(), round_id: v.string(), ...guestArg },
  handler: async (ctx, args) => {
    const { session, seats } = await requireHost(ctx, args);
    const { phase, days } = sessionData(session);
    if (
      session.current_round_id === args.round_id &&
      (session.current_phase === "voting_results" || session.current_phase === "vote_death_reveal")
    ) {
      return { day_index: phase?.dayIndex, eliminated_player_id: readEliminatedId(phase) ?? null };
    }
    const dh = days.find((e) => e.round_id === args.round_id);
    if (dh) return { day_index: dh.day_index, eliminated_player_id: dh.removed_player_ids[0] ?? null };
    if (session.status !== "in_progress" || session.is_game_over) fail(E.NOT_ACTIVE);
    if (session.current_phase !== "voting" || session.current_round_id !== args.round_id) fail(E.MOVED_ON);

    const d = phase?.dayIndex;
    if (d === undefined || !Number.isInteger(d)) fail(E.MOVED_ON);
    const rows = await ctx.db
      .query("game_actions")
      .withIndex("by_session_round_type_phase", (q) =>
        q.eq("session_id", session.id).eq("round_id", args.round_id).eq("action_type", "vote").eq("phase_index", d),
      )
      .collect();
    const votes = rows.filter((a) => seats.some((s) => s.is_alive && s.player_id === a.actor_player_id));
    if (!votesReady(seats, votes)) fail(E.VOTES_INCOMPLETE);
    const { counts, eliminated } = tallyVotes(seats, votes);
    await ctx.db.patch(session._id, {
      current_phase: "voting_results",
      current_phase_data: { type: "votingResults", dayIndex: d, voteCounts: counts, eliminatedPlayerId: eliminated },
      updated_at: nowAppleEpochSeconds(),
    });
    return { day_index: d, eliminated_player_id: eliminated ?? null };
  },
});

export const resolveVoteAtomic = mutation({
  args: { session_id: v.string(), round_id: v.string(), ...guestArg },
  handler: async (ctx, args) => {
    const { session, seats } = await requireHost(ctx, args);
    const { phase, days } = sessionData(session);
    const dh = days.find((e) => e.round_id === args.round_id);
    if (dh) {
      return {
        day_index: dh.day_index,
        eliminated_player_id: dh.removed_player_ids[0] ?? null,
        next_phase: dh.next_phase,
        winner: dh.next_phase === "game_over" ? (session.winner ?? null) : null,
      };
    }
    if (session.status !== "in_progress" || session.is_game_over) fail(E.NOT_ACTIVE);
    if (session.current_round_id !== args.round_id) fail(E.MOVED_ON);
    if (session.current_phase !== "vote_death_reveal") fail(E.WRONG_PHASE);

    const d = phase?.dayIndex;
    if (d === undefined || !Number.isInteger(d)) fail(E.MOVED_ON);
    const eliminatedId = readEliminatedId(phase);
    const victim = seats.find((s) => s.is_alive && s.player_id === eliminatedId);
    const removed = victim ? [victim.player_id] : [];
    if (victim) await ctx.db.patch(victim._id, { is_alive: false, removal_note: "Voted out" });
    const seatsAfter = seats.map((s) => (s === victim ? { ...s, is_alive: false } : s));
    const win = evaluateWinners(seatsAfter.filter((s) => s.is_alive), false);
    const next = win.over ? "game_over" : "night";
    const record: DayRecord = {
      day_index: d,
      round_id: args.round_id,
      removed_player_ids: removed,
      next_phase: next,
      timestamp: nowAppleEpochSeconds(),
    };
    const dayHistory = [...days.filter((e) => e.day_index !== d), record].sort((a, b) => a.day_index - b.day_index);
    await ctx.db.patch(session._id, { day_index: d + 1, day_history: dayHistory, updated_at: nowAppleEpochSeconds() });

    if (win.over) await finishGame(ctx, session, seats, win.winner);
    else await enterRound(ctx, session, seats, "night", { type: "night", nightIndex: d + 1 });
    if (victim && victim.user_id === session.host_user_id) await transferHostAfterDeath(ctx, session, seatsAfter);
    return {
      day_index: d,
      eliminated_player_id: removed[0] ?? null,
      next_phase: next,
      winner: win.over ? (win.winner ?? null) : null,
    };
  },
});
