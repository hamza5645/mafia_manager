# Critical Issue: Auth Tokens Not Passed to Database

## Problem
The Supabase Swift SDK has a valid auth session in the app, but `auth.uid()` returns NULL in the database during INSERT operations. This causes RLS policies to fail.

## Evidence
```
✅ [SessionService] Auth session found - User ID: 8CA034DB-4633-43AD-9214-8363AF64439C
🔑 [SessionService] Access token present: true
🔐 [addPlayer] Token expires at: 2025-11-17 8:34:53 PM +0000
❌ RLS policy violation - auth.uid() is NULL on database side
```

## Root Cause
The Supabase Swift SDK is not automatically including JWT tokens in PostgREST (database) requests, even though:
- The auth session exists
- The access token is present
- The token hasn't expired

## Current Workaround (INSECURE)
```sql
CREATE POLICY "Users can join a session"
ON public.session_players
FOR INSERT
WITH CHECK (true);  -- Allows ALL inserts - NOT SECURE!
```

## Proper Solutions to Investigate

### Solution 1: Force Token Inclusion (Recommended)
Ensure the Supabase client explicitly includes auth headers in every request:

```swift
// In SupabaseService.swift
private init() {
    self.client = SupabaseClient(
        supabaseURL: URL(string: SupabaseConfig.supabaseURL)!,
        supabaseKey: SupabaseConfig.supabaseAnonKey,
        options: SupabaseClientOptions(
            db: .init(schema: "public"),
            auth: .init(
                autoRefreshToken: true,
                persistSession: true,
                detectSessionInURL: false
            )
        )
    )
}
```

### Solution 2: Check SDK Version
The issue might be a known bug in certain versions of supabase-swift. Check:
- Current SDK version
- Known issues on GitHub
- Update to latest version if available

### Solution 3: Manual Token Passing
Explicitly pass the auth token in database requests:

```swift
// Before database operations
let session = try await supabase.auth.session
// The SDK should automatically use this session for subsequent requests
```

### Solution 4: Use Service Role Key (NOT RECOMMENDED)
Use the service role key instead of anon key - this bypasses RLS entirely but is **extremely insecure** for client apps.

## Testing Required
1. Test with latest supabase-swift SDK version
2. Check if auth tokens work for other operations (e.g., SELECT)
3. Verify session persistence across app restarts
4. Test token refresh mechanism

## Files to Modify
- `Core/Services/SupabaseService.swift` - Client initialization
- `Core/Services/AuthService.swift` - Session management
- `Core/Services/Multiplayer/SessionService.swift` - Database operations

## References
- Supabase Swift SDK: https://github.com/supabase/supabase-swift
- RLS Documentation: https://supabase.com/docs/guides/auth/row-level-security
- Auth Context: https://supabase.com/docs/guides/auth/server-side/creating-a-client

## Cleanup Required After Fix
- [ ] Remove `WITH CHECK (true)` policy
- [ ] Restore proper RLS policy: `auth.uid() = user_id`
- [ ] Remove diagnostic trigger
- [ ] Remove extra logging from SessionService
- [ ] Test all multiplayer operations with proper RLS


