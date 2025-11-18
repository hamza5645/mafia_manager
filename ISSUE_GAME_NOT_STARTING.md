# ISSUE: Game Not Starting After Lobby

## Status: CRITICAL BUG
**Severity**: Critical - Blocks all gameplay  
**Date Reported**: 2025-11-18  
**Affects**: All multiplayer games  

---

## Problem Description

After creating a room, joining with a second player, and the host clicking "Start Game", the app **remains stuck on the lobby screen**. The game phase changes in the database (from "lobby" to "role_reveal"), roles are assigned, but **no navigation occurs**.

---

## Root Cause

**Missing navigation logic in `MultiplayerLobbyView.swift`**

### What Happens:
1. ✅ Host clicks "Start Game" button in `MultiplayerLobbyView`
2. ✅ `MultiplayerGameStore.startGame()` is called successfully
3. ✅ Roles and numbers are assigned via `sessionService.assignRolesAndNumbers()`
4. ✅ Session status updated to `.inProgress`
5. ✅ Phase updated to `"role_reveal"` with `.roleReveal(currentPlayerIndex: 0)` data
6. ✅ Local state refreshed via `refreshPlayers()`
7. ❌ **NO NAVIGATION OCCURS** - app stays on `MultiplayerLobbyView`

### Why It Fails:
```swift
// MultiplayerLobbyView.swift line 204-205
try await multiplayerStore.startGame()
// Game has started - navigation will be handled by phase updates
```

**The comment is misleading** - there is NO code that handles navigation based on phase updates!

`MultiplayerLobbyView` has:
- ❌ No `.navigationDestination()` watching `currentSession.currentPhase`
- ❌ No `@State` variable triggering navigation on phase change
- ❌ No view switcher based on `currentSession.currentPhaseData`

The phase changes in the database and `MultiplayerGameStore.currentSession`, but the UI has no way to react to this change and navigate to the appropriate screen.

---

## Expected Behavior

When `startGame()` completes successfully:
1. Phase changes to `"role_reveal"`
2. App should navigate from `MultiplayerLobbyView` → Role Reveal View
3. Players see their assigned roles one by one
4. After all roles revealed → Navigate to Night Phase View
5. Continue through game phases based on `currentSession.currentPhase`

---

## Current Behavior

1. Phase changes to `"role_reveal"` in database ✅
2. App stays on `MultiplayerLobbyView` forever ❌
3. Players see room code and player list but cannot proceed ❌
4. "Start Game" button remains visible (shouldn't be after starting) ❌

---

## Architecture Analysis

### Phase Flow (from GameSession.swift)
```swift
enum PhaseData: Codable {
    case lobby
    case roleReveal(currentPlayerIndex: Int)
    case night(nightIndex: Int, activeRole: String?)
    case morning(nightIndex: Int)
    case deathReveal(nightIndex: Int)
    case voting(dayIndex: Int)
    case gameOver(winner: String?)
}
```

### What Exists:
- ✅ **MultiplayerNightView**: Handles `.night` phase (checks `currentPhaseData` on line 11)
- ✅ **MultiplayerVotingView**: Handles `.voting` phase (checks `currentPhaseData` on line 11)  
- ❌ **Role Reveal View**: Does NOT exist for multiplayer!
- ❌ **Phase Router**: No parent view that switches between phase views!

### Navigation Chain Issues:
```
GameModeSelectionView
  └─> MultiplayerMenuView (creates MultiplayerGameStore)
       └─> CreateGameView (.sheet, navigationDestination to lobby) ✅
            └─> MultiplayerLobbyView (NO navigationDestination for phases!) ❌
```

The navigation ends at `MultiplayerLobbyView` - there's nowhere to go from there!

---

## Solution Required

### Option 1: Add Phase Router in MultiplayerLobbyView (Recommended)

```swift
// Add to MultiplayerLobbyView.swift
var body: some View {
    Group {
        if let session = multiplayerStore.currentSession {
            switch session.currentPhaseData {
            case .lobby:
                // Show lobby UI (existing code)
                lobbyContent
            case .roleReveal(let currentPlayerIndex):
                MultiplayerRoleRevealView(currentPlayerIndex: currentPlayerIndex)
            case .night:
                MultiplayerNightView()
            case .voting:
                MultiplayerVotingView()
            case .gameOver:
                GameOverView()
            default:
                // Handle other phases (morning, death reveal)
                Text("Phase: \(session.currentPhase)")
            }
        }
    }
}

private var lobbyContent: some View {
    // Move existing ScrollView/VStack code here
}
```

### Option 2: Create MultiplayerGameCoordinator View

```swift
// New file: MultiplayerGameCoordinator.swift
struct MultiplayerGameCoordinator: View {
    @EnvironmentObject private var multiplayerStore: MultiplayerGameStore
    
    var body: some View {
        Group {
            if let phaseData = multiplayerStore.currentSession?.currentPhaseData {
                switch phaseData {
                case .lobby:
                    MultiplayerLobbyView()
                case .roleReveal(let index):
                    MultiplayerRoleRevealView(currentIndex: index)
                case .night(let nightIndex, let activeRole):
                    MultiplayerNightView()
                case .morning(let nightIndex):
                    MultiplayerMorningView(nightIndex: nightIndex)
                case .deathReveal(let nightIndex):
                    MultiplayerDeathRevealView(nightIndex: nightIndex)
                case .voting(let dayIndex):
                    MultiplayerVotingView()
                case .gameOver(let winner):
                    GameOverView()
                }
            } else {
                ProgressView()
            }
        }
        .animation(.default, value: multiplayerStore.currentSession?.currentPhaseData)
    }
}

// Update CreateGameView & JoinGameView:
.navigationDestination(isPresented: $showingLobby) {
    MultiplayerGameCoordinator()  // Instead of MultiplayerLobbyView()
        .environmentObject(multiplayerStore)
        .environmentObject(authStore)
}
```

---

## Missing Views That Need To Be Created

1. **MultiplayerRoleRevealView**
   - Show "You are [Role]" with number
   - If mafia, show teammates
   - Button to mark "Seen" 
   - When all players seen, host advances to night phase

2. **MultiplayerMorningView** (optional, can skip to death reveal)
   - Show morning message
   - Auto-advance after timer

3. **MultiplayerDeathRevealView**
   - Show who died overnight
   - Display if doctor saved anyone
   - Display inspector results (private to inspector)
   - Auto-advance after timer

4. **MultiplayerGameOverView** (can reuse existing GameOverView)
   - Show winner and stats

---

## Code Changes Required

### 1. Create MultiplayerRoleRevealView.swift
```swift
import SwiftUI

struct MultiplayerRoleRevealView: View {
    @EnvironmentObject private var multiplayerStore: MultiplayerGameStore
    let currentPlayerIndex: Int
    
    @State private var hasSeen = false
    
    var body: some View {
        VStack(spacing: 32) {
            if let myRole = multiplayerStore.myRole,
               let myNumber = multiplayerStore.myNumber {
                
                // Role Icon
                Image(systemName: myRole.symbolName)
                    .font(.system(size: 100))
                    .foregroundStyle(myRole.accentColor)
                
                // Role Name
                Text("You are")
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Colors.textSecondary)
                
                Text(myRole.displayName.uppercased())
                    .font(Design.Typography.largeTitle)
                    .foregroundStyle(myRole.accentColor)
                
                // Number
                Text("Number: \(myNumber)")
                    .font(Design.Typography.title2)
                    .foregroundStyle(Design.Colors.textPrimary)
                
                // Mafia teammates (if applicable)
                if myRole == .mafia && !multiplayerStore.mafiaTeammates.isEmpty {
                    VStack(spacing: 12) {
                        Text("Your teammates:")
                            .font(Design.Typography.body)
                            .foregroundStyle(Design.Colors.textSecondary)
                        
                        ForEach(multiplayerStore.mafiaTeammates) { teammate in
                            Text("\(teammate.playerName) (#\(teammate.playerNumber ?? 0))")
                                .font(Design.Typography.body)
                                .foregroundStyle(Design.Colors.mafiaRed)
                        }
                    }
                }
                
                // Confirm Button
                Button {
                    markAsSeen()
                } label: {
                    Text(hasSeen ? "Waiting for others..." : "I've Seen My Role")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(hasSeen ? Design.Colors.textSecondary : Design.Colors.brandGold)
                        .foregroundColor(Design.Colors.surface0)
                        .cornerRadius(Design.Radii.medium)
                }
                .disabled(hasSeen)
                .padding(.horizontal, 20)
            }
        }
    }
    
    private func markAsSeen() {
        hasSeen = true
        Task {
            // Update player ready status or phase progress
            try? await multiplayerStore.markRoleAsSeen()
        }
    }
}
```

### 2. Add markRoleAsSeen() to MultiplayerGameStore.swift
```swift
// Add this method to MultiplayerGameStore
func markRoleAsSeen() async throws {
    guard let playerId = myPlayer?.id else { return }
    
    // Mark player as having seen their role
    try await sessionService.updatePlayerReady(playerId: playerId, isReady: true)
    
    // If all players have seen, host advances phase
    if isHost {
        let allReady = allPlayers.allSatisfy { $0.isReady }
        if allReady {
            // Advance to night phase
            guard let session = currentSession else { return }
            try await sessionService.updateSessionPhase(
                sessionId: session.id,
                currentPhase: "night",
                phaseData: .night(nightIndex: 0, activeRole: nil)
            )
        }
    }
}
```

### 3. Modify MultiplayerLobbyView.swift

**Replace entire `body` property:**

```swift
var body: some View {
    ZStack {
        Design.Colors.surface0.ignoresSafeArea()
        
        // Phase-based routing
        if let session = multiplayerStore.currentSession {
            switch session.currentPhaseData {
            case .lobby, .none:
                lobbyContent  // Existing lobby UI
                
            case .roleReveal(let index):
                MultiplayerRoleRevealView(currentPlayerIndex: index)
                    .navigationBarBackButtonHidden(true)
                
            case .night:
                MultiplayerNightView()
                    .navigationBarBackButtonHidden(true)
                
            case .voting:
                MultiplayerVotingView()
                    .navigationBarBackButtonHidden(true)
                
            case .gameOver:
                GameOverView()
                    .navigationBarBackButtonHidden(true)
                
            default:
                Text("Phase: \(session.currentPhase)")
                    .foregroundStyle(Design.Colors.textPrimary)
            }
        } else {
            ProgressView()
        }
    }
    .navigationBarBackButtonHidden(true)
    .confirmationDialog("Leave Game", isPresented: $showingLeaveConfirmation) {
        Button("Leave", role: .destructive) {
            leaveGame()
        }
        Button("Cancel", role: .cancel) {}
    } message: {
        Text("Are you sure you want to leave this game?")
    }
}

private var lobbyContent: some View {
    // Move existing ScrollView code here (lines 16-176)
    ScrollView {
        VStack(spacing: 24) {
            // ... existing lobby UI code ...
        }
    }
}
```

---

## Testing Plan

After implementing the fix:

1. **Create Room**: Host creates room ✓ (already working)
2. **Join Room**: Player 2 joins ✓ (already working)  
3. **Start Game**: Host clicks "Start Game"
4. **✅ Expected**: Both devices navigate to MultiplayerRoleRevealView
5. **✅ Expected**: Each player sees their role and number
6. **✅ Expected**: Mafia members see their teammates
7. **Mark Seen**: Players click "I've Seen My Role"
8. **✅ Expected**: When all ready, advance to MultiplayerNightView
9. **Continue**: Test full game flow through all phases

---

## Immediate Action Required

**Priority 1**: Implement Option 1 (Phase Router in MultiplayerLobbyView)
- ✅ Simpler, fewer file changes
- ✅ Keeps navigation logic in one place
- ✅ Easier to test

**Priority 2**: Create MultiplayerRoleRevealView
- Required for game to progress past lobby
- Relatively simple view

**Priority 3**: Test with 2 simulators
- Verify navigation occurs on both devices
- Verify phase synchronization via realtime updates

---

## Related Issues

- **Missing Views**: Morning, Death Reveal views also need to be created
- **Phase Transitions**: Need to implement full phase progression logic
- **Bot Actions**: Host needs to auto-submit actions for bots during night/voting
- **Timers**: Phase timers need to be displayed and enforced

---

## Files To Modify

1. `Features/Multiplayer/MultiplayerLobbyView.swift` - Add phase routing
2. `Features/Multiplayer/MultiplayerRoleRevealView.swift` - CREATE NEW
3. `Core/Store/MultiplayerGameStore.swift` - Add `markRoleAsSeen()`

---

## Estimated Fix Time

- **Quick Fix** (bare minimum): 30 minutes
  - Add basic phase routing in MultiplayerLobbyView
  - Create minimal MultiplayerRoleRevealView
  
- **Complete Fix** (proper implementation): 2-3 hours
  - Full phase routing with animations
  - All missing views (Role Reveal, Morning, Death Reveal)
  - Proper phase transition logic
  - Testing on 2 simulators

---

## Conclusion

The multiplayer architecture is **90% complete** - database, real-time sync, role assignment all work perfectly. The only missing piece is **navigation between phases**. This is a straightforward fix that unblocks all multiplayer gameplay.

Once this navigation is implemented, the full multiplayer flow will work end-to-end.
