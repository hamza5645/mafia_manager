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

// Resolves the caller's user record. Clerk identities must match any asserted
// app user id. Unauthenticated callers may resolve only anonymous rows and
// must present the matching high-entropy guest secret hash.
export async function resolveCaller(
  ctx: Ctx,
  assertedUserAppId?: string,
  guestSecretHash?: string,
) {
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
  if (!asserted.is_anonymous || asserted.auth_subject) {
    throw new ConvexError("Authentication required");
  }
  if (!guestSecretHash || asserted.guest_secret_hash !== guestSecretHash) {
    throw new ConvexError("Invalid guest credentials");
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

// Strict host guard taking an asserted user_id (which must match Clerk auth
// if present). For host-only mutations whose call sites pass caller user_id.
export async function requireSessionHostStrict(
  ctx: Ctx,
  sessionId: string,
  assertedUserAppId: string,
  guestSecretHash?: string,
) {
  const caller = await resolveCaller(ctx, assertedUserAppId, guestSecretHash);
  if (!(await userIsSessionHost(ctx, sessionId, caller.id))) {
    throw new ConvexError("Only the host can perform this action");
  }
  return caller;
}

export async function requireSessionMember(
  ctx: Ctx,
  sessionId: string,
  assertedUserAppId: string,
  guestSecretHash?: string,
) {
  const caller = await resolveCaller(ctx, assertedUserAppId, guestSecretHash);
  const player = await ctx.db
    .query("session_players")
    .withIndex("by_session_user", (q) =>
      q.eq("session_id", sessionId).eq("user_id", caller.id),
    )
    .first();
  if (!player) {
    throw new ConvexError("Caller is not in this session");
  }
  return { caller, player };
}

export async function requirePlayerOwner(
  ctx: Ctx,
  playerAppId: string,
  guestSecretHash?: string,
) {
  const player = await ctx.db
    .query("session_players")
    .withIndex("by_app_id", (q) => q.eq("id", playerAppId))
    .unique();
  if (!player) {
    throw new ConvexError("Player not found");
  }
  if (!player.user_id) {
    throw new ConvexError("Player has no owner");
  }
  const caller = await resolveCaller(ctx, player.user_id, guestSecretHash);
  if (player.user_id !== caller.id) {
    throw new ConvexError("Caller is not this player");
  }
  return caller;
}

export async function requireActionActor(
  ctx: Ctx,
  sessionId: string,
  actorPlayerId: string,
  callerUserAppId?: string,
  guestSecretHash?: string,
) {
  const actor = await ctx.db
    .query("session_players")
    .withIndex("by_session_player", (q) =>
      q.eq("session_id", sessionId).eq("player_id", actorPlayerId),
    )
    .unique();
  if (!actor) {
    throw new ConvexError("Actor is not in this session");
  }
  if (actor.is_bot) {
    if (!callerUserAppId) {
      throw new ConvexError("caller_user_id required for bot actions");
    }
    return await requireSessionHostStrict(
      ctx,
      sessionId,
      callerUserAppId,
      guestSecretHash,
    );
  }
  if (!actor.user_id) {
    throw new ConvexError("Actor has no owner");
  }
  const caller = await resolveCaller(ctx, actor.user_id, guestSecretHash);
  if (actor.user_id !== caller.id) {
    throw new ConvexError("Caller does not control this actor");
  }
  return caller;
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
  // The host sees all roles: the host client is the authoritative game
  // master — it drives bot actions, evaluates win conditions (alive mafia
  // count), and records revealed death roles. Hiding roles from the host
  // breaks all three. This matches the Supabase get_visible_role contract.
  const canSeeRole =
    session.is_game_over ||
    session.current_phase === "game_over" ||
    player.user_id === viewer?.id ||
    (viewer != null && session.host_user_id === viewer.id) ||
    (viewerPlayer?.role === "mafia" && player.role === "mafia");

  return {
    ...player,
    role: canSeeRole ? player.role : undefined,
  };
}

// Resolves the viewer for role-visibility / action-visibility filtering.
// When Clerk auth is present, ignore the client-supplied `assertedViewerAppId`
// to prevent spoofing — pass through the authenticated user's record only.
// Guests must prove control of the asserted anonymous row through resolveCaller.
export async function resolveViewer(
  ctx: Ctx,
  assertedViewerAppId?: string,
  guestSecretHash?: string,
) {
  const clerkViewer = await getCurrentUser(ctx);
  if (clerkViewer) return clerkViewer;
  if (!assertedViewerAppId) return null;
  return await resolveCaller(ctx, assertedViewerAppId, guestSecretHash);
}

// Strips `inspector_result` from an action row when the viewer should not
// see it. Visible to: the inspector actor themselves and everyone after
// game_over. Citizens/Mafia/Doctors never see other inspectors' results.
export function filterActionForViewer(
  row: any,
  session: any,
  viewer: any | null,
  players: any[],
) {
  if (!row.action_data?.inspector_result) return row;
  const viewerPlayer = viewer
    ? players.find((candidate) => candidate.user_id === viewer.id)
    : null;
  const isActor = !!viewerPlayer && viewerPlayer.player_id === row.actor_player_id;
  const isGameOver =
    session.is_game_over || session.current_phase === "game_over";
  if (isActor || isGameOver) return row;
  const { inspector_result, ...rest } = row.action_data;
  return {
    ...row,
    action_data: Object.keys(rest).length > 0 ? rest : undefined,
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
