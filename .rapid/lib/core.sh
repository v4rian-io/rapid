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
rapid_warn() { printf '! rapid: %s\n' "$*" >&2; }

# rapid_dev_root REV: the commit rapid's history starts at on REV's first-parent line: the
# oldest "[NEW] Seed the rapid workflow" commit there (a repository that held commits before its
# first setup keeps them below its seed, outside every check), else the first commit.
rapid_dev_root() {
  git log --first-parent --format='%H %s' "$1" \
    | awk '{ l = $1 } substr($0, 42) == "[NEW] Seed the rapid workflow" { s = $1 } END { print (s != "" ? s : l) }'
}

# rapid_root: the work tree root of the repository the caller stands in.
rapid_root() { git rev-parse --show-toplevel 2>/dev/null || rapid_die "not inside a git repository"; }

# rapid_ns: the .rapid directory of that repository.
rapid_ns() { printf '%s/.rapid' "$(rapid_root)"; }

# rapid_conf KEY [DEFAULT]: one value from .rapid/conf (key=value, spaces
# around = ignored). With RAPID_CONF_REV set, the conf committed at that
# revision is read instead of the work tree's, so land applies dev's policy
# and a branch can never relax its own gates. A key set twice is an error, so
# a merge residue never changes policy silently.
rapid_conf_text() {
  if [ -n "${RAPID_CONF_REV:-}" ]; then
    git show "$RAPID_CONF_REV:.rapid/conf" 2>/dev/null || true
  elif [ -f "$(rapid_ns)/conf" ]; then
    cat "$(rapid_ns)/conf"
  fi
}
rapid_conf() {
  local key="$1" def="${2-}" text n v
  text=$(rapid_conf_text)
  n=$(grep -cE "^[[:space:]]*${key}[[:space:]]*=" <<<"$text" || true)
  case "$n" in
    0) printf '%s' "$def"; return 0 ;;
    1) ;;
    *) RAPID_RC=2 rapid_die "conf sets $key more than once; keep one line" ;;
  esac
  v=$(sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" <<<"$text" | sed -E 's/[[:space:]]+$//')
  if [ -z "$v" ]; then printf '%s' "$def"; else printf '%s' "$v"; fi
}

# rapid_has_remote: 0 when an origin remote is configured.
rapid_has_remote() { git remote get-url origin >/dev/null 2>&1; }

# rapid_branch: the current branch name, empty when detached. A git that cannot
# answer is not a detached HEAD: its own error stands and the caller stops.
rapid_branch() { git symbolic-ref --short -q HEAD || [ $? = 1 ]; }

# rapid_tmpdir NAME: a private temp directory honouring TMPDIR.
rapid_tmpdir() { mktemp -d "${TMPDIR:-/tmp}/rapid-$1.XXXXXX"; }
