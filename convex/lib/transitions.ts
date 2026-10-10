import { Doc } from "../_generated/dataModel";
import { MutationCtx } from "../_generated/server";
import { listSeats } from "./guards";
import { nextHostAfterDeath, nextHostOnLeave } from "./rules";
import { nowAppleEpochSeconds, uuid } from "./util";

type Session = Doc<"game_sessions">;
type Seat = Doc<"session_players">;

async function deleteTentatives(ctx: MutationCtx, sessionId: string) {
  const rows = await ctx.db
    .query("tentative_selections")
    .withIndex("by_session_phase_type", (q) => q.eq("session_id", sessionId))
    .collect();
  for (const row of rows) await ctx.db.delete(row._id);
}

async function deleteActionsAndTentatives(ctx: MutationCtx, sessionId: string) {
  const actions = await ctx.db
    .query("game_actions")
    .withIndex("by_session", (q) => q.eq("session_id", sessionId))
    .collect();
  for (const action of actions) await ctx.db.delete(action._id);
  await deleteTentatives(ctx, sessionId);
}

// A new night or voting round: fresh round id, humans not ready, drafts cleared.
export async function enterRound(ctx: MutationCtx, session: Session, seats: Seat[], phase: "night" | "voting", data: object) {
  for (const seat of seats) if (!seat.is_bot) await ctx.db.patch(seat._id, { is_ready: false });
  await deleteTentatives(ctx, session.id);
  await ctx.db.patch(session._id, {
    current_phase: phase,
    current_phase_data: data,
    current_round_id: uuid(),
    updated_at: nowAppleEpochSeconds(),
  });
}

// Every seat, bots included, becomes not ready so Play Again starts clean.
export async function finishGame(ctx: MutationCtx, session: Session, seats: Seat[], winner?: "mafia" | "citizen") {
  const now = nowAppleEpochSeconds();
  await ctx.db.patch(session._id, {
    current_phase: "game_over",
    current_phase_data: winner ? { type: "gameOver", winner } : { type: "gameOver" },
    is_game_over: true,
    winner,
    status: "completed",
    completed_at: now,
    updated_at: now,
  });
  for (const seat of seats) await ctx.db.patch(seat._id, { is_ready: false });
}

// `seats` must already reflect this transaction's deaths.
export async function transferHostAfterDeath(ctx: MutationCtx, session: Session, seats: Seat[]) {
  const next = nextHostAfterDeath(seats, session.host_user_id, true);
  if (next?.user_id) {
    await ctx.db.patch(session._id, { host_user_id: next.user_id, updated_at: nowAppleEpochSeconds() });
  }
}

export async function cancelSessionAndRemovePlayers(ctx: MutationCtx, session: Session) {
  const seats = await listSeats(ctx, session.id);
  if (seats.length === 0 && (session.status === "cancelled" || session.status === "completed")) return;
  const completed = session.status === "completed";
  const now = nowAppleEpochSeconds();
  await ctx.db.patch(session._id, {
    status: completed ? "completed" : "cancelled",
    current_phase: completed ? session.current_phase : "cancelled",
    current_phase_data: completed ? session.current_phase_data : undefined,
    current_round_id: undefined,
    completed_at: session.completed_at ?? now,
    updated_at: now,
  });
  for (const seat of seats) await ctx.db.delete(seat._id);
  await deleteActionsAndTentatives(ctx, session.id);
}

// Deletes the seat (if any); a leaving host hands over to the earliest remaining
// human, and the room is cancelled when none is left.
export async function removeSeatAndTransferHost(
  ctx: MutationCtx,
  session: Session,
  seat: Seat | null,
  leavingUserId: string | undefined,
) {
  if (seat) await ctx.db.delete(seat._id);
  if (!leavingUserId || session.host_user_id !== leavingUserId) return;
  const next = nextHostOnLeave(await listSeats(ctx, session.id));
  if (!next?.user_id) return await cancelSessionAndRemovePlayers(ctx, session);
  await ctx.db.patch(session._id, { host_user_id: next.user_id, updated_at: nowAppleEpochSeconds() });
}

// Play Again: the caller becomes host of a fresh lobby with the same seats.
export async function resetToLobby(ctx: MutationCtx, session: Session, seats: Seat[], callerId: string) {
  await ctx.db.patch(session._id, {
    host_user_id: callerId,
    original_host_user_id: session.original_host_user_id ?? session.host_user_id,
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
    updated_at: nowAppleEpochSeconds(),
  });
  for (const seat of seats) {
    await ctx.db.patch(seat._id, {
      role: undefined,
      player_number: undefined,
      is_alive: true,
      removal_note: undefined,
      is_ready: seat.user_id === callerId,
    });
  }
  await deleteActionsAndTentatives(ctx, session.id);
}
