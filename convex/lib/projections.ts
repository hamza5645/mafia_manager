import { Infer, v } from "convex/values";
import { Doc } from "../_generated/dataModel";
import { actionTypeValidator, roleValidator, sessionStatusValidator } from "../validators";
import { AssignedNumber, ROLE_OF_TYPE, sessionData } from "./rules";

// Role privacy is enforced here, not in SwiftUI. The host still sees every
// role and action because the host client drives the bots.
type Session = Doc<"game_sessions">;
type Seat = Doc<"session_players">;
type User = Doc<"users">;

export const isOver = (session: Session) => session.is_game_over || session.current_phase === "game_over";

const PHASE_FIELDS: Record<string, string[]> = {
  lobby: [],
  roleReveal: ["currentPlayerIndex"],
  night: ["nightIndex", "activeRole"],
  morning: ["nightIndex"],
  deathReveal: ["nightIndex"],
  voting: ["dayIndex"],
  votingResults: ["dayIndex", "voteCounts", "eliminatedPlayerId"],
  voteDeathReveal: [
    "dayIndex",
    "eliminatedPlayerId",
    "eliminatedPlayerName",
    "eliminatedPlayerNumber",
    "eliminatedPlayerRole",
    "voteCount",
  ],
  gameOver: ["winner"],
};

// Stored history and phase rows are v.any(), so every projection copies only
// keys its returns validator (below) allows; the validator then rejects drift.
const pick = (row: object, keys: string[]) =>
  Object.fromEntries(
    keys.flatMap((k) => {
      const value = (row as Record<string, unknown>)[k];
      return value === undefined || value === null ? [] : [[k, value]];
    }),
  );

export function sessionForViewer(session: Session, caller: User | null, seat: Seat | null): SessionProjection {
  const { phase, nights, days, assigned } = sessionData(session);
  const outsider = {
    id: session.id,
    room_code: session.room_code,
    host_user_id: session.host_user_id,
    status: session.status,
    created_at: session.created_at,
    started_at: session.started_at,
    completed_at: session.completed_at,
    max_players: session.max_players,
    bot_count: session.bot_count,
    current_phase: session.current_phase,
    day_index: session.day_index,
    is_game_over: session.is_game_over,
    winner: session.winner,
    updated_at: session.updated_at,
    assigned_numbers: [] as AssignedNumber[],
    night_history: [] as NightView[],
    day_history: [] as DayView[],
  };
  const isHost = caller !== null && session.host_user_id === caller.id;
  if (!seat && !isHost) return outsider;
  const fields = phase && PHASE_FIELDS[phase.type];
  const member = {
    ...outsider,
    original_host_user_id: session.original_host_user_id,
    current_phase_data: phase && fields ? (pick(phase, ["type", ...fields]) as PhaseView) : undefined,
    current_round_id: session.current_round_id,
    assigned_numbers: assigned.map((row) => ({ player_id: row.player_id, number: row.number })),
  };
  if (isHost || isOver(session)) {
    return {
      ...member,
      night_history: nights.map((row) => pick(row, Object.keys(nightRecordValidator.fields)) as NightView),
      day_history: days.map((row) => pick(row, Object.keys(dayRecordValidator.fields)) as DayView),
    };
  }
  return {
    ...member,
    night_history: nights
      .filter((row) => row.is_resolved === true)
      .map((row) => pick(row, ["night_index", "is_resolved", "resulting_deaths", "revealed_death_roles", "timestamp"]) as NightView),
    day_history: days.map((row) => pick(row, ["day_index", "removed_player_ids", "timestamp"]) as DayView),
  };
}

// `viewer` is the caller's own seat; callers return [] to outsiders before this.
export function playerForViewer(row: Seat, session: Session, viewer: Seat, isHost: boolean) {
  const isMe = row.user_id === viewer.user_id;
  const canSeeRole =
    isOver(session) || isMe || isHost || (viewer.role === "mafia" && row.role === "mafia");
  // During the night a ready flag reveals who holds an active role.
  const maskReady = session.current_phase === "night" && !isHost && !isMe;
  return {
    id: row.id,
    session_id: row.session_id,
    user_id: row.user_id,
    player_id: row.player_id,
    player_name: row.player_name,
    player_number: row.player_number,
    role: canSeeRole ? row.role : undefined,
    is_bot: row.is_bot,
    is_alive: row.is_alive,
    is_online: row.is_online,
    is_ready: maskReady ? false : row.is_ready,
    joined_at: row.joined_at,
    removal_note: row.removal_note,
    is_me: isMe,
  };
}

type RowViewer = { session: Session; seat: Seat; isHost: boolean; allVoted: boolean };

// §7.3/§7.4. Drafts have no round_id, so vote drafts stay private to host and actor.
function canSeeRow(row: { action_type: string; actor_player_id: string; round_id?: string }, v: RowViewer) {
  if (v.isHost || v.seat.player_id === row.actor_player_id) return true;
  const over = isOver(v.session);
  if (row.action_type === "vote") {
    if (!row.round_id) return false;
    const openVote =
      !over && v.session.current_phase === "voting" && row.round_id === v.session.current_round_id;
    return !openVote || v.allVoted;
  }
  return over || v.seat.role === ROLE_OF_TYPE[row.action_type];
}

export function actionForViewer(row: Doc<"game_actions">, v: RowViewer) {
  if (!canSeeRow(row, v)) return null;
  const result = row.action_data?.inspector_result;
  const showResult =
    result !== undefined && (v.isHost || v.seat.player_id === row.actor_player_id || isOver(v.session));
  return {
    id: row.id,
    session_id: row.session_id,
    round_id: row.round_id,
    action_type: row.action_type,
    phase_index: row.phase_index,
    actor_player_id: row.actor_player_id,
    target_player_id: row.target_player_id,
    action_data: showResult ? { inspector_result: result as InspectorResult } : undefined,
    created_at: row.created_at,
  };
}

export function tentativeForViewer(row: Doc<"tentative_selections">, v: RowViewer) {
  if (!canSeeRow(row, v)) return null;
  return {
    actor_player_id: row.actor_player_id,
    target_player_id: row.target_player_id,
    action_type: row.action_type,
    phase_index: row.phase_index,
    updated_at: row.updated_at,
  };
}

// Exact `returns` shapes of views:*. Swift decodes these (see contract fixtures
// in tests/fixtures/contract), so a change here is an API change. Free-text
// fields of stored v.any() rows accept any string, as the Swift decoder does.
const optionalId = v.optional(v.string());
const nullable = <T extends Parameters<typeof v.union>[0]>(validator: T) => v.union(validator, v.null());

const phaseDataValidator = v.object({
  type: v.string(),
  currentPlayerIndex: v.optional(v.number()),
  nightIndex: v.optional(v.number()),
  activeRole: v.optional(v.string()),
  dayIndex: v.optional(v.number()),
  // `{ [player_id]: n }`, or the legacy Swift alternating `[id, n, ...]` array.
  voteCounts: v.optional(v.union(v.record(v.string(), v.number()), v.array(v.union(v.string(), v.number())))),
  eliminatedPlayerId: optionalId,
  eliminatedPlayerName: v.optional(v.string()),
  eliminatedPlayerNumber: v.optional(v.number()),
  eliminatedPlayerRole: v.optional(v.string()),
  voteCount: v.optional(v.number()),
  winner: v.optional(v.string()),
});

// Optional wherever the Swift decoder tolerates absence (records from old hosts).
const nightRecordValidator = v.object({
  night_index: v.number(),
  round_id: optionalId,
  is_resolved: v.optional(v.boolean()),
  mafia_target_id: optionalId,
  inspector_checked_id: optionalId,
  doctor_protected_id: optionalId,
  target_was_saved: v.optional(v.boolean()),
  resulting_deaths: v.array(v.string()),
  revealed_death_roles: v.optional(v.record(v.string(), v.string())),
  mafia_player_numbers: v.optional(v.array(v.number())),
  doctor_player_numbers: v.optional(v.array(v.number())),
  inspector_player_numbers: v.optional(v.array(v.number())),
  next_phase: v.optional(v.union(v.literal("morning"), v.literal("game_over"))),
  timestamp: v.number(),
});

const dayRecordValidator = v.object({
  day_index: v.number(),
  round_id: optionalId,
  removed_player_ids: v.array(v.string()),
  next_phase: v.optional(v.union(v.literal("night"), v.literal("game_over"))),
  timestamp: v.number(),
});

const sessionProjectionValidator = v.object({
  id: v.string(),
  room_code: v.string(),
  host_user_id: v.string(),
  status: sessionStatusValidator,
  created_at: v.number(),
  started_at: v.optional(v.number()),
  completed_at: v.optional(v.number()),
  max_players: v.number(),
  bot_count: v.number(),
  current_phase: v.string(),
  day_index: v.number(),
  is_game_over: v.boolean(),
  winner: v.optional(roleValidator),
  updated_at: v.number(),
  assigned_numbers: v.array(v.object({ player_id: v.string(), number: v.number() })),
  night_history: v.array(nightRecordValidator),
  day_history: v.array(dayRecordValidator),
  // Members only:
  original_host_user_id: optionalId,
  current_phase_data: v.optional(phaseDataValidator),
  current_round_id: optionalId,
});

export const sessionViewValidator = v.object({
  session: sessionProjectionValidator,
  viewer: v.object({
    user_id: nullable(v.string()),
    player_record_id: nullable(v.string()),
    player_id: nullable(v.string()),
    is_member: v.boolean(),
    is_host: v.boolean(),
  }),
});

export const playerViewValidator = v.object({
  id: v.string(),
  session_id: v.string(),
  user_id: optionalId,
  player_id: v.string(),
  player_name: v.string(),
  player_number: v.optional(v.number()),
  role: v.optional(roleValidator),
  is_bot: v.boolean(),
  is_alive: v.boolean(),
  is_online: v.boolean(),
  is_ready: v.boolean(),
  joined_at: v.number(),
  removal_note: v.optional(v.string()),
  is_me: v.boolean(),
});

const inspectorResultValidator = v.union(v.literal("mafia"), v.literal("not_mafia"), v.literal("blocked"));

export const roundStateValidator = v.object({
  round_id: nullable(v.string()),
  phase: v.string(),
  phase_index: nullable(v.number()),
  ready_to_advance: v.boolean(),
  actions: v.array(
    v.object({
      id: v.string(),
      session_id: v.string(),
      round_id: v.string(),
      action_type: actionTypeValidator,
      phase_index: v.number(),
      actor_player_id: v.string(),
      target_player_id: optionalId,
      action_data: v.optional(v.object({ inspector_result: inspectorResultValidator })),
      created_at: v.number(),
    }),
  ),
  tentative: v.array(
    v.object({
      actor_player_id: v.string(),
      target_player_id: optionalId,
      action_type: actionTypeValidator,
      phase_index: v.number(),
      updated_at: v.number(),
    }),
  ),
});

export const hostPresenceValidator = v.object({
  host_user_id: v.string(),
  // Server Apple-epoch seconds; null when the host has no presence row.
  host_last_heartbeat: nullable(v.number()),
  server_now: v.number(),
  stale_after_seconds: v.number(),
});

type SessionProjection = Infer<typeof sessionProjectionValidator>;
type PhaseView = Infer<typeof phaseDataValidator>;
type NightView = Infer<typeof nightRecordValidator>;
type DayView = Infer<typeof dayRecordValidator>;
type InspectorResult = Infer<typeof inspectorResultValidator>;
