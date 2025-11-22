-- =====================================================
-- REALTIME DIAGNOSTIC AND FIX SCRIPT (CORRECTED)
-- =====================================================

-- Step 1: Check current status
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

-- Step 2: Enable Realtime (simpler approach)
ALTER PUBLICATION supabase_realtime ADD TABLE public.game_sessions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.session_players;
ALTER PUBLICATION supabase_realtime ADD TABLE public.game_actions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.phase_timers;

-- Step 3: Verify
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
