# Updated Security & Logic Issues List
## After README Review (2025-11-07)

Based on review of the updated README.md, here are the **22 verified issues**:

---

## 🔴 CRITICAL SECURITY ISSUES (3)

### CRITICAL-001: Hardcoded Supabase Credentials
**File**: `Core/Services/SupabaseConfig.swift:4-5`
- Anon key exposed in source code
- Permanently in git history
- **Action**: Rotate immediately, move to environment variables

### CRITICAL-002: Insecure Token Storage in UserDefaults
**File**: `Core/Store/AuthStore.swift:15-32`
- Auth tokens in unencrypted UserDefaults
- Extractable via backup/jailbreak
- **Action**: Migrate to iOS Keychain immediately

### CRITICAL-003: Missing Input Validation
**Files**: Multiple locations
- No validation on player names (length, special chars, newlines)
- No email format validation
- Risk of UI crashes, export corruption, injection attacks
- **Action**: Add comprehensive input validation layer

---

## 🟠 HIGH PRIORITY ISSUES (7)

### HIGH-001: Missing Rate Limiting on Authentication
**File**: `Core/Store/AuthStore.swift`
- No client-side rate limiting
- Vulnerable to brute force attacks
- **Fix**: Implement exponential backoff after failed attempts

### HIGH-002: Supabase RLS Bypass via Manual Token Injection
**File**: `Core/Services/DatabaseService.swift:9-10, 154-156`
- Manual `Authorization` header injection bypasses SDK security
- No token validation before use
- **Fix**: Validate tokens or fix underlying SDK issue properly

### HIGH-003: Number Range Doesn't Match Documentation
**File**: `Core/Store/GameStore.swift:55` vs `README.md:12`
- **README says**: "numbers are unique random values from 1–99"
- **Code does**: `Array(1...(count * 2))` → max range 1-38 for 19 players
- **Impact**: Documentation mismatch, potential UI/game design issues
- **Fix**: Either update code to use 1-99 range OR fix README to match implementation

### HIGH-004: Two-Phase Night Resolution Can Be Called Multiple Times
**File**: `Core/Store/GameStore.swift:306-326`
- `resolveNightOutcome()` has no guard against duplicate calls
- Line 309: `action.resultingDeaths.removeAll()` clears previous deaths
- **Impact**: Could resurrect dead players, inconsistent state
- **Proof of Concept**:
```swift
gameStore.resolveNightOutcome(targetWasSaved: false)  // Player dies
gameStore.resolveNightOutcome(targetWasSaved: true)   // Player revives! 🧟
```
- **Fix**: Add guard to check if night already resolved

### HIGH-005: Win Condition Needs Guard Against Re-evaluation
**File**: `Core/Store/GameStore.swift:398-421`
- `evaluateWinners()` called from both `resolveNightOutcome()` and `applyDayRemovals()`
- Note: Dual evaluation is **intentional** per code comments (line 414: "Optional: also end immediately after day")
- README says "Mafia >= Non-Mafia at day start" but code also checks after day removals
- **Issue**: No guard to prevent re-setting `isGameOver` if already true
- **Impact**: Could set game over state multiple times, potential navigation bugs
- **Fix**: Add `guard !state.isGameOver else { return }` at start of function

### HIGH-006: Custom Role Config Validation Missing
**File**: `Core/Store/GameStore.swift:62-75`
- No validation that custom roles sum correctly
- If config has 10 roles for 8 players → crash
- If config has 5 roles for 8 players → unexpected fallback to citizens
- **Fix**: Validate `totalCustomRoles <= count` before use

### HIGH-007: Auth State Restoration Race Condition
**File**: `Core/Store/AuthStore.swift:49-64`
- Session restoration in `init()` Task but app starts immediately
- Views render before `isAuthenticated` is set
- **Fix**: Add `@Published var isRestoringSession = true` and show loading state

---

## 🟡 MEDIUM PRIORITY ISSUES (8)

### MEDIUM-001: Kill Attribution Logic Flaw with Dead Mafia
**File**: `Core/Store/GameStore.swift:361-372`
- Uses snapshot of `night.mafiaNumbers` from night start
- Dead mafia still get credit for kills after they die
- **Test case**: Mafia dies on Day 1, still gets credit for Night 2 kill
- **Fix**: Add `aliveMafiaIDs: [UUID]` to `NightAction` struct

### MEDIUM-002: Inspector Check Returns Ambiguous Result
**File**: `Core/Store/GameStore.swift:266-272`
- When inspector checks another inspector, both result fields are `nil`
- Can't distinguish "no check" from "checked inspector"
- **Impact**: Poor UX, game master has no feedback
- **Fix**: Set `inspectorRole = .inspector` or add `wasInspectorBlocked` flag

### MEDIUM-003: Phase Transition Logic Fragile
**File**: `Core/Store/GameStore.swift:177-203`
- `transitionToNextRole()` checks if `inspectorCheckedPlayerID == nil`
- Ambiguous: Could mean "not acted" OR "chose to skip"
- **Fix**: Add explicit completion flags to `NightAction`

### MEDIUM-004: No Validation for Mafia Targeting Rules
**File**: `Core/Store/GameStore.swift:277-282`
- Silent failure if mafia targets mafia (defensive code but no error)
- UI has filter but can be bypassed programmatically
- **Fix**: Throw explicit errors instead of silent failure

### MEDIUM-005: Persistence Failures Are Silent
**File**: `Core/Services/Persistence.swift:24-34`
- All save errors swallowed without user notification
- User plays entire game thinking it's saved
- App crash → all progress lost
- **Fix**: Propagate errors and show user warnings

### MEDIUM-006: Token Expiration Not Handled
**File**: `Core/Services/DatabaseService.swift`
- Manual token injection doesn't check expiration
- Multi-step operations fail mid-way if token expires
- **Fix**: Check expiration and refresh before each operation

### MEDIUM-007: Persistence Race on Rapid State Changes
**File**: `Core/Store/GameStore.swift:98-100`
- Multiple rapid mutations could interleave writes
- Atomic write could fail with concurrent saves
- **Fix**: Add debouncing or use Actor for serialization

### MEDIUM-008: Silent Failures Throughout Codebase
**Files**: Multiple
- Persistence failures ignored (`Persistence.swift:30-33`)
- Auth profile loading failures ignored (`AuthStore.swift:124-126`)
- Cloud sync failures ignored per-player (`GameStore.swift:389-392`)
- **Fix**: Implement error state tracking and user notifications

---

## 🟢 LOW PRIORITY ISSUES (4)

### LOW-001: Potential Memory Leak with AuthStore Reference
**File**: `Core/Store/GameStore.swift:12, 21-23`
- GameStore holds strong reference to AuthStore
- Should be `weak var authStore: AuthStore?`
- Low impact since both are app-lifetime singletons

### LOW-002: No Retry Logic for Network Operations
**Files**: `AuthService.swift`, `DatabaseService.swift`
- All network operations fail immediately
- **Fix**: Add exponential backoff retry logic

### LOW-003: No Offline Detection
**Files**: Network service files
- App doesn't check network availability
- **Fix**: Use `NWPathMonitor` to track connectivity

### LOW-004: Missing Test Coverage for Edge Cases
**File**: `mafia_managerTests/GameStoreTests.swift`
- Tests don't cover edge cases identified in audit:
  - Double night resolution
  - Custom role validation
  - Phase transition edge cases
  - Kill attribution with dead mafia
  - Inspector checking inspector
- **Fix**: Add test cases for all identified bugs

---

## Summary of Changes from Original Audit

### New Finding:
- **HIGH-003**: Number range mismatch between README (1-99) and code (1-38 max)

### Clarifications:
- **HIGH-005**: Dual win evaluation is **intentional** design (not a bug), but still needs guard
- README confirms game logic understanding was correct:
  - 4 players: 1 Mafia, 1 Police, 2 Citizens ✓
  - Police cannot check other Police ✓
  - Doctor can protect self ✓
  - Mafia cannot target Mafia ✓

### Removed:
- Database constraints/indexes (were suggestions, not bugs)

---

## Priority Order (Top 10 to Fix First)

1. **CRITICAL-001**: Rotate Supabase credentials NOW
2. **CRITICAL-002**: Migrate tokens to Keychain
3. **CRITICAL-003**: Add input validation
4. **HIGH-003**: Fix number range (1-99 vs 1-38 mismatch)
5. **HIGH-004**: Prevent double night resolution
6. **HIGH-005**: Add guard to win evaluation
7. **HIGH-001**: Add auth rate limiting
8. **HIGH-006**: Validate custom role configs
9. **HIGH-007**: Fix auth restoration race
10. **MEDIUM-001**: Fix kill attribution logic

---

**Total Issues**: 22
- 🔴 Critical: 3
- 🟠 High: 7
- 🟡 Medium: 8
- 🟢 Low: 4

**Estimated Total Fix Time**: ~2 weeks
