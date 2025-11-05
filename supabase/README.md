# Supabase Database Setup

## Applying the RLS Policies

To fix the "new row violates row-level security policy" error, you need to apply the RLS policies to your Supabase database.

### Option 1: Using Supabase Dashboard (Recommended)

1. Go to your Supabase project dashboard: https://ptspsxqmbfvcwczjpztd.supabase.co
2. Navigate to the SQL Editor (left sidebar)
3. Click "New Query"
4. Copy and paste the contents of `migrations/20250111_enable_rls_policies.sql`
5. Click "Run" to execute the migration

### Option 2: Using Supabase CLI

If you have the Supabase CLI installed:

```bash
cd supabase
supabase db push
```

## What This Migration Does

This migration enables Row Level Security (RLS) on three tables and creates policies that:

1. **profiles** table:
   - Allow users to create their own profile during signup
   - Allow users to view and update only their own profile

2. **player_stats** table:
   - Allow users to view, insert, update, and delete only their own stats

3. **custom_roles_configs** table:
   - Allow users to view, insert, update, and delete only their own role configurations

These policies ensure that users can only access their own data while maintaining security.
