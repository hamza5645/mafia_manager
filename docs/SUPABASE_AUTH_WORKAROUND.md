# Supabase Swift SDK Authentication Workaround

## Issue

The Supabase Swift SDK (v2.37.0) has a known session persistence bug where authentication sessions are not properly stored or retrieved after login. This causes database operations to fail with 401 Unauthorized errors even though the user appears to be authenticated.

**Symptoms:**
- User can log in successfully
- `AuthStore.isAuthenticated` is `true`
- `AuthStore.currentUserId` is populated
- Database operations fail with 401 Unauthorized
- `supabase.auth.session` returns `nil` even immediately after `signIn()`

## Root Cause

The Supabase Swift SDK's automatic session persistence is broken. Even after calling `signIn()` and receiving a valid session with access and refresh tokens, subsequent calls to `supabase.auth.session` return `nil`. The session is not being stored in the SDK's storage layer.

## Workaround

We've implemented a manual token management system that bypasses the SDK's broken session persistence:

### 1. Manual Token Storage in AuthStore

```swift
// Store tokens manually in AuthStore
@Published var accessToken: String?
@Published var refreshToken: String?

// After successful sign-in
let session = try await authService.signIn(email: email, password: password)
self.accessToken = session.accessToken
self.refreshToken = session.refreshToken
```

### 2. Manual Authorization Header Injection

For every database operation on `player_groups`, we manually attach the access token:

```swift
// In DatabaseService
var accessToken: String?

func createPlayerGroup(_ group: PlayerGroup) async throws {
    var request = try supabase
        .from("player_groups")
        .insert(group)

    if let token = accessToken {
        request = request.setHeader(name: "Authorization", value: "Bearer \(token)")
    }

    try await request.execute()
}
```

### 3. Token Injection Before Database Calls

In views that call database operations, inject the token before each call:

```swift
// Before calling database service
databaseService.accessToken = authStore.accessToken
playerGroups = try await databaseService.getPlayerGroups(userId: userId)
```

## Affected Operations

All `player_groups` database operations require manual token injection:

- `getPlayerGroups()` - Used in Settings and SetupView
- `getPlayerGroup()` - Get single group
- `createPlayerGroup()` - Create new group
- `updatePlayerGroup()` - Update existing group
- `deletePlayerGroup()` - Delete group

## Files Modified

- `Core/Store/AuthStore.swift` - Added manual token storage
- `Core/Services/DatabaseService.swift` - Added token injection to all player_groups operations
- `Features/Stats/PlayerGroupsView.swift` - Inject tokens before database calls
- `Features/Setup/SetupView.swift` - Inject tokens in loadPlayerGroups()

## Future Considerations

This workaround should be removed once Supabase fixes the session persistence issue in their Swift SDK. Monitor:
- https://github.com/supabase/supabase-swift/issues
- https://github.com/orgs/supabase/discussions/35158

When upgrading the Supabase Swift SDK, test if session persistence works correctly and remove this workaround if the issue is resolved.

## Testing

To verify the workaround is working:
1. Log in to the app
2. Create a player group in Settings
3. Navigate to SetupView main page
4. Click "Load Player Group" - groups should appear
5. Verify no 401 Unauthorized errors in logs
