-- =====================================================
-- PLAYER GROUPS - COMPLETE FIX
-- =====================================================
-- Run this entire script in Supabase SQL Editor
-- This will show diagnostics and fix any issues

-- =====================================================
-- DIAGNOSTICS
-- =====================================================

-- Check if table exists
SELECT
    CASE
        WHEN EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'player_groups')
        THEN 'player_groups table EXISTS ✓'
        ELSE 'player_groups table MISSING ✗'
    END AS table_status;

-- Check if RLS is enabled
SELECT
    relname AS table_name,
    CASE
        WHEN relrowsecurity THEN 'RLS ENABLED ✓'
        ELSE 'RLS DISABLED ✗'
    END AS rls_status
FROM pg_class
WHERE relname = 'player_groups' AND relnamespace = 'public'::regnamespace;

-- List all current policies
SELECT
    '📋 Current policies:' AS info,
    policyname,
    cmd AS command,
    CASE
        WHEN qual IS NOT NULL THEN 'Has USING clause ✓'
        ELSE 'No USING clause'
    END AS using_clause,
    CASE
        WHEN with_check IS NOT NULL THEN 'Has WITH CHECK clause ✓'
        ELSE 'No WITH CHECK clause'
    END AS check_clause
FROM pg_policies
WHERE tablename = 'player_groups' AND schemaname = 'public';

-- =====================================================
-- FIX
-- =====================================================

-- Create table if missing
CREATE TABLE IF NOT EXISTS public.player_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    group_name TEXT NOT NULL,
    player_names JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    UNIQUE(user_id, group_name)
);

-- Enable RLS
ALTER TABLE public.player_groups ENABLE ROW LEVEL SECURITY;

-- Drop all existing policies
DROP POLICY IF EXISTS "Users can view their own player groups" ON public.player_groups;
DROP POLICY IF EXISTS "Users can insert their own player groups" ON public.player_groups;
DROP POLICY IF EXISTS "Users can update their own player groups" ON public.player_groups;
DROP POLICY IF EXISTS "Users can delete their own player groups" ON public.player_groups;

-- Create policies (EXACT same pattern as custom_roles_configs)
CREATE POLICY "Users can view their own player groups"
    ON public.player_groups
    FOR SELECT
    USING (user_id = auth.uid());

CREATE POLICY "Users can insert their own player groups"
    ON public.player_groups
    FOR INSERT
    WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update their own player groups"
    ON public.player_groups
    FOR UPDATE
    USING (user_id = auth.uid());

CREATE POLICY "Users can delete their own player groups"
    ON public.player_groups
    FOR DELETE
    USING (user_id = auth.uid());

-- =====================================================
-- VERIFY FIX
-- =====================================================

-- Show final policy status
SELECT
    '✅ FINAL VERIFICATION:' AS status,
    COUNT(*) AS policy_count,
    CASE
        WHEN COUNT(*) = 4 THEN 'All 4 policies created successfully! ✓'
        ELSE 'ERROR: Expected 4 policies, found ' || COUNT(*) || ' ✗'
    END AS result
FROM pg_policies
WHERE tablename = 'player_groups' AND schemaname = 'public';

-- Show details of each policy
SELECT
    policyname AS policy_name,
    cmd AS command_type,
    SUBSTRING(qual::text, 1, 100) AS using_clause,
    SUBSTRING(with_check::text, 1, 100) AS with_check_clause
FROM pg_policies
WHERE tablename = 'player_groups' AND schemaname = 'public'
ORDER BY policyname;

-- =====================================================
-- DONE!
-- =====================================================
-- If you see "All 4 policies created successfully!" above,
-- try creating a player group in the app now.
--
-- If it still fails, the issue is likely with:
-- 1. The user_id being sent from the app
-- 2. auth.uid() returning null (not logged in)
-- 3. A type mismatch between UUIDs
-- =====================================================
