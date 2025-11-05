-- Run this query in Supabase SQL Editor to see all existing RLS policies
-- This will help us understand what's currently configured

-- 1. Check if RLS is enabled on the profiles table
SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public' AND tablename = 'profiles';

-- 2. View all existing policies on the profiles table
SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'profiles';

-- 3. Check the profiles table structure
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'profiles'
ORDER BY ordinal_position;
