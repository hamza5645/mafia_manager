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
  if (!nextHost?.user_id) {
    await cancelSessionAndRemovePlayers(ctx, session);
    return;
  }

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

// Night actors and targets reveal roles. Return no row unless the viewer may
// coordinate that action. The host needs every action to resolve the game;
// teammates see their role's selections, but inspector results stay private.
export function filterActionForViewer(
  row: any,
  session: any,
  viewer: any | null,
  players: any[],
) {
  const viewerPlayer = viewer
    ? players.find((candidate) => candidate.user_id === viewer.id)
    : null;
  if (!viewerPlayer) return null;
  const isActor = viewerPlayer.player_id === row.actor_player_id;
  const isHost = session.host_user_id === viewer.id;
  const isGameOver = session.is_game_over || session.current_phase === "game_over";
  const actionRole: Record<string, string> = {
    mafia_target: "mafia", doctor_protect: "doctor", inspector_check: "inspector",
  };
  if (!isHost && !isGameOver && !isActor && row.action_type !== "vote" &&
      viewerPlayer.role !== actionRole[row.action_type]) {
    return null;
  }
  if (!row.action_data?.inspector_result || isHost || isActor || isGameOver) return row;
  const { inspector_result, ...rest } = row.action_data;
  return { ...row, action_data: Object.keys(rest).length > 0 ? rest : undefined };
}

export function nextPhaseSequence(session: any) {
  return (session.phase_sequence ?? 0) + 1;
}

export function ensureUuid(value: string, field: string) {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) {
    throw new ConvexError(`${field} must be a UUID string`);
  }
}

// Public discovery never returns game records or arbitrary phase payloads.
// Members receive published outcomes; only the authoritative host (or members
// after game over) receive the private night record used for resolution/replay.
export function sessionForViewer(session: any, viewer: any | null, players: any[]) {
  const isMember = !!viewer && players.some(player => player.user_id === viewer.id);
  if (isMember && (session.host_user_id === viewer.id || session.is_game_over || session.current_phase === "game_over")) {
    return session;
  }
  const phase = session.current_phase_data;
  const phaseFields: Record<string, string[]> = {
    lobby: [], roleReveal: ["currentPlayerIndex"], night: ["nightIndex", "activeRole"],
    morning: ["nightIndex"], deathReveal: ["nightIndex"], voting: ["dayIndex"],
    votingResults: ["dayIndex", "voteCounts", "eliminatedPlayerId"],
    voteDeathReveal: ["dayIndex", "eliminatedPlayerId", "eliminatedPlayerName", "eliminatedPlayerNumber", "eliminatedPlayerRole", "voteCount"],
    gameOver: ["winner"],
  };
  const safePhase = isMember && phase && phaseFields[phase.type]
    ? Object.fromEntries(["type", ...phaseFields[phase.type]].filter(key => phase[key] !== undefined).map(key => [key, phase[key]]))
    : undefined;
  return {
    id: session.id, room_code: session.room_code, host_user_id: session.host_user_id,
    status: session.status, created_at: session.created_at, started_at: session.started_at,
    completed_at: session.completed_at, max_players: session.max_players, bot_count: session.bot_count,
    current_phase: session.current_phase, current_phase_data: safePhase, day_index: session.day_index,
    is_game_over: session.is_game_over, winner: session.winner,
    assigned_numbers: isMember ? session.assigned_numbers.map((row: any) => ({ player_id: row.player_id, number: row.number })) : [],
    night_history: isMember ? session.night_history.filter((row: any) => row.is_resolved === true).map((row: any) => ({
      night_index: row.night_index, is_resolved: true, resulting_deaths: row.resulting_deaths,
      revealed_death_roles: row.revealed_death_roles, timestamp: row.timestamp,
    })) : [],
    day_history: isMember ? session.day_history.map((row: any) => ({ day_index: row.day_index, removed_player_ids: row.removed_player_ids, timestamp: row.timestamp })) : [],
    current_round_id: isMember ? session.current_round_id : undefined,
    rematch_deadline: isMember ? session.rematch_deadline : undefined,
    phase_sequence: session.phase_sequence, updated_at: session.updated_at,
  };
}

export function validateGameAction(session: any, players: any[], args: {
  actor_player_id: string; target_player_id?: string; action_type: string; phase_index: number;
}) {
  if (session.status !== "in_progress" || session.is_game_over) {
    throw new ConvexError("Game is not active");
  }
  const isVote = args.action_type === "vote";
  const expectedPhase = isVote ? "voting" : "night";
  if (session.current_phase !== expectedPhase) {
    throw new ConvexError("Action is not allowed in this phase");
  }
  const data = session.current_phase_data;
  const activeIndex = isVote ? data?.dayIndex : data?.nightIndex;
  if (!Number.isInteger(activeIndex) || args.phase_index !== activeIndex) {
    throw new ConvexError("Stale phase index");
  }
  const actor = players.find(player => player.player_id === args.actor_player_id);
  if (!actor || !actor.is_alive) throw new ConvexError("Actor is not alive in this session");
  const actionRole: Record<string, string> = {
    mafia_target: "mafia", doctor_protect: "doctor", inspector_check: "inspector",
  };
  if (!isVote && actor.role !== actionRole[args.action_type]) {
    throw new ConvexError("Action is not allowed for this role");
  }
  // No target represents abstention/no eligible target, or clearing a tentative
  // selection. It never computes an inspector result.
  if (!args.target_player_id) return actor;
  const target = players.find(player => player.player_id === args.target_player_id);
  if (!target || !target.is_alive) throw new ConvexError("Target is not alive in this session");
  if (args.action_type === "mafia_target" && target.role === "mafia") {
    throw new ConvexError("Mafia cannot target a teammate");
  }
  if (args.action_type === "inspector_check" && target.player_id === actor.player_id) {
    throw new ConvexError("Inspector cannot inspect themselves");
  }
  return actor;
}


export async function cancelSessionAndRemovePlayers(ctx: MutationCtx, session: any) {
  const players = await listSessionPlayers(ctx, session.id);
  if (players.length === 0 && ["cancelled", "completed"].includes(session.status)) return;
  const completed = session.status === "completed";
  await ctx.db.patch(session._id, {
    status: completed ? "completed" : "cancelled",
    current_phase: completed ? session.current_phase : "cancelled",
    current_phase_data: completed ? session.current_phase_data : undefined,
    current_round_id: undefined, night_resolution: undefined, rematch_deadline: undefined,
    completed_at: session.completed_at ?? nowAppleEpochSeconds(),
    updated_at: nowAppleEpochSeconds(), phase_sequence: nextPhaseSequence(session),
  });
  for (const player of players) await ctx.db.delete(player._id);
  const actions = await ctx.db.query("game_actions").withIndex("by_session", q => q.eq("session_id", session.id)).collect();
  for (const action of actions) await ctx.db.delete(action._id);
  const selections = await ctx.db.query("tentative_selections").withIndex("by_session_phase_type", q => q.eq("session_id", session.id)).collect();
  for (const selection of selections) await ctx.db.delete(selection._id);
}
