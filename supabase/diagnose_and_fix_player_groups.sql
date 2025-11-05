-- =====================================================
-- DIAGNOSE AND FIX PLAYER GROUPS RLS
-- =====================================================

-- Step 1: Check if table exists
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'player_groups') THEN
        RAISE NOTICE 'Table player_groups exists';
    ELSE
        RAISE NOTICE 'Table player_groups DOES NOT exist - creating it...';
    END IF;
END $$;

-- Step 2: Create table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.player_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    group_name TEXT NOT NULL,
    player_names JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    UNIQUE(user_id, group_name)
);

-- Step 3: Make absolutely sure RLS is enabled
ALTER TABLE public.player_groups ENABLE ROW LEVEL SECURITY;

-- Step 4: Drop ALL existing policies
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT policyname FROM pg_policies WHERE tablename = 'player_groups' AND schemaname = 'public')
    LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON public.player_groups';
        RAISE NOTICE 'Dropped policy: %', r.policyname;
    END LOOP;
END $$;

-- Step 5: Create policies matching custom_roles_configs EXACTLY
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

-- Step 6: Verify policies were created
SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'player_groups'
ORDER BY policyname;

-- =====================================================
-- COMPLETE! The output above should show 4 policies.
-- =====================================================
