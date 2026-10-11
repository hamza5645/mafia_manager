import { v } from "convex/values";
import { Doc } from "./_generated/dataModel";
import { QueryCtx, query } from "./_generated/server";
import { getSession, listSeats, seatOf } from "./lib/guards";
import { getCaller } from "./lib/identity";
import { presenceOf } from "./lib/presence";
import {
  actionForViewer,
  hostPresenceValidator,
  isOver,
  playerForViewer,
  playerViewValidator,
  roundStateValidator,
  sessionForViewer,
  sessionViewValidator,
  tentativeForViewer,
} from "./lib/projections";
import { NIGHT_TYPES, TYPE_OF_ROLE, hostStaleAfter, nightActionsReady, sessionData, votesReady } from "./lib/rules";
import { nowAppleEpochSeconds } from "./lib/util";
import { guestArg } from "./validators";

// Subscription snapshots. These never throw ConvexError: a missing session or a
// non-member viewer gets null / [] so the client can observe its own removal.
// None of them reads session_presence except getHostPresence, so heartbeats
// re-run only that one.

async function loadMember(ctx: QueryCtx, args: { session_id: string; guest_secret_hash?: string }) {
  const session = await getSession(ctx, args.session_id);
  if (!session) return null;
  const caller = await getCaller(ctx, args.guest_secret_hash);
  if (!caller) return null;
  const seat = await seatOf(ctx, session.id, caller.id);
  if (!seat) return null;
  return { session, seat, isHost: session.host_user_id === caller.id };
}

export const getSessionView = query({
  args: { session_id: v.string(), ...guestArg },
  returns: v.union(sessionViewValidator, v.null()),
  handler: async (ctx, args) => {
    const session = await getSession(ctx, args.session_id);
    if (!session) return null;
    const caller = await getCaller(ctx, args.guest_secret_hash);
    // Only the caller's own seat is read, so other players' seat writes don't re-run this.
    const seat = caller ? await seatOf(ctx, session.id, caller.id) : null;
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
  returns: v.array(playerViewValidator),
  handler: async (ctx, args) => {
    const member = await loadMember(ctx, args);
    if (!member) return [];
    const seats = await listSeats(ctx, member.session.id);
    return seats.map((s) => playerForViewer(s, member.session, member.seat, member.isHost));
  },
});

function phaseIndexOf(session: Doc<"game_sessions">): number | null {
  const { phase: data } = sessionData(session);
  if (session.current_phase === "night") return data?.nightIndex ?? null;
  if (["voting", "voting_results", "vote_death_reveal"].includes(session.current_phase)) return data?.dayIndex ?? null;
  return null;
}

// Reads only what this viewer may see. During an open night a non-host sees
// only its own role's rows (citizens none), so only that range is read; the
// roster is read for the host and, during voting, for allVoted.
export const getRoundState = query({
  args: { session_id: v.string(), ...guestArg },
  returns: v.union(roundStateValidator, v.null()),
  handler: async (ctx, args) => {
    const member = await loadMember(ctx, args);
    if (!member) return null;
    const { session, seat, isHost } = member;
    const roundId = session.current_round_id ?? null;
    const phaseIndex = phaseIndexOf(session);
    const night = session.current_phase === "night";
    const ownRoleOnly = night && !isHost && !isOver(session);
    const ownType = seat.role && TYPE_OF_ROLE[seat.role];
    const nightTypes = ownRoleOnly ? (ownType ? [ownType] : []) : NIGHT_TYPES;
    const seats = isHost || session.current_phase === "voting" ? await listSeats(ctx, session.id) : null;

    const actionRanges = !roundId
      ? []
      : ownRoleOnly
        ? nightTypes.map((type) =>
            ctx.db
              .query("game_actions")
              .withIndex("by_unique_action", (q) =>
                q.eq("session_id", session.id).eq("round_id", roundId).eq("action_type", type),
              )
              .collect(),
          )
        : [
            ctx.db
              .query("game_actions")
              .withIndex("by_unique_action", (q) => q.eq("session_id", session.id).eq("round_id", roundId))
              .collect(),
          ];
    const actions = (await Promise.all(actionRanges))
      .flat()
      .sort((a, b) => a.created_at - b.created_at || a._creationTime - b._creationTime);
    // Only night drafts are shared; the app never sends vote drafts. by_actor
    // orders by actor, so each type's drafts are put back in creation order.
    const tentatives =
      night && phaseIndex !== null
        ? (
            await Promise.all(
              nightTypes.map(async (type) =>
                (
                  await ctx.db
                    .query("tentative_selections")
                    .withIndex("by_actor", (q) =>
                      q.eq("session_id", session.id).eq("phase_index", phaseIndex).eq("action_type", type),
                    )
                    .collect()
                ).sort((a, b) => a._creationTime - b._creationTime),
              ),
            )
          ).flat()
        : [];

    const votes = actions.filter((a) => a.action_type === "vote" && a.phase_index === phaseIndex);
    let ready = false;
    if (isHost && seats && session.current_phase === "role_reveal") {
      ready = seats.every((s) => s.is_bot || s.is_ready);
    } else if (isHost && seats && night && roundId !== null && phaseIndex !== null) {
      const resolved = sessionData(session).nights.some((e) => e.round_id === roundId && e.is_resolved);
      ready = !resolved && nightActionsReady(seats, actions, roundId, phaseIndex);
    } else if (isHost && seats && session.current_phase === "voting") {
      ready = votesReady(seats, votes);
    }

    // Only an open vote consults allVoted, and the roster is loaded then.
    const allVoted =
      seats !== null && seats.filter((s) => s.is_alive).every((s) => votes.some((a) => a.actor_player_id === s.player_id));
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

// The client's host-offline check. Reads the session, the caller's seat and
// only the host's presence row, so other players' heartbeats never re-run it.
// `server_now` is the server clock when this result was computed; the result
// is not recomputed just because time passes.
export const getHostPresence = query({
  args: { session_id: v.string(), ...guestArg },
  returns: v.union(hostPresenceValidator, v.null()),
  handler: async (ctx, args) => {
    const member = await loadMember(ctx, args);
    if (!member) return null;
    const { session } = member;
    const host = await presenceOf(ctx, session.id, session.host_user_id);
    return {
      host_user_id: session.host_user_id,
      host_last_heartbeat: host?.last_heartbeat ?? null,
      server_now: nowAppleEpochSeconds(),
      stale_after_seconds: hostStaleAfter(session),
    };
  },
});
