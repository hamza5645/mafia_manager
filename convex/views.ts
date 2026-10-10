import { v } from "convex/values";
import { Doc } from "./_generated/dataModel";
import { QueryCtx, query } from "./_generated/server";
import { getSession, listSeats } from "./lib/guards";
import { getCaller } from "./lib/identity";
import { actionForViewer, playerForViewer, sessionForViewer, tentativeForViewer } from "./lib/projections";
import { NIGHT_TYPES, nightActionsReady, sessionData, votesReady } from "./lib/rules";
import { guestArg } from "./validators";

// Subscription snapshots. These never throw ConvexError: a missing session or a
// non-member viewer gets null / [] so the client can observe its own removal.

async function loadMember(ctx: QueryCtx, args: { session_id: string; guest_secret_hash?: string }) {
  const session = await getSession(ctx, args.session_id);
  if (!session) return null;
  const caller = await getCaller(ctx, args.guest_secret_hash);
  if (!caller) return null;
  const seats = await listSeats(ctx, session.id);
  const seat = seats.find((s) => s.user_id === caller.id);
  if (!seat) return null;
  return { session, seats, seat, isHost: session.host_user_id === caller.id };
}

export const getSessionView = query({
  args: { session_id: v.string(), ...guestArg },
  handler: async (ctx, args) => {
    const session = await getSession(ctx, args.session_id);
    if (!session) return null;
    const caller = await getCaller(ctx, args.guest_secret_hash);
    // Only the caller's own seat is read, so other players' heartbeats don't re-run this.
    const seat = caller
      ? await ctx.db
          .query("session_players")
          .withIndex("by_session_user", (q) => q.eq("session_id", session.id).eq("user_id", caller.id))
          .first()
      : null;
    return {
      session: sessionForViewer(session, caller, seat),
      viewer: {
        user_id: caller?.id ?? null,
        player_record_id: seat?.id ?? null,
        player_id: seat?.player_id ?? null,
        is_member: seat !== null,
        is_host: caller !== null && session.host_user_id === caller.id,
      },
    };
  },
});

export const getPlayers = query({
  args: { session_id: v.string(), ...guestArg },
  handler: async (ctx, args) => {
    const member = await loadMember(ctx, args);
    if (!member) return [];
    return member.seats.map((s) => playerForViewer(s, member.session, member.seat, member.isHost));
  },
});

function phaseIndexOf(session: Doc<"game_sessions">): number | null {
  const { phase: data } = sessionData(session);
  if (session.current_phase === "night") return data?.nightIndex ?? null;
  if (["voting", "voting_results", "vote_death_reveal"].includes(session.current_phase)) return data?.dayIndex ?? null;
  return null;
}

export const getRoundState = query({
  args: { session_id: v.string(), ...guestArg },
  handler: async (ctx, args) => {
    const member = await loadMember(ctx, args);
    if (!member) return null;
    const { session, seats, seat, isHost } = member;
    const roundId = session.current_round_id ?? null;
    const phaseIndex = phaseIndexOf(session);

    const actions = roundId
      ? (
          await ctx.db
            .query("game_actions")
            .withIndex("by_session_round_type_phase", (q) => q.eq("session_id", session.id).eq("round_id", roundId))
            .collect()
        ).sort((a, b) => a.created_at - b.created_at || a._creationTime - b._creationTime)
      : [];
    const tentativeTypes =
      session.current_phase === "night" ? NIGHT_TYPES : session.current_phase === "voting" ? (["vote"] as const) : [];
    const tentatives = [];
    if (phaseIndex !== null) {
      for (const type of tentativeTypes) {
        tentatives.push(
          ...(await ctx.db
            .query("tentative_selections")
            .withIndex("by_session_phase_type", (q) =>
              q.eq("session_id", session.id).eq("phase_index", phaseIndex).eq("action_type", type),
            )
            .collect()),
        );
      }
    }

    const votes = actions.filter((a) => a.action_type === "vote" && a.phase_index === phaseIndex);
    let ready = false;
    if (isHost && session.current_phase === "role_reveal") {
      ready = seats.every((s) => s.is_bot || s.is_ready);
    } else if (isHost && session.current_phase === "night" && roundId !== null && phaseIndex !== null) {
      const resolved = sessionData(session).nights.some((e) => e.round_id === roundId && e.is_resolved);
      ready = !resolved && nightActionsReady(seats, actions, roundId, phaseIndex);
    } else if (isHost && session.current_phase === "voting") {
      ready = votesReady(seats, votes);
    }

    const allVoted = seats.filter((s) => s.is_alive).every((s) => votes.some((a) => a.actor_player_id === s.player_id));
    const viewer = { session, seat, isHost, allVoted };
    return {
      round_id: roundId,
      phase: session.current_phase,
      phase_index: phaseIndex,
      ready_to_advance: ready,
      actions: actions.flatMap((row) => actionForViewer(row, viewer) ?? []),
      tentative: tentatives.flatMap((row) => tentativeForViewer(row, viewer) ?? []),
    };
  },
});
