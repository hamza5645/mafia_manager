-- Fix multiplayer RPC/schema drift that was identified in the March 2026 audit.
-- This migration is safe to run multiple times.

CREATE OR REPLACE FUNCTION public.add_session_player(
    p_session_id UUID,
    p_user_id UUID,
    p_player_id UUID,
    p_player_name TEXT,
    p_is_bot BOOLEAN DEFAULT false
)
RETURNS SETOF public.session_players
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_session public.game_sessions%ROWTYPE;
    v_inserted public.session_players%ROWTYPE;
    v_player_count INT;
BEGIN
    SELECT * INTO v_session
    FROM public.game_sessions
    WHERE id = p_session_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Session not found: %', p_session_id;
    END IF;

    IF v_session.status <> 'waiting' OR v_session.current_phase <> 'lobby' THEN
        RAISE EXCEPTION 'Session is not joinable: %', p_session_id;
    END IF;

    SELECT COUNT(*) INTO v_player_count
    FROM public.session_players
    WHERE session_id = p_session_id;

    IF v_player_count >= v_session.max_players THEN
        RAISE EXCEPTION 'Session is full: %', p_session_id;
    END IF;

    IF p_is_bot THEN
        IF auth.uid() IS DISTINCT FROM v_session.host_user_id THEN
            RAISE EXCEPTION 'Only the host can add bots to session %', p_session_id;
        END IF;

        IF p_user_id IS NOT NULL THEN
            RAISE EXCEPTION 'Bots must not provide a user_id';
        END IF;
    ELSE
        IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id THEN
            RAISE EXCEPTION 'Authenticated user mismatch while joining session %', p_session_id;
        END IF;

        IF EXISTS (
            SELECT 1
            FROM public.session_players
            WHERE session_id = p_session_id
              AND user_id = p_user_id
        ) THEN
            RAISE EXCEPTION 'User % is already in session %', p_user_id, p_session_id;
        END IF;
    END IF;

    INSERT INTO public.session_players (
        session_id,
        user_id,
        player_id,
        player_name,
        is_bot,
        is_alive,
        is_online,
        is_ready
    ) VALUES (
        p_session_id,
        p_user_id,
        p_player_id,
        p_player_name,
        p_is_bot,
        true,
        NOT p_is_bot,
        true
    )
    RETURNING * INTO v_inserted;

    RETURN QUERY
    SELECT *
    FROM public.session_players
    WHERE id = v_inserted.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.add_session_player(UUID, UUID, UUID, TEXT, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.reset_players_ready(p_session_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.session_players
    SET is_ready = false
    WHERE session_id = p_session_id
      AND is_bot = false;
END;
$$;

GRANT EXECUTE ON FUNCTION public.reset_players_ready(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_visible_role(
    p_session_id UUID,
    p_player_id UUID,
    p_viewing_user_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    player_role TEXT;
    viewer_role TEXT;
    player_user_id UUID;
    session_phase TEXT;
    session_is_game_over BOOLEAN;
BEGIN
    SELECT role, user_id INTO player_role, player_user_id
    FROM public.session_players
    WHERE session_id = p_session_id AND player_id = p_player_id;

    IF player_user_id = p_viewing_user_id THEN
        RETURN player_role;
    END IF;

    SELECT current_phase, is_game_over
    INTO session_phase, session_is_game_over
    FROM public.game_sessions
    WHERE id = p_session_id;

    IF session_phase = 'game_over' OR COALESCE(session_is_game_over, false) THEN
        RETURN player_role;
    END IF;

    SELECT role INTO viewer_role
    FROM public.session_players
    WHERE session_id = p_session_id AND user_id = p_viewing_user_id;

    IF viewer_role = 'mafia' AND player_role = 'mafia' THEN
        RETURN player_role;
    END IF;

    IF EXISTS(
        SELECT 1 FROM public.game_sessions
        WHERE id = p_session_id AND host_user_id = p_viewing_user_id
    ) THEN
        RETURN player_role;
    END IF;

    RETURN NULL;
END;
$$;

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

    IF p_action_type = 'inspector_check' AND p_target_player_id IS NOT NULL THEN
        SELECT role INTO v_result
        FROM public.session_players
        WHERE session_id = p_session_id
          AND player_id = p_target_player_id;

        IF v_result = 'mafia' THEN
            RETURN json_build_object('success', true, 'result', 'mafia');
        ELSIF v_result = 'inspector' THEN
            RETURN json_build_object('success', true, 'result', 'blocked');
        ELSIF v_result IS NOT NULL THEN
            RETURN json_build_object('success', true, 'result', 'not_mafia');
        END IF;
    END IF;

    RETURN json_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_night_atomic(
    p_session_id UUID,
    p_night_record JSONB,
    p_eliminated_player_ids UUID[],
    p_next_phase TEXT,
    p_next_phase_data JSONB,
    p_is_game_over BOOLEAN DEFAULT NULL,
    p_winner TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_night_index INT;
    v_night_index_text TEXT;
    v_night_history JSONB;
    v_updated_history JSONB;
BEGIN
    v_night_index_text := COALESCE(
        NULLIF(p_night_record->>'night_index', ''),
        NULLIF(p_night_record->>'nightIndex', '')
    );

    IF v_night_index_text IS NULL OR v_night_index_text !~ '^[0-9]+$' THEN
        RAISE EXCEPTION 'resolve_night_atomic received invalid night index payload: %', p_night_record
            USING ERRCODE = '22023';
    END IF;

    v_night_index := v_night_index_text::INT;

    SELECT COALESCE(night_history, '[]'::jsonb) INTO v_night_history
    FROM public.game_sessions
    WHERE id = p_session_id;

    v_updated_history := (
        SELECT COALESCE(jsonb_agg(elem), '[]'::jsonb)
        FROM jsonb_array_elements(v_night_history) elem
        CROSS JOIN LATERAL (
            SELECT CASE
                WHEN COALESCE(
                    NULLIF(elem->>'night_index', ''),
                    NULLIF(elem->>'nightIndex', '')
                ) ~ '^[0-9]+$'
                THEN (
                    COALESCE(
                        NULLIF(elem->>'night_index', ''),
                        NULLIF(elem->>'nightIndex', '')
                    )
                )::INT
                ELSE NULL
            END AS elem_night_index
        ) existing_record
        WHERE existing_record.elem_night_index IS DISTINCT FROM v_night_index
    );

    v_updated_history := v_updated_history || p_night_record;

    UPDATE public.session_players
    SET is_alive = false,
        removal_note = 'Eliminated at night ' || v_night_index
    WHERE session_id = p_session_id
      AND player_id = ANY(p_eliminated_player_ids);

    UPDATE public.game_sessions
    SET night_history = v_updated_history,
        current_phase = p_next_phase,
        current_phase_data = p_next_phase_data,
        is_game_over = COALESCE(p_is_game_over, is_game_over),
        winner = CASE
            WHEN p_is_game_over IS TRUE OR p_winner IS NOT NULL THEN p_winner
            ELSE winner
        END,
        status = CASE
            WHEN p_is_game_over IS TRUE THEN 'completed'
            ELSE status
        END,
        completed_at = CASE
            WHEN p_is_game_over IS TRUE THEN NOW()
            ELSE completed_at
        END,
        updated_at = NOW()
    WHERE id = p_session_id;

    RETURN TRUE;
END;
$$;
