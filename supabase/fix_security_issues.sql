-- =====================================================
-- SECURITY FIXES: ROLE PRIVACY & ACTION HANDLING
-- =====================================================

-- 1. SECURE VIEW FOR PLAYERS (Prevents Role Leakage)
CREATE OR REPLACE VIEW public.game_session_players AS
SELECT
    sp.id,
    sp.session_id,
    sp.user_id,
    sp.player_id,
    sp.player_name,
    sp.player_number,
    -- Use the existing function to mask the role based on viewing user
    public.get_visible_role(sp.session_id, sp.player_id, auth.uid()) as role,
    sp.is_bot,
    sp.is_alive,
    sp.is_online,
    sp.is_ready,
    sp.last_heartbeat,
    sp.joined_at,
    sp.removal_note
FROM public.session_players sp;

-- Grant access to the view
GRANT SELECT ON public.game_session_players TO authenticated, anon;


-- 2. SECURE GAME ACTIONS RLS (Prevents Action/Result Leakage)
DROP POLICY IF EXISTS "Players can view actions in their session" ON public.game_actions;

CREATE POLICY "Players can view actions in their session"
ON public.game_actions
FOR SELECT
USING (
    -- 1. Host can see everything
    (EXISTS (SELECT 1 FROM public.game_sessions WHERE id = session_id AND host_user_id = auth.uid()))
    OR
    -- 2. Actor can see their own actions (linked via session_players)
    (EXISTS (
        SELECT 1 FROM public.session_players 
        WHERE session_id = game_actions.session_id 
        AND player_id = actor_player_id 
        AND user_id = auth.uid()
    ))
    OR
    -- 3. Public actions (Votes) are visible to everyone in session
    (action_type = 'vote' AND public.user_is_in_session(session_id, auth.uid()))
);


-- 3. SERVER-SIDE ACTION SUBMISSION RPC (Handles Inspector Logic Securely)
CREATE OR REPLACE FUNCTION public.submit_game_action(
    p_session_id UUID,
    p_action_type TEXT,
    p_phase_index INT,
    p_actor_player_id UUID,
    p_target_player_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_actor_role TEXT;
    v_target_role TEXT;
    v_result TEXT := NULL;
    v_action_data JSONB := NULL;
    v_existing_action_id UUID;
    v_actor_user_id UUID;
    v_host_user_id UUID;
BEGIN
    -- Get Session Host
    SELECT host_user_id INTO v_host_user_id
    FROM public.game_sessions
    WHERE id = p_session_id;

    -- Get Actor Details
    SELECT role, user_id INTO v_actor_role, v_actor_user_id
    FROM public.session_players
    WHERE session_id = p_session_id AND player_id = p_actor_player_id;

    -- Authorization Check:
    -- 1. Actor is the authenticated user
    -- 2. OR Actor is a bot (user_id is null) AND authenticated user is Host
    IF v_actor_user_id = auth.uid() THEN
        -- Authorized as self
    ELSIF v_actor_user_id IS NULL AND v_host_user_id = auth.uid() THEN
        -- Authorized as host controlling bot
    ELSE
        RAISE EXCEPTION 'Unauthorized action submission';
    END IF;

    -- Logic for Inspector
    IF p_action_type = 'inspector_check' AND v_actor_role = 'inspector' AND p_target_player_id IS NOT NULL THEN
        SELECT role INTO v_target_role
        FROM public.session_players
        WHERE session_id = p_session_id AND player_id = p_target_player_id;

        IF v_target_role = 'mafia' THEN
            v_result := 'mafia';
        ELSIF v_target_role = 'inspector' THEN
             v_result := 'blocked';
        ELSE
            v_result := 'not_mafia';
        END IF;

        v_action_data := jsonb_build_object('inspectorResult', v_result);
    END IF;

    -- Insert or Update Action
    INSERT INTO public.game_actions (session_id, action_type, phase_index, actor_player_id, target_player_id, action_data)
    VALUES (p_session_id, p_action_type, p_phase_index, p_actor_player_id, p_target_player_id, v_action_data)
    ON CONFLICT (session_id, action_type, phase_index, actor_player_id)
    DO UPDATE SET
        target_player_id = EXCLUDED.target_player_id,
        action_data = EXCLUDED.action_data,
        created_at = NOW()
    RETURNING id INTO v_existing_action_id;

    RETURN jsonb_build_object('success', true, 'action_id', v_existing_action_id, 'result', v_result);
END;
$$;

