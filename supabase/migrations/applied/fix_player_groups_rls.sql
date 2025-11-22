-- =====================================================
-- FIX PLAYER GROUPS RLS
-- =====================================================
-- Run this if you're getting RLS violations

-- First, let's completely remove and recreate the policies
DROP POLICY IF EXISTS "Users can view their own player groups" ON public.player_groups;
DROP POLICY IF EXISTS "Users can insert their own player groups" ON public.player_groups;
DROP POLICY IF EXISTS "Users can update their own player groups" ON public.player_groups;
DROP POLICY IF EXISTS "Users can delete their own player groups" ON public.player_groups;

-- Make sure RLS is enabled
ALTER TABLE public.player_groups ENABLE ROW LEVEL SECURITY;

-- Recreate policies matching the exact pattern from custom_roles_configs
CREATE POLICY "Users can view their own player groups"
ON public.player_groups
FOR SELECT
USING (user_id = auth.uid());

CREATE POLICY "Users can insert their own player groups"
ON public.player_groups
FOR INSERT
WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update their own player groups"
ON public.player_groups
FOR UPDATE
USING (user_id = auth.uid());

CREATE POLICY "Users can delete their own player groups"
ON public.player_groups
FOR DELETE
USING (user_id = auth.uid());

-- =====================================================
-- DONE! Try creating a player group now.
-- =====================================================
