-- Fix the INSERT policy for profiles table
-- This ensures users can create their own profile during signup

-- First, drop the existing INSERT policy (if it exists)
DROP POLICY IF EXISTS "Users can create their own profile" ON public.profiles;

-- Recreate the INSERT policy with correct configuration
-- IMPORTANT: The WITH CHECK clause must allow the insert to succeed
CREATE POLICY "Users can create their own profile"
ON public.profiles
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = id);

-- Verify the policy was created
SELECT policyname, cmd, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'profiles'
  AND policyname = 'Users can create their own profile';
