# Asking Claude Effectively (Token Budget Mode)

**ACTIVE GUARDRAILS** (enforced unless you override):

- **Never read more than 3 files per request** without confirmation
- **Never expand a file beyond 200 lines** without confirmation
- **Prefer grep/rg/sed -n** to preview slices before full reads
- **When pulling multiple files**, ask for explicit globs first

**Default constraints** (override explicitly if needed):

1. **File reads**: Max 3 files per request without confirmation
2. **Line limits**: Max 200 lines per file without confirmation
3. **Preview first**: Use `grep`/`rg`/`sed -n` to preview slices before full reads
4. **Glob patterns**: Ask me for explicit globs when pulling multiple files
5. **Summaries**: Prefer summaries over full dumps (tool output ≤200 lines)
6. **No mass scans**: Don't scan whole repo; read only files you must touch
7. **Focused queries**: "Show me X in file Y" beats "search everywhere for X"
8. **Use wrappers**: `cc_run` and `cc_read` (from `scripts/cc_env.sh`) for large commands
9. **Architecture questions**: Check `docs/ARCHITECTURE_NOTES.md` before asking
10. **Build/run questions**: Check `docs/CLAUDE_PRIMER.md` first

**Example good queries**:
- "Read only `GameStore.swift` lines 1-120, show me the role distribution logic"
- "Grep for 'endNight' in Core/Store/, summarize what you find"
- "What's the two-phase night resolution?" (answer: check ARCHITECTURE_NOTES)

**Example token-expensive queries** (avoid unless necessary):
- "Read all files in Features/"
- "Show me everything about authentication"
- "Search the entire codebase for X"
