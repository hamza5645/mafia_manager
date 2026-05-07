/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as actions from "../actions.js";
import type * as gameFlow from "../gameFlow.js";
import type * as health from "../health.js";
import type * as lib from "../lib.js";
import type * as migration from "../migration.js";
import type * as players from "../players.js";
import type * as roomCodes from "../roomCodes.js";
import type * as sessions from "../sessions.js";
import type * as stats from "../stats.js";
import type * as users from "../users.js";
import type * as validators from "../validators.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  actions: typeof actions;
  gameFlow: typeof gameFlow;
  health: typeof health;
  lib: typeof lib;
  migration: typeof migration;
  players: typeof players;
  roomCodes: typeof roomCodes;
  sessions: typeof sessions;
  stats: typeof stats;
  users: typeof users;
  validators: typeof validators;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {};
