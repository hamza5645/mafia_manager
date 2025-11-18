-- =====================================================
-- REALTIME DIAGNOSTIC AND FIX SCRIPT
-- =====================================================
-- This script checks if Realtime is enabled and fixes it if not
--
-- Run this in your Supabase SQL Editor:
-- https://ptspsxqmbfvcwczjpztd.supabase.co/project/ptspsxqmbfvcwczjpztd/sql/new

-- =====================================================
-- 1. DIAGNOSTIC: Check current Realtime status
-- =====================================================

SELECT 
    cls.relname AS table_name,
    EXISTS (
        SELECT 1
        FROM pg_catalog.pg_publication_rel rel
        JOIN pg_catalog.pg_class cls2 ON cls2.oid = rel.prrelid
        WHERE rel.prpubid = (SELECT oid FROM pg_catalog.pg_publication WHERE pubname = 'supabase_realtime')
          AND cls2.relnamespace = 'public'::regnamespace
          AND cls2.relname = cls.relname
    ) AS is_realtime_enabled
FROM pg_catalog.pg_class cls
WHERE cls.relnamespace = 'public'::regnamespace
  AND cls.relname IN ('game_sessions', 'session_players', 'game_actions', 'phase_timers')
ORDER BY cls.relname;

-- =====================================================
-- 2. FIX: Enable Realtime for all multiplayer tables
-- =====================================================

-- Enable for game_sessions
DO $$
BEGIN
    -- First, try to remove if it exists (in case of stale entry)
    BEGIN
        ALTER PUBLICATION supabase_realtime DROP TABLE IF EXISTS public.game_sessions;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
    
    -- Now add it
    ALTER PUBLICATION supabase_realtime ADD TABLE public.game_sessions;
    RAISE NOTICE 'Realtime enabled for game_sessions';
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'game_sessions already in realtime publication';
WHEN OTHERS THEN
    RAISE WARNING 'Error enabling realtime for game_sessions: %', SQLERRM;
END $$;

-- Enable for session_players
DO $$
BEGIN
    BEGIN
        ALTER PUBLICATION supabase_realtime DROP TABLE IF EXISTS public.session_players;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
    
    ALTER PUBLICATION supabase_realtime ADD TABLE public.session_players;
    RAISE NOTICE 'Realtime enabled for session_players';
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'session_players already in realtime publication';
WHEN OTHERS THEN
    RAISE WARNING 'Error enabling realtime for session_players: %', SQLERRM;
END $$;

-- Enable for game_actions
DO $$
BEGIN
    BEGIN
        ALTER PUBLICATION supabase_realtime DROP TABLE IF EXISTS public.game_actions;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
    
    ALTER PUBLICATION supabase_realtime ADD TABLE public.game_actions;
    RAISE NOTICE 'Realtime enabled for game_actions';
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'game_actions already in realtime publication';
WHEN OTHERS THEN
    RAISE WARNING 'Error enabling realtime for game_actions: %', SQLERRM;
END $$;

-- Enable for phase_timers
DO $$
BEGIN
    BEGIN
        ALTER PUBLICATION supabase_realtime DROP TABLE IF EXISTS public.phase_timers;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
    
    ALTER PUBLICATION supabase_realtime ADD TABLE public.phase_timers;
    RAISE NOTICE 'Realtime enabled for phase_timers';
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'phase_timers already in realtime publication';
WHEN OTHERS THEN
    RAISE WARNING 'Error enabling realtime for phase_timers: %', SQLERRM;
END $$;

-- =====================================================
-- 3. VERIFY: Check Realtime status again
-- =====================================================

SELECT 
    cls.relname AS table_name,
    EXISTS (
        SELECT 1
        FROM pg_catalog.pg_publication_rel rel
        JOIN pg_catalog.pg_class cls2 ON cls2.oid = rel.prrelid
        WHERE rel.prpubid = (SELECT oid FROM pg_catalog.pg_publication WHERE pubname = 'supabase_realtime')
          AND cls2.relnamespace = 'public'::regnamespace
          AND cls2.relname = cls.relname
    ) AS is_realtime_enabled
FROM pg_catalog.pg_class cls
WHERE cls.relnamespace = 'public'::regnamespace
  AND cls.relname IN ('game_sessions', 'session_players', 'game_actions', 'phase_timers')
ORDER BY cls.relname;

-- =====================================================
-- EXPECTED OUTPUT:
-- =====================================================
-- All four tables should show "true" for is_realtime_enabled:
--
-- table_name        | is_realtime_enabled
-- ------------------+--------------------
-- game_actions      | true
-- game_sessions     | true
-- phase_timers      | true
-- session_players   | true
--
-- If any show "false", there may be a deeper issue with your
-- Supabase Realtime configuration.
