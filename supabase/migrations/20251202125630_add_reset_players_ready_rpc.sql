-- Reset all human players' ready status in a session (single batch update)
-- Replaces sequential per-player updates to reduce latency and API calls
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
