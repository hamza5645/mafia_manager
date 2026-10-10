import { Doc } from "../_generated/dataModel";
import { E, fail } from "./errors";
import { nowAppleEpochSeconds } from "./util";

// Pure game rules ported from MultiplayerGameStore.swift (MGS) and GameStore.swift.
type Seat = Doc<"session_players">;
type Action = Doc<"game_actions">;
type Session = Doc<"game_sessions">;
type Role = NonNullable<Seat["role"]>;
type ActionType = Action["action_type"];

export const NIGHT_TYPES = ["mafia_target", "doctor_protect", "inspector_check"] as const;
export const ROLE_OF_TYPE: Record<string, Role | undefined> = {
  mafia_target: "mafia",
  doctor_protect: "doctor",
  inspector_check: "inspector",
};
const TYPE_OF_ROLE: Record<string, ActionType | undefined> = {
  mafia: "mafia_target",
  doctor: "doctor_protect",
  inspector: "inspector_check",
};
export const HOST_STALE_SECONDS = 15;

// GameStore.swift 488-504.
export function roleDistribution(n: number) {
  const p = Math.min(Math.max(n, 4), 19);
  const [mafia, doctor, inspector] = p <= 5 ? [1, 0, 1] : p <= 8 ? [2, 1, 1] : p <= 14 ? [4, 1, 2] : [5, 2, 2];
  return { mafia, doctor, inspector, citizen: n - mafia - doctor - inspector };
}

// MGS 2050-2068. An action with no target still counts as submitted.
export function nightActionsReady(seats: Seat[], actions: Action[], roundId: string, nightIndex: number) {
  const alive = seats.filter((s) => s.is_alive);
  if (alive.length === 0) return false;
  return alive.every((p) => {
    if (p.role === "citizen") return true;
    const required = p.role && TYPE_OF_ROLE[p.role];
    if (!required) return false;
    return actions.some(
      (a) =>
        a.actor_player_id === p.player_id &&
        a.action_type === required &&
        a.round_id === roundId &&
        a.phase_index === nightIndex,
    );
  });
}

// MGS 2349-2417. Humans may abstain; bots must name a target.
export function votesReady(seats: Seat[], votes: Action[]) {
  const voted = new Set(votes.map((a) => a.actor_player_id));
  const votedWithTarget = new Set(votes.filter((a) => a.target_player_id !== undefined).map((a) => a.actor_player_id));
  return seats
    .filter((s) => s.is_alive)
    .every((p) => (p.is_bot ? votedWithTarget.has(p.player_id) : voted.has(p.player_id)));
}

// MGS 2714-2768.
export function majorityTarget(actions: Action[], validTargets: string[], humanIds: Set<string>): string | undefined {
  if (actions.length === 0) return undefined;
  const counts = new Map<string, number>();
  for (const a of actions) {
    if (a.target_player_id !== undefined) counts.set(a.target_player_id, (counts.get(a.target_player_id) ?? 0) + 1);
  }
  if (counts.size === 0) return validTargets[0];
  const max = Math.max(...counts.values());
  const leaders = [...counts.keys()].filter((id) => counts.get(id) === max);
  if (leaders.length === 1) return leaders[0];
  const humanVoted = new Set(
    actions.filter((a) => humanIds.has(a.actor_player_id) && a.target_player_id !== undefined).map((a) => a.target_player_id),
  );
  const humanLeaders = leaders.filter((id) => humanVoted.has(id));
  if (humanLeaders.length === 1) return humanLeaders[0];
  return actions
    .filter((a) => a.target_player_id !== undefined && leaders.includes(a.target_player_id))
    .sort((a, b) => a.created_at - b.created_at || a._creationTime - b._creationTime)[0].target_player_id;
}

// MGS 2096-2210. Only actions from alive seats holding the matching role count (D1).
export function buildNightRecord(seats: Seat[], actions: Action[], nightIndex: number, roundId: string) {
  const alive = seats.filter((s) => s.is_alive);
  const humanIds = new Set(seats.filter((s) => !s.is_bot).map((s) => s.player_id));
  const actorOf = (a: Action) => alive.find((s) => s.player_id === a.actor_player_id);
  const counted = (type: ActionType) =>
    actions.filter((a) => a.action_type === type && actorOf(a)?.role === ROLE_OF_TYPE[type]);
  const numbers = (list: Action[]) =>
    list
      .map((a) => actorOf(a)?.player_number)
      .filter((n): n is number => n !== undefined)
      .sort((a, b) => a - b);
  const ids = (list: Seat[]) => list.map((s) => s.player_id);

  const mafiaA = counted("mafia_target");
  const doctorA = counted("doctor_protect");
  const inspA = counted("inspector_check");
  const mafiaTarget = majorityTarget(mafiaA, ids(alive.filter((s) => s.role !== "mafia")), humanIds);
  const doctorTarget = majorityTarget(doctorA, ids(alive), humanIds);
  const inspTarget = majorityTarget(inspA, ids(alive.filter((s) => s.role !== "inspector")), humanIds);
  // Any single doctor protection on the mafia target saves it (MGS 2151-2152).
  const saved = mafiaTarget !== undefined && doctorA.some((a) => a.target_player_id === mafiaTarget);
  return {
    night_index: nightIndex,
    round_id: roundId,
    is_resolved: false,
    mafia_target_id: mafiaTarget,
    inspector_checked_id: inspTarget,
    doctor_protected_id: saved ? mafiaTarget : doctorTarget,
    target_was_saved: saved,
    resulting_deaths: [] as string[],
    revealed_death_roles: {} as Record<string, Role>,
    mafia_player_numbers: numbers(mafiaA),
    doctor_player_numbers: numbers(doctorA),
    inspector_player_numbers: numbers(inspA),
    timestamp: nowAppleEpochSeconds(),
  };
}

// MGS 2863-2915.
export function evaluateWinners(aliveAfter: Seat[], startOfDay: boolean): { over: boolean; winner?: "mafia" | "citizen" } {
  if (aliveAfter.length === 0) return { over: true };
  const mafia = aliveAfter.filter((s) => s.role === "mafia").length;
  const non = aliveAfter.length - mafia;
  if (aliveAfter.every((s) => s.is_bot)) return { over: true, winner: mafia === 0 ? "citizen" : "mafia" };
  if (mafia === 0) return { over: true, winner: "citizen" };
  if (startOfDay ? mafia > non : mafia >= non) return { over: true, winner: "mafia" };
  return { over: false };
}

// MGS 2419-2495. A tie or no votes eliminates nobody.
export function tallyVotes(seats: Seat[], votes: Action[]) {
  const counts: Record<string, number> = {};
  for (const p of seats) if (p.is_alive) counts[p.player_id] = 0;
  for (const v of votes) {
    if (v.target_player_id !== undefined) counts[v.target_player_id] = (counts[v.target_player_id] ?? 0) + 1;
  }
  const max = Math.max(...Object.values(counts));
  const leaders = Object.keys(counts).filter((id) => counts[id] === max);
  return { counts, eliminated: max > 0 && leaders.length === 1 ? leaders[0] : undefined };
}

// Accepts the server's `{ [player_id]: n }` and the legacy Swift alternating
// array `[id, n, id, n, ...]`, whose ids Swift encoded in upper case.
export function readVoteCounts(data: any): Record<string, number> {
  const raw = data?.voteCounts;
  if (!Array.isArray(raw)) return raw && typeof raw === "object" ? raw : {};
  const counts: Record<string, number> = {};
  for (let i = 0; i + 1 < raw.length; i += 2) counts[String(raw[i]).toLowerCase()] = Number(raw[i + 1]);
  return counts;
}

// Legacy Swift phase data stored upper-case ids; server ids are lower case.
export function readEliminatedId(data: any): string | undefined {
  return typeof data?.eliminatedPlayerId === "string" ? data.eliminatedPlayerId.toLowerCase() : undefined;
}

export function validateGameAction(
  session: Session,
  seats: Seat[],
  args: { actor_player_id: string; target_player_id?: string; action_type: ActionType; phase_index: number },
) {
  if (session.status !== "in_progress" || session.is_game_over) fail(E.NOT_ACTIVE);
  const isVote = args.action_type === "vote";
  if (session.current_phase !== (isVote ? "voting" : "night")) fail(E.WRONG_PHASE);
  const active = isVote ? session.current_phase_data?.dayIndex : session.current_phase_data?.nightIndex;
  if (!Number.isInteger(active) || args.phase_index !== active) fail(E.MOVED_ON);
  const actor = seats.find((s) => s.player_id === args.actor_player_id) ?? fail(E.PLAYER_NOT_FOUND);
  if (!actor.is_alive) fail(E.ACTOR_DEAD);
  if (!isVote && actor.role !== ROLE_OF_TYPE[args.action_type]) fail(E.WRONG_ROLE);
  if (args.target_player_id === undefined) return;
  const target = seats.find((s) => s.player_id === args.target_player_id);
  if (!target || !target.is_alive) fail(E.TARGET_DEAD);
  if (args.action_type === "mafia_target" && target.role === "mafia") fail(E.MAFIA_TEAMMATE);
  if (args.action_type === "inspector_check" && target.player_id === actor.player_id) fail(E.INSPECT_SELF);
}

// MGS 2834-2861: alive humans other than the host, optionally with a fresh heartbeat.
export function nextHostAfterDeath(seats: Seat[], excludingUserId: string, fresh: boolean): Seat | undefined {
  const now = nowAppleEpochSeconds();
  return seats
    .filter(
      (s) =>
        s.is_alive &&
        !s.is_bot &&
        s.user_id &&
        s.user_id !== excludingUserId &&
        (!fresh || now - s.last_heartbeat <= HOST_STALE_SECONDS),
    )
    .sort((a, b) => a.joined_at - b.joined_at)[0];
}

// Leaving: any remaining human seat, earliest joined; alive/heartbeat not required.
export function nextHostOnLeave(seats: Seat[]): Seat | undefined {
  return seats.filter((s) => !s.is_bot && s.user_id).sort((a, b) => a.joined_at - b.joined_at)[0];
}
