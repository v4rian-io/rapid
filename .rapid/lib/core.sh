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
# rapid_series: the series a branch opened now belongs to (the next version without its last number).
rapid_series() {
  local v rel n
  read -r v rel <<<"$(rapid_version_last dev)"
  n=$(rapid_version_next "$v" "$rel" "$(rapid_year)")
  printf '%s' "${n%.*}"
}
# rapid_branch_name KIND NAME [NUMBER] [SERIES] -> pool/<series>/[<number>.]<kind>.<name>.
rapid_branch_name() { printf 'pool/%s/%s%s.%s' "${4:-$(rapid_series)}" "${3:+$3.}" "$1" "$2"; }

# Branch numbers. A branch is named pool/v<series>/<number>.<kind>.<name>: the number
# orders branches by creation and is never handed out twice, online or offline.
#   - it is n<N>, N one more than the highest number this clone knows of
#     (never below the count of merges on dev), the numbers of origin's
#     anchors included when origin answers;
#   - opening a branch never pushes: the number is carried by the branch's
#     safety anchor, written in this clone (one work tree at a time), and reaches
#     origin with that anchor in the push that carries the branch; a branch whose number
#     another clone published first takes the next free number at its land.
# The anchor is never deleted or moved and its commit date is the creation time:
# by number, then by that date, every branch ever started, landed or not,
# keeps its creation order. A landed merge carries its number in
# the Branch-Number: trailer.
RAPID_NUM_RE='n[0-9]+'
# rapid_branch_number REF: the number in REF's name (empty for an unnumbered branch).
rapid_branch_number() {
  local n="${1#refs/heads/}"; n="${n##*/}"
  case "$n" in *.*) n="${n%%.*}"; [[ "$n" =~ ^$RAPID_NUM_RE$ ]] && printf '%s' "$n" ;; esac
  return 0
}
# RAPID_POOL_NS: the ref namespace of branches.
RAPID_POOL_NS="refs/heads/pool"

rapid_kind_ok() { case " $RAPID_KINDS " in *" $1 "*) return 0 ;; esac; return 1; }
rapid_slug_ok() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]{1,47}$ ]]; }

# Safety anchors ("safety anchors stay forever"). Every branch keeps the commit
# it forked from for the life of the repository, on a branch,
# so forge rulesets cover it: refs/heads/safety/v<series>/<name> names an anchor
# commit whose only parent is the fork point and whose message, author and
# date record the branch and who started it when (a commit per branch, so two
# branches forked from one dev tip never share an anchor). rapid branch writes it,
# every push that carries the branch carries it (pre-push, land),
# and nothing deletes or moves it (pre-push, the agent guard, the
# rapid-safety-lockdown ruleset). A branch made by hand or before anchors existed
# gets one where it leaves dev when it is first pushed or landed.
RAPID_ZERO=0000000000000000000000000000000000000000
# rapid_anchor_ref REF -> refs/heads/safety/v<series>/<name> for pool/v<series>/<name>.
rapid_anchor_ref() {
  local r="${1#refs/heads/}"
  r="${r#pool/}"
  printf 'refs/heads/safety/%s' "$r"
}
# rapid_anchor_commit NAME FORK: a new anchor commit for v<series>/<name> on FORK (no ref written).
rapid_anchor_commit() {
  local fork; fork=$(git rev-parse "$2^{commit}")
  git commit-tree "$fork^{tree}" -p "$fork" -m "rapid branch $1: fork point $fork"
}
# rapid_anchor_make REF FORK [REMOTE]: write REF's anchor at FORK unless one
# exists; prints the anchor ref. With REMOTE,
# an anchor the remote already holds (a branch shared from another clone) is
# fetched instead of written.
rapid_anchor_make() {
  local ref name
  ref=$(rapid_anchor_ref "$1"); name="${ref#refs/heads/safety/}"
  if [ -n "${3:-}" ] && ! git rev-parse -q --verify "$ref" >/dev/null; then
    if [ -n "$(git ls-remote "$3" "$ref" 2>/dev/null || true)" ]; then
      git fetch -q --no-tags "$3" "$ref:$ref" 2>/dev/null || true
    fi
  fi
  if ! git rev-parse -q --verify "$ref" >/dev/null; then
    # create only: when another work tree wrote it a moment ago, that one stands
    git update-ref "$ref" "$(rapid_anchor_commit "$name" "$2")" "$RAPID_ZERO" 2>/dev/null || true
  fi
  printf '%s' "$ref"
}

# rapid_lock_lift PATH WHAT: every rapid lock holds its holder's pid (a file whose first word is
# it). 0 when PATH is free, or its holder is gone: the lock is then lifted and the lift logged in
# <git common dir>/rapid/log ("<UTC> lifted <lock>: holder pid <p> gone (<WHAT>, pid <self>)");
# 1 while the holder lives (busy). WHAT names the command that lifts.
rapid_lock_lift() {
  local p="$1" what="$2" pid=""
  [ -e "$p" ] || return 0
  read -r pid _ < "$p" 2>/dev/null || pid=""
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then return 1; fi
  # a lock with no pid yet is being written: busy, unless it is a minute old
  [ -n "$pid" ] || [ -n "$(find "$p" -mmin +1 2>/dev/null)" ] || return 1
  rm -f "$p"
  printf '%s lifted %s: holder pid %s gone (%s, pid %s)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${p##*/}" "${pid:-none}" "$what" "$$" \
    >> "$(git rev-parse --git-common-dir)/rapid/log" 2>/dev/null || true
}
