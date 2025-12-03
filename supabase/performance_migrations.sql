-- =====================================================
-- MAFIA MANAGER - PERFORMANCE OPTIMIZATION MIGRATIONS
-- =====================================================
-- Run this file in your Supabase SQL Editor
-- Adds RPC functions for batch operations
--
-- IMPORTANT: This file is idempotent and can be run multiple times safely.

-- =====================================================
-- 1. BATCH ROLE ASSIGNMENT RPC
-- =====================================================
-- Assigns roles and numbers to all players in a single database transaction
-- Reduces N sequential HTTP requests to 1 RPC call

CREATE OR REPLACE FUNCTION batch_assign_roles(
    p_session_id UUID,
    p_assignments JSONB -- Array of {player_id, role, number}
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    assignment JSONB;
    player_uuid UUID;
    player_role TEXT;
    player_number INT;
BEGIN
    -- Validate session exists
    IF NOT EXISTS (SELECT 1 FROM public.game_sessions WHERE id = p_session_id) THEN
        RAISE EXCEPTION 'Session not found: %', p_session_id;
    END IF;

    -- Process each assignment in a single transaction
    FOR assignment IN SELECT * FROM jsonb_array_elements(p_assignments)
    LOOP
        player_uuid := (assignment->>'player_id')::UUID;
        player_role := assignment->>'role';
        player_number := (assignment->>'number')::INT;

        UPDATE public.session_players
        SET role = player_role,
            player_number = player_number,
            updated_at = NOW()
        WHERE session_id = p_session_id
          AND player_id = player_uuid;

        IF NOT FOUND THEN
            RAISE WARNING 'Player not found in session: %', player_uuid;
        END IF;
    END LOOP;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION batch_assign_roles(UUID, JSONB) TO authenticated;

-- =====================================================
-- 2. BATCH FETCH ACTIONS BY TYPES RPC
-- =====================================================
-- Fetches all actions of specified types in a single query
-- Replaces 3 separate queries for mafia/inspector/doctor actions

CREATE OR REPLACE FUNCTION fetch_actions_by_types(
    p_session_id UUID,
    p_round_id UUID,
    p_action_types TEXT[] -- Array of action types
)
RETURNS TABLE (
    id UUID,
    session_id UUID,
    round_id UUID,
    actor_player_id UUID,
    action_type TEXT,
    target_player_id UUID,
    phase_index INT,
    created_at TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT
        id,
        session_id,
        round_id,
        actor_player_id,
        action_type,
        target_player_id,
        phase_index,
        created_at
    FROM public.game_actions
    WHERE session_id = p_session_id
      AND round_id = p_round_id
      AND action_type = ANY(p_action_types);
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION fetch_actions_by_types(UUID, UUID, TEXT[]) TO authenticated;

-- =====================================================
-- 3. PERFORMANCE INDEXES
-- =====================================================
-- Add indexes for common query patterns if they don't exist

-- Index for fetching actions by session, round, and type
CREATE INDEX IF NOT EXISTS idx_game_actions_session_round_type
ON public.game_actions(session_id, round_id, action_type);

-- Index for fetching players by session
CREATE INDEX IF NOT EXISTS idx_session_players_session_id
ON public.session_players(session_id);

-- =====================================================
-- USAGE EXAMPLES
-- =====================================================
--
-- Batch assign roles (Swift):
--   try await supabase.rpc("batch_assign_roles", params: [
--       "p_session_id": sessionId.uuidString,
--       "p_assignments": assignments.map { ["player_id": $0.playerId, "role": $0.role, "number": $0.number] }
--   ]).execute()
--
-- Fetch actions by types (Swift):
--   try await supabase.rpc("fetch_actions_by_types", params: [
--       "p_session_id": sessionId.uuidString,
--       "p_round_id": roundId.uuidString,
--       "p_action_types": ["mafia_target", "police_investigate", "doctor_protect"]
--   ]).execute()
