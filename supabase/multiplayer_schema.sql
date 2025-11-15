-- =====================================================
-- MAFIA MANAGER - MULTIPLAYER DATABASE SCHEMA
-- =====================================================
-- Run this file in your Supabase SQL Editor after setup.sql
-- This adds multiplayer functionality to the existing database
--
-- IMPORTANT: This file is idempotent and can be run multiple times safely.

-- =====================================================
-- 1. CREATE MULTIPLAYER TABLES
-- =====================================================

-- Game Sessions table: Active multiplayer game rooms
CREATE TABLE IF NOT EXISTS public.game_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_code TEXT NOT NULL UNIQUE,
    host_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'waiting', -- waiting, in_progress, completed, cancelled
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,

    -- Game settings
    max_players INT DEFAULT 19 NOT NULL,
    bot_count INT DEFAULT 0 NOT NULL,
    night_timer_seconds INT DEFAULT 60 NOT NULL,
    day_timer_seconds INT DEFAULT 180 NOT NULL,

    -- Current game state (synced to all players)
    current_phase TEXT DEFAULT 'lobby', -- lobby, role_reveal, night, morning, death_reveal, voting, game_over
    current_phase_data JSONB,
    day_index INT DEFAULT 0,
    is_game_over BOOLEAN DEFAULT false,
    winner TEXT, -- mafia, citizen, or null

    -- Game data snapshots
    assigned_numbers JSONB, -- Array of {player_id, number}
    night_history JSONB DEFAULT '[]'::jsonb,
    day_history JSONB DEFAULT '[]'::jsonb,

    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Session Players table: Players in each game session
CREATE TABLE IF NOT EXISTS public.session_players (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES public.game_sessions(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL, -- null for bots
    player_id UUID NOT NULL, -- Local player UUID from game logic
    player_name TEXT NOT NULL,
    player_number INT, -- Assigned after game starts
    role TEXT, -- mafia, doctor, inspector, citizen (only visible to that player + host)
    is_bot BOOLEAN DEFAULT false,
    is_alive BOOLEAN DEFAULT true,
    is_online BOOLEAN DEFAULT true,
    is_ready BOOLEAN DEFAULT false,
    last_heartbeat TIMESTAMPTZ DEFAULT NOW(),
    joined_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    removal_note TEXT,

    -- Privacy: each player can only see their own role
    -- Mafia can see other mafia roles through a function
    UNIQUE(session_id, user_id),
    UNIQUE(session_id, player_id)
);

-- Game Actions table: All night and day actions
CREATE TABLE IF NOT EXISTS public.game_actions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES public.game_sessions(id) ON DELETE CASCADE,
    action_type TEXT NOT NULL, -- mafia_target, inspector_check, doctor_protect, vote
    phase_index INT NOT NULL, -- night_index or day_index
    actor_player_id UUID NOT NULL, -- Who performed the action
    target_player_id UUID, -- Who was targeted (null for skipped actions)
    action_data JSONB, -- Additional data (e.g., inspector result)
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,

    -- Ensure one action per player per phase
    UNIQUE(session_id, action_type, phase_index, actor_player_id)
);

-- Phase Timer table: Track phase timeouts
CREATE TABLE IF NOT EXISTS public.phase_timers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES public.game_sessions(id) ON DELETE CASCADE,
    phase_name TEXT NOT NULL,
    started_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    is_expired BOOLEAN DEFAULT false,

    UNIQUE(session_id, phase_name)
);

-- =====================================================
-- 2. CREATE INDEXES FOR PERFORMANCE
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_game_sessions_room_code ON public.game_sessions(room_code);
CREATE INDEX IF NOT EXISTS idx_game_sessions_host ON public.game_sessions(host_user_id);
CREATE INDEX IF NOT EXISTS idx_game_sessions_status ON public.game_sessions(status);

CREATE INDEX IF NOT EXISTS idx_session_players_session ON public.session_players(session_id);
CREATE INDEX IF NOT EXISTS idx_session_players_user ON public.session_players(user_id);
CREATE INDEX IF NOT EXISTS idx_session_players_online ON public.session_players(session_id, is_online);

CREATE INDEX IF NOT EXISTS idx_game_actions_session ON public.game_actions(session_id);
CREATE INDEX IF NOT EXISTS idx_game_actions_phase ON public.game_actions(session_id, phase_index, action_type);

CREATE INDEX IF NOT EXISTS idx_phase_timers_session ON public.phase_timers(session_id);

-- =====================================================
-- 3. ENABLE ROW LEVEL SECURITY
-- =====================================================

ALTER TABLE public.game_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.session_players ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.game_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.phase_timers ENABLE ROW LEVEL SECURITY;

-- =====================================================
-- 4. GAME_SESSIONS TABLE POLICIES
-- =====================================================

DROP POLICY IF EXISTS "Anyone can view active game sessions" ON public.game_sessions;
DROP POLICY IF EXISTS "Authenticated users can create game sessions" ON public.game_sessions;
DROP POLICY IF EXISTS "Host can update their own session" ON public.game_sessions;
DROP POLICY IF EXISTS "Host can delete their own session" ON public.game_sessions;

-- Allow anyone to view sessions (for joining via room code)
CREATE POLICY "Anyone can view active game sessions"
ON public.game_sessions
FOR SELECT
USING (status IN ('waiting', 'in_progress'));

-- Allow authenticated users to create sessions
CREATE POLICY "Authenticated users can create game sessions"
ON public.game_sessions
FOR INSERT
WITH CHECK (auth.uid() = host_user_id);

-- Allow host to update their session
CREATE POLICY "Host can update their own session"
ON public.game_sessions
FOR UPDATE
USING (auth.uid() = host_user_id);

-- Allow host to delete their session
CREATE POLICY "Host can delete their own session"
ON public.game_sessions
FOR DELETE
USING (auth.uid() = host_user_id);

-- =====================================================
-- 5. SESSION_PLAYERS TABLE POLICIES
-- =====================================================

DROP POLICY IF EXISTS "Players can view players in their session" ON public.session_players;
DROP POLICY IF EXISTS "Users can join a session" ON public.session_players;
DROP POLICY IF EXISTS "Users can update their own player status" ON public.session_players;
DROP POLICY IF EXISTS "Users can leave a session" ON public.session_players;
DROP POLICY IF EXISTS "Host can manage all players in their session" ON public.session_players;

-- Allow players to view all players in their session (but roles are filtered by function)
CREATE POLICY "Players can view players in their session"
ON public.session_players
FOR SELECT
USING (
    session_id IN (
        SELECT session_id FROM public.session_players WHERE user_id = auth.uid()
    )
);

-- Allow users to join a session
CREATE POLICY "Users can join a session"
ON public.session_players
FOR INSERT
WITH CHECK (
    auth.uid() = user_id AND
    (SELECT status FROM public.game_sessions WHERE id = session_id) = 'waiting'
);

-- Allow users to update their own player status (ready, heartbeat)
CREATE POLICY "Users can update their own player status"
ON public.session_players
FOR UPDATE
USING (auth.uid() = user_id);

-- Allow users to leave a session
CREATE POLICY "Users can leave a session"
ON public.session_players
FOR DELETE
USING (auth.uid() = user_id);

-- Allow host to manage all players (for bots, kicking, etc.)
CREATE POLICY "Host can manage all players in their session"
ON public.session_players
FOR ALL
USING (
    session_id IN (
        SELECT id FROM public.game_sessions WHERE host_user_id = auth.uid()
    )
);

-- =====================================================
-- 6. GAME_ACTIONS TABLE POLICIES
-- =====================================================

DROP POLICY IF EXISTS "Players can view actions in their session" ON public.game_actions;
DROP POLICY IF EXISTS "Players can create their own actions" ON public.game_actions;
DROP POLICY IF EXISTS "Players can update their own actions" ON public.game_actions;

-- Allow players to view actions (with privacy filters applied)
CREATE POLICY "Players can view actions in their session"
ON public.game_actions
FOR SELECT
USING (
    session_id IN (
        SELECT session_id FROM public.session_players WHERE user_id = auth.uid()
    )
);

-- Allow players to create their own actions
CREATE POLICY "Players can create their own actions"
ON public.game_actions
FOR INSERT
WITH CHECK (
    session_id IN (
        SELECT session_id FROM public.session_players WHERE user_id = auth.uid() AND player_id = actor_player_id
    )
);

-- Allow players to update their own actions (within same phase)
CREATE POLICY "Players can update their own actions"
ON public.game_actions
FOR UPDATE
USING (
    session_id IN (
        SELECT session_id FROM public.session_players WHERE user_id = auth.uid() AND player_id = actor_player_id
    )
);

-- =====================================================
-- 7. PHASE_TIMERS TABLE POLICIES
-- =====================================================

DROP POLICY IF EXISTS "Players can view timers in their session" ON public.phase_timers;
DROP POLICY IF EXISTS "Host can manage timers" ON public.phase_timers;

-- Allow players to view timers
CREATE POLICY "Players can view timers in their session"
ON public.phase_timers
FOR SELECT
USING (
    session_id IN (
        SELECT session_id FROM public.session_players WHERE user_id = auth.uid()
    )
);

-- Allow host to manage timers
CREATE POLICY "Host can manage timers"
ON public.phase_timers
FOR ALL
USING (
    session_id IN (
        SELECT id FROM public.game_sessions WHERE host_user_id = auth.uid()
    )
);

-- =====================================================
-- 8. HELPER FUNCTIONS
-- =====================================================

-- Generate unique 6-character room code
CREATE OR REPLACE FUNCTION public.generate_room_code()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- Exclude ambiguous chars
    result TEXT := '';
    i INT;
    code_exists BOOLEAN;
BEGIN
    LOOP
        result := '';
        FOR i IN 1..6 LOOP
            result := result || substr(chars, floor(random() * length(chars) + 1)::int, 1);
        END LOOP;

        -- Check if code already exists
        SELECT EXISTS(SELECT 1 FROM public.game_sessions WHERE room_code = result) INTO code_exists;

        -- If code is unique, return it
        IF NOT code_exists THEN
            RETURN result;
        END IF;
    END LOOP;
END;
$$;

-- Get visible role for a player (privacy filter)
-- Players can see their own role, mafia can see other mafia, everyone else sees null
CREATE OR REPLACE FUNCTION public.get_visible_role(
    p_session_id UUID,
    p_player_id UUID,
    p_viewing_user_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    player_role TEXT;
    viewer_role TEXT;
    player_user_id UUID;
BEGIN
    -- Get the player's actual role and user_id
    SELECT role, user_id INTO player_role, player_user_id
    FROM public.session_players
    WHERE session_id = p_session_id AND player_id = p_player_id;

    -- If viewing own role, return it
    IF player_user_id = p_viewing_user_id THEN
        RETURN player_role;
    END IF;

    -- Get viewer's role
    SELECT role INTO viewer_role
    FROM public.session_players
    WHERE session_id = p_session_id AND user_id = p_viewing_user_id;

    -- If both are mafia, show the role
    IF viewer_role = 'mafia' AND player_role = 'mafia' THEN
        RETURN player_role;
    END IF;

    -- If viewer is host, show the role (for debugging/admin)
    IF EXISTS(
        SELECT 1 FROM public.game_sessions
        WHERE id = p_session_id AND host_user_id = p_viewing_user_id
    ) THEN
        RETURN player_role;
    END IF;

    -- Otherwise, hide the role
    RETURN NULL;
END;
$$;

-- Check if all players in a role have submitted their action
CREATE OR REPLACE FUNCTION public.all_role_actions_submitted(
    p_session_id UUID,
    p_role TEXT,
    p_phase_index INT,
    p_action_type TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    total_alive_role INT;
    submitted_actions INT;
BEGIN
    -- Count alive players with this role
    SELECT COUNT(*) INTO total_alive_role
    FROM public.session_players
    WHERE session_id = p_session_id
        AND role = p_role
        AND is_alive = true;

    -- If no players with this role, return true (skip)
    IF total_alive_role = 0 THEN
        RETURN true;
    END IF;

    -- Count submitted actions
    SELECT COUNT(DISTINCT actor_player_id) INTO submitted_actions
    FROM public.game_actions
    WHERE session_id = p_session_id
        AND action_type = p_action_type
        AND phase_index = p_phase_index;

    -- Return true if all have submitted
    RETURN submitted_actions >= total_alive_role;
END;
$$;

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

-- Create triggers for auto-updating updated_at
DROP TRIGGER IF EXISTS update_game_sessions_updated_at ON public.game_sessions;
CREATE TRIGGER update_game_sessions_updated_at
    BEFORE UPDATE ON public.game_sessions
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

-- =====================================================
-- 9. REALTIME CONFIGURATION
-- =====================================================

-- Enable Realtime for multiplayer tables
-- Note: This needs to be enabled in Supabase Dashboard > Database > Replication
-- Or via SQL:
ALTER PUBLICATION supabase_realtime ADD TABLE public.game_sessions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.session_players;
ALTER PUBLICATION supabase_realtime ADD TABLE public.game_actions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.phase_timers;

-- =====================================================
-- SETUP COMPLETE!
-- =====================================================
-- Multiplayer database is now ready!
--
-- Next steps:
-- 1. Enable Realtime in Supabase Dashboard if not already enabled
-- 2. Implement Swift services to interact with these tables
-- 3. Build the multiplayer UI
