#!/bin/bash

# codex_analyze.sh
# Autonomous delegation script for Claude Code to call Codex Agent
# Returns structured output that Claude Code can parse and apply
#
# Usage:
#   ./scripts/codex_analyze.sh "task description" [context_files...]
#
# Output format:
#   Analysis, recommendations, and code snippets from Codex Agent

set -e

TASK="$1"
shift  # Remove first argument, rest are context files

if [ -z "$TASK" ]; then
    echo "ERROR: No task specified"
    exit 1
fi

# Build context string
CONTEXT_FILES=""
if [ $# -gt 0 ]; then
    CONTEXT_FILES="Context files:\n"
    for file in "$@"; do
        if [ -f "$file" ]; then
            CONTEXT_FILES="${CONTEXT_FILES}- $file\n"
        fi
    done
fi

# Build the prompt for Codex
# Instruct Codex to provide structured output that Claude Code can parse
PROMPT="$TASK

${CONTEXT_FILES}
Working directory: $(pwd)
Project: Mafia Manager iOS app (SwiftUI + MVVM)

IMPORTANT: Provide your response in a structured format:
1. ANALYSIS: Brief analysis of the task
2. SOLUTION: Step-by-step solution approach
3. CODE: Any code changes needed (with file paths and line numbers)
4. NOTES: Any important considerations

Be concise and specific. Focus on actionable recommendations."

# Run codex in exec mode and capture output
# Note: Codex may have MCP errors but these don't affect functionality
OUTPUT=$(/opt/homebrew/bin/codex --ask-for-approval never --sandbox read-only exec "$PROMPT" 2>&1 || true)

# Extract only the codex response (after "codex" line)
# Look for the response between markers
if echo "$OUTPUT" | grep -q "^codex$"; then
    # Extract from "codex" to "tokens used" (or end of output)
    echo "$OUTPUT" | sed -n '/^codex$/,/^tokens used$/p' | sed '1d;$d' | sed '/^tokens used$/d'
else
    # If no "codex" marker, likely an error - show relevant parts
    echo "$OUTPUT" | grep -v "^ERROR:" | grep -v "^OpenAI Codex" | grep -v "^---" | grep -v "^workdir:" | grep -v "^model:" | grep -v "^provider:" | grep -v "^approval:" | grep -v "^sandbox:" | grep -v "^reasoning" | grep -v "^session id:" | tail -20
fi

exit 0
