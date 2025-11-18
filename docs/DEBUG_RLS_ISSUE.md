# Debugging RLS Issue - Current Status

## Problem
`auth.uid()` returns NULL during INSERT operations from the Swift client, causing RLS policies to fail.

## Root Cause Investigation
When testing with SQL, `auth.uid()` returns NULL even from SECURITY DEFINER functions. This indicates that the Supabase client is **not including the JWT auth token in database requests**.

## Current Diagnostic Setup

### 1. Ultra-Permissive Policy Active
The `session_players` INSERT policy currently allows:
- Any insert if `auth.uid()` IS NOT NULL  
- Any insert for bots (user_id IS NULL)

### 2. Trigger Logging
A trigger logs every INSERT attempt showing:
- `user_id` being inserted
- `session_id` 
- `auth.uid()` value (this is the key)
- `player_name`

## Next Steps to Test

1. **Try joining a game** from the iOS app
2. **Check Xcode console** for these log lines:
   ```
   ✅ [SessionService] Auth session found - User ID: ...
   🔐 [addPlayer] Auth token verified before insert
   ```

3. **Check Supabase logs** for the trigger output:
   ```sql
   -- Run this query in Supabase SQL Editor:
   SELECT * FROM mcp_supabase_get_logs WHERE service = 'postgres' 
   AND event_message LIKE '%INSERT ATTEMPT%'
   ORDER BY timestamp DESC LIMIT 5;
   ```

## Possible Issues & Solutions

### Issue 1: JWT Token Not Included in Requests
**Symptom:** `auth.uid()` is NULL  
**Cause:** Supabase Swift SDK not automatically including auth headers  
**Solution:** Explicitly set auth headers or use service role key (not recommended for production)

### Issue 2: Session Not Persisting
**Symptom:** Auth session exists in Swift but not in database  
**Cause:** Session not properly saved/restored  
**Solution:** Call `supabase.auth.setSession()` after sign-in

### Issue 3: Wrong Auth Context
**Symptom:** Auth works for some operations but not others  
**Cause:** Different request contexts  
**Solution:** Ensure all requests use the same authenticated client instance

## Temporary Workaround (if auth.uid() is NULL)

If `auth.uid()` continues to return NULL, we can:
1. Remove the `auth.uid()` check temporarily
2. Add application-level validation instead
3. Use service role key for backend operations (requires server component)

## Files Modified for Debugging
- Added logging trigger in database
- Made INSERT policy ultra-permissive  
- Added auth verification before INSERT in SessionService.swift

## Cleanup Required After Fix
- [ ] Remove diagnostic trigger
- [ ] Restore proper INSERT policy with `auth.uid() = user_id` check
- [ ] Remove extra logging from SessionService.swift


