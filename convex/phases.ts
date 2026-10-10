import { v } from "convex/values";
import { mutation } from "./_generated/server";
import { E, fail } from "./lib/errors";
import { requireHost } from "./lib/guards";
import { readEliminatedId, readVoteCounts, sessionData } from "./lib/rules";
import { enterRound } from "./lib/transitions";
import { nowAppleEpochSeconds } from "./lib/util";
import { guestArg, phaseTargetValidator } from "./validators";

const PREDECESSOR = {
  night: "role_reveal",
  death_reveal: "morning",
  voting: "death_reveal",
  vote_death_reveal: "voting_results",
} as const;

// Outcome-free transitions only. Outcomes (deaths, winners, histories) are
// written by night:resolveNightAtomic and voting:resolveVoteAtomic.
export const advancePhase = mutation({
  args: { session_id: v.string(), to_phase: phaseTargetValidator, ...guestArg },
  handler: async (ctx, args) => {
    const { session, seats } = await requireHost(ctx, args);
    if (session.current_phase === args.to_phase) return { current_phase: session.current_phase };
    if (session.status !== "in_progress" || session.is_game_over) fail(E.NOT_ACTIVE);
    if (session.current_phase !== PREDECESSOR[args.to_phase]) fail(E.MOVED_ON);
    const { phase: data } = sessionData(session);

    if (args.to_phase === "night") {
      await enterRound(ctx, session, seats, "night", { type: "night", nightIndex: 0 });
    } else if (args.to_phase === "voting") {
      await enterRound(ctx, session, seats, "voting", { type: "voting", dayIndex: session.day_index });
    } else if (args.to_phase === "death_reveal") {
      await ctx.db.patch(session._id, {
        current_phase: "death_reveal",
        current_phase_data: { type: "deathReveal", nightIndex: data?.nightIndex },
        updated_at: nowAppleEpochSeconds(),
      });
    } else {
      // MGS 2497-2547.
      const eliminatedId = readEliminatedId(data);
      const seat = seats.find((s) => s.player_id === eliminatedId);
      await ctx.db.patch(session._id, {
        current_phase: "vote_death_reveal",
        current_phase_data: {
          type: "voteDeathReveal",
          dayIndex: data?.dayIndex,
          eliminatedPlayerId: eliminatedId,
          eliminatedPlayerName: seat?.player_name,
          eliminatedPlayerNumber: seat?.player_number,
          eliminatedPlayerRole: seat?.role,
          voteCount: eliminatedId ? readVoteCounts(data)[eliminatedId] : undefined,
        },
        updated_at: nowAppleEpochSeconds(),
      });
    }
    return { current_phase: args.to_phase };
  },
});
