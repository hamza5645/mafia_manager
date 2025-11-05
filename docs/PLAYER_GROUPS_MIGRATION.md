# Player Groups Migration Guide

## Overview

Player Groups is a new feature that allows users to save groups of player names for quick game setup. This feature is similar to Custom Roles but focuses on saving player names instead of role distributions.

## Database Migration Required

**IMPORTANT**: You must run the new migration SQL before using this feature.

### Migration Steps

1. Open your Supabase project SQL Editor
2. Run the following SQL (or run the updated `supabase/setup.sql` if starting fresh):

```sql
-- Player Groups table: Saved groups of player names
CREATE TABLE IF NOT EXISTS public.player_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    group_name TEXT NOT NULL,
    player_names JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    UNIQUE(user_id, group_name)
);

-- Enable Row Level Security
ALTER TABLE public.player_groups ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view their own player groups"
ON public.player_groups
FOR SELECT
USING (user_id = auth.uid());

CREATE POLICY "Users can insert their own player groups"
ON public.player_groups
FOR INSERT
WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update their own player groups"
ON public.player_groups
FOR UPDATE
USING (user_id = auth.uid());

CREATE POLICY "Users can delete their own player groups"
ON public.player_groups
FOR DELETE
USING (user_id = auth.uid());
```

## New Files Created

### Models
- `Core/Models/PlayerGroup.swift` - Data model for player groups

### Views
- `Features/Stats/PlayerGroupsView.swift` - UI for managing player groups
  - `PlayerGroupsView` - Main list view
  - `EmptyPlayerGroupsView` - Empty state
  - `PlayerGroupCard` - Individual group card
  - `AddPlayerGroupView` - Create new group sheet

### Database
- Updated `Core/Services/DatabaseService.swift` with player group CRUD methods:
  - `getPlayerGroups(userId:)`
  - `getPlayerGroup(id:)`
  - `createPlayerGroup(_:)`
  - `updatePlayerGroup(_:)`
  - `deletePlayerGroup(id:)`

### Modified Files
- `Features/Setup/SetupView.swift` - Added "Load Player Group" button and sheet
  - `LoadPlayerGroupSheet` - Sheet to select a saved group
- `Features/Settings/SettingsView.swift` - Added navigation link to Player Groups
- `supabase/setup.sql` - Added player_groups table and policies

## Features

### 1. Create Player Groups
- Navigate to Settings → Player Groups (requires login)
- Tap "+" to create a new group
- Enter a group name (e.g., "Usual Squad")
- Add 4-19 player names
- Names must be unique within the group
- Save to cloud (Supabase)

### 2. View Saved Groups
- List displays all saved groups
- Shows group name and player count
- Expandable to see all player names
- Pull to refresh

### 3. Load Groups in Setup
- In SetupView, tap "Load Player Group" (only shown when authenticated)
- Select a saved group from the list
- Player names are loaded into the setup fields
- Ready to assign roles

### 4. Delete Groups
- Swipe or tap trash icon on any group card
- Confirmation dialog prevents accidental deletion
- Permanent deletion from Supabase

## User Flow

```
1. User logs in
2. Navigate to Settings → Player Groups
3. Create a new group with player names
4. Save to cloud
5. Return to Setup screen
6. Tap "Load Player Group"
7. Select group
8. Names populate automatically
9. Assign roles and start game
```

## Technical Details

### Data Model
```swift
struct PlayerGroup: Codable, Identifiable, Sendable {
    let id: UUID
    let userId: UUID
    var groupName: String
    var playerNames: [String]
    let createdAt: Date
    var updatedAt: Date
}
```

### Database Schema
- **Table**: `player_groups`
- **Storage**: Player names stored as JSONB array
- **Constraints**: Unique constraint on `(user_id, group_name)` prevents duplicate group names per user
- **RLS**: Full row-level security ensuring users only access their own groups
- **Cascading**: `ON DELETE CASCADE` on `user_id` automatically deletes groups when user is deleted

### Validation
- Group name: Cannot be empty
- Player count: Must be 4-19 players
- Uniqueness: Player names must be unique (case-insensitive)
- Trimming: Whitespace is trimmed from all inputs

## Benefits

1. **Quick Setup**: No need to re-enter regular player names
2. **Multiple Groups**: Save different groups for different occasions (e.g., "Work Friends", "Family", "Tournament Squad")
3. **Cloud Sync**: Groups sync across devices via Supabase
4. **Error Prevention**: Pre-validated player lists reduce setup mistakes
5. **Flexibility**: Can still edit loaded names before assigning roles

## UI/UX Considerations

- **Login Required**: Feature only available when authenticated (similar to Custom Roles)
- **Empty State**: Helpful message when no groups exist
- **Visual Consistency**: Matches Custom Roles design patterns
- **Animations**: Smooth transitions when loading groups
- **Feedback**: Loading states and error handling throughout

## Future Enhancements (Optional)

- Export/import groups as JSON
- Share groups with other users
- Auto-suggest player names based on stats
- Quick edit groups from setup screen
- Duplicate group feature
- Recently used groups
- Favorite/pin specific groups

## Testing Checklist

- [ ] Create a new player group
- [ ] Load a player group in SetupView
- [ ] Delete a player group
- [ ] Verify unique group names per user
- [ ] Test with exactly 4 players
- [ ] Test with 19 players
- [ ] Test duplicate name validation
- [ ] Test loading groups when offline
- [ ] Test RLS policies (user can't see other users' groups)
- [ ] Test cascade deletion when user is deleted

## Rollback Plan

If issues arise, you can safely remove the feature:

```sql
-- Drop the table (this will delete all player groups)
DROP TABLE IF EXISTS public.player_groups CASCADE;
```

Then remove the new files and revert modified files to their previous versions.
