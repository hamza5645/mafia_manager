-- =====================================================
-- TEST AUTH.UID() FUNCTION
-- =====================================================
-- Run this while logged into the app to see if auth.uid()
-- returns your user ID correctly

-- This should show your current user_id if you're authenticated
SELECT
    auth.uid() AS current_user_id,
    CASE
        WHEN auth.uid() IS NULL THEN '❌ NOT LOGGED IN - auth.uid() is NULL'
        ELSE '✅ LOGGED IN - auth.uid() = ' || auth.uid()::text
    END AS auth_status;

-- Check if your user exists in auth.users
SELECT
    id AS user_id,
    email,
    created_at,
    CASE
        WHEN id = auth.uid() THEN '✅ This is YOU (matches auth.uid())'
        ELSE 'This is another user'
    END AS match_status
FROM auth.users
ORDER BY created_at DESC
LIMIT 5;

-- Test if you can see custom_roles_configs (which works)
SELECT
    'Testing custom_roles_configs RLS:' AS test,
    COUNT(*) AS your_configs_count
FROM public.custom_roles_configs
WHERE user_id = auth.uid();

-- Test if you can see player_groups
SELECT
    'Testing player_groups RLS:' AS test,
    COUNT(*) AS your_groups_count
FROM public.player_groups
WHERE user_id = auth.uid();

-- Show ALL player_groups (bypassing RLS - only works for admins)
-- If this fails with permission denied, that's expected
SELECT
    'All player_groups (admin view):' AS test,
    id,
    user_id,
    group_name,
    CASE
        WHEN user_id = auth.uid() THEN '✅ YOURS'
        ELSE 'Other user'
    END AS ownership
FROM public.player_groups
LIMIT 10;
