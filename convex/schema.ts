import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

const role = v.union(
  v.literal("mafia"),
  v.literal("doctor"),
  v.literal("inspector"),
  v.literal("citizen"),
);

const sessionStatus = v.union(
  v.literal("waiting"),
  v.literal("in_progress"),
  v.literal("completed"),
  v.literal("cancelled"),
);

const actionType = v.union(
  v.literal("mafia_target"),
  v.literal("inspector_check"),
  v.literal("doctor_protect"),
  v.literal("vote"),
);

export default defineSchema({
  users: defineTable({
    id: v.string(),
    auth_subject: v.optional(v.string()),
    display_name: v.string(),
    is_anonymous: v.boolean(),
    guest_secret_hash: v.optional(v.string()),
    email: v.optional(v.string()),
    legacy_supabase_user_id: v.optional(v.string()),
    created_at: v.number(),
    updated_at: v.number(),
  })
    .index("by_app_id", ["id"])
    .index("by_auth_subject", ["auth_subject"])
    .index("by_guest_secret_hash", ["guest_secret_hash"])
    .index("by_email_unclaimed", ["email", "auth_subject"])
    .index("by_legacy_supabase_user_id", ["legacy_supabase_user_id"]),

  player_stats: defineTable({
    id: v.string(),
    user_id: v.string(),
    player_name: v.string(),
    games_played: v.number(),
    games_won: v.number(),
    games_lost: v.number(),
    total_kills: v.number(),
    times_mafia: v.number(),
    times_doctor: v.number(),
    times_inspector: v.number(),
    times_citizen: v.number(),
    legacy_supabase_id: v.optional(v.string()),
    legacy_supabase_user_id: v.optional(v.string()),
    created_at: v.number(),
    updated_at: v.number(),
  })
    .index("by_app_id", ["id"])
    .index("by_user", ["user_id"])
    .index("by_user_player", ["user_id", "player_name"])
    .index("by_legacy_supabase_id", ["legacy_supabase_id"]),

  custom_roles_configs: defineTable({
    id: v.string(),
    user_id: v.string(),
    config_name: v.string(),
    role_distribution: v.object({
      mafia_count: v.number(),
      doctor_count: v.number(),
      inspector_count: v.number(),
      citizen_count: v.number(),
      total_players: v.number(),
    }),
    legacy_supabase_id: v.optional(v.string()),
    legacy_supabase_user_id: v.optional(v.string()),
    created_at: v.number(),
    updated_at: v.number(),
  })
    .index("by_app_id", ["id"])
    .index("by_user", ["user_id"])
    .index("by_user_config_name", ["user_id", "config_name"])
    .index("by_legacy_supabase_id", ["legacy_supabase_id"]),

  player_groups: defineTable({
    id: v.string(),
    user_id: v.string(),
    group_name: v.string(),
    player_names: v.array(v.string()),
    legacy_supabase_id: v.optional(v.string()),
    legacy_supabase_user_id: v.optional(v.string()),
    created_at: v.number(),
    updated_at: v.number(),
  })
    .index("by_app_id", ["id"])
    .index("by_user", ["user_id"])
    .index("by_user_group_name", ["user_id", "group_name"])
    .index("by_legacy_supabase_id", ["legacy_supabase_id"]),

  game_sessions: defineTable({
    id: v.string(),
    room_code: v.string(),
    host_user_id: v.string(),
    status: sessionStatus,
    created_at: v.number(),
    started_at: v.optional(v.number()),
    completed_at: v.optional(v.number()),
    max_players: v.number(),
    bot_count: v.number(),
    current_phase: v.string(),
    current_phase_data: v.optional(v.any()),
    day_index: v.number(),
    is_game_over: v.boolean(),
    winner: v.optional(role),
    assigned_numbers: v.array(v.any()),
    night_history: v.array(v.any()),
    day_history: v.array(v.any()),
    current_round_id: v.optional(v.string()),
    rematch_deadline: v.optional(v.number()),
    phase_sequence: v.optional(v.number()),
    updated_at: v.number(),
  })
    .index("by_app_id", ["id"])
    .index("by_room_code", ["room_code"])
    .index("by_host", ["host_user_id"])
    .index("by_status", ["status"]),

  session_players: defineTable({
    id: v.string(),
    session_id: v.string(),
    user_id: v.optional(v.string()),
    player_id: v.string(),
    player_name: v.string(),
    player_number: v.optional(v.number()),
    role: v.optional(role),
    is_bot: v.boolean(),
    is_alive: v.boolean(),
    is_online: v.boolean(),
    is_ready: v.boolean(),
    last_heartbeat: v.number(),
    joined_at: v.number(),
    removal_note: v.optional(v.string()),
  })
    .index("by_app_id", ["id"])
    .index("by_session", ["session_id"])
    .index("by_session_user", ["session_id", "user_id"])
    .index("by_session_player", ["session_id", "player_id"])
    .index("by_user", ["user_id"]),

  game_actions: defineTable({
    id: v.string(),
    session_id: v.string(),
    round_id: v.string(),
    action_type: actionType,
    phase_index: v.number(),
    actor_player_id: v.string(),
    target_player_id: v.optional(v.string()),
    action_data: v.optional(v.any()),
    created_at: v.number(),
  })
    .index("by_app_id", ["id"])
    .index("by_session", ["session_id"])
    .index("by_session_round_type_phase", [
      "session_id",
      "round_id",
      "action_type",
      "phase_index",
    ])
    .index("by_unique_action", [
      "session_id",
      "round_id",
      "action_type",
      "phase_index",
      "actor_player_id",
    ]),

  tentative_selections: defineTable({
    id: v.string(),
    session_id: v.string(),
    actor_player_id: v.string(),
    target_player_id: v.optional(v.string()),
    action_type: actionType,
    phase_index: v.number(),
    updated_at: v.number(),
  })
    .index("by_app_id", ["id"])
    .index("by_session_phase_type", ["session_id", "phase_index", "action_type"])
    .index("by_actor", [
      "session_id",
      "phase_index",
      "action_type",
      "actor_player_id",
    ]),
});
