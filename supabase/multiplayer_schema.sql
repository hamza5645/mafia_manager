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

    -- Round ID for action isolation (prevents action replay across rounds)
    current_round_id UUID DEFAULT gen_random_uuid(),

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
    round_id UUID NOT NULL, -- Links to game_sessions.current_round_id for action isolation
    action_type TEXT NOT NULL, -- mafia_target, inspector_check, doctor_protect, vote
    phase_index INT NOT NULL, -- night_index or day_index
    actor_player_id UUID NOT NULL, -- Who performed the action
    target_player_id UUID, -- Who was targeted (null for skipped actions)
    action_data JSONB, -- Additional data (e.g., inspector result)
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,

    -- Ensure one action per player per round+phase
    UNIQUE(session_id, round_id, action_type, phase_index, actor_player_id)
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
CREATE INDEX IF NOT EXISTS idx_game_actions_round ON public.game_actions(session_id, round_id, phase_index);

-- =====================================================
-- 3. ENABLE ROW LEVEL SECURITY
-- =====================================================

ALTER TABLE public.game_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.session_players ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.game_actions ENABLE ROW LEVEL SECURITY;

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

-- Helper needed by session_players policies (must be defined before those policies run)
CREATE OR REPLACE FUNCTION public.session_is_joinable(p_session_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE((
        SELECT status = 'waiting'
        FROM public.game_sessions
        WHERE id = p_session_id
    ), false);
$$;

-- Helper to check if user is in a session (bypasses RLS to avoid infinite recursion)
CREATE OR REPLACE FUNCTION public.user_is_in_session(p_session_id UUID, p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS(
        SELECT 1
        FROM public.session_players
        WHERE session_id = p_session_id AND user_id = p_user_id
    );
$$;

-- Helper to check if user is in a session with a specific player_id (bypasses RLS to avoid infinite recursion)
CREATE OR REPLACE FUNCTION public.user_is_player_in_session(p_session_id UUID, p_user_id UUID, p_player_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS(
        SELECT 1
        FROM public.session_players
        WHERE session_id = p_session_id 
        AND user_id = p_user_id
        AND player_id = p_player_id
    );
$$;

-- =====================================================
-- 5. SESSION_PLAYERS TABLE POLICIES
-- =====================================================

DROP POLICY IF EXISTS "Players can view players in their session" ON public.session_players;
DROP POLICY IF EXISTS "Users can join a session" ON public.session_players;
DROP POLICY IF EXISTS "Users can update their own player status" ON public.session_players;
DROP POLICY IF EXISTS "Users can leave a session" ON public.session_players;
DROP POLICY IF EXISTS "Host can manage all players in their session" ON public.session_players;

-- Allow players to view all players in their session (but roles are filtered by function)
-- Uses SECURITY DEFINER function to avoid infinite recursion
CREATE POLICY "Players can view players in their session"
ON public.session_players
FOR SELECT
USING (
    -- Use SECURITY DEFINER function to avoid recursion
    public.user_is_in_session(session_id, auth.uid())
    OR
    -- OR if you're the host of the session
    session_id IN (
        SELECT id FROM public.game_sessions WHERE host_user_id = auth.uid()
    )
);

-- Allow users to join a session
-- This needs to work for BOTH host creating and non-host joining
CREATE POLICY "Users can join a session"
ON public.session_players
FOR INSERT
WITH CHECK (
    -- Either you're inserting yourself (authenticated user)
    (auth.uid() = user_id)
    OR
    -- OR you're the host inserting a bot (user_id IS NULL)
    (user_id IS NULL AND session_id IN (
        SELECT id FROM public.game_sessions WHERE host_user_id = auth.uid()
    ))
);

-- Allow users to update their own player status (ready, heartbeat)
CREATE POLICY "Users can update their own player status"
ON public.session_players
FOR UPDATE
USING (
    auth.uid() = user_id
    OR
    -- Host can update any player in their session
    session_id IN (
        SELECT id FROM public.game_sessions WHERE host_user_id = auth.uid()
    )
);

-- Allow users to leave a session
CREATE POLICY "Users can leave a session"
ON public.session_players
FOR DELETE
USING (
    auth.uid() = user_id
    OR
    -- Host can remove any player from their session
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
-- Uses SECURITY DEFINER function to avoid infinite recursion
CREATE POLICY "Players can view actions in their session"
ON public.game_actions
FOR SELECT
USING (
    public.user_is_in_session(session_id, auth.uid())
);

-- Allow players to create their own actions
-- Uses SECURITY DEFINER function to avoid infinite recursion
CREATE POLICY "Players can create their own actions"
ON public.game_actions
FOR INSERT
WITH CHECK (
    public.user_is_player_in_session(session_id, auth.uid(), actor_player_id)
);

-- Allow players to update their own actions (within same phase)
-- Uses SECURITY DEFINER function to avoid infinite recursion
CREATE POLICY "Players can update their own actions"
ON public.game_actions
FOR UPDATE
USING (
    public.user_is_player_in_session(session_id, auth.uid(), actor_player_id)
);

-- =====================================================
-- 7. HELPER FUNCTIONS
-- =====================================================

-- Generate unique 6-character room code
CREATE OR REPLACE FUNCTION public.generate_room_code()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

-- Submit game action RPC (handles action insertion with round_id)
CREATE OR REPLACE FUNCTION public.submit_game_action(
    p_session_id UUID,
    p_round_id UUID,
    p_action_type TEXT,
    p_phase_index INT,
    p_actor_player_id UUID,
    p_target_player_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result TEXT;
BEGIN
    -- Insert or update the action
    INSERT INTO public.game_actions (
        session_id,
        round_id,
        action_type,
        phase_index,
        actor_player_id,
        target_player_id
    ) VALUES (
        p_session_id,
        p_round_id,
        p_action_type,
        p_phase_index,
        p_actor_player_id,
        p_target_player_id
    )
    ON CONFLICT (session_id, round_id, action_type, phase_index, actor_player_id)
    DO UPDATE SET
        target_player_id = EXCLUDED.target_player_id,
        created_at = NOW();

    -- For inspector checks, determine the result
    IF p_action_type = 'inspector_check' AND p_target_player_id IS NOT NULL THEN
        SELECT role INTO v_result
        FROM public.session_players
        WHERE session_id = p_session_id
          AND player_id = p_target_player_id;

        IF v_result = 'mafia' THEN
            RETURN json_build_object('success', true, 'result', 'mafia');
        ELSE
            RETURN json_build_object('success', true, 'result', 'not_mafia');
        END IF;
    END IF;

    RETURN json_build_object('success', true);
END;
$$;

-- Atomic night resolution function (prevents race conditions)
-- Applies player eliminations AND updates night_history in a single transaction
CREATE OR REPLACE FUNCTION public.resolve_night_atomic(
    p_session_id UUID,
    p_night_record JSONB,
    p_eliminated_player_ids UUID[],
    p_next_phase TEXT,
    p_next_phase_data JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_night_index INT;
    v_night_history JSONB;
    v_updated_history JSONB;
BEGIN
    -- Extract night_index from the record
    v_night_index := (p_night_record->>'nightIndex')::INT;

    -- Get current night_history
    SELECT night_history INTO v_night_history
    FROM public.game_sessions
    WHERE id = p_session_id;

    -- Remove any existing record for this night_index (prevent duplicates)
    v_updated_history := (
        SELECT jsonb_agg(elem)
        FROM jsonb_array_elements(v_night_history) elem
        WHERE (elem->>'nightIndex')::INT != v_night_index
    );

    -- If all records were removed, initialize empty array
    IF v_updated_history IS NULL THEN
        v_updated_history := '[]'::jsonb;
    END IF;

    -- Append the new night record
    v_updated_history := v_updated_history || p_night_record;

    -- Update players (set is_alive = false) in one statement
    UPDATE public.session_players
    SET is_alive = false,
        removal_note = 'Eliminated at night ' || v_night_index
    WHERE session_id = p_session_id
      AND player_id = ANY(p_eliminated_player_ids);

    -- Update session state (night_history + phase transition) in one statement
    UPDATE public.game_sessions
    SET night_history = v_updated_history,
        current_phase = p_next_phase,
        current_phase_data = p_next_phase_data,
        updated_at = NOW()
    WHERE id = p_session_id;

    RETURN TRUE;
END;
$$;

-- =====================================================
-- 7b. SECURE VIEWS FOR ROLE VISIBILITY
-- =====================================================

-- View that applies role visibility rules using get_visible_role function
-- CRITICAL: Always use this view (not session_players directly) when fetching players
-- to ensure proper role privacy:
-- - Host sees all roles
-- - Players see their own role
-- - Mafia see other mafia roles
-- - Everyone else sees null for other players' roles
CREATE OR REPLACE VIEW public.game_session_players AS
SELECT
    id,
    session_id,
    user_id,
    player_id,
    player_name,
    player_number,
    get_visible_role(session_id, player_id, auth.uid()) AS role,
    is_bot,
    is_alive,
    is_online,
    is_ready,
    last_heartbeat,
    joined_at,
    removal_note
FROM session_players sp;

-- Grant access to the view
GRANT SELECT ON public.game_session_players TO authenticated;

-- =====================================================
-- 8. REALTIME CONFIGURATION
-- =====================================================

-- Enable Realtime for multiplayer tables (idempotent - only adds missing entries)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_publication_rel rel
        JOIN pg_catalog.pg_class cls ON cls.oid = rel.prrelid
        WHERE rel.prpubid = (SELECT oid FROM pg_catalog.pg_publication WHERE pubname = 'supabase_realtime')
          AND cls.relnamespace = 'public'::regnamespace
          AND cls.relname = 'game_sessions'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.game_sessions;
    END IF;
EXCEPTION WHEN duplicate_object THEN
    NULL;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_publication_rel rel
        JOIN pg_catalog.pg_class cls ON cls.oid = rel.prrelid
        WHERE rel.prpubid = (SELECT oid FROM pg_catalog.pg_publication WHERE pubname = 'supabase_realtime')
          AND cls.relnamespace = 'public'::regnamespace
          AND cls.relname = 'session_players'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.session_players;
    END IF;
EXCEPTION WHEN duplicate_object THEN
    NULL;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_publication_rel rel
        JOIN pg_catalog.pg_class cls ON cls.oid = rel.prrelid
        WHERE rel.prpubid = (SELECT oid FROM pg_catalog.pg_publication WHERE pubname = 'supabase_realtime')
          AND cls.relnamespace = 'public'::regnamespace
          AND cls.relname = 'game_actions'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.game_actions;
    END IF;
EXCEPTION WHEN duplicate_object THEN
    NULL;
END $$;

-- =====================================================
-- 9. HOST TRANSFER ON LEAVE
-- =====================================================

-- Function to transfer host when current host leaves
CREATE OR REPLACE FUNCTION public.transfer_host_on_leave()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    new_host_user_id UUID;
BEGIN
    -- Check if deleted player was the host
    IF OLD.user_id = (SELECT host_user_id FROM public.game_sessions WHERE id = OLD.session_id) THEN
        -- Find the oldest remaining player (by joined_at) to become new host
        SELECT user_id INTO new_host_user_id
        FROM public.session_players
        WHERE session_id = OLD.session_id
        AND user_id IS NOT NULL -- Must be a real user, not a bot
        ORDER BY joined_at ASC
        LIMIT 1;

        -- If we found a new host, transfer ownership
        IF new_host_user_id IS NOT NULL THEN
            UPDATE public.game_sessions
            SET host_user_id = new_host_user_id
            WHERE id = OLD.session_id;

            RAISE NOTICE 'Host transferred to user % in session %', new_host_user_id, OLD.session_id;
        ELSE
            -- No remaining human players, session should probably be deleted
            -- But we'll let it remain for now (host cleanup can be handled separately)
            RAISE NOTICE 'No remaining players to transfer host in session %', OLD.session_id;
        END IF;
    END IF;

    RETURN OLD;
END;
$$;

-- Trigger that fires after a player leaves
DROP TRIGGER IF EXISTS on_player_leave_transfer_host ON public.session_players;

CREATE TRIGGER on_player_leave_transfer_host
    AFTER DELETE ON public.session_players
    FOR EACH ROW
    EXECUTE FUNCTION public.transfer_host_on_leave();

-- =====================================================
-- SETUP COMPLETE!
-- =====================================================
-- Multiplayer database is now ready!
--
-- Next steps:
-- 1. Enable Realtime in Supabase Dashboard if not already enabled
-- 2. Implement Swift services to interact with these tables
-- 3. Build the multiplayer UI
