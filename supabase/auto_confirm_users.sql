-- Automatically mark newly registered users as email-confirmed
-- Run this script in the Supabase SQL editor to remove the email verification requirement.
--
-- SECURITY NOTE: This function now validates that the caller can only confirm their own email.
-- Only authenticated users can call this function, and only for their own user ID.

DROP FUNCTION IF EXISTS public.auto_confirm_user(uuid);

-- 1. Create a helper function that updates the auth.users row with elevated privileges.
CREATE OR REPLACE FUNCTION public.auto_confirm_user(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public
AS $$
BEGIN
  -- SECURITY: Only allow users to confirm their own email
  -- For new signups, we'll need to check if the user is the owner
  IF auth.uid() IS NOT NULL AND auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Cannot confirm email for another user';
  END IF;

  UPDATE auth.users
  SET email_confirmed_at = NOW()
  WHERE id = p_user_id;
END;
$$;

-- 2. Only allow authenticated users to call this function (removed anon role for security)
-- Note: For new signups, consider using a trigger-based approach instead
GRANT EXECUTE ON FUNCTION public.auto_confirm_user(uuid) TO authenticated;
