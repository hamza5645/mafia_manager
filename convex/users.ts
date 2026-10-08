import { ConvexError, v } from "convex/values";
import { mutation, query } from "./_generated/server";
import {
  getCurrentUser,
  nowAppleEpochSeconds,
  requireCurrentUser,
  resolveCaller,
  uuid,
  nextPhaseSequence,
} from "./lib";

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
      args.display_name?.trim() || existing?.display_name || displayNameFromIdentity(identity as any);
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
        const claimedName = args.display_name?.trim() || target.display_name || displayName;
        if (claimable.length > 1) {
          console.warn(
            `[ensureUser] multiple legacy rows for ${identityEmail}; claiming ${target.id}, leaving ${claimable.length - 1} unclaimed`,
          );
        }
        await ctx.db.patch(target._id, {
          auth_subject: identity.subject,
          display_name: claimedName,
          is_anonymous: false,
          updated_at: timestamp,
        });
        return {
          ...target,
          auth_subject: identity.subject,
          display_name: claimedName,
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
  args: {
    user_id: v.string(),
    guest_secret_hash: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    await resolveCaller(ctx, args.user_id, args.guest_secret_hash);
    return await ctx.db
      .query("users")
      .withIndex("by_app_id", (q) => q.eq("id", args.user_id))
      .unique();
  },
});

export const updateProfile = mutation({
  args: {
    user_id: v.string(),
    display_name: v.string(),
    is_anonymous: v.optional(v.boolean()),
    guest_secret_hash: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    await resolveCaller(ctx, args.user_id, args.guest_secret_hash);
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
    // Proof that the caller controls the guest account. Required: the caller
    // must hold the guest's secret in their keychain (hash returned by the
    // client's sha256(secret)). Without this, any signed-in user could merge
    // an arbitrary guest's stats into their account and delete the guest row.
    guest_secret_hash: v.string(),
  },
  handler: async (ctx, args) => {
    // Caller must be Clerk-authenticated AND must match target_user_id.
    // Guests cannot merge — merging is by definition "claim guest data into
    // a real account", so the target side must be a real authenticated user.
    const caller = await requireCurrentUser(ctx);
    if (caller.id !== args.target_user_id) {
      throw new ConvexError("target_user_id must match authenticated caller");
    }

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
    if (!guest.is_anonymous || guest.auth_subject) {
      throw new ConvexError("guest_user_id does not reference a guest account");
    }
    if (!guest.guest_secret_hash || guest.guest_secret_hash !== args.guest_secret_hash) {
      throw new ConvexError("Invalid guest credentials");
    }

    const memberships = await ctx.db.query("session_players")
      .withIndex("by_user", q => q.eq("user_id", guest.id)).collect();
    for (const member of memberships) {
      const existingSeat = await ctx.db.query("session_players")
        .withIndex("by_session_user", q => q.eq("session_id", member.session_id).eq("user_id", target.id)).first();
      if (existingSeat) {
        throw new ConvexError("Leave the account's existing seat in this room before upgrading the guest");
      }
    }

    let transferredCount = 0;
    const guestStats = await ctx.db.query("player_stats")
      .withIndex("by_user", q => q.eq("user_id", guest.id)).collect();
    for (const source of guestStats) {
      const targets = await ctx.db.query("player_stats")
        .withIndex("by_user_player", q => q.eq("user_id", target.id).eq("player_name", source.player_name))
        .collect();
      if (targets.length === 0) {
        await ctx.db.patch(source._id, { user_id: target.id, updated_at: nowAppleEpochSeconds() });
      } else {
        // Keep the stable account row, preferring legacy lineage when present.
        // Collect also repairs collisions left by an earlier buggy merge.
        targets.sort((a, b) => Number(!a.legacy_supabase_id) - Number(!b.legacy_supabase_id) ||
          a.created_at - b.created_at || a.id.localeCompare(b.id));
        const canonical = targets[0];
        const counters = {
          games_played: 0, games_won: 0, games_lost: 0, total_kills: 0,
          times_mafia: 0, times_doctor: 0, times_inspector: 0, times_citizen: 0,
        };
        for (const row of [...targets, source]) {
          for (const key of Object.keys(counters) as (keyof typeof counters)[]) counters[key] += row[key];
        }
        await ctx.db.patch(canonical._id, { ...counters, updated_at: nowAppleEpochSeconds() });
        for (const duplicate of targets.slice(1)) await ctx.db.delete(duplicate._id);
        await ctx.db.delete(source._id);
      }
      transferredCount += 1;
    }
    for (const table of ["custom_roles_configs", "player_groups"] as const) {
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

    // Preserve player IDs/roles/actions while switching the proven owner. Every
    // reference is transferred in this transaction before the guest is deleted.
    for (const member of memberships) await ctx.db.patch(member._id, { user_id: target.id });
    const hostedRooms = await ctx.db.query("game_sessions")
      .withIndex("by_host", q => q.eq("host_user_id", guest.id)).collect();
    for (const room of hostedRooms) {
      await ctx.db.patch(room._id, {
        host_user_id: target.id, updated_at: nowAppleEpochSeconds(), phase_sequence: nextPhaseSequence(room),
      });
    }
    const originalRooms = await ctx.db.query("game_sessions")
      .withIndex("by_original_host", q => q.eq("original_host_user_id", guest.id)).collect();
    for (const room of originalRooms) {
      await ctx.db.patch(room._id, { original_host_user_id: target.id, updated_at: nowAppleEpochSeconds() });
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
