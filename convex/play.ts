import { ConvexError, v } from "convex/values";
import { Doc } from "./_generated/dataModel";
import { MutationCtx, mutation } from "./_generated/server";
import { E, fail } from "./lib/errors";
import { requireHost, requireSeat, seatByPlayer } from "./lib/guards";
import { sessionData, validateGameAction } from "./lib/rules";
import { nowAppleEpochSeconds, uuid } from "./lib/util";
import { actionTypeValidator, guestArg } from "./validators";

type Seat = Doc<"session_players">;
type ActionArgs = {
  session_id: string;
  round_id: string;
  action_type: Doc<"game_actions">["action_type"];
  phase_index: number;
  actor_player_id: string;
  target_player_id?: string;
};
type InspectorResult = "mafia" | "not_mafia" | "blocked";

// Bots are driven by the host; humans act only for their own seat.
function requireActor(caller: Doc<"users">, session: Doc<"game_sessions">, actor: Seat | null | undefined): Seat {
  if (!actor) return fail(E.PLAYER_NOT_FOUND);
  if (actor.is_bot ? session.host_user_id !== caller.id : actor.user_id !== caller.id) {
    fail(actor.is_bot ? E.HOST_ONLY : E.NOT_YOUR_PLAYER);
  }
  return actor;
}

// The checked actor and the target by point read instead of the whole roster
// (validateGameAction looks up only these two). The caller's own seat is
// reused when it is the actor.
async function actorAndTarget(
  ctx: MutationCtx,
  caller: Doc<"users">,
  session: Doc<"game_sessions">,
  own: Seat,
  args: { actor_player_id: string; target_player_id?: string },
): Promise<Seat[]> {
  const read = async (playerId: string) =>
    playerId === own.player_id ? own : await seatByPlayer(ctx, session.id, playerId);
  const actor = requireActor(caller, session, await read(args.actor_player_id));
  const target = args.target_player_id === undefined ? null : await read(args.target_player_id);
  return target ? [actor, target] : [actor];
}

const nightClosed = (session: Doc<"game_sessions">, roundId: string | undefined) =>
  roundId !== undefined && sessionData(session).nights.some((e) => e.round_id === roundId);

// Validates and stores one action. `seats` must hold the actor and the target
// (validateGameAction looks up only those two). Every check runs before any write.
async function storeAction(ctx: MutationCtx, session: Doc<"game_sessions">, seats: Seat[], args: ActionArgs) {
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
      return { success: true, result: existing.action_data?.inspector_result as InspectorResult | undefined };
    }
    const target = seats.find((s) => s.player_id === args.target_player_id);
    const result: InspectorResult | undefined = !target
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

  // Same target: nothing to write, and created_at keeps its tie-break position.
  if (existing && existing.target_player_id === args.target_player_id) return { success: true };
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
}

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
    const { caller, session, seat } = await requireSeat(ctx, args);
    const seats = await actorAndTarget(ctx, caller, session, seat, args);
    return await storeAction(ctx, session, seats, args);
  },
});

// Host only: every pending bot action in one transaction against one roster
// read. Each item gets exactly submitAction's checks; a failing item reports
// its message and does not stop the others.
export const submitBotActions = mutation({
  args: {
    session_id: v.string(),
    round_id: v.string(),
    phase_index: v.number(),
    actions: v.array(
      v.object({
        actor_player_id: v.string(),
        action_type: actionTypeValidator,
        target_player_id: v.optional(v.string()),
      }),
    ),
    ...guestArg,
  },
  handler: async (ctx, args) => {
    const { caller, session, seats } = await requireHost(ctx, args);
    const results: { actor_player_id: string; ok: boolean; error?: string; result?: InspectorResult }[] = [];
    for (const item of args.actions) {
      try {
        const actor = requireActor(caller, session, seats.find((s) => s.player_id === item.actor_player_id));
        if (!actor.is_bot) fail(E.NOT_YOUR_PLAYER);
        const stored = await storeAction(ctx, session, seats, {
          session_id: args.session_id,
          round_id: args.round_id,
          phase_index: args.phase_index,
          ...item,
        });
        const result = "result" in stored ? stored.result : undefined;
        results.push({ actor_player_id: item.actor_player_id, ok: true, ...(result ? { result } : {}) });
      } catch (error) {
        if (!(error instanceof ConvexError)) throw error;
        results.push({ actor_player_id: item.actor_player_id, ok: false, error: String(error.data) });
      }
    }
    return { results };
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
    const { caller, session, seat } = await requireSeat(ctx, args);
    validateGameAction(session, await actorAndTarget(ctx, caller, session, seat, args), args);
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
    // A tap on the current draft target writes nothing.
    if (existing && existing.target_player_id === args.target_player_id) return null;
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
