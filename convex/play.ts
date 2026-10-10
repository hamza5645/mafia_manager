import { v } from "convex/values";
import { Doc } from "./_generated/dataModel";
import { mutation } from "./_generated/server";
import { E, fail } from "./lib/errors";
import { requireRoster } from "./lib/guards";
import { validateGameAction } from "./lib/rules";
import { nowAppleEpochSeconds, uuid } from "./lib/util";
import { actionTypeValidator, guestArg } from "./validators";

// Bots are driven by the host; humans act only for their own seat.
function requireActor(
  caller: Doc<"users">,
  session: Doc<"game_sessions">,
  seats: Doc<"session_players">[],
  actorPlayerId: string,
) {
  const actor = seats.find((s) => s.player_id === actorPlayerId) ?? fail(E.PLAYER_NOT_FOUND);
  if (actor.is_bot ? session.host_user_id !== caller.id : actor.user_id !== caller.id) {
    fail(actor.is_bot ? E.HOST_ONLY : E.NOT_YOUR_PLAYER);
  }
}

const nightClosed = (session: Doc<"game_sessions">, roundId: string | undefined) =>
  roundId !== undefined && session.night_history.some((e: any) => e.round_id === roundId);

export const submitAction = mutation({
  args: {
    session_id: v.string(),
    round_id: v.string(),
    action_type: actionTypeValidator,
    phase_index: v.number(),
    actor_player_id: v.string(),
    target_player_id: v.optional(v.string()),
    ...guestArg,
  },
  handler: async (ctx, args) => {
    const { caller, session, seats } = await requireRoster(ctx, args);
    requireActor(caller, session, seats, args.actor_player_id);
    if (!session.current_round_id || session.current_round_id !== args.round_id) fail(E.MOVED_ON);
    validateGameAction(session, seats, args);
    if (args.action_type !== "vote" && nightClosed(session, args.round_id)) fail(E.NIGHT_CLOSED);

    const existing = await ctx.db
      .query("game_actions")
      .withIndex("by_unique_action", (q) =>
        q
          .eq("session_id", args.session_id)
          .eq("round_id", args.round_id)
          .eq("action_type", args.action_type)
          .eq("phase_index", args.phase_index)
          .eq("actor_player_id", args.actor_player_id),
      )
      .first();

    if (args.action_type === "inspector_check") {
      // One check per round: a retry returns the stored result.
      if (existing) {
        if (existing.target_player_id !== args.target_player_id) fail(E.ALREADY_INSPECTED);
        return { success: true, result: existing.action_data?.inspector_result };
      }
      const target = seats.find((s) => s.player_id === args.target_player_id);
      const result = !target
        ? undefined
        : target.role === "inspector"
          ? "blocked"
          : target.role === "mafia"
            ? "mafia"
            : "not_mafia";
      await ctx.db.insert("game_actions", {
        id: uuid(),
        session_id: args.session_id,
        round_id: args.round_id,
        action_type: args.action_type,
        phase_index: args.phase_index,
        actor_player_id: args.actor_player_id,
        target_player_id: args.target_player_id,
        action_data: result ? { inspector_result: result } : undefined,
        created_at: nowAppleEpochSeconds(),
      });
      return { success: true, result };
    }

    if (existing) {
      await ctx.db.patch(existing._id, { target_player_id: args.target_player_id, created_at: nowAppleEpochSeconds() });
    } else {
      await ctx.db.insert("game_actions", {
        id: uuid(),
        session_id: args.session_id,
        round_id: args.round_id,
        action_type: args.action_type,
        phase_index: args.phase_index,
        actor_player_id: args.actor_player_id,
        target_player_id: args.target_player_id,
        created_at: nowAppleEpochSeconds(),
      });
    }
    return { success: true };
  },
});

export const setTentativeSelection = mutation({
  args: {
    session_id: v.string(),
    actor_player_id: v.string(),
    action_type: actionTypeValidator,
    phase_index: v.number(),
    target_player_id: v.optional(v.string()),
    ...guestArg,
  },
  handler: async (ctx, args) => {
    const { caller, session, seats } = await requireRoster(ctx, args);
    requireActor(caller, session, seats, args.actor_player_id);
    validateGameAction(session, seats, args);
    if (args.action_type !== "vote" && nightClosed(session, session.current_round_id)) fail(E.NIGHT_CLOSED);
    const existing = await ctx.db
      .query("tentative_selections")
      .withIndex("by_actor", (q) =>
        q
          .eq("session_id", args.session_id)
          .eq("phase_index", args.phase_index)
          .eq("action_type", args.action_type)
          .eq("actor_player_id", args.actor_player_id),
      )
      .first();
    const payload = { target_player_id: args.target_player_id, updated_at: nowAppleEpochSeconds() };
    if (existing) {
      await ctx.db.patch(existing._id, payload);
    } else {
      await ctx.db.insert("tentative_selections", {
        id: uuid(),
        session_id: args.session_id,
        actor_player_id: args.actor_player_id,
        action_type: args.action_type,
        phase_index: args.phase_index,
        ...payload,
      });
    }
    return null;
  },
});
