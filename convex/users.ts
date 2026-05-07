import { ConvexError, v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { getCurrentUser, nowAppleEpochSeconds, uuid } from "./lib";

function displayNameFromIdentity(identity: any) {
  const name = identity.name ?? identity.nickname ?? identity.email;
  return typeof name === "string" && name.trim().length > 0 ? name.trim() : "Player";
}

export const ensureUser = mutation({
  args: {
    display_name: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) {
      throw new ConvexError("Authentication required");
    }

    const existing = await ctx.db
      .query("users")
      .withIndex("by_auth_subject", (q) => q.eq("auth_subject", identity.subject))
      .unique();

    const timestamp = nowAppleEpochSeconds();
    const displayName =
      args.display_name?.trim() || displayNameFromIdentity(identity as any);
    const identityEmail =
      typeof (identity as any).email === "string"
        ? ((identity as any).email as string).toLowerCase()
        : undefined;

    if (existing) {
      await ctx.db.patch(existing._id, {
        display_name: displayName,
        email: identityEmail ?? existing.email,
        updated_at: timestamp,
      });
      return {
        ...existing,
        display_name: displayName,
        email: identityEmail ?? existing.email,
        updated_at: timestamp,
      };
    }

    if (identityEmail) {
      const unclaimed = await ctx.db
        .query("users")
        .withIndex("by_email_unclaimed", (q) =>
          q.eq("email", identityEmail).eq("auth_subject", undefined),
        )
        .collect();
      const claimable = unclaimed
        .filter((row) => row.legacy_supabase_user_id !== undefined)
        .sort((a, b) => b.updated_at - a.updated_at);
      if (claimable.length > 0) {
        const target = claimable[0];
        if (claimable.length > 1) {
          console.warn(
            `[ensureUser] multiple legacy rows for ${identityEmail}; claiming ${target.id}, leaving ${claimable.length - 1} unclaimed`,
          );
        }
        await ctx.db.patch(target._id, {
          auth_subject: identity.subject,
          display_name: displayName,
          is_anonymous: false,
          updated_at: timestamp,
        });
        return {
          ...target,
          auth_subject: identity.subject,
          display_name: displayName,
          is_anonymous: false,
          updated_at: timestamp,
        };
      }
    }

    const doc = {
      id: uuid(),
      auth_subject: identity.subject,
      display_name: displayName,
      is_anonymous: false,
      email: identityEmail,
      created_at: timestamp,
      updated_at: timestamp,
    };
    await ctx.db.insert("users", doc);
    return doc;
  },
});

export const createOrRestoreGuest = mutation({
  args: {
    guest_secret_hash: v.string(),
    display_name: v.string(),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("users")
      .withIndex("by_guest_secret_hash", (q) =>
        q.eq("guest_secret_hash", args.guest_secret_hash),
      )
      .first();

    const timestamp = nowAppleEpochSeconds();
    if (existing) {
      await ctx.db.patch(existing._id, {
        display_name: args.display_name,
        updated_at: timestamp,
      });
      return { ...existing, display_name: args.display_name, updated_at: timestamp };
    }

    const doc = {
      id: uuid(),
      display_name: args.display_name,
      is_anonymous: true,
      guest_secret_hash: args.guest_secret_hash,
      created_at: timestamp,
      updated_at: timestamp,
    };
    await ctx.db.insert("users", doc);
    return doc;
  },
});

export const getMe = query({
  args: {},
  handler: async (ctx) => await getCurrentUser(ctx),
});

export const getUserProfile = query({
  args: { user_id: v.string() },
  handler: async (ctx, args) =>
    await ctx.db
      .query("users")
      .withIndex("by_app_id", (q) => q.eq("id", args.user_id))
      .unique(),
});

export const updateProfile = mutation({
  args: {
    user_id: v.string(),
    display_name: v.string(),
    is_anonymous: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_app_id", (q) => q.eq("id", args.user_id))
      .unique();
    if (!user) {
      throw new ConvexError("User not found");
    }

    const patch = {
      display_name: args.display_name,
      is_anonymous: args.is_anonymous ?? user.is_anonymous,
      updated_at: nowAppleEpochSeconds(),
    };
    await ctx.db.patch(user._id, patch);
    return { ...user, ...patch };
  },
});

export const mergeGuestIntoAccount = mutation({
  args: {
    guest_user_id: v.string(),
    target_user_id: v.string(),
  },
  handler: async (ctx, args) => {
    const guest = await ctx.db
      .query("users")
      .withIndex("by_app_id", (q) => q.eq("id", args.guest_user_id))
      .unique();
    const target = await ctx.db
      .query("users")
      .withIndex("by_app_id", (q) => q.eq("id", args.target_user_id))
      .unique();

    if (!guest || !target) {
      throw new ConvexError("User not found");
    }

    let transferredCount = 0;
    for (const table of ["player_stats", "custom_roles_configs", "player_groups"] as const) {
      const docs = await ctx.db
        .query(table)
        .withIndex("by_user", (q) => q.eq("user_id", args.guest_user_id))
        .collect();
      for (const doc of docs) {
        await ctx.db.patch(doc._id, {
          user_id: args.target_user_id,
          updated_at: nowAppleEpochSeconds(),
        });
        transferredCount += 1;
      }
    }

    await ctx.db.delete(guest._id);
    return {
      success: true,
      merged_count: transferredCount,
      transferred_count: transferredCount,
      error: undefined,
    };
  },
});
