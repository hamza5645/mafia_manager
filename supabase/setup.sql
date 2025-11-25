-- =====================================================
-- MAFIA MANAGER - COMPLETE DATABASE SETUP
-- =====================================================
-- Run this entire file in your Supabase SQL Editor
-- This creates all tables, policies, and triggers needed for the app
--
-- IMPORTANT: This file is idempotent and can be run multiple times safely.
-- It will drop and recreate all policies to ensure they are up to date.

-- =====================================================
-- 1. CREATE TABLES
-- =====================================================

-- Profiles table: User account information
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL,
    is_anonymous BOOLEAN DEFAULT false NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Add is_anonymous column if it doesn't exist (for existing installations)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'is_anonymous'
    ) THEN
        ALTER TABLE public.profiles ADD COLUMN is_anonymous BOOLEAN DEFAULT false NOT NULL;
    END IF;
END $$;

-- Player Stats table: Game statistics for each player
CREATE TABLE IF NOT EXISTS public.player_stats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    player_name TEXT NOT NULL,
    games_played INT DEFAULT 0 NOT NULL,
    games_won INT DEFAULT 0 NOT NULL,
    games_lost INT DEFAULT 0 NOT NULL,
    total_kills INT DEFAULT 0 NOT NULL,
    times_mafia INT DEFAULT 0 NOT NULL,
    times_doctor INT DEFAULT 0 NOT NULL,
    times_inspector INT DEFAULT 0 NOT NULL,
    times_citizen INT DEFAULT 0 NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    UNIQUE(user_id, player_name)
);

-- Custom Roles Configs table: Saved role distributions
CREATE TABLE IF NOT EXISTS public.custom_roles_configs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    config_name TEXT NOT NULL,
    role_distribution JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    UNIQUE(user_id, config_name)
);

-- Player Groups table: Saved groups of player names
CREATE TABLE IF NOT EXISTS public.player_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    group_name TEXT NOT NULL,
    player_names JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    UNIQUE(user_id, group_name)
);

-- =====================================================
-- 2. ENABLE ROW LEVEL SECURITY
-- =====================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.player_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.custom_roles_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.player_groups ENABLE ROW LEVEL SECURITY;

-- =====================================================
-- 3. PROFILES TABLE POLICIES
-- =====================================================

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can create their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can view their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;

-- Allow users to insert their own profile during signup
CREATE POLICY "Users can create their own profile"
ON public.profiles
FOR INSERT
WITH CHECK (auth.uid() = id);

-- Allow users to view their own profile
CREATE POLICY "Users can view their own profile"
ON public.profiles
FOR SELECT
USING (auth.uid() = id);

-- Allow users to update their own profile
CREATE POLICY "Users can update their own profile"
ON public.profiles
FOR UPDATE
USING (auth.uid() = id);

-- =====================================================
-- 4. PLAYER_STATS TABLE POLICIES
-- =====================================================

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view their own stats" ON public.player_stats;
DROP POLICY IF EXISTS "Users can insert their own stats" ON public.player_stats;
DROP POLICY IF EXISTS "Users can update their own stats" ON public.player_stats;
DROP POLICY IF EXISTS "Users can delete their own stats" ON public.player_stats;

-- Allow users to view their own stats
CREATE POLICY "Users can view their own stats"
ON public.player_stats
FOR SELECT
USING (auth.uid() = user_id);

-- Allow users to insert their own stats
CREATE POLICY "Users can insert their own stats"
ON public.player_stats
FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Allow users to update their own stats
CREATE POLICY "Users can update their own stats"
ON public.player_stats
FOR UPDATE
USING (auth.uid() = user_id);

-- Allow users to delete their own stats
CREATE POLICY "Users can delete their own stats"
ON public.player_stats
FOR DELETE
USING (auth.uid() = user_id);

-- =====================================================
-- 5. CUSTOM_ROLES_CONFIGS TABLE POLICIES
-- =====================================================

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view their own role configs" ON public.custom_roles_configs;
DROP POLICY IF EXISTS "Users can insert their own role configs" ON public.custom_roles_configs;
DROP POLICY IF EXISTS "Users can update their own role configs" ON public.custom_roles_configs;
DROP POLICY IF EXISTS "Users can delete their own role configs" ON public.custom_roles_configs;

-- Allow users to view their own role configs
CREATE POLICY "Users can view their own role configs"
ON public.custom_roles_configs
FOR SELECT
USING (auth.uid() = user_id);

-- Allow users to insert their own role configs
CREATE POLICY "Users can insert their own role configs"
ON public.custom_roles_configs
FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Allow users to update their own role configs
CREATE POLICY "Users can update their own role configs"
ON public.custom_roles_configs
FOR UPDATE
USING (auth.uid() = user_id);

-- Allow users to delete their own role configs
CREATE POLICY "Users can delete their own role configs"
ON public.custom_roles_configs
FOR DELETE
USING (auth.uid() = user_id);

-- =====================================================
-- 6. PLAYER_GROUPS TABLE POLICIES
-- =====================================================

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view their own player groups" ON public.player_groups;
DROP POLICY IF EXISTS "Users can insert their own player groups" ON public.player_groups;
DROP POLICY IF EXISTS "Users can update their own player groups" ON public.player_groups;
DROP POLICY IF EXISTS "Users can delete their own player groups" ON public.player_groups;

-- Allow users to view their own player groups
CREATE POLICY "Users can view their own player groups"
ON public.player_groups
FOR SELECT
USING (user_id = auth.uid());

-- Allow users to insert their own player groups
CREATE POLICY "Users can insert their own player groups"
ON public.player_groups
FOR INSERT
WITH CHECK (user_id = auth.uid());

-- Allow users to update their own player groups
CREATE POLICY "Users can update their own player groups"
ON public.player_groups
FOR UPDATE
USING (user_id = auth.uid());

-- Allow users to delete their own player groups
CREATE POLICY "Users can delete their own player groups"
ON public.player_groups
FOR DELETE
USING (user_id = auth.uid());

-- =====================================================
-- 7. AUTO-CREATE PROFILE TRIGGER
-- =====================================================

-- Function that automatically creates a profile when a user signs up
-- Handles both regular users and anonymous users
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name, is_anonymous, created_at, updated_at)
  VALUES (
    NEW.id,
    COALESCE(
      NEW.raw_user_meta_data->>'display_name',
      CASE WHEN NEW.is_anonymous THEN 'Guest' ELSE NEW.email END
    ),
    COALESCE(NEW.is_anonymous, false),
    NOW(),
    NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    is_anonymous = EXCLUDED.is_anonymous,
    display_name = CASE
      WHEN profiles.is_anonymous AND NOT EXCLUDED.is_anonymous
      THEN COALESCE(NEW.raw_user_meta_data->>'display_name', profiles.display_name)
      ELSE profiles.display_name
    END,
    updated_at = NOW();
  RETURN NEW;
END;
$$;

-- Trigger that fires after a new user is created
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- =====================================================
-- 8. ANONYMOUS USER STATS MERGE FUNCTION
-- =====================================================
-- This function merges stats from an anonymous user to a permanent account
-- Used when an anonymous user signs into an existing account

CREATE OR REPLACE FUNCTION public.merge_anonymous_stats(
    p_anonymous_user_id UUID,
    p_target_user_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_merged_count INT := 0;
    v_transferred_count INT := 0;
    v_anon_stat RECORD;
    v_target_stat player_stats%ROWTYPE;
BEGIN
    -- Verify the anonymous user exists and is actually anonymous
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = p_anonymous_user_id AND is_anonymous = true
    ) THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Source user is not anonymous or does not exist'
        );
    END IF;

    -- Verify target user exists and is not anonymous
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = p_target_user_id AND is_anonymous = false
    ) THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Target user does not exist or is anonymous'
        );
    END IF;

    -- Process each stat from anonymous user
    FOR v_anon_stat IN
        SELECT * FROM public.player_stats
        WHERE user_id = p_anonymous_user_id
    LOOP
        -- Check if target user has stats for same player_name
        SELECT * INTO v_target_stat
        FROM public.player_stats
        WHERE user_id = p_target_user_id
          AND player_name = v_anon_stat.player_name;

        IF FOUND THEN
            -- MERGE: Sum all numeric stats
            UPDATE public.player_stats
            SET
                games_played = games_played + v_anon_stat.games_played,
                games_won = games_won + v_anon_stat.games_won,
                games_lost = games_lost + v_anon_stat.games_lost,
                total_kills = total_kills + v_anon_stat.total_kills,
                times_mafia = times_mafia + v_anon_stat.times_mafia,
                times_doctor = times_doctor + v_anon_stat.times_doctor,
                times_inspector = times_inspector + v_anon_stat.times_inspector,
                times_citizen = times_citizen + v_anon_stat.times_citizen,
                updated_at = NOW()
            WHERE id = v_target_stat.id;

            v_merged_count := v_merged_count + 1;

            -- Delete the anonymous stat (now merged)
            DELETE FROM public.player_stats WHERE id = v_anon_stat.id;
        ELSE
            -- TRANSFER: Move stat to target user (no conflict)
            UPDATE public.player_stats
            SET user_id = p_target_user_id, updated_at = NOW()
            WHERE id = v_anon_stat.id;

            v_transferred_count := v_transferred_count + 1;
        END IF;
    END LOOP;

    -- Also transfer other user data (custom_roles_configs, player_groups)
    UPDATE public.custom_roles_configs
    SET user_id = p_target_user_id, updated_at = NOW()
    WHERE user_id = p_anonymous_user_id;

    UPDATE public.player_groups
    SET user_id = p_target_user_id, updated_at = NOW()
    WHERE user_id = p_anonymous_user_id;

    -- Delete the anonymous user's profile (orphaned)
    DELETE FROM public.profiles WHERE id = p_anonymous_user_id;

    RETURN json_build_object(
        'success', true,
        'merged_count', v_merged_count,
        'transferred_count', v_transferred_count
    );
END;
$$;

-- =====================================================
-- SETUP COMPLETE!
-- =====================================================
-- Your database is now ready for the Mafia Manager app.
--
-- Next steps:
-- 1. Disable email confirmation in Authentication → Providers → Email
-- 2. Enable Anonymous Sign-In in Authentication → Providers → Anonymous Sign-In
-- 3. Update Core/Services/SupabaseConfig.swift with your API credentials
-- 4. Build and run the app!
