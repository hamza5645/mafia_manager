import { Doc } from "../_generated/dataModel";
import { MutationCtx, QueryCtx } from "../_generated/server";
import { E, fail } from "./errors";
import { requireCaller } from "./identity";

type Ctx = QueryCtx | MutationCtx;
type SessionArgs = { session_id: string; guest_secret_hash?: string };

export async function getSession(ctx: Ctx, sessionId: string): Promise<Doc<"game_sessions"> | null> {
  return await ctx.db
    .query("game_sessions")
    .withIndex("by_app_id", (q) => q.eq("id", sessionId))
    .unique();
}

export async function listSeats(ctx: Ctx, sessionId: string): Promise<Doc<"session_players">[]> {
  const seats = await ctx.db
    .query("session_players")
    .withIndex("by_session", (q) => q.eq("session_id", sessionId))
    .collect();
  return seats.sort((a, b) => a.joined_at - b.joined_at || a._creationTime - b._creationTime);
}

export async function requireSeat(ctx: Ctx, a: SessionArgs) {
  const session = (await getSession(ctx, a.session_id)) ?? fail(E.GAME_NOT_FOUND);
  const caller = await requireCaller(ctx, a.guest_secret_hash);
  const seat =
    (await ctx.db
      .query("session_players")
      .withIndex("by_session_user", (q) => q.eq("session_id", a.session_id).eq("user_id", caller.id))
      .first()) ?? fail(E.NOT_MEMBER);
  return { caller, session, seat };
}

export async function requireRoster(ctx: Ctx, a: SessionArgs) {
  const session = (await getSession(ctx, a.session_id)) ?? fail(E.GAME_NOT_FOUND);
  const caller = await requireCaller(ctx, a.guest_secret_hash);
  const seats = await listSeats(ctx, a.session_id);
  const seat = seats.find((s) => s.user_id === caller.id) ?? fail(E.NOT_MEMBER);
  return { caller, session, seats, seat };
}

export async function requireHost(ctx: Ctx, a: SessionArgs) {
  const session = (await getSession(ctx, a.session_id)) ?? fail(E.GAME_NOT_FOUND);
  const caller = await requireCaller(ctx, a.guest_secret_hash);
  if (session.host_user_id !== caller.id) fail(E.HOST_ONLY);
  const seats = await listSeats(ctx, a.session_id);
  const seat = seats.find((s) => s.user_id === caller.id) ?? null;
  return { caller, session, seats, seat };
}
