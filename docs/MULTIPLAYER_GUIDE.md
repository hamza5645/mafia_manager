# Multiplayer Mafia Manager - Setup & Implementation Guide

## Overview

This guide covers the complete multiplayer implementation for Mafia Manager, transforming the single-device pass-around game into a real-time online multiplayer experience where each player uses their own phone.

## Architecture Summary

### Three-Layer System

1. **Personal Layer** - What only I can see (my role, my night actions)
2. **Shared Layer** - What everyone can see (who's alive, day votes, announcements)
3. **Authority Layer** - Server-side truth (all roles, all actions, game resolution)

### Key Components

- **Database**: Supabase PostgreSQL with Realtime subscriptions
- **State Management**: MultiplayerGameStore coordinates all multiplayer state
- **Real-time Sync**: Supabase Realtime for WebSocket communication
- **Privacy**: Row Level Security (RLS) policies ensure role privacy

## Database Setup

### 1. Run the Multiplayer Schema

After setting up your Supabase project with `supabase/setup.sql`, run the multiplayer schema:

```bash
# In Supabase SQL Editor, run:
supabase/multiplayer_schema.sql
```

This creates:
- `game_sessions` - Multiplayer game rooms
- `session_players` - Players in each session
- `game_actions` - Night and day actions
- `phase_timers` - Phase countdown timers

### 2. Enable Realtime

In Supabase Dashboard → Database → Replication:
- Enable replication for: `game_sessions`, `session_players`, `game_actions`, `phase_timers`

Or via SQL (already in schema):
```sql
ALTER PUBLICATION supabase_realtime ADD TABLE public.game_sessions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.session_players;
ALTER PUBLICATION supabase_realtime ADD TABLE public.game_actions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.phase_timers;
```

## Game Flow

### 1. Session Creation

**Host creates a game:**
1. Navigate to: Game Mode Selection → Online Game → Create Game
2. Enter player name, set bot count, configure timers
3. Receive 6-character room code (e.g., "AB3K7M")
4. Wait in lobby for players to join

**Players join:**
1. Navigate to: Game Mode Selection → Online Game → Join Game
2. Enter room code and player name
3. Click ready when all players have joined

### 2. Role Assignment (Parallel)

- Host clicks "Start Game" when 4-19 players are ready
- Server assigns roles and numbers to all players
- Each player sees only their own role reveal
- Mafia members can see other mafia identities

### 3. Night Phase (Parallel)

**All roles act simultaneously:**
- **Mafia**: See teammates, coordinate target selection (60s default timer)
- **Doctor**: Choose player to protect
- **Inspector**: Choose player to investigate
- **Citizens**: Wait for morning

**Night resolution:**
- When all actions submitted OR timer expires
- Server processes: mafia target, doctor save, inspector result
- Transition to morning phase

### 4. Morning & Death Reveal

- All players see night results simultaneously
- Deaths announced
- Win conditions checked

### 5. Day Discussion & Voting (Parallel)

**Voting phase:**
- Private ballot: each player selects elimination target
- Timer runs (180s default)
- Server tallies votes when all submitted OR timer expires
- Results revealed simultaneously
- Ties = no elimination

### 6. Win Conditions

- **Citizens win**: All mafia eliminated
- **Mafia win**: Mafia ≥ Non-mafia alive

## Code Architecture

### Models (`Core/Models/Multiplayer/`)

```swift
GameSession      // Room state, settings, current phase
SessionPlayer    // Player info with privacy filters
GameAction       // Night/day actions
PhaseTimer       // Phase countdown timers
```

### Services (`Core/Services/Multiplayer/`)

```swift
SessionService   // CRUD operations for sessions/players
RealtimeService  // WebSocket subscriptions & presence
```

### Store (`Core/Store/`)

```swift
MultiplayerGameStore  // Coordinates multiplayer state
                      // Wraps GameStore logic
                      // Manages real-time sync
```

### Views (`Features/Multiplayer/`)

```swift
GameModeSelectionView    // Choose Local vs Online
MultiplayerMenuView      // Create or Join
CreateGameView           // Host setup
JoinGameView             // Enter room code
MultiplayerLobbyView     // Waiting room
MultiplayerNightView     // Parallel night actions
MultiplayerVotingView    // Private voting
```

## Privacy & Security

### Role Privacy

Implemented via:
1. **RLS Policies**: Database-level filtering
2. **Helper Function**: `get_visible_role()` determines what each player can see
3. **Client Filtering**: MultiplayerGameStore exposes only visible data

**Privacy Rules:**
- Players see only their own role
- Mafia see other mafia roles
- Host sees all roles (for debugging)
- Dead players see nothing new

### Row Level Security

All tables have RLS enabled:
```sql
-- Example: session_players
CREATE POLICY "Players can view players in their session"
ON public.session_players
FOR SELECT
USING (
    session_id IN (
        SELECT session_id FROM public.session_players
        WHERE user_id = auth.uid()
    )
);
```

## Real-time Synchronization

### Subscription Pattern

```swift
// Subscribe to session updates
try await realtimeService.subscribeToSession(
    sessionId: sessionId,
    onSessionUpdate: { session in
        // Update local session state
    },
    onPlayerUpdate: { player in
        // Update player list
    },
    onActionUpdate: { action in
        // Handle action confirmations
    }
)
```

### Heartbeat & Presence

- **Heartbeat**: Every 5 seconds, update `last_heartbeat`
- **Presence**: Supabase Realtime tracks online/offline status
- **Reconnection**: Players can rejoin with same role/state

## Bot Integration

### Server-Controlled Bots

- Host processes bot actions in `processBotActions(nightIndex:)`
- Uses existing `BotDecisionService` for targeting
- Bots auto-submit actions at phase start
- No client-side bot logic needed

## Timer System

### Phase Timers

```swift
PhaseTimer(
    sessionId: sessionId,
    phaseName: "night_1",
    durationSeconds: 60
)
```

**Auto-advance:**
- Timer expires → Host auto-submits missing actions
- Graceful handling of AFK players

## Migration from Local Mode

### Shared Game Logic

Both modes use same core game rules:
- Role distribution
- Win conditions
- Night resolution logic
- Voting mechanics

### Mode Selection

```swift
GameModeSelectionView
├── Local Mode → SetupView (existing)
└── Online Mode → MultiplayerMenuView (new)
```

## Testing Strategy

### Multi-Device Testing

**Using iOS Simulators:**
```bash
# Terminal 1: iPhone 17 Pro
xcrun simctl boot "iPhone 17 Pro"

# Terminal 2: iPhone 15
xcrun simctl boot "iPhone 15"

# Terminal 3: iPad Pro
xcrun simctl boot "iPad Pro (11-inch)"
```

**Test Flow:**
1. Device A: Create game → get room code
2. Device B: Join game → enter room code
3. Device C: Join game
4. Device A: Start game
5. All devices: Verify role reveal
6. All devices: Submit night actions
7. All devices: Vote
8. Verify state synchronization

### Key Test Scenarios

- [ ] Room creation and joining
- [ ] Role privacy (can't see others' roles)
- [ ] Mafia coordination (see teammates)
- [ ] Parallel night actions
- [ ] Timer expiration handling
- [ ] Disconnection/reconnection
- [ ] Bot auto-actions
- [ ] Private voting
- [ ] Win condition detection

## Common Issues & Solutions

### Issue: Players can see other players' roles

**Solution:** Check RLS policies and `get_visible_role()` function

### Issue: Realtime not working

**Solutions:**
1. Verify Realtime is enabled for tables
2. Check subscription channel matches session ID
3. Ensure auth token is valid

### Issue: Actions not syncing

**Solutions:**
1. Check `game_actions` table policies
2. Verify action type and phase index match
3. Check for unique constraint violations

### Issue: Timer not counting down

**Solution:** Ensure `timerUpdateTimer` is running in MultiplayerGameStore

## Future Enhancements

### Potential Additions

1. **Chat System**: In-game text chat for discussion phase
2. **Voice Integration**: WebRTC for voice discussion
3. **Spectator Mode**: Watch games in progress
4. **Custom Roles**: Dynamic role creation
5. **Game History**: Record and replay games
6. **Leaderboards**: Cross-game statistics
7. **Reconnection Queue**: Handle mid-game disconnects
8. **Host Migration**: Transfer host if they leave

## Performance Considerations

### Database Queries

- Indexed lookups on `session_id`, `user_id`, `room_code`
- Limit realtime subscriptions to current session only
- Batch player updates where possible

### Network Optimization

- Debounce heartbeat updates (5s interval)
- Use UPSERT for actions (update if exists)
- Minimize payload sizes in realtime events

### Client-Side Optimization

- Cache visible players locally
- Update UI only when state changes
- Unsubscribe from channels on leave

## API Reference

### SessionService

```swift
createSession(hostUserId:maxPlayers:botCount:) async throws -> GameSession
joinSession(roomCode:userId:playerName:) async throws -> (GameSession, SessionPlayer)
leaveSession(sessionId:userId:) async throws
getSessionPlayers(sessionId:) async throws -> [SessionPlayer]
assignRolesAndNumbers(sessionId:assignments:) async throws
submitAction(_:) async throws
```

### MultiplayerGameStore

```swift
createSession(playerName:botCount:nightTimerSeconds:dayTimerSeconds:) async throws
joinSession(roomCode:playerName:) async throws
leaveSession() async throws
startGame() async throws
submitNightAction(actionType:nightIndex:targetPlayerId:) async throws
submitVote(dayIndex:targetPlayerId:) async throws
toggleReady() async throws
```

## Support & Troubleshooting

For issues or questions:
1. Check Supabase logs in Dashboard → Logs
2. Verify RLS policies in Database → Policies
3. Test with direct SQL queries to isolate issues
4. Review realtime subscription events in browser console

## Conclusion

This multiplayer implementation maintains all the core Mafia game mechanics while enabling true simultaneous gameplay across devices. The privacy-first architecture ensures each player sees only what they should, while the host maintains control over game flow and timing.
