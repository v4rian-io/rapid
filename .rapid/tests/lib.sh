# shellcheck shell=bash
# tests/lib.sh - scenario helpers: scratch repos, bare remotes, actors.
# Every scenario sources this file, works only under its own temp root and
# asserts end state with git plumbing, then 'rapid doctor --history'.
set -euo pipefail
RAPID_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# TMPDIR may end with a slash (the macOS default does): T is the path as pwd prints it
T=$(mktemp -d "${TMPDIR:-/tmp}/rapid-scenario.XXXXXX"); T=$(cd "$T" && pwd)
trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1 RAPID_YEAR="${RAPID_YEAR:-2026}"
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
git config --file "$GIT_CONFIG_GLOBAL" advice.detachedHead false
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE RAPID_CONF_REV RAPID_OFFLINE RAPID_TRACKER RAPID_RELAND_STEP RAPID_DEVEXEC
# nor its session markers: a scenario's actors are the team it scripts
unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT
# a scenario never inherits the caller's commit dates (a backdated preflight
# backup would read as stale to the agent guard)
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { :; }

# actor NAME EMAIL: every later git call authors and commits as this actor.
actor() {
  export GIT_AUTHOR_NAME="$1" GIT_COMMITTER_NAME="$1" GIT_AUTHOR_EMAIL="$2" GIT_COMMITTER_EMAIL="$2"
}
actor "Agent One" agent1@team.test

# rapid ARGS: the rapid under test, the one installed for the run (on PATH). A branch
# opened without -r states a scenario requirement, since land refuses the
# placeholder (land-integrity checks that refusal with the real rapid). A bare 'rapid
# land' lands and closes, as rapid itself does; here a close that fails its gate is also
# pruned when this land opened the batch, so the scenario's repository is as it was before
# that land (the batch that stays open after a failed close is batch-land's subject).
rapid() {
  if [ "${1:-}" = land ] && [[ " $* " != *" --batch "* ]] && [[ " $* " != *" --pr "* ]] && [[ " $* " != *" --dry-run "* ]] \
     && [[ " $* " != *" --halt "* ]] && [[ " $* " != *" --prune "* ]] && [[ " $* " != *" -h "* ]] && [[ " $* " != *" --help "* ]]; then
    local _bf _had=0 _rc=0; _bf="$(git rev-parse --git-common-dir 2>/dev/null)/rapid/batch"; [ ! -s "$_bf" ] || _had=1
    command rapid "$@" || _rc=$?
    if [ "$_rc" != 0 ] && [ "$_rc" != 4 ] && [ "$_had" = 0 ] && [ -s "$_bf" ] && [ ! -s "$_bf.passed" ]; then command rapid land --prune >/dev/null 2>&1 || true; fi
    return "$_rc"
  elif [ "${1:-}" = branch ] && [ $# -ge 3 ] && [[ "${2:-}" != --* ]] && [[ " $* " != *" -r "* ]] && [[ " $* " != *" --ticket "* ]]; then
    command rapid "$@" -r "Scenario branch $3: the change this scenario lands."
  else
    command rapid "$@"
  fi
}

# mkrepo DIR [origin]: a fresh repo set up by the installed rapid (its .rapid holds data only); both
# gates check that every *.bad file is gone. With "origin" it also has the bare
# remote origin at $T/origin.git, seeded by rapid setup (what a scenario gets
# from: git remote add origin "$(mkremote origin)"; rapid setup).
# Under tests/run.sh (RAPID_TEST_FIXTURE set) the result is a copy of a session
# fixture: built once per run and per setup input (the actors, the RAPID_/GIT_
# environment, the global git config, origin or not), then copied, so a
# scenario never pays for the setup another one already ran. A set commit
# date, a non-empty DIR or an existing $T/origin.git builds afresh.
mkrepo() {
  local d="$1" o="${2:-}" fx
  if [ -n "${RAPID_TEST_FIXTURE:-}" ] && [ -z "${GIT_AUTHOR_DATE:-}${GIT_COMMITTER_DATE:-}" ] \
     && { [ ! -e "$d" ] || [ -z "$(ls -A "$d" 2>/dev/null)" ]; } && { [ -z "$o" ] || [ ! -e "$T/origin.git" ]; }; then
    fx="$RAPID_TEST_FIXTURE/repo${o:+-$o}.$(_mkrepo_key)"
    if _fixture "$fx" _mkrepo_fixture "$o"; then
      mkdir -p "$d"; cp -R "$fx/r/." "$d"
      # the hook stubs live in the git directory, named by its own path: the copy names its own
      git -C "$d" config core.hooksPath "$(cd "$d/.git" && pwd -P)/rapid/hooks"
      [ -z "$o" ] || { cp -R "$fx/origin.git" "$T/origin.git"; git -C "$d" remote set-url origin "$T/origin.git"; }
      return 0
    fi
  fi
  _mkrepo_build "$d"
  [ -z "$o" ] || ( cd "$d" && git remote add origin "$(mkremote origin)" && rapid setup >/dev/null )
}

# _mkrepo_fixture [origin] DIR: the fixture itself: DIR/r, and DIR/origin.git with origin.
_mkrepo_fixture() {
  local o="$1" d="$2"
  _mkrepo_build "$d/r"
  [ -z "$o" ] || { git init -q --bare "$d/origin.git"; cd "$d/r" && git remote add origin "$d/origin.git" && rapid setup >/dev/null; }
}

# _mkrepo_key: a checksum of every input rapid setup reads besides this .rapid.
_mkrepo_key() {
  { env | grep -E '^(RAPID_|GIT_)' | grep -vE '^(RAPID_TEST_FIXTURE|GIT_CONFIG_GLOBAL)=' | LC_ALL=C sort
    cat "$GIT_CONFIG_GLOBAL" 2>/dev/null; } | cksum | tr -c '0-9\n' '-' | sed 's/-*$//'
}

# _fixture PATH BUILDER [ARG]: make PATH once per run. The first caller builds
# it (BUILDER [ARG] DIR) under a lock and publishes it with an atomic symlink;
# the others wait for it. It fails (the caller builds without it) when the
# build fails or a lock left by a dead builder is still there after 300 s.
_fixture() {
  local fx="$1" b="$2" a="${3:-}" own i=0
  [ -e "$fx" ] && return 0
  if mkdir "$fx.lock" 2>/dev/null; then
    own="$fx.$$"
    if ( "$b" "$a" "$own" ) >/dev/null 2>&1; then ln -s "$(basename "$own")" "$fx"; return 0; fi
    rm -rf "$own"; rmdir "$fx.lock"; return 1
  fi
  while [ ! -e "$fx" ] && [ -d "$fx.lock" ] && [ $i -lt 1500 ]; do sleep 0.2; i=$((i + 1)); done
  [ -e "$fx" ]
}

_mkrepo_build() {
  local d="$1"
  mkdir -p "$d"; git -C "$d" init -q
  mkdir -p "$d/.rapid"
  # test_paths=*: in a scratch repo every path counts as a test path, so the commit audit's
  # "a behaviour change touches a test" smell stays out of scenarios about other rules (commit-audit sets it)
  cat > "$d/.rapid/conf" <<'CONF'
land_who=anyone
max_commits=20
test_paths=*
commit_body=optional
requirement_test=optional
gates_fast=sh check.sh
gates_full=sh check.sh
gates_release=sh check.sh
CONF
  printf '#!/bin/sh\n# the project test: fails while any *.bad file exists\n! ls *.bad >/dev/null 2>&1\n' > "$d/check.sh"
  ( cd "$d" && git add check.sh && command rapid setup >/dev/null )
}

# mkremote NAME: a bare repo under T, path printed.
mkremote() { git init -q --bare "$T/$1.git"; printf '%s' "$T/$1.git"; }

# commit FILE [CONTENT] [SUBJECT] [TRAILER]: one ruled commit on the current branch.
# A [FIX] or [HOTFIX] subject gets the Cause: and Fix: paragraphs the commit audit requires.
commit() {
  local f="$1" c="${2:-$1}" s="${3:-[NEW] Add $1 to the project}" tr="${4:-}" cf=()
  printf '%s\n' "$c" > "$f"; git add -- "$f"
  case "$s" in "[FIX] "*|"[HOTFIX] "*) cf=(-m "Cause: the defect this scenario plants." -m "Fix: the repair this scenario makes.") ;; esac
  if [ -n "$tr" ]; then git commit -q -m "$s" ${cf[@]+"${cf[@]}"} -m "$tr"; else git commit -q -m "$s" ${cf[@]+"${cf[@]}"}; fi
}

# history_clean: doctor --history passes.
history_clean() { rapid doctor --history >/dev/null || { rapid doctor --history >&2 || true; fail "doctor --history reports violations"; }; }

# refused CMD...: the command must fail; its stderr is kept in $T/err.
refused() { if "$@" >"$T/out" 2>"$T/err"; then fail "expected refusal: $*"; fi; }

# settle: wait until the anchors a branch push of this clone queued have reached origin (the
# pre-push hook sends them in one push right after the push that carries the branch).
settle() {
  local d i=0; d="$(git rev-parse --git-common-dir)/rapid"
  while ls "$d"/push-after.* >/dev/null 2>&1 && [ "$i" -lt 600 ]; do sleep 0.1; i=$((i + 1)); done
}

# lref NAME [NS]: the branch rapid named for NAME here
# (pool/v<series>/<number>.<kind>.<name>, or an unnumbered one made by hand); empty when none.
lref() {
  git for-each-ref --format='%(refname:short)' "refs/heads/${2:-pool}" \
    | grep -E "^${2:-pool}/v[0-9.]+/(n[0-9]+[.])?[a-z]+[.]$1\$" | sed -n 1p || true
}
# lname NAME [NS]: lref, failing the scenario when there is none.
lname() {
  local r; r=$(lref "$@"); [ -n "$r" ] || fail "no ${2:-pool} branch for name $1"; printf '%s' "$r"
}
# rbranch REMOTE NAME [NS]: REMOTE's refs/heads ref of NAME's branch, empty when it has none.
rbranch() {
  git ls-remote "$1" "refs/heads/${3:-pool}/*" | cut -f2 | grep -E "/(n[0-9]+[.])?[a-z]+[.]$2\$" | sed -n 1p || true
}

# fixture_merges N: N more merges on dev, each the shape rapid land writes (one fix commit
# carrying its requirement file, the merge trailers, an
# annotated version tag), made with plumbing so 200 of them take seconds, not 200 lands
# (doctor-history and parallel-history).
fixture_merges() {
  local n="$1" i s base branch tree last rd idx b
  rd="$T/fx"; idx="$T/fx.index"; mkdir -p "$rd"
  GIT_INDEX_FILE="$idx" git read-tree dev
  base=$(git rev-parse dev); last=$(git tag --points-at dev -l 'v*'); last=${last##*.}
  ( . "$RAPID_SRC/lib/core.sh"
    for i in $(seq $((last + 1)) $((last + n))); do
      s="bulk$i"
      printf '%s\n' "$s" > "$rd/$s.txt"
      printf '# fix/%s\n\nFixture branch %s: one landed merge of many.\n' "$s" "$s" > "$rd/$s.md"
      b=$(git hash-object -w "$rd/$s.txt" "$rd/$s.md" | tr '\n' ' ')
      set -- $b
      printf '100644 blob %s\t%s\n100644 blob %s\t.rapid/requirements/%s.md\n' "$1" "$s.txt" "$2" "$s" \
        | GIT_INDEX_FILE="$idx" git update-index --index-info
      tree=$(GIT_INDEX_FILE="$idx" git write-tree)
      branch=$(git commit-tree "$tree" -p "$base" -m "[FIX] Repair $s in the project" -m "Cause: the defect this fixture plants." -m "Fix: the repair this fixture makes.")
      base=$(printf '[MERGE] pool/v2026.0/fix.%s into dev: v2026.0.%s\n\nLands fix/%s: the fixture branch %s.\n\n- Commits, oldest first:\n    - %s: [FIX] Repair %s in the project\n\nBranch-Base: %s\nRequirement: .rapid/requirements/%s.md\nGates: fast=pass full=pass\nTested-Tree: %s\nBranch-Number: n%s\n' \
        "$s" "$i" "$s" "$s" "$(git rev-parse --short "$branch")" "$s" "$base" "$s" "$tree" "$i" | git commit-tree "$tree" -p "$base" -p "$branch")
      printf 'tag v2026.0.%s\nfrom %s\ntagger %s <%s> 1700000000 +0000\ndata <<EOT\nv2026.0.%s\nEOT\n\n' "$i" "$base" "$GIT_COMMITTER_NAME" "$GIT_COMMITTER_EMAIL" "$i" >> "$T/fx.tags"
    done
    git fast-import --quiet < "$T/fx.tags"
    git update-ref refs/heads/dev "$base" )
  git reset -q --hard dev
}

# The rapid under test is installed once per run, the canonical way: a clone of the framework
# made from this source tree, carrying a version tag, linked into the bin directory of a home
# of its own by rapid setup --install; every scenario finds that rapid on PATH. Under
# tests/run.sh it is a session fixture (built once, under the fixture lock); a scenario run
# on its own builds it under its temp root.
_tool_build() {
  local d="$2"
  mkdir -p "$d/clone" "$d/home/.local/bin"
  cp -R "$RAPID_SRC" "$d/clone/.rapid"
  ( cd "$d/clone" && git init -q && git add -- .rapid \
    && git -c core.hooksPath=/dev/null -c user.name=rapid -c user.email=rapid@team.test commit -q -m "[NEW] Carry the framework" \
    && git -c user.name=rapid -c user.email=rapid@team.test tag -a v2026.0.1 -m v2026.0.1 \
    && git -c user.name=rapid -c user.email=rapid@team.test tag -a release/v2026.0.1 -m "rapid release v2026.0.1" ) || return 1
  HOME="$d/home" PATH="$d/home/.local/bin:$PATH" bash "$d/clone/.rapid/rapid" setup --install >/dev/null || return 1
}
_tool() {
  local fx
  if [ -n "${RAPID_TEST_FIXTURE:-}" ]; then
    fx="$RAPID_TEST_FIXTURE/tool"
    _fixture "$fx" _tool_build "" || fx=""
  fi
  if [ -z "${fx:-}" ]; then fx="$T/.tool"; _tool_build "" "$fx" >/dev/null 2>&1 || fail "the rapid under test could not be installed"; fi
  _tool_dir="$(cd "$fx" && pwd -P)"
  export PATH="$_tool_dir/home/.local/bin:$PATH"
  # TOOL: the .rapid directory of the installed clone (its agent tools, its libraries)
  TOOL="$_tool_dir/clone/.rapid"
}
_tool

# selfhosted DIR [origin]: a repository that carries rapid itself, as the framework's own
# repository does: the source's .rapid is in it (its tests, admins and requirement files left
# out: a scenario brings its own), set up by its own .rapid/rapid, hooks as files, checked by
# the copy dev holds. After it, rapid on PATH serves a repository that holds .rapid/rapid by
# that copy, any other repository by the installed tool.
selfhosted() {
  local d="$1" tool
  mkdir -p "$d"; git -C "$d" init -q; cp -R "$RAPID_SRC" "$d/.rapid"
  rm -rf "$d/.rapid/tests" "$d/.rapid/admins" "$d/.rapid/requirements"
  printf '%s\n' land_who=anyone max_commits=20 'test_paths=*' commit_body=optional requirement_test=optional \
    'gates_fast=sh check.sh' 'gates_full=sh check.sh' 'gates_release=sh check.sh' > "$d/.rapid/conf"
  printf '#!/bin/sh\n# the project test: fails while any *.bad file exists\n! ls *.bad >/dev/null 2>&1\n' > "$d/check.sh"
  if [ ! -x "$T/.selfbin/rapid" ]; then
    tool="$(type -P rapid)"; mkdir -p "$T/.selfbin"
    printf '#!/bin/sh\nr="$(git rev-parse --show-toplevel 2>/dev/null)/.rapid/rapid"\n[ -x "$r" ] && exec "$r" "$@"\nexec "%s" "$@"\n' "$tool" > "$T/.selfbin/rapid"
    chmod +x "$T/.selfbin/rapid"; PATH="$T/.selfbin:$PATH"
  fi
  ( cd "$d" && git add check.sh && ./.rapid/rapid setup >/dev/null ) || fail "the self-hosted repository $d"
  [ -z "${2:-}" ] || ( cd "$d" && git remote add origin "$(mkremote "$2")" && ./.rapid/rapid setup >/dev/null ) || fail "the origin of $d"
}
