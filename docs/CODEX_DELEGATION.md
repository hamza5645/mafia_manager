# Codex Agent Delegation Guide

This document explains when and how Claude Code should **autonomously delegate** tasks to Codex Agent (GPT-5.1 with high reasoning) to save tokens and leverage its advanced capabilities.

## Autonomous Delegation Philosophy

Claude Code should proactively delegate tasks to Codex Agent **without asking the user**. Codex GPT-5.1 with high reasoning is very capable and can handle complex tasks. The workflow:

1. **Claude Code decides** a task is suitable for delegation
2. **Delegates to Codex** using `./scripts/codex_analyze.sh`
3. **Receives recommendations** from Codex
4. **Applies changes** using Claude Code's file tools
5. **Reports results** to the user

The user should only see the final result, not the delegation happening behind the scenes.

## When to Delegate

Claude Code should consider delegating to Codex Agent in these scenarios:

### High Priority for Delegation
1. **Repetitive refactoring tasks** — Renaming variables across multiple files, updating import statements, fixing formatting
2. **Simple bug fixes with clear instructions** — Type errors, nil-safety issues, straightforward logic bugs
3. **Boilerplate generation** — Test scaffolding, protocol conformances, simple CRUD operations
4. **Low-context tasks** — Tasks that don't require deep understanding of game architecture patterns
5. **Token budget running low** — When approaching token limits and task is suitable for another agent

### Keep with Claude Code
1. **Architecture decisions** — Changes that affect GameStore pattern, two-phase night resolution, or core patterns
2. **Complex state management** — Mutations involving multiple phases, win conditions, or intricate game logic
3. **Supabase integration** — Database schema changes, realtime subscriptions, auth flows
4. **UI/UX decisions** — Design token usage, navigation patterns, privacy blur implementations
5. **Tasks requiring project context** — Anything that benefits from understanding docs/ARCHITECTURE_NOTES.md

## How to Delegate

### Option 1: Direct Bash Invocation
```bash
codex exec "Fix all type errors in Features/Multiplayer/MultiplayerLobbyView.swift"
```

### Option 2: Using Helper Script (Recommended)
```bash
./scripts/delegate_to_codex.sh "Task description" [context_files...]
```

**Example:**
```bash
./scripts/delegate_to_codex.sh \
  "Add missing @MainActor annotations to all View structs" \
  Features/Multiplayer/MultiplayerLobbyView.swift \
  Features/Multiplayer/CreateGameView.swift
```

### Option 3: Interactive Mode (Recommended for File Edits)
```bash
codex "Create unit tests for SeededRandom service following existing test patterns"
# This opens interactive mode where Codex Agent can make file edits
```

**Note:** Interactive mode is currently required for file modifications due to sandbox restrictions in exec mode (see Known Limitations below).

## Sandbox Limitation & Workaround

⚠️ **Current Issue:** Codex Agent's `exec` mode runs in read-only sandbox by default, preventing file modifications even with `--sandbox` flags. This appears to be a configuration or version-specific issue.

**Workarounds:**

1. **Use Interactive Mode (Recommended):**
   ```bash
   codex "Implement the multiply function in Calculator.swift"
   # Codex will open interactive session and can edit files
   ```

2. **Use for Analysis/Planning Only:**
   ```bash
   # Have Codex analyze and provide recommendations
   codex exec "Analyze GameStore.swift and suggest refactoring improvements"
   # Then apply changes yourself or delegate to Claude Code
   ```

3. **Apply Diffs Manually:**
   ```bash
   codex "Fix type errors in MultiplayerService"
   # After Codex generates plan, apply using `codex apply`
   ```

4. **Configure Sandbox (if possible):**
   - Check `~/.config/codex/config.toml` for sandbox overrides
   - Try: `codex --dangerously-bypass-approvals-and-sandbox exec "task"`
   - ⚠️ Only use in trusted, isolated environments

Until this is resolved, prefer **interactive mode** for file modifications or use Codex for **analysis/recommendations** only.

## Delegation Workflow

1. **Assess task complexity** — Can this be done without deep architecture knowledge?
2. **Prepare context** — Identify specific files Codex Agent should focus on
3. **Delegate with clear instructions** — Be specific about what needs to change
4. **Review changes** — Always verify Codex Agent's work before committing
5. **Document gotchas** — If Codex Agent struggles with something, document it here

## Example Delegations

### Good Delegations ✅
```bash
# Simple refactoring
codex exec "Rename variable 'gameID' to 'gameSessionID' in Core/Models/MultiplayerGame.swift"

# Boilerplate generation
./scripts/delegate_to_codex.sh "Add Equatable conformance to all Role enum cases"

# Formatting fixes
codex exec "Fix all SwiftLint warnings in Features/Multiplayer directory"
```

### Bad Delegations ❌
```bash
# Too architecture-heavy
codex exec "Refactor GameStore to support concurrent multiplayer games"

# Requires deep context
codex exec "Fix the two-phase night resolution to handle edge cases better"

# Supabase-specific
codex exec "Update realtime subscriptions to handle connection failures gracefully"
```

## Configuration

Codex Agent is pre-configured in your shell with:
- `--ask-for-approval never` (auto-approve actions)
- `--sandbox danger-full-access` (full system access)

These settings allow autonomous operation but mean you should:
1. **Review all changes** before committing
2. **Use git** to track and potentially revert changes
3. **Test thoroughly** after delegation

## Token Optimization Tips

When Claude Code is running low on tokens:
1. Batch simple tasks for Codex Agent delegation
2. Use Codex Agent for exploration of unfamiliar code areas
3. Have Codex Agent generate summaries of large files
4. Delegate test writing after Claude Code designs the test cases

## Known Limitations

- **Read-only sandbox in exec mode** — File modifications don't work in `codex exec` mode; use interactive mode instead
- **No access to Claude Code's project knowledge** — Codex Agent doesn't know about CLAUDE.md, ARCHITECTURE_NOTES.md, or project-specific patterns
- **Different code style** — May not follow your established patterns; review carefully
- **No awareness of previous session context** — Each delegation is fresh; provide full context
- **MCP server timeouts** — May see errors about Supabase/XcodeBuildMCP timeouts; these don't affect core functionality

## Emergency Fallback

If Claude Code hits token limits mid-task:
```bash
# Hand off entire remaining task to Codex Agent
codex "Continue the work Claude Code started on [describe task].
Current state: [describe what's done].
Remaining work: [describe what's left].
See git status for current changes."
```

## Updates & Improvements

- **Last updated:** 2025-11-16
- **Codex Agent version:** Run `codex --version` to check
- **Claude Code integration:** First implementation

### Future Enhancements
- [ ] Create slash command for quick delegation (e.g., `/delegate "task"`)
- [ ] Add pre-commit hook to review delegated changes
- [ ] Build task routing logic (auto-delegate simple tasks)
- [ ] Integration tests between Claude Code and Codex Agent workflows
