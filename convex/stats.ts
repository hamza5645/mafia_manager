import { v } from "convex/values";
import { Doc } from "./_generated/dataModel";
import { MutationCtx, mutation, query } from "./_generated/server";
import { E, fail } from "./lib/errors";
import { requireCaller } from "./lib/identity";
import { cleanText, nowAppleEpochSeconds, uuid } from "./lib/util";
import { guestArg, roleDistributionValidator, roleValidator } from "./validators";

// Every function is scoped to the caller's own rows. Missing and foreign rows
// behave identically, so existence is never leaked.

type Row<T extends "player_stats" | "custom_roles_configs" | "player_groups"> = Omit<Doc<T>, "_id" | "_creationTime">;

const statOut = (row: Row<"player_stats">) => ({
  id: row.id,
  user_id: row.user_id,
  player_name: row.player_name,
  games_played: row.games_played,
  games_won: row.games_won,
  games_lost: row.games_lost,
  total_kills: row.total_kills,
  times_mafia: row.times_mafia,
  times_doctor: row.times_doctor,
  times_inspector: row.times_inspector,
  times_citizen: row.times_citizen,
  created_at: row.created_at,
  updated_at: row.updated_at,
});

const configOut = (row: Row<"custom_roles_configs">) => ({
  id: row.id,
  user_id: row.user_id,
  config_name: row.config_name,
  role_distribution: row.role_distribution,
  created_at: row.created_at,
  updated_at: row.updated_at,
});

const groupOut = (row: Row<"player_groups">) => ({
  id: row.id,
  user_id: row.user_id,
  group_name: row.group_name,
  player_names: row.player_names,
  created_at: row.created_at,
  updated_at: row.updated_at,
});

async function ownedRow<T extends "player_stats" | "custom_roles_configs" | "player_groups">(
  ctx: MutationCtx,
  table: T,
  id: string,
  userId: string,
): Promise<Doc<T> | null> {
  const row = (await ctx.db
    .query(table)
    .withIndex("by_app_id", (q: any) => q.eq("id", id))
    .unique()) as Doc<T> | null;
  return row && row.user_id === userId ? row : null;
}

type Distribution = Doc<"custom_roles_configs">["role_distribution"];
function checkRoleCounts(d: Distribution) {
  const counts = [d.mafia_count, d.doctor_count, d.inspector_count, d.citizen_count, d.total_players];
  const sum = d.mafia_count + d.doctor_count + d.inspector_count + d.citizen_count;
  if (counts.some((n) => !Number.isInteger(n) || n < 0 || n > 30) || d.total_players !== sum || sum < 1) {
    fail(E.ROLE_COUNTS);
  }
}

function cleanPlayerNames(names: string[]) {
  if (names.length < 1 || names.length > 19) fail(E.GROUP_SIZE);
  return names.map((name) => cleanText(name, 1, 50, E.PLAYER_NAME));
}

async function configNamed(ctx: MutationCtx, userId: string, name: string) {
  return await ctx.db
    .query("custom_roles_configs")
    .withIndex("by_user_config_name", (q) => q.eq("user_id", userId).eq("config_name", name))
    .first();
}

async function groupNamed(ctx: MutationCtx, userId: string, name: string) {
  return await ctx.db
    .query("player_groups")
    .withIndex("by_user_group_name", (q) => q.eq("user_id", userId).eq("group_name", name))
    .first();
}

export const listPlayerStats = query({
  args: { ...guestArg },
  handler: async (ctx, args) => {
    const caller = await requireCaller(ctx, args.guest_secret_hash);
    const rows = await ctx.db
      .query("player_stats")
      .withIndex("by_user", (q) => q.eq("user_id", caller.id))
      .collect();
    return rows.map(statOut);
  },
});

export const getPlayerStat = query({
  args: { player_name: v.string(), ...guestArg },
  handler: async (ctx, args) => {
    const caller = await requireCaller(ctx, args.guest_secret_hash);
    const row = await ctx.db
      .query("player_stats")
      .withIndex("by_user_player", (q) => q.eq("user_id", caller.id).eq("player_name", args.player_name))
      .first();
    return row ? statOut(row) : null;
  },
});

// Records one finished game for one player name. Not idempotent.
export const upsertPlayerStat = mutation({
  args: { player_name: v.string(), role: roleValidator, won: v.boolean(), kills: v.number(), ...guestArg },
  handler: async (ctx, args) => {
    const caller = await requireCaller(ctx, args.guest_secret_hash);
    const playerName = cleanText(args.player_name, 1, 50, E.PLAYER_NAME);
    if (!Number.isInteger(args.kills) || args.kills < 0 || args.kills > 100) fail(E.KILLS);
    const existing = await ctx.db
      .query("player_stats")
      .withIndex("by_user_player", (q) => q.eq("user_id", caller.id).eq("player_name", playerName))
      .first();
    const increments = {
      games_played: 1,
      games_won: args.won ? 1 : 0,
      games_lost: args.won ? 0 : 1,
      total_kills: args.kills,
      times_mafia: args.role === "mafia" ? 1 : 0,
      times_doctor: args.role === "doctor" ? 1 : 0,
      times_inspector: args.role === "inspector" ? 1 : 0,
      times_citizen: args.role === "citizen" ? 1 : 0,
    };
    const timestamp = nowAppleEpochSeconds();
    if (!existing) {
      const doc = {
        id: uuid(),
        user_id: caller.id,
        player_name: playerName,
        ...increments,
        created_at: timestamp,
        updated_at: timestamp,
      };
      await ctx.db.insert("player_stats", doc);
      return statOut(doc);
    }
    const patch = { ...increments, updated_at: timestamp };
    for (const key of Object.keys(increments) as (keyof typeof increments)[]) patch[key] += existing[key];
    await ctx.db.patch(existing._id, patch);
    return statOut({ ...existing, ...patch });
  },
});

export const deletePlayerStat = mutation({
  args: { id: v.string(), ...guestArg },
  handler: async (ctx, args) => {
    const caller = await requireCaller(ctx, args.guest_secret_hash);
    const row = await ownedRow(ctx, "player_stats", args.id, caller.id);
    if (row) await ctx.db.delete(row._id);
    return null;
  },
});

export const listCustomRoleConfigs = query({
  args: { ...guestArg },
  handler: async (ctx, args) => {
    const caller = await requireCaller(ctx, args.guest_secret_hash);
    const rows = await ctx.db
      .query("custom_roles_configs")
      .withIndex("by_user", (q) => q.eq("user_id", caller.id))
      .collect();
    return rows.map(configOut);
  },
});

export const createCustomRoleConfig = mutation({
  args: { config_name: v.string(), role_distribution: roleDistributionValidator, ...guestArg },
  handler: async (ctx, args) => {
    const caller = await requireCaller(ctx, args.guest_secret_hash);
    const configName = cleanText(args.config_name, 1, 100, E.LIBRARY_NAME);
    checkRoleCounts(args.role_distribution);
    if (await configNamed(ctx, caller.id, configName)) fail(E.CONFIG_EXISTS);
    const timestamp = nowAppleEpochSeconds();
    const doc = {
      id: uuid(),
      user_id: caller.id,
      config_name: configName,
      role_distribution: args.role_distribution,
      created_at: timestamp,
      updated_at: timestamp,
    };
    await ctx.db.insert("custom_roles_configs", doc);
    return configOut(doc);
  },
});

export const updateCustomRoleConfig = mutation({
  args: { id: v.string(), config_name: v.string(), role_distribution: roleDistributionValidator, ...guestArg },
  handler: async (ctx, args) => {
    const caller = await requireCaller(ctx, args.guest_secret_hash);
    const row = (await ownedRow(ctx, "custom_roles_configs", args.id, caller.id)) ?? fail(E.CONFIG_NOT_FOUND);
    const configName = cleanText(args.config_name, 1, 100, E.LIBRARY_NAME);
    checkRoleCounts(args.role_distribution);
    const clash = await configNamed(ctx, caller.id, configName);
    if (clash && clash.id !== row.id) fail(E.CONFIG_EXISTS);
    const patch = { config_name: configName, role_distribution: args.role_distribution, updated_at: nowAppleEpochSeconds() };
    await ctx.db.patch(row._id, patch);
    return configOut({ ...row, ...patch });
  },
});

export const deleteCustomRoleConfig = mutation({
  args: { id: v.string(), ...guestArg },
  handler: async (ctx, args) => {
    const caller = await requireCaller(ctx, args.guest_secret_hash);
    const row = await ownedRow(ctx, "custom_roles_configs", args.id, caller.id);
    if (row) await ctx.db.delete(row._id);
    return null;
  },
});

export const listPlayerGroups = query({
  args: { ...guestArg },
  handler: async (ctx, args) => {
    const caller = await requireCaller(ctx, args.guest_secret_hash);
    const rows = await ctx.db
      .query("player_groups")
      .withIndex("by_user", (q) => q.eq("user_id", caller.id))
      .collect();
    return rows.map(groupOut);
  },
});

export const createPlayerGroup = mutation({
  args: { group_name: v.string(), player_names: v.array(v.string()), ...guestArg },
  handler: async (ctx, args) => {
    const caller = await requireCaller(ctx, args.guest_secret_hash);
    const groupName = cleanText(args.group_name, 1, 100, E.LIBRARY_NAME);
    const playerNames = cleanPlayerNames(args.player_names);
    if (await groupNamed(ctx, caller.id, groupName)) fail(E.GROUP_EXISTS);
    const timestamp = nowAppleEpochSeconds();
    const doc = {
      id: uuid(),
      user_id: caller.id,
      group_name: groupName,
      player_names: playerNames,
      created_at: timestamp,
      updated_at: timestamp,
    };
    await ctx.db.insert("player_groups", doc);
    return groupOut(doc);
  },
});

export const updatePlayerGroup = mutation({
  args: { id: v.string(), group_name: v.string(), player_names: v.array(v.string()), ...guestArg },
  handler: async (ctx, args) => {
    const caller = await requireCaller(ctx, args.guest_secret_hash);
    const row = (await ownedRow(ctx, "player_groups", args.id, caller.id)) ?? fail(E.GROUP_NOT_FOUND);
    const groupName = cleanText(args.group_name, 1, 100, E.LIBRARY_NAME);
    const playerNames = cleanPlayerNames(args.player_names);
    const clash = await groupNamed(ctx, caller.id, groupName);
    if (clash && clash.id !== row.id) fail(E.GROUP_EXISTS);
    const patch = { group_name: groupName, player_names: playerNames, updated_at: nowAppleEpochSeconds() };
    await ctx.db.patch(row._id, patch);
    return groupOut({ ...row, ...patch });
  },
});

export const deletePlayerGroup = mutation({
  args: { id: v.string(), ...guestArg },
  handler: async (ctx, args) => {
    const caller = await requireCaller(ctx, args.guest_secret_hash);
    const row = await ownedRow(ctx, "player_groups", args.id, caller.id);
    if (row) await ctx.db.delete(row._id);
    return null;
  },
});
