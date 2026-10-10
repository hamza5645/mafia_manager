import { Doc } from "../_generated/dataModel";
import { MutationCtx, QueryCtx } from "../_generated/server";
import { E, fail } from "./errors";
import { sha256Hex } from "./util";

type Ctx = QueryCtx | MutationCtx;

export type PublicUser = {
  id: string;
  display_name: string;
  is_anonymous: boolean;
  created_at: number;
  updated_at: number;
};

const isLiveGuest = (u: Doc<"users">) => u.is_anonymous === true && u.auth_subject === undefined;

export async function findGuestByProof(ctx: Ctx, hash: string | undefined): Promise<Doc<"users"> | null> {
  if (!hash) return null;
  const digest = await sha256Hex(hash);
  const byDigest = await ctx.db
    .query("users")
    .withIndex("by_guest_secret_digest", (q) => q.eq("guest_secret_digest", digest))
    .collect();
  return byDigest.find(isLiveGuest) ?? null;
}

export async function getAccountUser(ctx: Ctx): Promise<Doc<"users"> | null> {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) return null;
  return await ctx.db
    .query("users")
    .withIndex("by_auth_subject", (q) => q.eq("auth_subject", identity.subject))
    .unique();
}

// A live guest proof wins over the Clerk identity, so a pending guest merge
// keeps acting as the guest until the merge deletes the guest row.
export async function getCaller(ctx: Ctx, hash?: string): Promise<Doc<"users"> | null> {
  return (await findGuestByProof(ctx, hash)) ?? (await getAccountUser(ctx));
}

export async function requireCaller(ctx: Ctx, hash?: string): Promise<Doc<"users">> {
  return (await getCaller(ctx, hash)) ?? fail(E.AUTH);
}

export function publicUser(u: PublicUser): PublicUser {
  return {
    id: u.id,
    display_name: u.display_name,
    is_anonymous: u.is_anonymous,
    created_at: u.created_at,
    updated_at: u.updated_at,
  };
}
