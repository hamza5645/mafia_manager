-- Automatically mark newly registered users as email-confirmed
-- Run this script in the Supabase SQL editor to remove the email verification requirement.

DROP FUNCTION IF EXISTS public.auto_confirm_user(uuid);

-- 1. Create a helper function that updates the auth.users row with elevated privileges.
CREATE OR REPLACE FUNCTION public.auto_confirm_user(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public
AS $$
BEGIN
  UPDATE auth.users
  SET email_confirmed_at = NOW()
  WHERE id = p_user_id;
END;
$$;

-- 2. Allow both anonymous and authenticated clients to call this function.
GRANT EXECUTE ON FUNCTION public.auto_confirm_user(uuid) TO anon, authenticated;
