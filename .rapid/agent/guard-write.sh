#!/usr/bin/env bash
# rapid agent hook: PreToolUse(Write|Edit|NotebookEdit) guard for Claude Code. Denies any write under a protected
# .rapid/ (conf and admins excepted, and the project's own data: requirements, tests, version), and any
# write under rapid's state in the git common dir (rapid/, the rapid-close note): consumers
# change the canonical framework repo. The path is resolved (relative to cwd, symlinks, case) before the check, and
# the framework source repo is recognised only by the .rapid/rapid it tracks. The check
# lives in guard_destructive.py (protected()); without python3 or the module the write is refused.
here=$(cd "$(dirname "$0")" && pwd)
if ! command -v python3 >/dev/null 2>&1 || [ ! -f "$here/guard_destructive.py" ]; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"rapid guard: python3 or guard_destructive.py is missing, so the write was not checked and is refused; reinstall with 'rapid setup --agent'."}}'
  exit 0
fi
exec python3 "$here/guard_destructive.py" --write
