-- Run this in Supabase SQL Editor to diagnose email issues

-- 1. Check if the email exists in auth.users
SELECT
    id,
    email,
    email_confirmed_at,
    created_at,
    last_sign_in_at,
    raw_user_meta_data->>'display_name' as display_name
FROM auth.users
WHERE email = 'hamza@gmail.com';

-- 2. Check if there's a corresponding profile
SELECT
    id,
    display_name,
    created_at
FROM public.profiles
WHERE id IN (
    SELECT id FROM auth.users WHERE email = 'hamza@gmail.com'
);

-- 3. Check authentication settings
-- Run these in separate queries to see current configuration:

-- Check if email confirmation is required
-- Go to: Authentication → Settings → Email Auth
-- Look for "Confirm email" setting

-- 4. List ALL users to see what's in the database
SELECT
    id,
    email,
    email_confirmed_at,
    created_at,
    raw_user_meta_data->>'display_name' as display_name
FROM auth.users
ORDER BY created_at DESC
LIMIT 20;

-- 5. Check for any email domain restrictions
-- Go to: Authentication → Settings
-- Look for "Allowed email domains" or similar settings
