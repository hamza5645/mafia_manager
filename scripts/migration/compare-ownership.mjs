// Pure parity assertions: source rows are {id,user_id}; target rows expose only
// app IDs and legacy tags. Reports contain counts, never emails/names/proofs.
export function compareOwnership(source, target) {
  const tables = ['users', 'player_stats', 'custom_roles_configs', 'player_groups'];
  const userIds = new Set(target.users.map(row => row.id));
  const legacyUsers = new Map(target.users.filter(row => row.legacy_supabase_user_id !== undefined)
    .map(row => [row.legacy_supabase_user_id, row.id]));
  const report = {};
  for (const table of tables) {
    const key = table === 'users' ? 'legacy_supabase_user_id' : 'legacy_supabase_id';
    const rows = target[table].filter(row => row[key] !== undefined);
    const expected = new Set(source[table].map(row => row.id));
    const byLegacy = new Map();
    for (const row of rows) byLegacy.set(row[key], [...(byLegacy.get(row[key]) ?? []), row]);
    const result = {
      source_count: source[table].length, legacy_convex_count: rows.length, total_convex_count: target[table].length,
      missing_rows: 0, unexpected_legacy_rows: rows.filter(row => !expected.has(row[key])).length,
      duplicate_legacy_ids: [...byLegacy.values()].filter(group => group.length > 1).length,
      owner_mapping_errors: 0, orphan_rows: 0, per_user_count_mismatches: 0,
    };
    for (const row of source[table]) {
      const matches = byLegacy.get(row.id) ?? [];
      if (matches.length === 0) { result.missing_rows++; continue; }
      if (table !== 'users') {
        const owner = legacyUsers.get(row.user_id);
        for (const match of matches) {
          if (!owner || match.user_id !== owner || match.legacy_supabase_user_id !== row.user_id) result.owner_mapping_errors++;
        }
      }
    }
    if (table !== 'users') {
      result.orphan_rows = target[table].filter(row => !userIds.has(row.user_id)).length;
      const sourceCounts = new Map(), targetCounts = new Map();
      for (const row of source[table]) sourceCounts.set(row.user_id, (sourceCounts.get(row.user_id) ?? 0) + 1);
      for (const row of rows) targetCounts.set(row.user_id, (targetCounts.get(row.user_id) ?? 0) + 1);
      for (const user of source.users) {
        const mapped = legacyUsers.get(user.id);
        if ((sourceCounts.get(user.id) ?? 0) !== (targetCounts.get(mapped) ?? 0)) result.per_user_count_mismatches++;
      }
    }
    result.passed = result.source_count === result.legacy_convex_count &&
      ['missing_rows', 'unexpected_legacy_rows', 'duplicate_legacy_ids', 'owner_mapping_errors', 'orphan_rows', 'per_user_count_mismatches'].every(key => result[key] === 0);
    report[table] = result;
  }
  return { passed: Object.values(report).every(result => result.passed), tables: report };
}
