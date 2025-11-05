-- Enable Row Level Security on tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.player_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.custom_roles_configs ENABLE ROW LEVEL SECURITY;

-- =====================================================
-- PROFILES TABLE POLICIES
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
-- PLAYER_STATS TABLE POLICIES
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
-- CUSTOM_ROLES_CONFIGS TABLE POLICIES
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
