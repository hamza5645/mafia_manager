-- Auto-confirm email addresses for new user signups
-- This uses a database trigger approach which is more secure than allowing
-- client-side calls to confirm emails.
--
-- WARNING: This should ONLY be used in development environments.
-- For production, you should use proper email verification.

-- Create a function that auto-confirms new users
CREATE OR REPLACE FUNCTION public.auto_confirm_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public
AS $$
BEGIN
  -- Auto-confirm the email immediately on signup
  NEW.email_confirmed_at = NOW();
  NEW.confirmed_at = NOW();
  RETURN NEW;
END;
$$;

-- Create trigger that fires BEFORE insert on auth.users
DROP TRIGGER IF EXISTS auto_confirm_user_trigger ON auth.users;

CREATE TRIGGER auto_confirm_user_trigger
  BEFORE INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_confirm_new_user();

-- Note: This trigger-based approach is more secure than the function-based approach
-- as it doesn't expose any RPC endpoints that could be exploited.
