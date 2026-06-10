import { ConvexError, v } from "convex/values";
import { mutation, query } from "./_generated/server";
import {
  actionTypeValidator,
  roleValidator,
  sessionStatusValidator,
} from "./validators";
import {
  filterActionForViewer,
  listSessionPlayers,
  nextPhaseSequence,
  nowAppleEpochSeconds,
  requireActionActorIfAuthenticated,
  requireDocByAppId,
  requirePlayerOwnerIfAuthenticated,
  requireSessionHostStrict,
  resolveCaller,
  resolveViewer,
  transferHostIfNeeded,
  uuid,
  visiblePlayerForViewer,
} from "./lib";

async function getSession(ctx: any, sessionId: string) {
  return await ctx.db
    .query("game_sessions")
    .withIndex("by_app_id", (q: any) => q.eq("id", sessionId))
    .unique();
}

async function getPlayer(ctx: any, playerRecordId: string) {
  return await ctx.db
    .query("session_players")
    .withIndex("by_app_id", (q: any) => q.eq("id", playerRecordId))
    .unique();
}

async function generateRoomCode(ctx: any) {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    const code = String(Math.floor(100000 + Math.random() * 900000));
    const existing = await ctx.db
      .query("game_sessions")
      .withIndex("by_room_code", (q: any) => q.eq("room_code", code))
      .first();
    if (!existing) {
      return code;
    }
  }
  throw new ConvexError("Could not generate a unique room code");
}

function serializeMaybe<T>(value: T | undefined): T | undefined {
  return value === undefined ? undefined : value;
}

export const createSession = mutation({
  args: {
    host_user_id: v.string(),
    max_players: v.number(),
    bot_count: v.number(),
  },
  handler: async (ctx, args) => {
    await resolveCaller(ctx, args.host_user_id);
    const timestamp = nowAppleEpochSeconds();
    const session = {
      id: uuid(),
      room_code: await generateRoomCode(ctx),
      host_user_id: args.host_user_id,
      status: "waiting" as const,
      created_at: timestamp,
      max_players: args.max_players,
      bot_count: args.bot_count,
      current_phase: "lobby",
      current_phase_data: { type: "lobby" },
      day_index: 0,
      is_game_over: false,
      assigned_numbers: [],
      night_history: [],
      day_history: [],
      phase_sequence: 0,
      updated_at: timestamp,
    };
    await ctx.db.insert("game_sessions", session);
    return session;
  },
});

export const joinSession = mutation({
  args: {
    room_code: v.string(),
    user_id: v.string(),
    player_name: v.string(),
  },
  handler: async (ctx, args) => {
    await resolveCaller(ctx, args.user_id);
    const session = await ctx.db
      .query("game_sessions")
      .withIndex("by_room_code", (q) => q.eq("room_code", args.room_code.toUpperCase()))
      .first();
    if (!session || session.status !== "waiting") {
      throw new ConvexError("Game session not found");
    }

    const existingPlayers = await listSessionPlayers(ctx, session.id);
    if (existingPlayers.length >= session.max_players) {
      throw new ConvexError("Game session is full");
    }
    if (existingPlayers.some((player) => player.user_id === args.user_id)) {
      throw new ConvexError("You are already in this session");
    }

    const player = await addPlayerImpl(ctx, {
      session_id: session.id,
      user_id: args.user_id,
      player_name: args.player_name,
      is_bot: false,
    });
    return { session, player };
  },
});

export const leaveSession = mutation({
  args: { session_id: v.string(), user_id: v.string() },
  handler: async (ctx, args) => {
    await resolveCaller(ctx, args.user_id);
    const player = await ctx.db
      .query("session_players")
      .withIndex("by_session_user", (q) =>
        q.eq("session_id", args.session_id).eq("user_id", args.user_id),
      )
      .first();
    if (player) {
      await removePlayerImpl(ctx, player.id);
    }
  },
});

export const removePlayer = mutation({
  args: { player_id: v.string(), caller_user_id: v.string() },
  handler: async (ctx, args) => {
    const target = await getPlayer(ctx, args.player_id);
    if (!target) {
      throw new ConvexError("Player not found");
    }
    await requireSessionHostStrict(ctx, target.session_id, args.caller_user_id);
    return await removePlayerImpl(ctx, args.player_id);
  },
});

async function removePlayerImpl(ctx: any, playerRecordId: string) {
  const player = await getPlayer(ctx, playerRecordId);
  if (!player) {
    throw new ConvexError("Player not found");
  }
  const sessionId = player.session_id;
  const leavingUserId = player.user_id;
  await ctx.db.delete(player._id);
  await transferHostIfNeeded(ctx, sessionId, leavingUserId);
}

export const getSessionById = query({
  args: { session_id: v.string() },
  handler: async (ctx, args) => await getSession(ctx, args.session_id),
});

export const getSessionByRoomCode = query({
  args: { room_code: v.string() },
  handler: async (ctx, args) =>
    await ctx.db
      .query("game_sessions")
      .withIndex("by_room_code", (q) => q.eq("room_code", args.room_code.toUpperCase()))
      .first(),
});

export const updateSessionStatus = mutation({
  args: {
    session_id: v.string(),
    status: sessionStatusValidator,
    caller_user_id: v.string(),
  },
  handler: async (ctx, args) => {
    await requireSessionHostStrict(ctx, args.session_id, args.caller_user_id);
    const session = await requireDocByAppId(ctx, "game_sessions", args.session_id);
    await ctx.db.patch(session._id, {
      status: args.status,
      updated_at: nowAppleEpochSeconds(),
      phase_sequence: nextPhaseSequence(session),
    });
  },
});

export const updateSessionHost = mutation({
  args: {
    session_id: v.string(),
    new_host_user_id: v.string(),
    caller_user_id: v.string(),
  },
  handler: async (ctx, args) => {
    // This mutation is the host-transfer / host-claim path, used when the
    // current host has gone offline or been eliminated. Therefore we cannot
    // require caller_user_id === host_user_id; the caller is claiming
    // *because* the host is no longer responsive. We do enforce:
    //   1. caller_user_id matches Clerk identity if the caller is Clerk-authed
    //      (resolveCaller), so non-host Clerk users can't impersonate someone.
    //   2. The new host is actually a player in this session.
    //   3. If the current host is still considered online (recent heartbeat),
    //      only the current host themselves may transfer.
    // Guest-vs-guest takeover is still possible without auth, which matches the
    // codebase's documented guest auth posture.
    const caller = await resolveCaller(ctx, args.caller_user_id);
    const session = await requireDocByAppId(ctx, "game_sessions", args.session_id);

    const target = await ctx.db
      .query("session_players")
      .withIndex("by_session_user", (q) =>
        q.eq("session_id", args.session_id).eq("user_id", args.new_host_user_id),
      )
      .first();
    if (!target) {
      throw new ConvexError("New host is not in this session");
    }
    const callerPlayer = await ctx.db
      .query("session_players")
      .withIndex("by_session_user", (q) =>
        q.eq("session_id", args.session_id).eq("user_id", caller.id),
      )
      .first();
    if (!callerPlayer) {
      throw new ConvexError("Caller is not in this session");
    }

    // Host-stale guard: if the current host has a recent heartbeat, only they
    // may transfer (a true voluntary transfer). Stale heartbeats unblock the
    // takeover path for a session player to claim host for themselves.
    const HEARTBEAT_STALE_SECONDS = 15;
    const currentHostPlayer = await ctx.db
      .query("session_players")
      .withIndex("by_session_user", (q) =>
        q.eq("session_id", args.session_id).eq("user_id", session.host_user_id),
      )
      .first();
    const lastHeartbeat = currentHostPlayer?.last_heartbeat ?? 0;
    const hostIsFresh =
      currentHostPlayer !== null &&
      currentHostPlayer !== undefined &&
      nowAppleEpochSeconds() - lastHeartbeat < HEARTBEAT_STALE_SECONDS;
    if (hostIsFresh && caller.id !== session.host_user_id) {
      throw new ConvexError("Current host is still active");
    }
    if (caller.id !== session.host_user_id && args.new_host_user_id !== caller.id) {
      throw new ConvexError("Stale host takeover must claim the caller as host");
    }

    await ctx.db.patch(session._id, {
      host_user_id: args.new_host_user_id,
      updated_at: nowAppleEpochSeconds(),
      phase_sequence: nextPhaseSequence(session),
    });
  },
});

export const updateSessionPhase = mutation({
  args: {
    session_id: v.string(),
    current_phase: v.string(),
    current_phase_data: v.optional(v.any()),
    caller_user_id: v.string(),
  },
  handler: async (ctx, args) => {
    await requireSessionHostStrict(ctx, args.session_id, args.caller_user_id);
    const session = await requireDocByAppId(ctx, "game_sessions", args.session_id);
    await ctx.db.patch(session._id, {
      current_phase: args.current_phase,
      current_phase_data: serializeMaybe(args.current_phase_data),
      current_round_id:
        args.current_phase === "night" || args.current_phase === "voting"
          ? uuid()
          : session.current_round_id,
      updated_at: nowAppleEpochSeconds(),
      phase_sequence: nextPhaseSequence(session),
    });
  },
});

export const updateSessionState = mutation({
  args: {
    session_id: v.string(),
    current_phase: v.optional(v.string()),
    current_phase_data: v.optional(v.any()),
    day_index: v.optional(v.number()),
    night_history: v.optional(v.array(v.any())),
    day_history: v.optional(v.array(v.any())),
    is_game_over: v.optional(v.boolean()),
    winner: v.optional(roleValidator),
    caller_user_id: v.string(),
  },
  handler: async (ctx, args) => {
    await requireSessionHostStrict(ctx, args.session_id, args.caller_user_id);
    const session = await requireDocByAppId(ctx, "game_sessions", args.session_id);
    const patch: any = {
      updated_at: nowAppleEpochSeconds(),
      phase_sequence: nextPhaseSequence(session),
    };
    for (const key of [
      "current_phase",
      "current_phase_data",
      "day_index",
      "night_history",
      "day_history",
      "is_game_over",
      "winner",
    ] as const) {
      if (args[key] !== undefined) {
        patch[key] = args[key];
      }
    }
    if (args.current_phase === "night" || args.current_phase === "voting") {
      patch.current_round_id = uuid();
    }
    if (args.is_game_over === true) {
      patch.status = "completed";
      patch.completed_at = nowAppleEpochSeconds();
    }
    await ctx.db.patch(session._id, patch);
  },
});

export const resolveNightAtomic = mutation({
  args: {
    session_id: v.string(),
    night_record: v.any(),
    eliminated_player_ids: v.array(v.string()),
    next_phase: v.string(),
    next_phase_data: v.any(),
    is_game_over: v.optional(v.boolean()),
    winner: v.optional(roleValidator),
    caller_user_id: v.string(),
  },
  handler: async (ctx, args) => {
    await requireSessionHostStrict(ctx, args.session_id, args.caller_user_id);
    const session = await requireDocByAppId(ctx, "game_sessions", args.session_id);
    for (const playerId of args.eliminated_player_ids) {
      const player = await ctx.db
        .query("session_players")
        .withIndex("by_session_player", (q) =>
          q.eq("session_id", args.session_id).eq("player_id", playerId),
        )
        .first();
      if (player) {
        await ctx.db.patch(player._id, {
          is_alive: false,
          removal_note: "night",
        });
      }
    }

    const nightHistory = [...session.night_history];
    const existingIndex = nightHistory.findIndex(
      (record: any) => record.night_index === args.night_record.night_index,
    );
    if (existingIndex >= 0) {
      nightHistory[existingIndex] = args.night_record;
    } else {
      nightHistory.push(args.night_record);
    }

    await ctx.db.patch(session._id, {
      night_history: nightHistory,
      current_phase: args.next_phase,
      current_phase_data: args.next_phase_data,
      is_game_over: args.is_game_over ?? session.is_game_over,
      winner: args.winner ?? session.winner,
      status: args.is_game_over ? "completed" : session.status,
      completed_at: args.is_game_over ? nowAppleEpochSeconds() : session.completed_at,
      updated_at: nowAppleEpochSeconds(),
      phase_sequence: nextPhaseSequence(session),
    });
    return true;
  },
});

export const getSessionPlayers = query({
  args: {
    session_id: v.string(),
    viewer_user_id: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const session = await getSession(ctx, args.session_id);
    if (!session) {
      return [];
    }
    const players = await listSessionPlayers(ctx, args.session_id);
    // Strict for Clerk users (ignores spoofed viewer_user_id); falls back to
    // the asserted id for guest play. See resolveViewer in lib.ts.
    const viewer = await resolveViewer(ctx, args.viewer_user_id);
    return players
      .map((player) => visiblePlayerForViewer(player, session, viewer, players))
      .sort((a, b) => a.joined_at - b.joined_at);
  },
});

async function addPlayerImpl(
  ctx: any,
  args: {
    session_id: string;
    user_id?: string;
    player_name: string;
    is_bot: boolean;
  },
) {
  const timestamp = nowAppleEpochSeconds();
  const player = {
    id: uuid(),
    session_id: args.session_id,
    user_id: args.user_id,
    player_id: uuid(),
    player_name: args.player_name,
    is_bot: args.is_bot,
    is_alive: true,
    is_online: !args.is_bot,
    is_ready: true,
    last_heartbeat: timestamp,
    joined_at: timestamp,
  };
  await ctx.db.insert("session_players", player);
  return player;
}

export const addPlayer = mutation({
  args: {
    session_id: v.string(),
    user_id: v.optional(v.string()),
    player_name: v.string(),
    is_bot: v.boolean(),
    caller_user_id: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const session = await requireDocByAppId(ctx, "game_sessions", args.session_id);
    if (session.status !== "waiting") {
      throw new ConvexError("Players can only be added while waiting");
    }

    const existingPlayers = await listSessionPlayers(ctx, args.session_id);
    if (existingPlayers.length >= session.max_players) {
      throw new ConvexError("Game session is full");
    }

    if (args.is_bot) {
      if (!args.caller_user_id) {
        throw new ConvexError("caller_user_id required for bot adds");
      }
      await requireSessionHostStrict(ctx, args.session_id, args.caller_user_id);
    } else {
      if (!args.user_id || !args.caller_user_id) {
        throw new ConvexError("user_id and caller_user_id required for player adds");
      }
      const caller = await requireSessionHostStrict(
        ctx,
        args.session_id,
        args.caller_user_id,
      );
      if (args.user_id !== caller.id) {
        throw new ConvexError("Hosts can only add themselves directly");
      }
      if (existingPlayers.some((player) => player.user_id === args.user_id)) {
        throw new ConvexError("You are already in this session");
      }
    }
    // Strip caller_user_id from the row payload (it's auth metadata, not row data).
    const { caller_user_id: _ignored, ...payload } = args;
    return await addPlayerImpl(ctx, payload);
  },
});

export const updatePlayerReady = mutation({
  args: { player_id: v.string(), is_ready: v.boolean() },
  handler: async (ctx, args) => {
    const player = await getPlayer(ctx, args.player_id);
    if (!player) throw new ConvexError("Player not found");
    await requirePlayerOwnerIfAuthenticated(ctx, args.player_id);
    await ctx.db.patch(player._id, { is_ready: args.is_ready });
  },
});

export const resetAllPlayersReady = mutation({
  args: { session_id: v.string(), caller_user_id: v.string() },
  handler: async (ctx, args) => {
    await requireSessionHostStrict(ctx, args.session_id, args.caller_user_id);
    const players = await listSessionPlayers(ctx, args.session_id);
    for (const player of players) {
      if (!player.is_bot) {
        await ctx.db.patch(player._id, { is_ready: false });
      }
    }
  },
});

export const updatePlayerLifeStatus = mutation({
  args: {
    record_id: v.string(),
    is_alive: v.boolean(),
    removal_note: v.optional(v.string()),
    caller_user_id: v.string(),
  },
  handler: async (ctx, args) => {
    const player = await getPlayer(ctx, args.record_id);
    if (!player) throw new ConvexError("Player not found");
    await requireSessionHostStrict(ctx, player.session_id, args.caller_user_id);
    await ctx.db.patch(player._id, {
      is_alive: args.is_alive,
      removal_note: args.removal_note,
    });
  },
});

export const updatePlayerHeartbeat = mutation({
  args: { player_id: v.string() },
  handler: async (ctx, args) => {
    const player = await getPlayer(ctx, args.player_id);
    if (!player) return;
    await requirePlayerOwnerIfAuthenticated(ctx, args.player_id);
    await ctx.db.patch(player._id, {
      last_heartbeat: nowAppleEpochSeconds(),
      is_online: true,
    });
  },
});

export const assignRolesAndNumbers = mutation({
  args: {
    session_id: v.string(),
    assignments: v.array(
      v.object({
        player_id: v.string(),
        role: roleValidator,
        number: v.number(),
      }),
    ),
    caller_user_id: v.string(),
  },
  handler: async (ctx, args) => {
    await requireSessionHostStrict(ctx, args.session_id, args.caller_user_id);
    const session = await requireDocByAppId(ctx, "game_sessions", args.session_id);
    for (const assignment of args.assignments) {
      const player = await ctx.db
        .query("session_players")
        .withIndex("by_session_player", (q) =>
          q.eq("session_id", args.session_id).eq("player_id", assignment.player_id),
        )
        .first();
      if (player) {
        await ctx.db.patch(player._id, {
          role: assignment.role,
          player_number: assignment.number,
        });
      }
    }
    await ctx.db.patch(session._id, {
      assigned_numbers: args.assignments.map((assignment) => ({
        player_id: assignment.player_id,
        number: assignment.number,
      })),
      updated_at: nowAppleEpochSeconds(),
      phase_sequence: nextPhaseSequence(session),
    });
  },
});

export const submitAction = mutation({
  args: {
    session_id: v.string(),
    round_id: v.string(),
    action_type: actionTypeValidator,
    phase_index: v.number(),
    actor_player_id: v.string(),
    target_player_id: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    await requireActionActorIfAuthenticated(ctx, args.session_id, args.actor_player_id);
    const session = await requireDocByAppId(ctx, "game_sessions", args.session_id);

    // Reject stale rounds: the client must submit against the session's
    // current round. Previously the handler accepted any round_id and wrote
    // session.current_round_id into the payload, silently promoting stale
    // actions into the current round and defeating replay protection.
    if (!session.current_round_id || args.round_id !== session.current_round_id) {
      throw new ConvexError("Stale round");
    }

    const players = await listSessionPlayers(ctx, args.session_id);
    const actor = players.find((player) => player.player_id === args.actor_player_id);
    if (!actor) {
      throw new ConvexError("Actor is not in this session");
    }

    const actionData: any = {};
    if (args.action_type === "inspector_check" && args.target_player_id) {
      const target = players.find((player) => player.player_id === args.target_player_id);
      actionData.inspector_result =
        target?.role === "inspector"
          ? "blocked"
          : target?.role === "mafia"
            ? "mafia"
            : "not_mafia";
    }

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

    const payload = {
      session_id: args.session_id,
      round_id: args.round_id,
      action_type: args.action_type,
      phase_index: args.phase_index,
      actor_player_id: args.actor_player_id,
      target_player_id: args.target_player_id,
      action_data: Object.keys(actionData).length > 0 ? actionData : undefined,
      created_at: nowAppleEpochSeconds(),
    };

    if (existing) {
      await ctx.db.patch(existing._id, payload);
    } else {
      await ctx.db.insert("game_actions", { id: uuid(), ...payload });
    }

    return {
      success: true,
      result: actionData.inspector_result,
    };
  },
});

export const getActionsForPhase = query({
  args: {
    session_id: v.string(),
    action_type: v.optional(actionTypeValidator),
    action_types: v.optional(v.array(actionTypeValidator)),
    phase_index: v.number(),
    round_id: v.optional(v.string()),
    viewer_user_id: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const types = args.action_types ?? (args.action_type ? [args.action_type] : null);
    if (!types || types.length === 0) {
      throw new ConvexError("Provide action_type or action_types");
    }
    const baseRows = args.round_id
      ? (
          await Promise.all(
            types.map((type) =>
              ctx.db
                .query("game_actions")
                .withIndex("by_session_round_type_phase", (q) =>
                  q
                    .eq("session_id", args.session_id)
                    .eq("round_id", args.round_id!)
                    .eq("action_type", type)
                    .eq("phase_index", args.phase_index),
                )
                .collect(),
            ),
          )
        ).flat()
      : await ctx.db
          .query("game_actions")
          .withIndex("by_session", (q) => q.eq("session_id", args.session_id))
          .filter((q) => q.eq(q.field("phase_index"), args.phase_index))
          .collect()
          .then((rows) =>
            rows.filter((row) => types.includes(row.action_type as any)),
          );
    const sorted = baseRows.sort((a, b) => a.created_at - b.created_at);
    const session = await getSession(ctx, args.session_id);
    if (!session) return sorted;
    const viewer = await resolveViewer(ctx, args.viewer_user_id);
    const players = await listSessionPlayers(ctx, args.session_id);
    return sorted.map((row) => filterActionForViewer(row, session, viewer, players));
  },
});

export const getAllActions = query({
  args: {
    session_id: v.string(),
    viewer_user_id: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const rows = (
      await ctx.db
        .query("game_actions")
        .withIndex("by_session", (q) => q.eq("session_id", args.session_id))
        .collect()
    ).sort((a, b) => a.created_at - b.created_at);
    const session = await getSession(ctx, args.session_id);
    if (!session) return rows;
    const viewer = await resolveViewer(ctx, args.viewer_user_id);
    const players = await listSessionPlayers(ctx, args.session_id);
    return rows.map((row) => filterActionForViewer(row, session, viewer, players));
  },
});

export const returnToLobby = mutation({
  args: {
    session_id: v.string(),
    player_id: v.string(),
    player_user_id: v.string(),
    original_host_user_id: v.string(),
  },
  handler: async (ctx, args) => {
    const caller = await resolveCaller(ctx, args.player_user_id);
    const session = await requireDocByAppId(ctx, "game_sessions", args.session_id);
    const player = await getPlayer(ctx, args.player_id);
    if (!player || player.session_id !== args.session_id) {
      throw new ConvexError("Player is not in this session");
    }
    if (player.user_id !== caller.id) {
      throw new ConvexError("Caller is not this player");
    }
    const isGameOver =
      session.is_game_over || session.current_phase === "game_over";
    if (session.current_phase !== "lobby" && !isGameOver) {
      throw new ConvexError("Cannot return to lobby before game over");
    }

    if (session.current_phase !== "lobby") {
      await ctx.db.patch(session._id, {
        host_user_id: args.player_user_id,
        status: "waiting",
        current_phase: "lobby",
        current_phase_data: { type: "lobby" },
        day_index: 0,
        is_game_over: false,
        winner: undefined,
        assigned_numbers: [],
        night_history: [],
        day_history: [],
        current_round_id: undefined,
        rematch_deadline: undefined,
        updated_at: nowAppleEpochSeconds(),
        phase_sequence: nextPhaseSequence(session),
      });

      const players = await listSessionPlayers(ctx, args.session_id);
      for (const player of players) {
        await ctx.db.patch(player._id, {
          role: undefined,
          player_number: undefined,
          is_alive: true,
          is_ready: player.id === args.player_id,
          removal_note: undefined,
        });
      }
    } else if (
      args.player_user_id === args.original_host_user_id &&
      session.host_user_id !== args.original_host_user_id
    ) {
      await ctx.db.patch(session._id, {
        host_user_id: args.original_host_user_id,
        updated_at: nowAppleEpochSeconds(),
        phase_sequence: nextPhaseSequence(session),
      });
    }

    if (player) {
      await ctx.db.patch(player._id, { is_ready: true });
    }
  },
});

export const setTentativeSelection = mutation({
  args: {
    session_id: v.string(),
    actor_player_id: v.string(),
    target_player_id: v.optional(v.string()),
    action_type: actionTypeValidator,
    phase_index: v.number(),
  },
  handler: async (ctx, args) => {
    await requireActionActorIfAuthenticated(ctx, args.session_id, args.actor_player_id);
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
    const payload = {
      target_player_id: args.target_player_id,
      updated_at: nowAppleEpochSeconds(),
    };
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
  },
});

export const listTentativeSelections = query({
  args: {
    session_id: v.string(),
    phase_index: v.number(),
    action_type: actionTypeValidator,
  },
  handler: async (ctx, args) =>
    await ctx.db
      .query("tentative_selections")
      .withIndex("by_session_phase_type", (q) =>
        q
          .eq("session_id", args.session_id)
          .eq("phase_index", args.phase_index)
          .eq("action_type", args.action_type),
      )
      .collect(),
});

export const listTentativeSelectionsForSession = query({
  args: { session_id: v.string() },
  handler: async (ctx, args) =>
    await ctx.db
      .query("tentative_selections")
      .withIndex("by_session_phase_type", (q) => q.eq("session_id", args.session_id))
      .collect(),
});

export const allRoleActionsSubmitted = query({
  args: {
    session_id: v.string(),
    role: roleValidator,
    phase_index: v.number(),
    action_type: actionTypeValidator,
  },
  handler: async (ctx, args) => {
    const players = await listSessionPlayers(ctx, args.session_id);
    const aliveOfRole = players.filter(
      (player) => player.is_alive && player.role === args.role,
    );
    if (aliveOfRole.length === 0) return true;

    const actions = await ctx.db
      .query("game_actions")
      .withIndex("by_session", (q) => q.eq("session_id", args.session_id))
      .filter((q) =>
        q.and(
          q.eq(q.field("action_type"), args.action_type),
          q.eq(q.field("phase_index"), args.phase_index),
        ),
      )
      .collect();
    const submittedActorIds = new Set(actions.map((row) => row.actor_player_id));
    return aliveOfRole.every((player) => submittedActorIds.has(player.player_id));
  },
});

export const executeRematch = mutation({
  args: { session_id: v.string(), caller_user_id: v.string() },
  handler: async (ctx, args) => {
    await requireSessionHostStrict(ctx, args.session_id, args.caller_user_id);
    const session = await requireDocByAppId(ctx, "game_sessions", args.session_id);

    const players = await listSessionPlayers(ctx, args.session_id);
    const readyCount = players.filter((player) => player.is_ready).length;
    if (readyCount < 4) {
      return {
        success: false,
        error: "Not enough players",
        confirmed_count: readyCount,
      };
    }

    for (const player of players) {
      if (!player.is_bot && !player.is_ready) {
        await ctx.db.delete(player._id);
      }
    }

    const remaining = await listSessionPlayers(ctx, args.session_id);
    const newHost = remaining
      .filter(
        (candidate) => !candidate.is_bot && candidate.is_ready && candidate.user_id,
      )
      .sort((a, b) => a.joined_at - b.joined_at)[0];
    if (!newHost?.user_id) {
      return {
        success: false,
        error: "No valid host found",
      };
    }

    await ctx.db.patch(session._id, {
      host_user_id: newHost.user_id,
      status: "waiting" as const,
      current_phase: "lobby",
      current_phase_data: { type: "lobby" },
      day_index: 0,
      is_game_over: false,
      winner: undefined,
      assigned_numbers: [],
      night_history: [],
      day_history: [],
      current_round_id: undefined,
      rematch_deadline: undefined,
      updated_at: nowAppleEpochSeconds(),
      phase_sequence: nextPhaseSequence(session),
    });

    for (const player of remaining) {
      await ctx.db.patch(player._id, {
        is_alive: true,
        is_ready: false,
        role: undefined,
        player_number: undefined,
        removal_note: undefined,
      });
    }

    const existingActions = await ctx.db
      .query("game_actions")
      .withIndex("by_session", (q) => q.eq("session_id", args.session_id))
      .collect();
    for (const action of existingActions) {
      await ctx.db.delete(action._id);
    }

    const existingTentatives = await ctx.db
      .query("tentative_selections")
      .withIndex("by_session_phase_type", (q) => q.eq("session_id", args.session_id))
      .collect();
    for (const tentative of existingTentatives) {
      await ctx.db.delete(tentative._id);
    }

    return {
      success: true,
      new_host_user_id: newHost.user_id,
      confirmed_count: readyCount,
    };
  },
});
