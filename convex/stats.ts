import { ConvexError, v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { roleDistributionValidator, roleValidator } from "./validators";
import { nowAppleEpochSeconds, uuid } from "./lib";

export const listPlayerStats = query({
  args: { user_id: v.string() },
  handler: async (ctx, args) =>
    await ctx.db
      .query("player_stats")
      .withIndex("by_user", (q) => q.eq("user_id", args.user_id))
      .order("asc")
      .collect(),
});

export const getPlayerStat = query({
  args: { user_id: v.string(), player_name: v.string() },
  handler: async (ctx, args) =>
    await ctx.db
      .query("player_stats")
      .withIndex("by_user_player", (q) =>
        q.eq("user_id", args.user_id).eq("player_name", args.player_name),
      )
      .unique(),
});

export const createPlayerStat = mutation({
  args: {
    id: v.optional(v.string()),
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
  },
  handler: async (ctx, args) => {
    const timestamp = nowAppleEpochSeconds();
    const doc = {
      ...args,
      id: args.id ?? uuid(),
      created_at: timestamp,
      updated_at: timestamp,
    };
    await ctx.db.insert("player_stats", doc);
    return doc;
  },
});

export const updatePlayerStat = mutation({
  args: {
    id: v.string(),
    games_played: v.number(),
    games_won: v.number(),
    games_lost: v.number(),
    total_kills: v.number(),
    times_mafia: v.number(),
    times_doctor: v.number(),
    times_inspector: v.number(),
    times_citizen: v.number(),
  },
  handler: async (ctx, args) => {
    const stat = await ctx.db
      .query("player_stats")
      .withIndex("by_app_id", (q) => q.eq("id", args.id))
      .unique();
    if (!stat) {
      throw new ConvexError("Player stat not found");
    }
    const patch = { ...args, updated_at: nowAppleEpochSeconds() };
    await ctx.db.patch(stat._id, patch);
    return { ...stat, ...patch };
  },
});

export const deletePlayerStat = mutation({
  args: { id: v.string() },
  handler: async (ctx, args) => {
    const stat = await ctx.db
      .query("player_stats")
      .withIndex("by_app_id", (q) => q.eq("id", args.id))
      .unique();
    if (stat) {
      await ctx.db.delete(stat._id);
    }
  },
});

export const upsertPlayerStat = mutation({
  args: {
    user_id: v.string(),
    player_name: v.string(),
    role: roleValidator,
    won: v.boolean(),
    kills: v.number(),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("player_stats")
      .withIndex("by_user_player", (q) =>
        q.eq("user_id", args.user_id).eq("player_name", args.player_name),
      )
      .unique();

    const rolePatch = {
      times_mafia: args.role === "mafia" ? 1 : 0,
      times_doctor: args.role === "doctor" ? 1 : 0,
      times_inspector: args.role === "inspector" ? 1 : 0,
      times_citizen: args.role === "citizen" ? 1 : 0,
    };

    if (!existing) {
      const timestamp = nowAppleEpochSeconds();
      const doc = {
        id: uuid(),
        user_id: args.user_id,
        player_name: args.player_name,
        games_played: 1,
        games_won: args.won ? 1 : 0,
        games_lost: args.won ? 0 : 1,
        total_kills: args.kills,
        ...rolePatch,
        created_at: timestamp,
        updated_at: timestamp,
      };
      await ctx.db.insert("player_stats", doc);
      return doc;
    }

    const patch = {
      games_played: existing.games_played + 1,
      games_won: existing.games_won + (args.won ? 1 : 0),
      games_lost: existing.games_lost + (args.won ? 0 : 1),
      total_kills: existing.total_kills + args.kills,
      times_mafia: existing.times_mafia + rolePatch.times_mafia,
      times_doctor: existing.times_doctor + rolePatch.times_doctor,
      times_inspector: existing.times_inspector + rolePatch.times_inspector,
      times_citizen: existing.times_citizen + rolePatch.times_citizen,
      updated_at: nowAppleEpochSeconds(),
    };
    await ctx.db.patch(existing._id, patch);
    return { ...existing, ...patch };
  },
});

export const listCustomRoleConfigs = query({
  args: { user_id: v.string() },
  handler: async (ctx, args) =>
    await ctx.db
      .query("custom_roles_configs")
      .withIndex("by_user", (q) => q.eq("user_id", args.user_id))
      .collect(),
});

export const getCustomRoleConfig = query({
  args: { id: v.string() },
  handler: async (ctx, args) =>
    await ctx.db
      .query("custom_roles_configs")
      .withIndex("by_app_id", (q) => q.eq("id", args.id))
      .unique(),
});

export const createCustomRoleConfig = mutation({
  args: {
    id: v.optional(v.string()),
    user_id: v.string(),
    config_name: v.string(),
    role_distribution: roleDistributionValidator,
  },
  handler: async (ctx, args) => {
    const timestamp = nowAppleEpochSeconds();
    const doc = {
      ...args,
      id: args.id ?? uuid(),
      created_at: timestamp,
      updated_at: timestamp,
    };
    await ctx.db.insert("custom_roles_configs", doc);
    return doc;
  },
});

export const updateCustomRoleConfig = mutation({
  args: {
    id: v.string(),
    config_name: v.string(),
    role_distribution: roleDistributionValidator,
  },
  handler: async (ctx, args) => {
    const config = await ctx.db
      .query("custom_roles_configs")
      .withIndex("by_app_id", (q) => q.eq("id", args.id))
      .unique();
    if (!config) {
      throw new ConvexError("Custom role config not found");
    }
    const patch = {
      config_name: args.config_name,
      role_distribution: args.role_distribution,
      updated_at: nowAppleEpochSeconds(),
    };
    await ctx.db.patch(config._id, patch);
    return { ...config, ...patch };
  },
});

export const deleteCustomRoleConfig = mutation({
  args: { id: v.string() },
  handler: async (ctx, args) => {
    const config = await ctx.db
      .query("custom_roles_configs")
      .withIndex("by_app_id", (q) => q.eq("id", args.id))
      .unique();
    if (config) {
      await ctx.db.delete(config._id);
    }
  },
});

export const listPlayerGroups = query({
  args: { user_id: v.string() },
  handler: async (ctx, args) =>
    await ctx.db
      .query("player_groups")
      .withIndex("by_user", (q) => q.eq("user_id", args.user_id))
      .collect(),
});

export const getPlayerGroup = query({
  args: { id: v.string() },
  handler: async (ctx, args) =>
    await ctx.db
      .query("player_groups")
      .withIndex("by_app_id", (q) => q.eq("id", args.id))
      .unique(),
});

export const createPlayerGroup = mutation({
  args: {
    id: v.optional(v.string()),
    user_id: v.string(),
    group_name: v.string(),
    player_names: v.array(v.string()),
  },
  handler: async (ctx, args) => {
    const timestamp = nowAppleEpochSeconds();
    const doc = {
      ...args,
      id: args.id ?? uuid(),
      created_at: timestamp,
      updated_at: timestamp,
    };
    await ctx.db.insert("player_groups", doc);
    return doc;
  },
});

export const updatePlayerGroup = mutation({
  args: {
    id: v.string(),
    group_name: v.string(),
    player_names: v.array(v.string()),
  },
  handler: async (ctx, args) => {
    const group = await ctx.db
      .query("player_groups")
      .withIndex("by_app_id", (q) => q.eq("id", args.id))
      .unique();
    if (!group) {
      throw new ConvexError("Player group not found");
    }
    const patch = {
      group_name: args.group_name,
      player_names: args.player_names,
      updated_at: nowAppleEpochSeconds(),
    };
    await ctx.db.patch(group._id, patch);
    return { ...group, ...patch };
  },
});

export const deletePlayerGroup = mutation({
  args: { id: v.string() },
  handler: async (ctx, args) => {
    const group = await ctx.db
      .query("player_groups")
      .withIndex("by_app_id", (q) => q.eq("id", args.id))
      .unique();
    if (group) {
      await ctx.db.delete(group._id);
    }
  },
});
