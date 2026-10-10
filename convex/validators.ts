import { v } from "convex/values";

export const roleValidator = v.union(
  v.literal("mafia"),
  v.literal("doctor"),
  v.literal("inspector"),
  v.literal("citizen"),
);

export const sessionStatusValidator = v.union(
  v.literal("waiting"),
  v.literal("in_progress"),
  v.literal("completed"),
  v.literal("cancelled"),
);

export const actionTypeValidator = v.union(
  v.literal("mafia_target"),
  v.literal("inspector_check"),
  v.literal("doctor_protect"),
  v.literal("vote"),
);

export const roleDistributionValidator = v.object({
  mafia_count: v.number(),
  doctor_count: v.number(),
  inspector_count: v.number(),
  citizen_count: v.number(),
  total_players: v.number(),
});

