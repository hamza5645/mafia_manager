import { ConvexError } from "convex/values";

// The complete set of messages a public function may throw. Swift shows the
// string as-is, so wording changes are user-visible.
export const E = {
  AUTH: "Please sign in to continue.",
  GUEST_INVALID: "Your guest session is invalid. Please try again.",
  GUEST_NOT_FOUND: "Guest progress could not be found.",
  MERGE_SEAT_CONFLICT: "Leave your other seat in this room before saving guest progress.",
  DISPLAY_NAME: "Display name must be 1 to 100 characters.",
  PLAYER_NAME: "Player name must be 1 to 50 characters.",
  LIBRARY_NAME: "Name must be 1 to 100 characters.",
  GROUP_SIZE: "A group needs 1 to 19 player names.",
  ROLE_COUNTS: "Role counts are invalid.",
  CONFIG_EXISTS: "A configuration with this name already exists.",
  GROUP_EXISTS: "A group with this name already exists.",
  CONFIG_NOT_FOUND: "Configuration not found.",
  GROUP_NOT_FOUND: "Group not found.",
  KILLS: "Kills must be a whole number from 0 to 100.",
  MAX_PLAYERS: "Max players must be between 4 and 19.",
  BOT_COUNT: "Bot count must leave room for the host.",
  ROOM_CODE: "Could not create a room code. Please try again.",
  GAME_NOT_FOUND: "Game not found.",
  GAME_STARTED: "This game has already started.",
  GAME_FULL: "This game is full.",
  NOT_MEMBER: "You are no longer in this game.",
  HOST_ONLY: "Only the host can do that.",
  HOST_ACTIVE: "The host is still connected.",
  HOST_SUCCESSOR: "Another player is taking over as host.",
  PLAYER_NOT_FOUND: "Player not found.",
  REMOVE_SELF: "You can't remove yourself. Leave the game instead.",
  PLAYER_COUNT: "A game needs 4 to 19 players.",
  ASSIGNMENT_COVERAGE: "Every player must get exactly one role and number.",
  ASSIGNMENT_ROLES: "Role assignment does not match the player count.",
  NOT_GAME_OVER: "Wait until the game ends before playing again.",
  MOVED_ON: "The game has moved on.",
  NOT_ACTIVE: "This game is no longer active.",
  WRONG_PHASE: "This action is not available right now.",
  WRONG_ROLE: "This action is not available for your role.",
  NOT_YOUR_PLAYER: "You can only act for your own player.",
  ACTOR_DEAD: "Eliminated players cannot act.",
  TARGET_DEAD: "Choose a player who is still alive.",
  MAFIA_TEAMMATE: "Mafia cannot target a teammate.",
  INSPECT_SELF: "Inspectors cannot investigate themselves.",
  ALREADY_INSPECTED: "You have already investigated a player tonight.",
  NIGHT_CLOSED: "Night actions are closed.",
  NIGHT_INCOMPLETE: "Waiting for all night actions to be submitted.",
  NIGHT_NOT_RECORDED: "Record the night actions first.",
  VOTES_INCOMPLETE: "Waiting for all votes to be submitted.",
} as const;

export function fail(message: string): never {
  throw new ConvexError(message);
}
