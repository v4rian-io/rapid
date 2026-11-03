# shellcheck shell=bash
# core.sh - shared helpers for every rapid verb. Sourced, never executed.
# Bash 3.2 compatible; callers run under set -euo pipefail.

RAPID_KINDS="feature fix r&d refactor docs test"
RAPID_PROTECTED="dev main"
# the requirement a new branch starts with; land refuses it until it is replaced
RAPID_REQ_PLACEHOLDER="State the requirement this branch meets, and how its tests verify it."

# Requirement files live at .rapid/requirements/<name>.md (rapid keeps to .rapid/).
RAPID_REQ_DIR=.rapid/requirements

rapid_die() { printf 'X rapid: %s\n' "$*" >&2; exit "${RAPID_RC:-1}"; }
rapid_info() { printf '%s\n' "$*"; }

# rapid_root: the work tree root of the repository the caller stands in.
rapid_root() { git rev-parse --show-toplevel 2>/dev/null || rapid_die "not inside a git repository"; }

# rapid_has_remote: 0 when an origin remote is configured.
rapid_has_remote() { git remote get-url origin >/dev/null 2>&1; }

# rapid_branch: the current branch name, empty when detached. A git that cannot
# answer is not a detached HEAD: its own error stands and the caller stops.
rapid_branch() { git symbolic-ref --short -q HEAD || [ $? = 1 ]; }
