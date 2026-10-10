/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as health from "../health.js";
import type * as lib_errors from "../lib/errors.js";
import type * as lib_guards from "../lib/guards.js";
import type * as lib_identity from "../lib/identity.js";
import type * as lib_projections from "../lib/projections.js";
import type * as lib_rules from "../lib/rules.js";
import type * as lib_transitions from "../lib/transitions.js";
import type * as lib_util from "../lib/util.js";
import type * as migrations from "../migrations.js";
import type * as night from "../night.js";
import type * as phases from "../phases.js";
import type * as play from "../play.js";
import type * as sessions from "../sessions.js";
import type * as stats from "../stats.js";
import type * as users from "../users.js";
import type * as validators from "../validators.js";
import type * as views from "../views.js";
import type * as voting from "../voting.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  health: typeof health;
  "lib/errors": typeof lib_errors;
  "lib/guards": typeof lib_guards;
  "lib/identity": typeof lib_identity;
  "lib/projections": typeof lib_projections;
  "lib/rules": typeof lib_rules;
  "lib/transitions": typeof lib_transitions;
  "lib/util": typeof lib_util;
  migrations: typeof migrations;
  night: typeof night;
  phases: typeof phases;
  play: typeof play;
  sessions: typeof sessions;
  stats: typeof stats;
  users: typeof users;
  validators: typeof validators;
  views: typeof views;
  voting: typeof voting;
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
