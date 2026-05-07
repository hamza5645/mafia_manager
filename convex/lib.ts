import { ConvexError } from "convex/values";
import { QueryCtx, MutationCtx } from "./_generated/server";

type Ctx = QueryCtx | MutationCtx;

// Apple/NSDate reference epoch (2001-01-01) in seconds. Swift's
// Date(timeIntervalSinceReferenceDate:) decodes this natively.
export const nowAppleEpochSeconds = () => Date.now() / 1000 - 978307200;
export const uuid = () => crypto.randomUUID();

export async function getByAppId<T extends string>(
  ctx: Ctx,
  table: T,
  id: string,
) {
  return await ctx.db
    .query(table as any)
    .withIndex("by_app_id" as any, (q: any) => q.eq("id", id))
    .unique();
}

export async function requireDocByAppId<T extends string>(
  ctx: Ctx,
  table: T,
  id: string,
  message = "Document not found",
) {
  const doc = await getByAppId(ctx, table, id);
  if (!doc) {
    throw new ConvexError(message);
  }
  return doc;
}

export async function getCurrentUser(ctx: Ctx) {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) {
    return null;
  }

  return await ctx.db
    .query("users")
    .withIndex("by_auth_subject", (q) => q.eq("auth_subject", identity.subject))
    .unique();
}

export async function requireCurrentUser(ctx: Ctx) {
  const user = await getCurrentUser(ctx);
  if (!user) {
    throw new ConvexError("Authentication required");
  }
  return user;
}

// Resolves the caller's user record. Prefers Clerk identity; if absent (guest),
// looks up the asserted user_id arg. When Clerk identity IS present, the
// asserted user_id must match it (strict). For guests, the asserted id is
// trusted. Net effect: Clerk users are strictly authenticated; guest users
// remain at the prior weak (trust-the-args) level — no regression for guests
// who do not have Clerk auth, real protection for users who do.
export async function resolveCaller(ctx: Ctx, assertedUserAppId?: string) {
  const clerkUser = await getCurrentUser(ctx);
  if (clerkUser) {
    if (assertedUserAppId && clerkUser.id !== assertedUserAppId) {
      throw new ConvexError("user_id must match authenticated caller");
    }
    return clerkUser;
  }
  if (!assertedUserAppId) {
    throw new ConvexError("Authentication required");
  }
  const asserted = await ctx.db
    .query("users")
    .withIndex("by_app_id", (q) => q.eq("id", assertedUserAppId))
    .unique();
  if (!asserted) {
    throw new ConvexError("User not found");
  }
  return asserted;
}

export async function userIsSessionHost(
  ctx: Ctx,
  sessionId: string,
  userId: string,
) {
  const session = await requireDocByAppId(ctx, "game_sessions", sessionId);
  return session.host_user_id === userId;
}

// Host-only guard. If Clerk auth is present, enforces strictly. If absent
// (guest caller), this is a no-op — equivalent to current pre-hardening
// behavior. Use only on mutations whose Swift call sites cannot easily pass
// the caller's user_id; for the rest prefer requireSessionHostStrict.
export async function requireSessionHostIfAuthenticated(
  ctx: Ctx,
  sessionId: string,
) {
  const clerkUser = await getCurrentUser(ctx);
  if (!clerkUser) return null;
  if (!(await userIsSessionHost(ctx, sessionId, clerkUser.id))) {
    throw new ConvexError("Only the host can perform this action");
  }
  return clerkUser;
}

// Strict host guard taking an asserted user_id (which must match Clerk auth
// if present). For host-only mutations whose call sites pass caller user_id.
export async function requireSessionHostStrict(
  ctx: Ctx,
  sessionId: string,
  assertedUserAppId: string,
) {
  const caller = await resolveCaller(ctx, assertedUserAppId);
  if (!(await userIsSessionHost(ctx, sessionId, caller.id))) {
    throw new ConvexError("Only the host can perform this action");
  }
  return caller;
}

export async function requirePlayerOwnerIfAuthenticated(
  ctx: Ctx,
  playerAppId: string,
) {
  const clerkUser = await getCurrentUser(ctx);
  if (!clerkUser) return null;
  const player = await ctx.db
    .query("session_players")
    .withIndex("by_app_id", (q) => q.eq("id", playerAppId))
    .unique();
  if (!player) {
    throw new ConvexError("Player not found");
  }
  if (player.user_id !== clerkUser.id) {
    throw new ConvexError("Caller is not this player");
  }
  return clerkUser;
}

export async function requireActionActorIfAuthenticated(
  ctx: Ctx,
  sessionId: string,
  actorPlayerId: string,
) {
  const clerkUser = await getCurrentUser(ctx);
  if (!clerkUser) return null;
  const actor = await ctx.db
    .query("session_players")
    .withIndex("by_session_player", (q) =>
      q.eq("session_id", sessionId).eq("player_id", actorPlayerId),
    )
    .unique();
  if (!actor) {
    throw new ConvexError("Actor is not in this session");
  }
  if (actor.user_id !== clerkUser.id) {
    throw new ConvexError("Caller does not control this actor");
  }
  return clerkUser;
}

export async function transferHostIfNeeded(
  ctx: MutationCtx,
  sessionId: string,
  leavingUserAppId: string | undefined,
) {
  if (!leavingUserAppId) return;
  const session = await ctx.db
    .query("game_sessions")
    .withIndex("by_app_id", (q) => q.eq("id", sessionId))
    .unique();
  if (!session) return;
  if (session.host_user_id !== leavingUserAppId) return;

  const remaining = await listSessionPlayers(ctx, sessionId);
  const nextHost = remaining
    .filter((candidate) => !candidate.is_bot && candidate.user_id)
    .sort((a, b) => a.joined_at - b.joined_at)[0];
  if (!nextHost?.user_id) return;

  await ctx.db.patch(session._id, {
    host_user_id: nextHost.user_id,
    updated_at: nowAppleEpochSeconds(),
    phase_sequence: nextPhaseSequence(session),
  });
}

export async function listSessionPlayers(ctx: Ctx, sessionId: string) {
  return await ctx.db
    .query("session_players")
    .withIndex("by_session", (q) => q.eq("session_id", sessionId))
    .collect();
}

export function visiblePlayerForViewer(
  player: any,
  session: any,
  viewer: any | null,
  players: any[],
) {
  const viewerPlayer = viewer
    ? players.find((candidate) => candidate.user_id === viewer.id)
    : null;
  const canSeeRole =
    session.is_game_over ||
    session.current_phase === "game_over" ||
    session.host_user_id === viewer?.id ||
    player.user_id === viewer?.id ||
    (viewerPlayer?.role === "mafia" && player.role === "mafia");

  return {
    ...player,
    role: canSeeRole ? player.role : undefined,
  };
}

export function nextPhaseSequence(session: any) {
  return (session.phase_sequence ?? 0) + 1;
}

export function ensureUuid(value: string, field: string) {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) {
    throw new ConvexError(`${field} must be a UUID string`);
  }
}
