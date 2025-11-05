#!/usr/bin/env bash
# Token-thrifty defaults for Claude Code sessions

export CC_MAX_CMD_LINES="${CC_MAX_CMD_LINES:-200}"

# Wrapper to limit command output to max lines
cc_run() {
  "$@" | stdbuf -o0 -e0 head -n "${CC_MAX_CMD_LINES}"
}

# Safe file reader with line limit
cc_read() {
  sed -n '1,'"${CC_MAX_CMD_LINES}"'p' "$@"
}

# Usage examples:
# cc_run xcodebuild clean
# cc_read path/to/large/file.txt
