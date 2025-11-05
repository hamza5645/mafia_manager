-- =====================================================
-- MAFIA MANAGER - COMPLETE DATABASE SETUP
-- =====================================================
-- Run this entire file in your Supabase SQL Editor
-- This creates all tables, policies, and triggers needed for the app

-- =====================================================
-- 1. CREATE TABLES
-- =====================================================

-- Profiles table: User account information
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

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

-- =====================================================
-- 2. ENABLE ROW LEVEL SECURITY
-- =====================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.player_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.custom_roles_configs ENABLE ROW LEVEL SECURITY;

-- =====================================================
-- 3. PROFILES TABLE POLICIES
-- =====================================================

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

-- Allow users to view their own stats
CREATE POLICY "Users can view their own stats"
ON public.player_stats
FOR SELECT
USING (user_id = auth.uid());

-- Allow users to insert their own stats
CREATE POLICY "Users can insert their own stats"
ON public.player_stats
FOR INSERT
WITH CHECK (user_id = auth.uid());

-- Allow users to update their own stats
CREATE POLICY "Users can update their own stats"
ON public.player_stats
FOR UPDATE
USING (user_id = auth.uid());

-- Allow users to delete their own stats
CREATE POLICY "Users can delete their own stats"
ON public.player_stats
FOR DELETE
USING (user_id = auth.uid());

-- =====================================================
-- 5. CUSTOM_ROLES_CONFIGS TABLE POLICIES
-- =====================================================

-- Allow users to view their own role configs
CREATE POLICY "Users can view their own role configs"
ON public.custom_roles_configs
FOR SELECT
USING (user_id = auth.uid());

-- Allow users to insert their own role configs
CREATE POLICY "Users can insert their own role configs"
ON public.custom_roles_configs
FOR INSERT
WITH CHECK (user_id = auth.uid());

-- Allow users to update their own role configs
CREATE POLICY "Users can update their own role configs"
ON public.custom_roles_configs
FOR UPDATE
USING (user_id = auth.uid());

-- Allow users to delete their own role configs
CREATE POLICY "Users can delete their own role configs"
ON public.custom_roles_configs
FOR DELETE
USING (user_id = auth.uid());

-- =====================================================
-- 6. AUTO-CREATE PROFILE TRIGGER
-- =====================================================

-- Function that automatically creates a profile when a user signs up
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

-- Trigger that fires after a new user is created
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- =====================================================
-- SETUP COMPLETE!
-- =====================================================
-- Your database is now ready for the Mafia Manager app.
--
-- Next steps:
-- 1. Disable email confirmation in Authentication → Providers → Email
-- 2. Update Core/Services/SupabaseConfig.swift with your API credentials
-- 3. Build and run the app!
