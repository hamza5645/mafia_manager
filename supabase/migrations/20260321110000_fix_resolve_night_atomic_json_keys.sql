-- MM-01: Fix resolve_night_atomic to read snake_case payload keys and preserve night history.
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
    v_night_index_text TEXT;
    v_night_history JSONB;
    v_updated_history JSONB;
BEGIN
    -- Extract night_index from the record, tolerating legacy camelCase payloads.
    v_night_index_text := COALESCE(
        NULLIF(p_night_record->>'night_index', ''),
        NULLIF(p_night_record->>'nightIndex', '')
    );

    IF v_night_index_text IS NULL OR v_night_index_text !~ '^[0-9]+$' THEN
        RAISE EXCEPTION 'resolve_night_atomic received invalid night index payload: %', p_night_record
            USING ERRCODE = '22023';
    END IF;

    v_night_index := v_night_index_text::INT;

    -- Get current night_history, defaulting null to an empty array.
    SELECT COALESCE(night_history, '[]'::jsonb) INTO v_night_history
    FROM public.game_sessions
    WHERE id = p_session_id;

    -- Remove any existing record for this night_index (prevent duplicates)
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
