# Supabase Database Setup

## IMPORTANT: Required Setup for Authentication

To fix the "new row violates row-level security policy" error, you need to set up a database trigger that automatically creates user profiles.

### Step 1: Set Up the Database Trigger (REQUIRED)

1. Go to your Supabase project dashboard: https://ptspsxqmbfvcwczjpztd.supabase.co
2. Navigate to the SQL Editor (left sidebar)
3. Click "New Query"
4. Copy and paste the contents of `alternative_trigger_approach.sql`
5. Click "Run" to execute

**What this does:**
- Creates a database trigger that automatically creates a profile when a new user signs up
- The trigger runs with elevated privileges, bypassing RLS
- The display_name is pulled from the user metadata passed during signup
- This is the recommended approach by Supabase for handling profile creation

### Step 2: Verify RLS Policies (Optional)

If you want to check what RLS policies currently exist:

1. In SQL Editor, run the contents of `diagnose_rls.sql`
2. This will show you all existing policies on the profiles table

### Step 3: Fix INSERT Policy (Only if needed)

If you're still having issues after Step 1, try running `fix_insert_policy.sql` to recreate the INSERT policy.

## How It Works Now

**Before (Old Approach - Had Issues):**
1. User signs up
2. Swift code tries to manually insert profile
3. RLS policy blocks it because session might not be fully established ❌

**After (New Approach - Works Reliably):**
1. User signs up with display_name in metadata
2. Database trigger automatically creates profile with elevated privileges
3. No RLS issues because trigger runs as SECURITY DEFINER ✅

## Database Tables

This setup manages three tables:

1. **profiles** table:
   - Auto-created by trigger on signup
   - Users can view and update only their own profile

2. **player_stats** table:
   - Users can view, insert, update, and delete only their own stats

3. **custom_roles_configs** table:
   - Users can view, insert, update, and delete only their own role configurations

All tables have RLS enabled to ensure users can only access their own data.
