-- Alternative approach: Use a database trigger to automatically create profiles
-- This bypasses RLS by running the insert with elevated privileges

-- 1. Create a function that runs with SECURITY DEFINER (elevated privileges)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name, created_at, updated_at)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'display_name', NEW.email),
    NOW(),
    NOW()
  );
  RETURN NEW;
END;
$$;

-- 2. Create a trigger that fires after a new user is created in auth.users
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Note: This approach creates the profile automatically when a user signs up
-- The display_name will be pulled from the user metadata if available
