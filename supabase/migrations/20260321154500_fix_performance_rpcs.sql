-- Repair optional performance RPCs so the fast paths match the current app code.

CREATE OR REPLACE FUNCTION public.batch_assign_roles(
    p_session_id UUID,
    p_assignments JSONB
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    assignment JSONB;
    player_uuid UUID;
    player_role TEXT;
    player_number INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.game_sessions WHERE id = p_session_id) THEN
        RAISE EXCEPTION 'Session not found: %', p_session_id;
    END IF;

    FOR assignment IN SELECT * FROM jsonb_array_elements(p_assignments)
    LOOP
        player_uuid := (assignment->>'player_id')::UUID;
        player_role := assignment->>'role';
        player_number := (assignment->>'number')::INT;

        UPDATE public.session_players
        SET role = player_role,
            player_number = player_number
        WHERE session_id = p_session_id
          AND player_id = player_uuid;

        IF NOT FOUND THEN
            RAISE WARNING 'Player not found in session: %', player_uuid;
        END IF;
    END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.batch_assign_roles(UUID, JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.fetch_actions_by_types(
    p_session_id UUID,
    p_round_id UUID,
    p_action_types TEXT[]
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
SET search_path = public
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

GRANT EXECUTE ON FUNCTION public.fetch_actions_by_types(UUID, UUID, TEXT[]) TO authenticated;
