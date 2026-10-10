import { v } from "convex/values";
import { MutationCtx, mutation, query } from "./_generated/server";
import { E, fail } from "./lib/errors";
import { findGuestByProof, getAccountUser, getCaller, publicUser, requireCaller } from "./lib/identity";
import { cleanText, nowAppleEpochSeconds, sha256Hex, uuid } from "./lib/util";
import { guestArg } from "./validators";

function displayNameFromIdentity(identity: { name?: string; nickname?: string; email?: string }) {
  const name = identity.name ?? identity.nickname ?? identity.email;
  return typeof name === "string" && name.trim().length > 0 ? name.trim() : "Player";
}

export const ensureUser = mutation({
  args: { display_name: v.optional(v.string()), ...guestArg },
  handler: async (ctx, args) => {
    const identity = (await ctx.auth.getUserIdentity()) ?? fail(E.AUTH);
    const requested = args.display_name?.trim()
      ? cleanText(args.display_name, 1, 100, E.DISPLAY_NAME)
      : undefined;
    const existing = await ctx.db
      .query("users")
      .withIndex("by_auth_subject", (q) => q.eq("auth_subject", identity.subject))
      .unique();
    const timestamp = nowAppleEpochSeconds();
    const email = typeof identity.email === "string" ? identity.email.toLowerCase() : undefined;

    if (existing) {
      const patch = {
        display_name: requested || existing.display_name || displayNameFromIdentity(identity),
        email: email ?? existing.email,
        updated_at: timestamp,
      };
      await ctx.db.patch(existing._id, patch);
      return publicUser({ ...existing, ...patch });
    }

    // Claim a migrated legacy row only for a verified email address.
    if (email && identity.emailVerified === true) {
      const unclaimed = await ctx.db
        .query("users")
        .withIndex("by_email_unclaimed", (q) => q.eq("email", email).eq("auth_subject", undefined))
        .collect();
      const claimable = unclaimed
        .filter((row) => row.legacy_supabase_user_id !== undefined)
        .sort((a, b) => b.updated_at - a.updated_at);
      if (claimable.length > 0) {
        const target = claimable[0];
        if (claimable.length > 1) {
          console.warn(
            `[ensureUser] multiple legacy rows for ${email}; claiming ${target.id}, leaving ${claimable.length - 1} unclaimed`,
          );
        }
        const patch = {
          auth_subject: identity.subject,
          display_name: requested || target.display_name || displayNameFromIdentity(identity),
          is_anonymous: false,
          updated_at: timestamp,
        };
        await ctx.db.patch(target._id, patch);
        return publicUser({ ...target, ...patch });
      }
    }

    const doc = {
      id: uuid(),
      auth_subject: identity.subject,
      display_name: requested || displayNameFromIdentity(identity),
      is_anonymous: false,
      email,
      created_at: timestamp,
      updated_at: timestamp,
    };
    await ctx.db.insert("users", doc);
    return publicUser(doc);
  },
});

export const getMe = query({
  args: { ...guestArg },
  handler: async (ctx, args) => {
    const caller = await getCaller(ctx, args.guest_secret_hash);
    return caller ? publicUser(caller) : null;
  },
});

export const createOrRestoreGuest = mutation({
  args: { display_name: v.string(), guest_secret_hash: v.string() },
  handler: async (ctx, args) => {
    if (!/^[0-9a-f]{64}$/.test(args.guest_secret_hash)) fail(E.GUEST_INVALID);
    const displayName = cleanText(args.display_name, 1, 100, E.DISPLAY_NAME);
    const timestamp = nowAppleEpochSeconds();
    const existing = await findGuestByProof(ctx, args.guest_secret_hash);
    if (existing) {
      const patch = { display_name: displayName, updated_at: timestamp };
      await ctx.db.patch(existing._id, patch);
      return publicUser({ ...existing, ...patch });
    }
    const doc = {
      id: uuid(),
      display_name: displayName,
      is_anonymous: true,
      guest_secret_digest: await sha256Hex(args.guest_secret_hash),
      created_at: timestamp,
      updated_at: timestamp,
    };
    await ctx.db.insert("users", doc);
    return publicUser(doc);
  },
});

export const updateProfile = mutation({
  args: { display_name: v.string(), ...guestArg },
  handler: async (ctx, args) => {
    const caller = await requireCaller(ctx, args.guest_secret_hash);
    const patch = {
      display_name: cleanText(args.display_name, 1, 100, E.DISPLAY_NAME),
      updated_at: nowAppleEpochSeconds(),
    };
    await ctx.db.patch(caller._id, patch);
    return publicUser({ ...caller, ...patch });
  },
});

// Finds a name the account does not use yet: "<name> (Guest)", "(Guest 2)", ...
async function freeLibraryName(
  ctx: MutationCtx,
  table: "custom_roles_configs" | "player_groups",
  userId: string,
  name: string,
) {
  const taken = async (candidate: string) =>
    table === "custom_roles_configs"
      ? (await ctx.db
          .query("custom_roles_configs")
          .withIndex("by_user_config_name", (q) => q.eq("user_id", userId).eq("config_name", candidate))
          .first()) !== null
      : (await ctx.db
          .query("player_groups")
          .withIndex("by_user_group_name", (q) => q.eq("user_id", userId).eq("group_name", candidate))
          .first()) !== null;
  let candidate = name;
  for (let n = 1; await taken(candidate); n += 1) {
    const suffix = n === 1 ? " (Guest)" : ` (Guest ${n})`;
    candidate = name.slice(0, 100 - suffix.length) + suffix;
  }
  return candidate;
}

export const mergeGuestIntoAccount = mutation({
  args: { guest_secret_hash: v.string() },
  handler: async (ctx, args) => {
    const account = (await getAccountUser(ctx)) ?? fail(E.AUTH);
    const digest = await sha256Hex(args.guest_secret_hash);
    const guest = await findGuestByProof(ctx, args.guest_secret_hash);
    if (!guest) {
      // A retry after a successful merge finds the tombstone instead of the guest.
      if (account.merged_guest_digests?.includes(digest)) {
        return { success: true, merged_count: 0, transferred_count: 0 };
      }
      fail(E.GUEST_NOT_FOUND);
    }

    const memberships = await ctx.db
      .query("session_players")
      .withIndex("by_user", (q) => q.eq("user_id", guest.id))
      .collect();
    for (const member of memberships) {
      const existingSeat = await ctx.db
        .query("session_players")
        .withIndex("by_session_user", (q) => q.eq("session_id", member.session_id).eq("user_id", account.id))
        .first();
      if (existingSeat) fail(E.MERGE_SEAT_CONFLICT);
    }

    let transferredCount = 0;
    const guestStats = await ctx.db
      .query("player_stats")
      .withIndex("by_user", (q) => q.eq("user_id", guest.id))
      .collect();
    for (const source of guestStats) {
      const targets = await ctx.db
        .query("player_stats")
        .withIndex("by_user_player", (q) => q.eq("user_id", account.id).eq("player_name", source.player_name))
        .collect();
      if (targets.length === 0) {
        await ctx.db.patch(source._id, { user_id: account.id, updated_at: nowAppleEpochSeconds() });
      } else {
        // Keep the stable account row, preferring legacy lineage when present.
        // Collect also repairs collisions left by an earlier buggy merge.
        targets.sort(
          (a, b) =>
            Number(!a.legacy_supabase_id) - Number(!b.legacy_supabase_id) ||
            a.created_at - b.created_at ||
            a.id.localeCompare(b.id),
        );
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

    const configs = await ctx.db
      .query("custom_roles_configs")
      .withIndex("by_user", (q) => q.eq("user_id", guest.id))
      .collect();
    for (const config of configs) {
      const configName = await freeLibraryName(ctx, "custom_roles_configs", account.id, config.config_name);
      await ctx.db.patch(config._id, { user_id: account.id, config_name: configName, updated_at: nowAppleEpochSeconds() });
      transferredCount += 1;
    }
    const groups = await ctx.db
      .query("player_groups")
      .withIndex("by_user", (q) => q.eq("user_id", guest.id))
      .collect();
    for (const group of groups) {
      const groupName = await freeLibraryName(ctx, "player_groups", account.id, group.group_name);
      await ctx.db.patch(group._id, { user_id: account.id, group_name: groupName, updated_at: nowAppleEpochSeconds() });
      transferredCount += 1;
    }

    // Preserve player ids, roles and actions while switching the proven owner.
    for (const member of memberships) await ctx.db.patch(member._id, { user_id: account.id });
    const hostedRooms = await ctx.db
      .query("game_sessions")
      .withIndex("by_host", (q) => q.eq("host_user_id", guest.id))
      .collect();
    for (const room of hostedRooms) {
      await ctx.db.patch(room._id, { host_user_id: account.id, updated_at: nowAppleEpochSeconds() });
    }
    const originalRooms = await ctx.db
      .query("game_sessions")
      .withIndex("by_original_host", (q) => q.eq("original_host_user_id", guest.id))
      .collect();
    for (const room of originalRooms) {
      await ctx.db.patch(room._id, { original_host_user_id: account.id, updated_at: nowAppleEpochSeconds() });
    }

    await ctx.db.patch(account._id, { merged_guest_digests: [...(account.merged_guest_digests ?? []), digest] });
    await ctx.db.delete(guest._id);
    return { success: true, merged_count: transferredCount, transferred_count: transferredCount };
  },
});
