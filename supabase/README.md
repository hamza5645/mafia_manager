# Supabase Setup Guide

Complete setup guide for the Mafia Manager Supabase backend.

## Quick Setup (2 Steps)

### Step 1: Disable Email Confirmation

1. Go to your Supabase Dashboard
2. Navigate to **Authentication** → **Providers** → **Email**
3. Scroll down and **DISABLE** the "Confirm email" toggle
4. Click **Save**

### Step 2: Run Database Setup

1. In your Supabase Dashboard, go to the **SQL Editor**
2. Click **"New Query"**
3. Copy and paste the entire contents of `setup.sql`
4. Click **"Run"**

That's it! The single SQL file creates everything:
- All database tables (profiles, player_stats, custom_roles_configs)
- Row-Level Security policies
- Auto-profile creation trigger

### Step 3: Update API Credentials

1. In Supabase, go to **Settings** → **API**
2. Copy your Project URL and `anon` public key
3. Update `Core/Services/SupabaseConfig.swift`:

```swift
enum SupabaseConfig {
    static let supabaseURL = "YOUR_PROJECT_URL"
    static let supabaseAnonKey = "YOUR_ANON_KEY"
}
```

## Testing

1. Build and run the app
2. Sign up with a test account
3. You should be immediately signed in (no email confirmation)
4. Check Supabase dashboard to verify user and profile were created

## What the Setup Creates

**Tables:**
- `profiles` - User display names
- `player_stats` - Game statistics per player
- `custom_roles_configs` - Saved role distributions

**Security:**
- Row-Level Security (RLS) ensures users only access their own data
- Automatic profile creation via database trigger

## Troubleshooting

**"Email not confirmed" error:**
- Disable "Confirm email" in Authentication settings (Step 1)

**Profile not created:**
- Make sure you ran the entire `setup.sql` file
- Check Supabase logs for errors
