import { ConvexError, v } from "convex/values";
import { internalMutation, internalQuery } from "./_generated/server";
import { roleDistributionValidator } from "./validators";
import { nowAppleEpochSeconds, uuid } from "./lib";

// All mutations here are internalMutation: only callable from the trusted
// migration script via the Convex deploy key, never from the client app.

const userRowValidator = v.object({
  legacy_supabase_user_id: v.string(),
  email: v.optional(v.string()),
  display_name: v.string(),
  is_anonymous: v.optional(v.boolean()),
  created_at: v.optional(v.number()),
  updated_at: v.optional(v.number()),
});

const playerStatRowValidator = v.object({
  legacy_supabase_id: v.string(),
  legacy_supabase_user_id: v.string(),
  player_name: v.string(),
  games_played: v.number(),
  games_won: v.number(),
  games_lost: v.number(),
  total_kills: v.number(),
  times_mafia: v.number(),
  times_doctor: v.number(),
  times_inspector: v.number(),
  times_citizen: v.number(),
  created_at: v.optional(v.number()),
  updated_at: v.optional(v.number()),
});

const customRoleConfigRowValidator = v.object({
  legacy_supabase_id: v.string(),
  legacy_supabase_user_id: v.string(),
  config_name: v.string(),
  role_distribution: roleDistributionValidator,
  created_at: v.optional(v.number()),
  updated_at: v.optional(v.number()),
});

const playerGroupRowValidator = v.object({
  legacy_supabase_id: v.string(),
  legacy_supabase_user_id: v.string(),
  group_name: v.string(),
  player_names: v.array(v.string()),
  created_at: v.optional(v.number()),
  updated_at: v.optional(v.number()),
});

async function findUserByLegacyId(ctx: any, legacyId: string) {
  return await ctx.db
    .query("users")
    .withIndex("by_legacy_supabase_user_id", (q: any) =>
      q.eq("legacy_supabase_user_id", legacyId),
    )
    .unique();
}

async function findUserByEmail(ctx: any, email: string) {
  const rows = await ctx.db
    .query("users")
    .withIndex("by_email_unclaimed", (q: any) => q.eq("email", email))
    .collect();
  return rows[0] ?? null;
}

export const ingestUsers = internalMutation({
  args: { rows: v.array(userRowValidator) },
  handler: async (ctx, args) => {
    let inserted = 0;
    let patched = 0;
    let claimed = 0;
    const fallback = nowAppleEpochSeconds();

    for (const row of args.rows) {
      const email = row.email?.toLowerCase();
      const existingByLegacy = await findUserByLegacyId(
        ctx,
        row.legacy_supabase_user_id,
      );
      if (existingByLegacy) {
        await ctx.db.patch(existingByLegacy._id, {
          display_name: row.display_name,
          email: email ?? existingByLegacy.email,
          is_anonymous: row.is_anonymous ?? existingByLegacy.is_anonymous,
          updated_at: row.updated_at ?? fallback,
        });
        patched += 1;
        continue;
      }

      if (email) {
        const claimedByEmail = await findUserByEmail(ctx, email);
        if (claimedByEmail) {
          await ctx.db.patch(claimedByEmail._id, {
            legacy_supabase_user_id: row.legacy_supabase_user_id,
            display_name: claimedByEmail.display_name || row.display_name,
            updated_at: row.updated_at ?? fallback,
          });
          claimed += 1;
          continue;
        }
      }

      await ctx.db.insert("users", {
        id: uuid(),
        display_name: row.display_name,
        is_anonymous: row.is_anonymous ?? false,
        email,
        legacy_supabase_user_id: row.legacy_supabase_user_id,
        created_at: row.created_at ?? fallback,
        updated_at: row.updated_at ?? fallback,
      });
      inserted += 1;
    }

    return { inserted, patched, claimed_into_existing: claimed };
  },
});

async function resolveOwner(ctx: any, legacyUserId: string) {
  const owner = await findUserByLegacyId(ctx, legacyUserId);
  return owner;
}

async function ingestChildBatch<R extends { legacy_supabase_id: string; legacy_supabase_user_id: string }>(
  ctx: any,
  table: "player_stats" | "custom_roles_configs" | "player_groups",
  rows: R[],
  build: (row: R, ownerId: string, fallback: number) => Record<string, any>,
) {
  let inserted = 0;
  let patched = 0;
  let orphaned = 0;
  const fallback = nowAppleEpochSeconds();

  for (const row of rows) {
    const owner = await resolveOwner(ctx, row.legacy_supabase_user_id);
    if (!owner) {
      orphaned += 1;
      console.warn(
        `[migration.${table}] orphan row legacy_id=${row.legacy_supabase_id} (user ${row.legacy_supabase_user_id} not ingested)`,
      );
      continue;
    }

    const existing = await ctx.db
      .query(table)
      .withIndex("by_legacy_supabase_id", (q: any) =>
        q.eq("legacy_supabase_id", row.legacy_supabase_id),
      )
      .unique();
    const payload = build(row, owner.id, fallback);
    if (existing) {
      await ctx.db.patch(existing._id, {
        ...payload,
        user_id: owner.id,
        updated_at: payload.updated_at ?? fallback,
      });
      patched += 1;
    } else {
      await ctx.db.insert(table, {
        id: uuid(),
        legacy_supabase_id: row.legacy_supabase_id,
        legacy_supabase_user_id: row.legacy_supabase_user_id,
        user_id: owner.id,
        created_at: payload.created_at ?? fallback,
        updated_at: payload.updated_at ?? fallback,
        ...payload,
      });
      inserted += 1;
    }
  }

  return { inserted, patched, orphaned };
}

export const ingestPlayerStats = internalMutation({
  args: { rows: v.array(playerStatRowValidator) },
  handler: async (ctx, args) =>
    await ingestChildBatch(ctx, "player_stats", args.rows, (row) => ({
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
    })),
});

export const ingestCustomRolesConfigs = internalMutation({
  args: { rows: v.array(customRoleConfigRowValidator) },
  handler: async (ctx, args) =>
    await ingestChildBatch(ctx, "custom_roles_configs", args.rows, (row) => ({
      config_name: row.config_name,
      role_distribution: row.role_distribution,
      created_at: row.created_at,
      updated_at: row.updated_at,
    })),
});

export const ingestPlayerGroups = internalMutation({
  args: { rows: v.array(playerGroupRowValidator) },
  handler: async (ctx, args) =>
    await ingestChildBatch(ctx, "player_groups", args.rows, (row) => ({
      group_name: row.group_name,
      player_names: row.player_names,
      created_at: row.created_at,
      updated_at: row.updated_at,
    })),
});

export const countByTable = internalQuery({
  args: {},
  handler: async (ctx) => {
    const [users, stats, configs, groups] = await Promise.all([
      ctx.db.query("users").collect(),
      ctx.db.query("player_stats").collect(),
      ctx.db.query("custom_roles_configs").collect(),
      ctx.db.query("player_groups").collect(),
    ]);
    return {
      users: users.length,
      legacy_users: users.filter(
        (row) => row.legacy_supabase_user_id !== undefined,
      ).length,
      player_stats: stats.length,
      custom_roles_configs: configs.length,
      player_groups: groups.length,
    };
  },
});

export const linkLegacyByAdmin = internalMutation({
  args: {
    email: v.string(),
    legacy_supabase_user_id: v.string(),
  },
  handler: async (ctx, args) => {
    const email = args.email.toLowerCase();
    const claimable = await ctx.db
      .query("users")
      .withIndex("by_email_unclaimed", (q) => q.eq("email", email))
      .collect();
    const target = claimable.find(
      (row) => row.auth_subject !== undefined && row.legacy_supabase_user_id === undefined,
    );
    if (!target) {
      throw new ConvexError(
        "No Clerk-claimed row with that email exists, or it already has a legacy id",
      );
    }
    await ctx.db.patch(target._id, {
      legacy_supabase_user_id: args.legacy_supabase_user_id,
      updated_at: nowAppleEpochSeconds(),
    });
    return { user_id: target.id };
  },
});

export const listLegacyOrphans = internalQuery({
  args: {},
  handler: async (ctx) => {
    const users = await ctx.db.query("users").collect();
    return users
      .filter((row) => row.legacy_supabase_user_id !== undefined && row.auth_subject === undefined)
      .map((row) => ({
        id: row.id,
        email: row.email,
        legacy_supabase_user_id: row.legacy_supabase_user_id,
      }));
  },
});
