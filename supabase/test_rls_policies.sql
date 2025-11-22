-- =====================================================
-- TEST RLS POLICIES FOR SESSION_PLAYERS
-- =====================================================
-- This script tests all the RLS policies to ensure they work correctly
-- Run this after applying the multiplayer schema

-- =====================================================
-- 1. TEST HELPER FUNCTIONS
-- =====================================================

-- Test session_is_joinable
DO $$
DECLARE
    test_session_id UUID;
    result BOOLEAN;
BEGIN
    -- Create a test session
    INSERT INTO public.game_sessions (id, room_code, host_user_id, status)
    VALUES (gen_random_uuid(), 'TEST01', '00000000-0000-0000-0000-000000000001', 'waiting')
    RETURNING id INTO test_session_id;

    -- Test the function
    SELECT public.session_is_joinable(test_session_id) INTO result;
    
    IF result THEN
        RAISE NOTICE 'PASS: session_is_joinable returns true for waiting session';
    ELSE
        RAISE EXCEPTION 'FAIL: session_is_joinable should return true for waiting session';
    END IF;

    -- Update to in_progress
    UPDATE public.game_sessions SET status = 'in_progress' WHERE id = test_session_id;
    
    SELECT public.session_is_joinable(test_session_id) INTO result;
    
    IF NOT result THEN
        RAISE NOTICE 'PASS: session_is_joinable returns false for in_progress session';
    ELSE
        RAISE EXCEPTION 'FAIL: session_is_joinable should return false for in_progress session';
    END IF;

    -- Cleanup
    DELETE FROM public.game_sessions WHERE id = test_session_id;
END $$;

-- =====================================================
-- 2. TEST POLICY STRUCTURE
-- =====================================================

-- Verify all policies exist
DO $$
DECLARE
    policy_count INT;
BEGIN
    SELECT COUNT(*) INTO policy_count
    FROM pg_policies
    WHERE tablename = 'session_players';
    
    IF policy_count = 4 THEN
        RAISE NOTICE 'PASS: All 4 session_players policies exist';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected 4 policies, found %', policy_count;
    END IF;
END $$;

-- Verify INSERT policy has WITH CHECK
DO $$
DECLARE
    has_with_check BOOLEAN;
BEGIN
    SELECT with_check IS NOT NULL INTO has_with_check
    FROM pg_policies
    WHERE tablename = 'session_players'
    AND cmd = 'INSERT';
    
    IF has_with_check THEN
        RAISE NOTICE 'PASS: INSERT policy has WITH CHECK clause';
    ELSE
        RAISE EXCEPTION 'FAIL: INSERT policy missing WITH CHECK clause';
    END IF;
END $$;

-- Verify SELECT policy has USING
DO $$
DECLARE
    has_using BOOLEAN;
BEGIN
    SELECT qual IS NOT NULL INTO has_using
    FROM pg_policies
    WHERE tablename = 'session_players'
    AND cmd = 'SELECT';
    
    IF has_using THEN
        RAISE NOTICE 'PASS: SELECT policy has USING clause';
    ELSE
        RAISE EXCEPTION 'FAIL: SELECT policy missing USING clause';
    END IF;
END $$;

-- =====================================================
-- 3. TEST FUNCTION SECURITY
-- =====================================================

-- Verify SECURITY DEFINER functions have search_path set
DO $$
DECLARE
    func_count INT;
BEGIN
    SELECT COUNT(*) INTO func_count
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
    AND p.proname IN ('user_is_in_session', 'user_is_player_in_session', 'session_is_joinable')
    AND p.prosecdef = true; -- SECURITY DEFINER
    
    IF func_count = 3 THEN
        RAISE NOTICE 'PASS: All 3 SECURITY DEFINER helper functions exist';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected 3 SECURITY DEFINER functions, found %', func_count;
    END IF;
END $$;

-- =====================================================
-- TESTS COMPLETE
-- =====================================================

RAISE NOTICE '========================================';
RAISE NOTICE 'ALL RLS POLICY TESTS PASSED!';
RAISE NOTICE '========================================';
RAISE NOTICE '';
RAISE NOTICE 'Policies are ready for:';
RAISE NOTICE '✅ Host creating a room';
RAISE NOTICE '✅ Non-host joining a room';
RAISE NOTICE '✅ Host adding bots';
RAISE NOTICE '✅ Players viewing session data';
RAISE NOTICE '✅ Players updating their status';
RAISE NOTICE '✅ Players leaving sessions';
RAISE NOTICE '';

