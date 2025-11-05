# Supabase Setup Guide

Quick setup guide for the Mafia Manager Supabase backend.

## Setup Steps

### Step 1: Disable Email Confirmation (IMPORTANT)

This app does not require email confirmation. To disable it:

1. Go to your Supabase Dashboard
2. Navigate to **Authentication** → **Providers** → **Email**
3. Scroll down and **DISABLE** the "Confirm email" toggle
4. Click **Save**

Users can now sign up and immediately sign in without confirming their email.

### Step 2: Run Database Migrations

In the Supabase SQL Editor, run these files in order:

1. **`migrations/20250111_enable_rls_policies.sql`**
   - Creates database tables (profiles, player_stats, custom_roles_configs)
   - Sets up Row-Level Security policies

2. **`alternative_trigger_approach.sql`**
   - Creates a trigger that automatically creates user profiles on signup
   - Uses the display_name from signup metadata

### Step 3: Update API Credentials

1. Get your credentials from **Settings** → **API**:
   - Project URL
   - `anon` public key

2. Update `Core/Services/SupabaseConfig.swift`:
```swift
enum SupabaseConfig {
    static let supabaseURL = "YOUR_PROJECT_URL"
    static let supabaseAnonKey = "YOUR_ANON_KEY"
}
```

## Testing

1. Build and run the app
2. Sign up with a test account
3. You should be immediately signed in (no email confirmation needed)
4. Check Supabase dashboard to verify user and profile were created

## Troubleshooting

**"Email not confirmed" error:**
- Make sure you disabled "Confirm email" in Step 1
- Wait a few minutes for settings to propagate

**Profile not created:**
- Verify the trigger was created (Step 2)
- Check Supabase logs for errors

## Database Schema

- **profiles**: User display names and metadata
- **player_stats**: Game statistics per player
- **custom_roles_configs**: Saved role configurations

All tables use Row-Level Security (RLS) to ensure users can only access their own data.
