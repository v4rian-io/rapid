# shellcheck shell=bash
# core.sh - shared helpers for every rapid verb. Sourced, never executed.
# Bash 3.2 compatible; callers run under set -euo pipefail.

RAPID_KINDS="feature fix r&d refactor docs test"
RAPID_PROTECTED="dev main"
# the requirement a new branch starts with; land refuses it until it is replaced
RAPID_REQ_PLACEHOLDER="State the requirement this branch meets, and how its tests verify it."

# Requirement files live at .rapid/requirements/<name>.md (rapid keeps to .rapid/).
RAPID_REQ_DIR=.rapid/requirements
# rapid_req_path REV NAME: the path of NAME's requirement file in REV (REV empty: the index);
# returns 1, printing nothing, when REV holds none.
rapid_req_path() {
  local p="$RAPID_REQ_DIR/$2.md"
  if git cat-file -e "$1:$p" 2>/dev/null; then printf '%s' "$p"; return 0; fi
  return 1
}

# Named rules, every one on from the first merge.
RAPID_RULES="red-test commit-audit commit-body branch-number no-coauthor"
# rapid_rule_on NAME: 0 when rule NAME applies here.
rapid_rule_on() { case " $RAPID_RULES " in *" $1 "*) return 0 ;; esac; return 1; }

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

# rapid_progress DIR TOTAL PREFIX TEXT: one live line on stderr, "<PREFIX>[n/TOTAL] TEXT". n counts
# the calls made on DIR exactly, under a lock, whatever order concurrent workers end in.
rapid_progress() {
  local d="$1" total="$2" pre="$3" text="$4" n i=0
  until mkdir "$d/.progress.lock" 2>/dev/null; do i=$((i + 1)); [ "$i" -lt 200 ] || break; sleep 0.05; done
  n=$(( $(cat "$d/.progress" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$d/.progress"
  rmdir "$d/.progress.lock" 2>/dev/null || true
  printf '%s[%s/%s] %s\n' "$pre" "$n" "$total" "$text" >&2
}

# rapid_private_wt NAME REV: a private detached work tree at REV in a new temp
# directory; prints its path, rc 1 when it cannot be made. Every caller then
# runs git -C on that path, so it must be a real work tree of its own: an
# empty path (mktemp failed, as when the temp directory is swept under a
# full disk), or a GIT_DIR exported by git to a hook, would make git -C act
# on the caller's own work tree, detaching its branch and checking out other
# commits over it.
rapid_private_wt() {
  local d
  d=$(rapid_tmpdir "$1" 2>/dev/null) && [ -n "$d" ] && [ -d "$d" ] || return 1
  git worktree add -q --detach "$d" "$2" >/dev/null 2>&1 || { rmdir "$d" 2>/dev/null || true; return 1; }
  [ "$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" = "$(cd "$d" && pwd -P)" ] || return 1
  # and git there uses that work tree's own git dir, not one GIT_DIR forces on it
  [ "$(git -C "$d" rev-parse --absolute-git-dir 2>/dev/null)" != "$(git rev-parse --absolute-git-dir 2>/dev/null)" ] || return 1
  # a heartbeat while rapid runs: the tree's root is touched every RAPID_BUSY_EVERY
  # seconds (default 240), so a sweeper that wipes work trees idle for an hour
  # (a gate running long under load writes nothing there) sees it in use. It looks
  # every two seconds whether the tree and rapid are still there, so it ends with
  # them: a heartbeat asleep for minutes after its tree is gone is a process too
  # many when hundreds of trees come and go, and a full process table fails forks
  ( hb=0; he="${RAPID_BUSY_EVERY:-240}"
    while [ -d "$d" ] && kill -0 $$ 2>/dev/null; do
      [ "$hb" -gt 0 ] && [ $((hb % he)) -ge 2 ] || touch "$d" 2>/dev/null || true
      sleep 2; hb=$((hb + 2))
    done ) >/dev/null 2>&1 &
  printf '%s' "$d"
}

# rapid_clone_id: this clone's private random id (in the git dir, never pushed).
# land's close note carries it, so pre-push trusts only notes this clone wrote.
rapid_clone_id() {
  local f; f="$(git rev-parse --git-common-dir)/rapid-clone-id"
  [ -s "$f" ] || od -An -N8 -tx1 /dev/urandom | tr -d ' \n' > "$f"
  cat "$f"
}

# A branch is the branch pool/v<year>.<series>/<number>.<kind>.<name>:
# the series is the one the branch opened in, the number orders branches by
# creation. A branch made by hand may come without a number
# (pool/v<year>.<series>/<kind>.<name>); it takes one when it lands.
RAPID_SERIES_RE='v[0-9]{4}\.[0-9]+'
# rapid_branch_parse REF -> "kind name" for a branch; fails for any other name.
rapid_branch_parse() {
  local r="${1#refs/heads/}" v rest k s
  case "$r" in
    pool/*/*) ;;
    *) return 1 ;;
  esac
  v=$(printf '%s' "$r" | cut -d/ -f2); rest=$(printf '%s' "$r" | cut -d/ -f3-)
  [[ "$v" =~ ^$RAPID_SERIES_RE$ ]] || return 1
  if [[ "$rest" =~ ^($RAPID_NUM_RE)\.([a-z]+)\.([a-z0-9-]+)$ ]]; then k="${BASH_REMATCH[2]}"; s="${BASH_REMATCH[3]}"
  elif [[ "$rest" =~ ^([a-z]+)\.([a-z0-9-]+)$ ]]; then k="${BASH_REMATCH[1]}"; s="${BASH_REMATCH[2]}"
  else return 1; fi
  rapid_kind_ok "$k" && rapid_slug_ok "$s" || return 1
  printf '%s %s\n' "$k" "$s"
}
# rapid_series: the series a branch opened now belongs to (the next version without its last number).
rapid_series() {
  local v rel n
  read -r v rel <<<"$(rapid_version_last dev)"
  n=$(rapid_version_next "$v" "$rel" "$(rapid_year)")
  printf '%s' "${n%.*}"
}
# rapid_branch_name KIND NAME [NUMBER] [SERIES] -> pool/<series>/[<number>.]<kind>.<name>.
rapid_branch_name() { printf 'pool/%s/%s%s.%s' "${4:-$(rapid_series)}" "${3:+$3.}" "$1" "$2"; }
# rapid_subject_branch SUBJECT: the branch a land's merge subject names
# ("[MERGE] pool/v<series>/<number>.<kind>.<name> into dev: <version>"); empty for any other subject.
rapid_subject_branch() { sed -nE 's/^\[MERGE\] (pool\/[^ ]+) into dev: .*/\1/p' <<<"$1"; }
# rapid_subject_kslash SUBJECT -> "<kind>/<name>", the short name of that branch in reports.
rapid_subject_kslash() { local ks; ks=$(rapid_subject_ks "$1"); [ -z "$ks" ] || printf '%s' "${ks/ //}"; }
# rapid_subject_ks SUBJECT -> "kind name" of that branch (empty when the subject names none).
rapid_subject_ks() { local p; p=$(rapid_subject_branch "$1"); [ -z "$p" ] || rapid_branch_parse "$p" || true; }

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

# A branch is pool/v<series>/<number>.<kind>.<name>; one never
# landed simply stays there (a branch not landed yet), its anchor kept forever.
# rapid_branch_open REF: 0 when REF names an open branch.
rapid_branch_open() { case "${1#refs/heads/}" in pool/*/*) return 0 ;; esac; return 1; }
# RAPID_POOL_NS: the ref namespace of branches.
RAPID_POOL_NS="refs/heads/pool"

rapid_kind_ok() { case " $RAPID_KINDS " in *" $1 "*) return 0 ;; esac; return 1; }
rapid_slug_ok() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]{1,47}$ ]]; }

# rapid_trailer COMMIT KEY: the value of trailer KEY in COMMIT's message.
rapid_trailer() {
  git log -1 --format=%B "$1" | git interpret-trailers --parse | sed -nE "s/^$2: (.*)$/\1/p" | sed -n 1p
}

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
# Vault refs. A safety anchor points at a branch's start; its vault branch at
# its end: rapid land writes refs/heads/vault/v<series>/<name> on the branch's tip
# as it landed (the merge's second parent), in the land's atomic push.
# Like an anchor it stays forever: pre-push,
# the agent guard and the rapid-vault-readonly ruleset refuse deleting or moving
# one, and sync --dev publishes those of offline lands. A re-land keeps the
# vault branch of the branch's first land.
# rapid_vault_ref REF -> refs/heads/vault/v<series>/<name>.
rapid_vault_ref() { local a; a=$(rapid_anchor_ref "$1"); printf 'refs/heads/vault/%s' "${a#refs/heads/safety/}"; }
# rapid_anchor_refs REF: the refs that travel with branch REF: its anchor.
rapid_anchor_refs() { rapid_anchor_ref "$1"; printf '\n'; }

# Banned files: secrets, keys, certificates, build output,
# dependency trees, archives and backups never enter history. The
# pre-commit hook refuses them in the staged set (for humans as for agents,
# whose guard already denies staging them), and land refuses a branch that
# adds one past the hook. Removing such a file is always allowed.
RAPID_BANNED_RE='(^|/)\.DS_Store$|(^|/)\.auth/|(^|/)keys/|\.(p8|p12|cer|pem|provisionprofile|mobileprovision)$|(^|/)build(-[^/]*)?/|(^|/)node_modules/|(^|/)\.env$|(^|/)\.env\.([^/]*)$|\.zip$|\.bak$'
# rapid_banned PATH...: prints each PATH the banned list names (an .env.example,
# .sample, .template or .dist file is a template, not a secret).
rapid_banned() {
  local p
  for p in "$@"; do
    [[ "$p" =~ $RAPID_BANNED_RE ]] || continue
    [[ "$p" =~ (^|/)\.env\.(example|sample|template|dist)$ ]] && continue
    printf '%s\n' "$p"
  done
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
