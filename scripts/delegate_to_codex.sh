#!/bin/bash

# delegate_to_codex.sh
# Helper script for Claude Code to delegate tasks to Codex Agent CLI
#
# Usage:
#   ./scripts/delegate_to_codex.sh "task description" [context_files...]
#
# Example:
#   ./scripts/delegate_to_codex.sh "Fix type errors in MultiplayerService" Core/Services/Multiplayer/MultiplayerService.swift

set -e

TASK="$1"
shift  # Remove first argument, rest are context files

if [ -z "$TASK" ]; then
    echo "Usage: $0 \"task description\" [context_files...]"
    exit 1
fi

# Build context string
CONTEXT=""
if [ $# -gt 0 ]; then
    CONTEXT="Context files to consider:\n"
    for file in "$@"; do
        if [ -f "$file" ]; then
            CONTEXT="${CONTEXT}- $file\n"
        fi
    done
fi

# Build the full prompt
PROMPT="$TASK

${CONTEXT}
Working directory: $(pwd)
Project: Mafia Manager iOS app (SwiftUI)

Please complete this task and provide a summary of changes made."

echo "🤖 Delegating to Codex Agent..."
echo "Task: $TASK"
echo ""

# Run codex in exec mode (non-interactive)
codex exec "$PROMPT"

echo ""
echo "✅ Codex Agent task completed"
