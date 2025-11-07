# Mafia Manager Security & Logic Audit Report

**Date**: 2025-11-07
**Auditor**: Claude Code
**Scope**: Complete codebase security, bug, and game logic review

---

## Executive Summary

This comprehensive audit identified **22 issues** across security, game logic, race conditions, and error handling categories. The findings range from **3 CRITICAL security vulnerabilities** to several medium-severity logic bugs and code quality concerns.

**Severity Breakdown:**
- 🔴 **CRITICAL**: 3 issues (immediate action required)
- 🟠 **HIGH**: 7 issues (should be addressed soon)
- 🟡 **MEDIUM**: 8 issues (should be fixed)
- 🟢 **LOW**: 4 issues (nice to have)

---

## 1. SECURITY VULNERABILITIES

### 🔴 CRITICAL-001: Hardcoded Supabase Credentials in Source Code
**File**: `Core/Services/SupabaseConfig.swift:4-5`

**Issue**: The Supabase anon key is hardcoded in source code that appears to be in a public repository.

```swift
static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

**Risk**:
- Exposed credentials can be extracted and used to access your Supabase project
- Attackers could abuse rate limits, access data, or perform unauthorized operations
- Once committed to git, this key is permanently in history even if changed

**Recommendation**:
1. **Immediately rotate** the Supabase anon key in your Supabase dashboard
2. Move credentials to environment variables or a `.xcconfig` file (gitignored)
3. Use a secrets management solution for production
4. Add `SupabaseConfig.swift` to `.gitignore` and use a template file instead
5. Review git history and consider using tools like `git-filter-repo` to remove the key from history

---

### 🔴 CRITICAL-002: Insecure Token Storage in UserDefaults
**File**: `Core/Store/AuthStore.swift:15-32`

**Issue**: Authentication tokens (access and refresh tokens) are stored in UserDefaults, which is **not encrypted**.

```swift
@Published var accessToken: String? {
    didSet {
        if let token = accessToken {
            UserDefaults.standard.set(token, forKey: "auth_access_token")
        }
    }
}
```

**Risk**:
- UserDefaults data is stored in plain text in `Library/Preferences/*.plist`
- Tokens can be extracted via device backup, jailbreak, or malware
- Compromised tokens grant full access to user's account

**Recommendation**:
1. **Migrate to iOS Keychain immediately** for token storage
2. Use `Security` framework or a wrapper like `KeychainAccess`
3. Mark tokens as `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`

**Example Fix**:
```swift
// Use Keychain instead
import Security

func saveToKeychain(key: String, value: String) {
    let data = value.data(using: .utf8)!
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: key,
        kSecValueData as String: data,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    ]
    SecItemDelete(query as CFDictionary)
    SecItemAdd(query as CFDictionary, nil)
}
```

---

### 🔴 CRITICAL-003: No Client-Side Input Validation
**Files**: Multiple locations

**Issue**: Critical lack of input validation across the application:

1. **Player Names** (`GameStore.swift:44-51`):
   - No length limits (could crash UI with extremely long names)
   - No sanitization of special characters
   - Could cause export format issues or XSS in web views

2. **Email Validation** (`AuthStore.swift:249-251`):
   - Only trims and lowercases, no format validation
   - Could allow invalid emails to be submitted

3. **Display Names** (`AuthStore.swift:137`):
   - No length limits
   - No character restrictions

**Risk**:
- UI rendering issues with long/special character names
- Export log corruption with newlines or special chars in names
- Potential for injection attacks if data is ever used in web contexts
- Poor UX with no client-side validation feedback

**Recommendation**:
```swift
// Add validation helper
struct InputValidator {
    static func validatePlayerName(_ name: String) -> Result<String, ValidationError> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return .failure(.empty)
        }

        guard trimmed.count <= 50 else {
            return .failure(.tooLong)
        }

        // Disallow newlines and control characters
        guard trimmed.rangeOfCharacter(from: .newlines) == nil,
              trimmed.rangeOfCharacter(from: .controlCharacters) == nil else {
            return .failure(.invalidCharacters)
        }

        return .success(trimmed)
    }

    static func validateEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        return NSPredicate(format:"SELF MATCHES %@", emailRegex).evaluate(with: email)
    }
}
```

---

### 🟠 HIGH-001: Missing Rate Limiting on Authentication
**File**: `Core/Store/AuthStore.swift`

**Issue**: No client-side rate limiting or cooldown on authentication attempts.

**Risk**:
- Brute force attacks against user accounts
- Credential stuffing attempts
- Resource exhaustion

**Recommendation**:
1. Implement exponential backoff after failed attempts
2. Add local cooldown (e.g., 30s after 5 failed attempts)
3. Track failed attempts in memory
4. Consider implementing CAPTCHA for repeated failures

---

### 🟠 HIGH-002: Supabase RLS Bypass Vulnerability Potential
**File**: `Core/Services/DatabaseService.swift:9-10, 154-156`

**Issue**: Manual token injection workaround could lead to security issues:

```swift
var accessToken: String?
// ...
if let token = accessToken {
    request = request.setHeader(name: "Authorization", value: "Bearer \(token)")
}
```

**Risk**:
- If `accessToken` is not properly validated or refreshed, expired/invalid tokens could be used
- Manual header injection bypasses SDK's built-in security checks
- No validation that token belongs to the `userId` being queried

**Recommendation**:
1. Remove manual token injection and fix the underlying SDK issue properly
2. If workaround is necessary, add token validation:
   ```swift
   guard let token = accessToken, await validateToken(token) else {
       throw AuthError.invalidToken
   }
   ```
3. Ensure token is refreshed before expiration
4. Add server-side validation that token's user_id matches query's user_id

---

## 2. GAME LOGIC BUGS

### 🟠 HIGH-003: Two-Phase Night Resolution Can Be Called Multiple Times
**File**: `Core/Store/GameStore.swift:306-326`

**Issue**: `resolveNightOutcome()` has no guard against being called multiple times for the same night.

```swift
func resolveNightOutcome(targetWasSaved: Bool) {
    guard let lastIndex = state.nightHistory.indices.last else { return }
    var action = state.nightHistory[lastIndex]
    action.resultingDeaths.removeAll()  // ⚠️ Clears previous deaths!

    if !targetWasSaved, let targetID = action.mafiaTargetPlayerID {
        // ... marks player as dead
    }
}
```

**Impact**:
- Calling twice could resurrect a dead player (deaths cleared on line 309)
- Could cause inconsistent game state
- Win conditions could be evaluated multiple times

**Test Case**:
```swift
gameStore.endNight(mafiaTargetID: target.id, ...)
gameStore.resolveNightOutcome(targetWasSaved: false)  // Player dies
gameStore.resolveNightOutcome(targetWasSaved: true)   // Player revives!
```

**Recommendation**:
```swift
func resolveNightOutcome(targetWasSaved: Bool) {
    guard let lastIndex = state.nightHistory.indices.last else { return }
    var action = state.nightHistory[lastIndex]

    // Guard against duplicate resolution
    guard action.resultingDeaths.isEmpty else {
        print("⚠️ Night outcome already resolved")
        return
    }

    // ... rest of logic
}
```

---

### 🟠 HIGH-004: Win Condition Evaluated Twice Creates Race Condition
**File**: `Core/Store/GameStore.swift:398-420`

**Issue**: `evaluateWinners()` is called in both `resolveNightOutcome()` and `applyDayRemovals()` with `startOfDay` flag, checking the same condition:

```swift
if !startOfDay && mafiaCount >= nonMafiaCount {
    state.isGameOver = true
    state.winner = .mafia
    state.currentPhase = .gameOver
    return
}
```

**Impact**:
- Game could transition to `.gameOver` phase multiple times
- If phase transitions trigger UI navigation, could cause navigation stack corruption
- Inconsistent with "single source of truth" pattern

**Recommendation**:
```swift
private func evaluateWinners(startOfDay: Bool) {
    // Guard against re-evaluation
    guard !state.isGameOver else { return }

    let mafiaCount = aliveMafia.count
    let nonMafiaCount = aliveNonMafia.count
    // ... rest of logic
}
```

---

### 🟠 HIGH-005: Role Distribution Validation Missing for Custom Configs
**File**: `Core/Store/GameStore.swift:62-75`

**Issue**: When using custom role configs, no validation that total roles equal player count:

```swift
if let customConfig = customRoleConfig,
   customConfig.roleDistribution.totalPlayers == count {
    roleCounts = (
        mafia: customConfig.roleDistribution.mafiaCount,
        doctors: customConfig.roleDistribution.doctorCount,
        inspectors: customConfig.roleDistribution.inspectorCount
    )
}
// Later...
let remaining = max(0, count - roles.count)  // ⚠️ Could be 0 if config has too many roles!
roles += Array(repeating: .citizen, count: remaining)
```

**Impact**:
- If custom config specifies 10 roles but only 8 players, `remaining = 0`
- Would attempt to assign 10 roles to 8 players, causing crash
- If custom config specifies 5 roles for 8 players, would have 3 citizens as fallback (unexpected)

**Recommendation**:
```swift
if let customConfig = customRoleConfig {
    let totalCustomRoles = customConfig.roleDistribution.mafiaCount +
                          customConfig.roleDistribution.doctorCount +
                          customConfig.roleDistribution.inspectorCount

    guard totalCustomRoles <= count else {
        print("⚠️ Custom config has more roles than players")
        // Fall back to default distribution
        roleCounts = Self.roleDistribution(for: count)
    }

    guard customConfig.roleDistribution.totalPlayers == count else {
        print("⚠️ Custom config player count mismatch")
        roleCounts = Self.roleDistribution(for: count)
    }
    // ... use custom config
}
```

---

### 🟡 MEDIUM-001: Kill Attribution Logic Flaw
**File**: `Core/Store/GameStore.swift:361-372`

**Issue**: Kill attribution checks if a player's number is in `night.mafiaNumbers`, but this is a snapshot of alive mafia at night start:

```swift
for night in state.nightHistory {
    if night.resultingDeaths.first != nil {
        let aliveMafiaInNight = state.players.filter { player in
            player.role == .mafia &&
            night.mafiaNumbers.contains(player.number)  // ⚠️ Snapshot from night start
        }
        for mafiaPlayer in aliveMafiaInNight {
            killsPerPlayer[mafiaPlayer.id, default: 0] += 1
        }
    }
}
```

**Impact**:
- If mafia player dies during day, they still get credit for subsequent night kills (because their number is still in snapshot)
- Inconsistent with "alive mafia share credit" rule stated in docs

**Test Case**:
- Night 1: Mafia #1 and #2 alive, kill someone → both get credit ✓
- Day 1: Mafia #1 voted out and dies
- Night 2: Only Mafia #2 alive, kills someone
- Result: Both Mafia #1 (dead) and #2 get credit ✗

**Recommendation**:
```swift
let aliveMafiaInNight = state.players.filter { player in
    player.role == .mafia &&
    player.alive &&  // ⚠️ Need to track alive status at time of night
    night.mafiaNumbers.contains(player.number)
}
```

**Better Solution**: Add `aliveMafiaIDs: [UUID]` to `NightAction` struct to track exact mafia who participated.

---

### 🟡 MEDIUM-002: Inspector Check Returns Ambiguous Result
**File**: `Core/Store/GameStore.swift:266-272`

**Issue**: When inspector checks another inspector, both `inspectorResultIsMafia` and `inspectorResultRole` are `nil`:

```swift
if let inspectID = inspectorCheckedID, let inspected = player(by: inspectID) {
    if inspected.role != .inspector {
        inspectorRole = inspected.role
        inspectorResult = (inspected.role == .mafia)
    }
    // ⚠️ If inspector, both remain nil
}
```

**Impact**:
- UI cannot distinguish between "no check performed" vs "checked an inspector"
- Game master might not realize inspector tried to check another inspector
- Poor UX - should provide feedback

**Recommendation**:
```swift
if let inspectID = inspectorCheckedID, let inspected = player(by: inspectID) {
    if inspected.role == .inspector {
        // Return a special indicator
        inspectorRole = .inspector
        inspectorResult = nil  // Or false
        // Add a "wasInspectorBlocked" flag to NightAction
    } else {
        inspectorRole = inspected.role
        inspectorResult = (inspected.role == .mafia)
    }
}
```

---

### 🟡 MEDIUM-003: Phase Transition Logic Fragile
**File**: `Core/Store/GameStore.swift:177-203`

**Issue**: `transitionToNextRole()` logic relies on checking if action fields are `nil`, but `nil` is ambiguous:

```swift
if currentNight?.inspectorCheckedPlayerID == nil && alivePlayers.contains(where: { $0.role == .inspector }) {
    // Mafia done, police not done yet
    state.currentPhase = .nightWakeUp(activeRole: .inspector)
}
```

**Problem**:
- `inspectorCheckedPlayerID == nil` could mean:
  1. Inspector hasn't acted yet (intended)
  2. Inspector chose to skip their action (also valid)
- Could cause infinite loop or skip inspector phase unintentionally

**Recommendation**:
- Add explicit phase tracking to `NightAction`:
```swift
struct NightAction {
    // ...
    var mafiaPhaseCompleted: Bool = false
    var inspectorPhaseCompleted: Bool = false
    var doctorPhaseCompleted: Bool = false
}
```

---

### 🟡 MEDIUM-004: No Validation for Mafia Targeting
**File**: `Core/Store/GameStore.swift:277-282`

**Issue**: `endNight()` has defensive code to prevent mafia targeting mafia, but it's silent and doesn't enforce:

```swift
if let targetID = mafiaTargetID,
   let target = player(by: targetID),
   target.role != .mafia,
   target.alive {
    // Intentionally no state.players[..].alive = false and no resulting death.
}
```

**Problem**:
- If `target.role == .mafia`, the code silently does nothing
- UI has filter (`NightPhaseView.swift:18`) but can be bypassed
- No error thrown or logged
- Game master doesn't get feedback that selection was invalid

**Recommendation**:
```swift
// Add validation
guard let targetID = mafiaTargetID else {
    throw GameError.noTargetSelected
}

let target = player(by: targetID)
guard target != nil else {
    throw GameError.invalidTarget
}

guard target!.role != .mafia else {
    throw GameError.cannotTargetMafia
}

guard target!.alive else {
    throw GameError.targetAlreadyDead
}
```

---

### 🟡 MEDIUM-005: Persistence Failure Detection Impossible
**File**: `Core/Services/Persistence.swift:24-34`

**Issue**: All persistence errors are silently swallowed:

```swift
func save(_ state: GameState) {
    do {
        // ... save logic
    } catch {
        // Silently fail - persistence is not critical for app functionality
    }
}
```

**Impact**:
- User plays entire game thinking progress is saved
- App crashes or closes → all progress lost
- No way to detect or recover from save failures
- No user feedback

**Recommendation**:
```swift
enum PersistenceError: Error {
    case saveFailed(Error)
    case loadFailed(Error)
}

func save(_ state: GameState) throws {
    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: stateURL, options: .atomic)
    } catch {
        // Log error
        print("❌ Failed to save game state: \(error)")
        throw PersistenceError.saveFailed(error)
    }
}

// In GameStore
private func save() {
    do {
        try Persistence.shared.save(state)
    } catch {
        // Show error to user
        showSaveError = true
    }
}
```

---

### 🟢 LOW-001: Potential Memory Leak with AuthStore Reference
**File**: `Core/Store/GameStore.swift:12, 21-23`

**Issue**: GameStore holds optional reference to AuthStore but it's never set to nil:

```swift
private var authStore: AuthStore?

func setAuthStore(_ authStore: AuthStore) {
    self.authStore = authStore
}
```

**Impact**:
- Minor - in practice both stores are app-lifetime singletons
- But violates proper reference management patterns
- Could cause issues in testing or if architecture changes

**Recommendation**:
```swift
private weak var authStore: AuthStore?
```

---

## 3. RACE CONDITIONS & CONCURRENCY

### 🟠 HIGH-006: Auth State Restoration Race Condition
**File**: `Core/Store/AuthStore.swift:49-64`

**Issue**: Session restoration happens in `init()` Task, but app might start using AuthStore before restoration completes:

```swift
init() {
    self.accessToken = UserDefaults.standard.string(forKey: "auth_access_token")
    self.refreshToken = UserDefaults.standard.string(forKey: "auth_refresh_token")

    Task {
        if let accessToken = self.accessToken, let refreshToken = self.refreshToken {
            try await authService.restoreSession(accessToken: accessToken, refreshToken: refreshToken)
        }
        await checkAuthState()  // ⚠️ Async
        setupAuthStateListener()
    }
}
```

**Impact**:
- Views might render before `isAuthenticated` is set
- Could show wrong UI state briefly
- Operations might start before session is ready

**Recommendation**:
```swift
@Published var isRestoringSession = true

init() {
    self.accessToken = UserDefaults.standard.string(forKey: "auth_access_token")
    self.refreshToken = UserDefaults.standard.string(forKey: "auth_refresh_token")

    Task {
        defer { isRestoringSession = false }
        // ... restoration logic
    }
}

// In views
if authStore.isRestoringSession {
    ProgressView("Restoring session...")
} else {
    // ... normal UI
}
```

---

### 🟡 MEDIUM-006: Token Expiration Not Handled in DatabaseService
**File**: `Core/Services/DatabaseService.swift`

**Issue**: Manual token injection doesn't handle token expiration:

```swift
var accessToken: String?

func getPlayerStats(userId: UUID) async throws -> [PlayerStats] {
    // ⚠️ Token could be expired here
    if let token = accessToken {
        request = request.setHeader(name: "Authorization", value: "Bearer \(token)")
    }
}
```

**Impact**:
- Multi-step operations could fail mid-way if token expires
- No automatic token refresh
- Poor UX with mysterious failures

**Recommendation**:
```swift
private func getValidToken() async throws -> String {
    guard let token = accessToken else {
        throw AuthError.notAuthenticated
    }

    // Check if token is about to expire (within 5 minutes)
    if isTokenExpiringSoon(token) {
        // Refresh token
        return try await refreshAccessToken()
    }

    return token
}
```

---

### 🟡 MEDIUM-007: Persistence Race on Rapid State Changes
**File**: `Core/Store/GameStore.swift:98-100`

**Issue**: Multiple rapid mutations could cause persistence race:

```swift
private func save() {
    Persistence.shared.save(state)  // ⚠️ Async write
}

func endNight(...) {
    // ... mutate state
    save()  // Write 1
}

func resolveNightOutcome(...) {
    // ... mutate state
    save()  // Write 2 - might execute before Write 1 completes
}
```

**Impact**:
- If called in rapid succession, writes could interleave
- Could save stale state
- File corruption possible if atomic write fails

**Recommendation**:
```swift
actor PersistenceActor {
    private var saveTask: Task<Void, Never>?

    func save(_ state: GameState) {
        // Cancel pending save
        saveTask?.cancel()

        // Debounce saves
        saveTask = Task {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            guard !Task.isCancelled else { return }
            // ... actual save
        }
    }
}
```

---

## 4. ERROR HANDLING & OBSERVABILITY

### 🟡 MEDIUM-008: Silent Failures Throughout Codebase
**Files**: Multiple

**Issue**: Critical operations fail silently without user feedback:

1. **Persistence** (`Persistence.swift:30-33`): Save failures ignored
2. **Auth Profile Loading** (`AuthStore.swift:124-126`): Profile load failures ignored
3. **Cloud Sync** (`GameStore.swift:389-392`): Stat sync failures ignored per-player

```swift
} catch {
    // Continue with other players even if one fails
    // In production, this should log to a proper logging system
}
```

**Impact**:
- User has no idea things are failing
- No telemetry or logs to debug issues
- Data loss without notification
- Poor UX

**Recommendation**:
1. Implement proper logging framework
2. Add error state to stores
3. Show non-intrusive error notifications to users
4. Track error metrics

```swift
enum AppError: Error {
    case persistenceFailed(Error)
    case syncFailed(playerName: String, Error)
    case authFailed(Error)
}

@Published var recentErrors: [AppError] = []

func handleError(_ error: AppError) {
    recentErrors.append(error)
    // Log to analytics
    // Show toast notification
}
```

---

### 🟢 LOW-002: No Retry Logic for Network Operations
**Files**: `AuthService.swift`, `DatabaseService.swift`

**Issue**: All network operations fail immediately without retry.

**Recommendation**:
```swift
func withRetry<T>(maxAttempts: Int = 3, operation: () async throws -> T) async throws -> T {
    var lastError: Error?

    for attempt in 1...maxAttempts {
        do {
            return try await operation()
        } catch {
            lastError = error
            if attempt < maxAttempts {
                try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 1_000_000_000))
            }
        }
    }

    throw lastError!
}
```

---

### 🟢 LOW-003: No Offline Detection
**Files**: Network service files

**Issue**: App doesn't check network availability before operations.

**Recommendation**:
```swift
import Network

class NetworkMonitor: ObservableObject {
    @Published var isConnected = true
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: DispatchQueue.global())
    }
}

// Use in views
if !networkMonitor.isConnected {
    Text("Offline - some features unavailable")
}
```

---

### 🟢 LOW-004: Missing Test Coverage for Edge Cases
**File**: `mafia_managerTests/GameStoreTests.swift`

**Issue**: Tests don't cover several edge cases identified in this audit:
- Double resolution of night outcome
- Custom role config validation
- Phase transition edge cases
- Kill attribution with dead mafia
- Inspector checking inspector

**Recommendation**: Add test cases for all bugs identified in this report.

---

## 5. DATABASE SECURITY REVIEW

### ✅ GOOD: Row Level Security Properly Configured
**File**: `supabase/setup.sql`

The RLS policies are correctly implemented:
- All tables have RLS enabled
- Policies properly check `auth.uid() = user_id`
- Users can only access their own data
- CRUD operations all validated

### 🟢 LOW: Consider Adding Additional Constraints
**File**: `supabase/setup.sql`

**Recommendations**:
1. Add CHECK constraints for data validation:
```sql
ALTER TABLE player_stats ADD CONSTRAINT games_played_non_negative
    CHECK (games_played >= 0);

ALTER TABLE player_stats ADD CONSTRAINT games_sum_valid
    CHECK (games_won + games_lost = games_played);

ALTER TABLE player_stats ADD CONSTRAINT kills_non_negative
    CHECK (total_kills >= 0);
```

2. Add indexes for common queries:
```sql
CREATE INDEX idx_player_stats_user_player ON player_stats(user_id, player_name);
CREATE INDEX idx_custom_roles_user ON custom_roles_configs(user_id);
CREATE INDEX idx_player_groups_user ON player_groups(user_id);
```

3. Add database-level audit logging:
```sql
CREATE TABLE audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id),
    table_name TEXT NOT NULL,
    operation TEXT NOT NULL,
    old_data JSONB,
    new_data JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

---

## 6. SUMMARY OF FINDINGS BY PRIORITY

### 🔴 IMMEDIATE ACTION REQUIRED (Fix within 24h)

1. **CRITICAL-001**: Rotate Supabase credentials and move to secure storage
2. **CRITICAL-002**: Migrate tokens from UserDefaults to Keychain
3. **CRITICAL-003**: Add input validation for all user inputs

### 🟠 HIGH PRIORITY (Fix within 1 week)

4. **HIGH-001**: Add rate limiting to authentication
5. **HIGH-002**: Fix/validate manual token injection
6. **HIGH-003**: Prevent double night resolution
7. **HIGH-004**: Guard against double win evaluation
8. **HIGH-005**: Validate custom role configs
9. **HIGH-006**: Fix auth restoration race condition

### 🟡 MEDIUM PRIORITY (Fix within 1 month)

10. **MEDIUM-001**: Fix kill attribution logic
11. **MEDIUM-002**: Improve inspector check feedback
12. **MEDIUM-003**: Make phase transitions more robust
13. **MEDIUM-004**: Add mafia targeting validation
14. **MEDIUM-005**: Surface persistence errors
15. **MEDIUM-006**: Handle token expiration
16. **MEDIUM-007**: Add persistence debouncing
17. **MEDIUM-008**: Implement proper error handling

### 🟢 NICE TO HAVE (Fix as time allows)

18. **LOW-001**: Fix AuthStore reference
19. **LOW-002**: Add network retry logic
20. **LOW-003**: Add offline detection
21. **LOW-004**: Expand test coverage
22. **Database**: Add constraints and indexes

---

## 7. SECURITY BEST PRACTICES CHECKLIST

### Current Status:
- ✅ RLS enabled on all tables
- ✅ User data isolation working correctly
- ✅ Auth state properly managed (with fixes needed)
- ❌ Credentials hardcoded in source
- ❌ Tokens stored insecurely
- ❌ No input validation
- ❌ No rate limiting
- ❌ Silent error handling
- ⚠️ Manual token injection (workaround)

### Recommended Security Hardening:
1. Implement all CRITICAL fixes immediately
2. Add application-level encryption for sensitive local data
3. Implement certificate pinning for API calls
4. Add request signing for critical operations
5. Implement session timeout and auto-logout
6. Add biometric authentication option
7. Implement secure logging (no sensitive data in logs)
8. Add jailbreak/root detection if handling sensitive data
9. Regular security audits and dependency updates

---

## 8. TESTING RECOMMENDATIONS

Create test cases for:
1. All identified bugs (23 test cases needed)
2. Security scenarios (token expiration, invalid inputs, etc.)
3. Race condition scenarios (parallel operations)
4. Edge cases (game boundaries, role distributions)
5. Persistence failures and recovery
6. Network failures and offline scenarios

---

## 9. CODE QUALITY OBSERVATIONS

### Good Practices Observed:
- ✅ SwiftUI MVVM architecture well-structured
- ✅ Single source of truth pattern (GameStore)
- ✅ Comprehensive unit tests started
- ✅ Clear separation of concerns
- ✅ Type-safe models with Codable
- ✅ Good documentation in CLAUDE.md files

### Areas for Improvement:
- Error handling strategy (silent failures)
- Input validation layer
- Logging and observability
- Concurrency management
- Secret management
- Test coverage

---

## 10. CONCLUSION

The Mafia Manager app has a solid architecture and follows good SwiftUI patterns. However, there are **critical security vulnerabilities** that need immediate attention, particularly around credential storage and token security.

The game logic is generally sound but has several edge cases that could lead to bugs or exploits. The two-phase night resolution system is a good design but needs guards against duplicate invocation.

**Estimated Fix Time:**
- Critical fixes: 4-8 hours
- High priority fixes: 2-3 days
- Medium priority fixes: 1 week
- Total: ~2 weeks for all issues

**Priority Roadmap:**
1. **Week 1**: Fix all CRITICAL and HIGH issues
2. **Week 2**: Address MEDIUM issues and improve tests
3. **Week 3**: Polish with LOW priority items and hardening

This audit provides a comprehensive baseline for improving the app's security posture and reliability. Regular security reviews should be conducted as the app evolves.

---

**Report Version**: 1.0
**Next Review**: Recommended after fixes implemented
