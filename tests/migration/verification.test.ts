import { expect, test } from 'vitest';
import { compareOwnership } from '../../scripts/migration/compare-ownership.mjs';

function fixture() {
  return {
    source: { users: [{ id: 'legacy-a' }, { id: 'legacy-b' }], player_stats: [{ id: 'stat-a', user_id: 'legacy-a' }], custom_roles_configs: [], player_groups: [] },
    target: { users: [{ id: 'app-a', legacy_supabase_user_id: 'legacy-a', auth_subject: 'claimed' }, { id: 'app-b', legacy_supabase_user_id: 'legacy-b' }, { id: 'fresh' }],
      player_stats: [{ id: 'app-stat', user_id: 'app-a', legacy_supabase_id: 'stat-a', legacy_supabase_user_id: 'legacy-a' }, { id: 'fresh-stat', user_id: 'fresh' }], custom_roles_configs: [], player_groups: [] },
  };
}

test('claimed legacy users and fresh Convex rows do not create false mismatches', () => {
  const { source, target } = fixture();
  expect(compareOwnership(source, target).passed).toBe(true);
});

test('equal global counts cannot hide a wrong owner or per-user stats count', () => {
  const { source, target } = fixture(); target.player_stats[0].user_id = 'app-b';
  const report = compareOwnership(source, target);
  expect(report.passed).toBe(false);
  expect(report.tables.player_stats.owner_mapping_errors).toBe(1);
  expect(report.tables.player_stats.per_user_count_mismatches).toBe(2);
});

test('missing and unexpected IDs, duplicate legacy IDs, and all child orphans fail', () => {
  const { source, target } = fixture();
  target.player_stats[0].legacy_supabase_id = 'unexpected';
  expect(compareOwnership(source, target).tables.player_stats.missing_rows).toBe(1);
  target.player_stats[0].legacy_supabase_id = 'stat-a';
  target.player_stats.push({ ...target.player_stats[0], id: 'duplicate' });
  expect(compareOwnership(source, target).tables.player_stats.duplicate_legacy_ids).toBe(1);
  target.player_stats[1].user_id = 'missing-user';
  expect(compareOwnership(source, target).tables.player_stats.orphan_rows).toBe(1);
});

test('wrong legacy owner tag and absent legacy parents fail', () => {
  const { source, target } = fixture(); target.player_stats[0].legacy_supabase_user_id = 'legacy-b';
  expect(compareOwnership(source, target).passed).toBe(false);
  target.users = target.users.filter(user => user.id !== 'app-a');
  const result = compareOwnership(source, target);
  expect(result.tables.users.missing_rows).toBe(1);
  expect(result.tables.player_stats.owner_mapping_errors).toBe(1);
  expect(result.tables.player_stats.orphan_rows).toBe(1);
});
