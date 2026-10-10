import { Doc } from "../_generated/dataModel";
import { AssignedNumber, DayRecord, NightRecord, ROLE_OF_TYPE, sessionData } from "./rules";

// Role privacy is enforced here, not in SwiftUI. The host still sees every
// role and action because the host client drives the bots.
type Session = Doc<"game_sessions">;
type Seat = Doc<"session_players">;
type User = Doc<"users">;

const isOver = (session: Session) => session.is_game_over || session.current_phase === "game_over";

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

const pick = <T extends object>(row: T, keys: (keyof T & string)[]) =>
  Object.fromEntries(keys.filter((k) => row[k] !== undefined).map((k) => [k, row[k]])) as Partial<T>;

export function sessionForViewer(session: Session, caller: User | null, seat: Seat | null) {
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
    night_history: [] as Partial<NightRecord>[],
    day_history: [] as Partial<DayRecord>[],
  };
  const isHost = caller !== null && session.host_user_id === caller.id;
  if (isHost || (seat && isOver(session))) {
    return {
      ...outsider,
      original_host_user_id: session.original_host_user_id,
      current_phase_data: phase,
      current_round_id: session.current_round_id,
      assigned_numbers: assigned,
      night_history: nights,
      day_history: days,
    };
  }
  if (!seat) return outsider;
  const fields = phase && PHASE_FIELDS[phase.type];
  return {
    ...outsider,
    original_host_user_id: session.original_host_user_id,
    current_phase_data: phase && fields ? pick(phase, ["type", ...fields]) : undefined,
    current_round_id: session.current_round_id,
    assigned_numbers: assigned.map((row) => ({ player_id: row.player_id, number: row.number })),
    night_history: nights
      .filter((row) => row.is_resolved === true)
      .map((row) => pick(row, ["night_index", "is_resolved", "resulting_deaths", "revealed_death_roles", "timestamp"])),
    day_history: days.map((row) => pick(row, ["day_index", "removed_player_ids", "timestamp"])),
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
    last_heartbeat: row.last_heartbeat,
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
    action_data: showResult ? { inspector_result: result } : undefined,
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
