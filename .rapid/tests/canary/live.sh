#!/usr/bin/env bash
# tests/canary/live.sh [--repo OWNER/NAME] [--dry-run] | --cleanup RUN
# The live canary (test tooling, not part of rapid): what
# the scenario matrix verifies against a gh stub, verified here against the real
# forge. It works in ONE persistent public repository (default
# <gh user>/rapid-canary, created once when missing) and never deletes a
# repository: every run lands run-unique branches (names ending in -<run>) onto the
# repository's own dev, so the forge's dev, main, tags and rulesets keep the
# whole history of every run, as rapid's rules require.
#
# Checks, each printed PASS or FAIL with what the forge answered:
#   C1 setup (first run) or an upgrade branch brings the canary to this framework;
#      rapid setup --remote leaves the rulesets on the forge, its
#      safety-lockdown, vault-readonly and branch-deletions among them (C1c)
#   C2 the server refuses a force push to dev and a deletion of dev (hooks skipped)
#   C3 the server refuses moving and deleting a version tag
#   C4 a branch not landed yet stays a branch: rapid status lists it, the forge holds its safety anchor
#   C5 the rapid-check, commit-audit and rapid-linux jobs run green on a pushed branch
#   C6 the owner releases with land_pr=optional (main moves, release tag pushed)
#   C7 under land_pr=required, rapid land --pr lands a branch through its PR once
#      the rapid-check and commit-audit statuses pass (land_approvals=0)
#   C8 under land_pr=required the owner can still release (audit hole M1)
#   C9 the run puts land_pr back to optional, so the next run starts the same way
#
# Cleanup: the run deletes only its own run-scoped refs that the rules let go:
# branches it pushed and did not land (pool/*/*-<run>). Version and release tags,
# safety anchors and dev and main are permanent by design; they
# are the record of the run. --cleanup RUN does the same for an interrupted run.
# Needs gh signed in with the repo and workflow scopes (probed once, before any
# write); never the delete_repo scope.
#
# Exit: 0 every check passed; 1 a check failed; 2 usage or a missing scope.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAPID_SRC="$(cd "$here/../.." && pwd)"
FW_ROOT="$(cd "$RAPID_SRC/.." && pwd)"
repo=""; dry=false; cleanup_run=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="${2:?}"; shift 2 ;;
    --dry-run) dry=true; shift ;;
    --cleanup) cleanup_run="${2:?}"; shift 2 ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    *) echo "X canary: unknown argument $1" >&2; exit 2 ;;
  esac
done
say() { printf '%s\n' "$*"; }
command -v gh >/dev/null 2>&1 || { echo "X canary: the gh CLI is required" >&2; exit 2; }
scopes=$(gh api -i user 2>/dev/null | sed -nE 's/^[Xx]-[Oo][Aa]uth-[Ss]copes: (.*)\r?$/\1/p' | tr -d '\r' | sed -n 1p)
for s in repo workflow; do
  case ", $scopes," in *", $s,"*) ;; *)
    echo "X canary: gh lacks the $s scope (has: ${scopes:-none}); nothing was written. The owner runs: gh auth refresh -h github.com -s $s" >&2
    exit 2 ;;
  esac
done
[ -n "$repo" ] || repo="$(gh api user --jq .login)/rapid-canary"
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "X canary: '$repo' is not OWNER/NAME" >&2; exit 2; }
url="${RAPID_CANARY_URL:-https://github.com/$repo.git}"   # a test points it at a local bare repository
run=$(date -u +%y%m%d%H%M%S)
if $dry; then say "dry run: run $run on public $repo (created when missing, never deleted): C1 to C9, run-scoped branches *-$run"; exit 0; fi

# cleanup RUN: delete the run's branches not landed yet on the forge, nothing else
cleanup_branches() {
  local r="$1" ref
  [[ "$r" =~ ^[0-9]{12}$ ]] || { echo "X canary: run '$r' is not a canary run id" >&2; return 1; }
  for ref in $(git ls-remote "$url" 'refs/heads/pool/*' 2>/dev/null | cut -f2 | grep -E "^refs/heads/pool/[a-z0-9.]+/[a-z0-9.-]+-$r\$" || true); do
    gh api -X DELETE "repos/$repo/git/$ref" >/dev/null 2>&1 && say "removed $ref (run $r)" || say "! could not remove $ref"
  done
}
if [ -n "$cleanup_run" ]; then cleanup_branches "$cleanup_run"; exit 0; fi

W=$(mktemp -d "${TMPDIR:-/tmp}/rapid-canary.XXXXXX")
fails=0
# the end state is always optional review: a run that stops under land_pr=required puts it back
restoring=0
end_state() {
  [ "$restoring" = 0 ] || return 0
  restoring=1
  [ -d "${r:-}/.git" ] || return 0
  cd "$r" || return 0
  git fetch -q origin '+refs/heads/dev:refs/remotes/origin/dev' >"$W/end-fetch.log" 2>&1 || true
  if grep -qx 'land_pr=required' <<<"$(git show refs/remotes/origin/dev:.rapid/conf 2>/dev/null || true)"; then
    if restore_optional "Run $run puts lands back to optional review at its end." endreview >"$W/end-restore.log" 2>&1; then
      say "end state: land_pr put back to optional"
    else
      say "! end state: the canary is LEFT at land_pr=required: $(tail -n 4 "$W/end-restore.log" "$W/pr-endreview.log" 2>/dev/null | tr '\n' ' ')"
    fi
  fi
}
trap 'rc=$?; set +e; end_state; cleanup_branches "$run" || true; rm -rf "$W"; exit "$rc"' EXIT
check() { if [ "$2" = ok ]; then say "PASS  $1  $3"; else say "FAIL  $1  $3"; fails=$((fails + 1)); fi; }

if ! gh repo view "$repo" >/dev/null 2>&1; then
  gh repo create "$repo" --public --description "rapid live canary: every run's branches land here; never deleted" >/dev/null
  say "created public $repo (persistent)"
fi
export GIT_CONFIG_GLOBAL="$W/gitconfig" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
git config --file "$GIT_CONFIG_GLOBAL" credential.https://github.com.helper '!gh auth git-credential'
export GIT_AUTHOR_NAME="rapid canary" GIT_COMMITTER_NAME="rapid canary" GIT_AUTHOR_EMAIL=canary@rapid-canary.invalid GIT_COMMITTER_EMAIL=canary@rapid-canary.invalid
unset RAPID_CONF_REV RAPID_OFFLINE RAPID_TRACKER RAPID_RELAND_STEP GIT_AUTHOR_DATE GIT_COMMITTER_DATE
# the canary's actor is a human row: an agent session that runs it does not mark it as an agent
unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT
r="$W/r"
# the rapid under test serves the canary as an installed tool: on PATH through a link, as rapid setup --install leaves it
mkdir -p "$W/bin"; ln -s "$RAPID_SRC/rapid" "$W/bin/rapid"; PATH="$W/bin:$PATH"
rapid() { command rapid "$@"; }
# the version tag of the rapid under test: what the canary pins in .rapid/version
tool_tag=$(git -C "$FW_ROOT" tag --merged HEAD -l 'v[0-9]*' | sort -t. -k1,1V -k2,2n -k3,3n | tail -n 1)
# body FILE TEXT ITEM: a merge body (paragraph, then a list)
body() { printf '%s\n\n- Canary run %s.\n    - %s.\n' "$2" "$run" "$3" > "$1"; }
# wait_runs SHA JOB...: every JOB's check run on SHA completes; prints "JOB=status/conclusion" (10 min cap)
wait_runs() {
  local sha="$1" i j c out=""; shift
  for i in $(seq 1 60); do
    out=""
    for j in "$@"; do
      c=$(gh api "repos/$repo/commits/$sha/check-runs" --jq "[.check_runs[] | select(.name == \"$j\")][0] | (.status + \"/\" + (.conclusion // \"\"))" 2>/dev/null || true)
      out="$out$j=$c "
    done
    case "$out" in *"=/"*|*"=queued/"*|*"=in_progress/"*|*"= "*) sleep 10 ;; *) printf '%s\n' "$out"; return 0 ;; esac
  done
  printf '%s(timeout)\n' "$out"
}
# land_pr_branch NAME TEXT ITEM: land one branch through its PR; prints the exit code
land_pr_branch() {
  local rc=0 m
  body "$W/body" "$2" "$3"
  rapid land --pr -F "$W/body" >"$W/pr-$1.log" 2>&1 || rc=$?
  if [ "$rc" = 3 ]; then
    m=$(git ls-remote origin "refs/heads/pool/$4" | cut -f1)
    [ -z "$m" ] || wait_runs "$m" rapid-check commit-audit > "$W/pr-$1.runs"
    rc=0; rapid land --pr -F "$W/body" >>"$W/pr-$1.log" 2>&1 || rc=$?
  fi
  echo "$rc"
}
# branch KIND NAME TEXT FILE: a run-scoped branch carrying FILE, ready to land
branch() {
  rapid branch "$1" "$2-$run" -r "$3" --test "$4" >/dev/null
  BRANCH=$(git symbolic-ref --short HEAD)   # the branch as rapid named it (it may number the slug)
  printf '%s %s\n' "$2" "$run" > "$4"; git add -- "$4"
  git commit -q -m "[NEW] Add the $2 file of this run" -m "Adds the $2 file that canary run $run lands."
}

# restore_optional WHY NAME: bring the canary back to land_pr=optional. GitHub refuses
# rapid land --pr's push while dev's ruleset carries the review rule (C7), so the
# owner's admin step comes first: dev's ruleset is put back to its optional
# rendering (remote/protected.json), then the branch that drops land_pr=required
# lands through its PR, and setup --remote renders the rules from dev's conf.
restore_optional() {
  local id rc=0
  id=$(gh api "repos/$repo/rulesets" --jq '.[] | select(.name == "rapid-protected") | .id' 2>/dev/null | sed -n 1p)
  [ -z "$id" ] || gh api -X PUT "repos/$repo/rulesets/$id" --input "$RAPID_SRC/remote/protected.json" >"$W/ruleset-put.log" 2>&1 \
    || say "! could not put rapid-protected back to its optional rendering: $(tail -n 2 "$W/ruleset-put.log" | tr '\n' ' ')"
  git switch -q dev 2>/dev/null || true
  branch refactor "$2" "$1" "$2-$run.txt"
  sed -i.bak -e '/^land_pr=required$/d' -e '/^land_approvals=0$/d' .rapid/conf; rm -f .rapid/conf.bak; git add .rapid/conf
  git commit -q -m "[MODE] Make review optional again" -m "Restores the canary policy so the next run starts the same way."
  rc=$(land_pr_branch "$2" "Restores optional review." "lands may go without a pull request" "${BRANCH#pool/}")
  rapid setup --remote >>"$W/remote.log" 2>&1 || say "! setup --remote after the restore: $(tail -n 2 "$W/remote.log" | tr '\n' ' ')"
  return "$rc"
}

# C1: the canary repository at this framework
if [ -z "$(git ls-remote "$url" refs/heads/dev 2>/dev/null)" ]; then
  mkdir -p "$r/.rapid"; cd "$r"; git init -q
  # instant gates and every path a test path: the canary verifies the forge, not a project
  printf 'land_who=anyone\nmax_commits=20\ntest_paths=*\ngates_fast=true\ngates_full=true\ngates_release=true\nforge_repo=%s\n' "$repo" > .rapid/conf
  git remote add origin "$url"
  if rapid setup --pin "$tool_tag" >"$W/setup.log" 2>&1; then check C1a ok "first run: setup seeded and pushed main and dev"; else check C1a fail "setup: $(tail -n 3 "$W/setup.log")"; fi
else
  git clone -q "$url" "$r"; cd "$r"; git switch -q dev
  rapid setup >"$W/setup.log" 2>&1 || true
  # C0: a run that stopped under land_pr=required left the canary there; put it back first
  if grep -qx 'land_pr=required' .rapid/conf; then
    restore_optional "Run $run puts lands back to optional review left by an earlier run." unreview0 && check C0 ok "restored land_pr=optional left by an earlier run" \
      || { check C0 fail "the canary stays at land_pr=required: $(tail -n 3 "$W"/pr-unreview0.log | tr '\n' ' ')"; exit 1; }
  fi
  # an upgrade branch only when the rapid under test is another version than the one the canary pins:
  # the upgrade is a branch that changes .rapid/version (a canary that still carries a copy of rapid
  # drops it in that branch: its .rapid holds data only from then on)
  if [ ! -e .rapid/rapid ] && [ "$(cat .rapid/version 2>/dev/null)" = "$tool_tag" ]; then
    check C1a ok "canary already at the rapid under test"
  else
    rapid branch refactor upgrade-$run -r "The canary pins the rapid under test for run $run." >/dev/null
    if [ -e .rapid/rapid ]; then
      for f in $(git ls-files .rapid | grep -vE '^[.]rapid/(conf|admins|version|requirements/)'); do git rm -q -- "$f"; done
    fi
    printf '%s\n' "$tool_tag" > .rapid/version; git add -- .rapid/version
    git commit -q -m "[REFACTOR] Pin the rapid under test for this run" -m "Brings the canary to the version of rapid this run tests." -m "Untested: a version pin changes no behaviour of the canary to test." >"$W/up.log" 2>&1 \
      || { check C1a fail "the upgrade commit was refused: $(tr '\n' ' ' < "$W/up.log" | cut -c1-600)"; exit 1; }
    body "$W/body" "Brings the canary to the rapid under test." "the pinned version changed"
    rapid land -F "$W/body" >"$W/up-land.log" 2>&1 && check C1a ok "upgrade branch landed" \
      || { check C1a fail "upgrade land: $(tail -n 3 "$W/up-land.log" | tr '\n' ' ')"; exit 1; }
  fi
fi
branch refactor forge "The canary keeps the rulesets and the rapid-check workflow of run $run on the forge." "forge-$run.txt"
rapid setup --remote >"$W/remote.log" 2>&1 || say "! setup --remote: $(tail -n 3 "$W/remote.log" | tr '\n' ' ')"
[ -f .github/workflows/rapid-check.yml ] && git add .github/workflows/rapid-check.yml
git diff --cached --quiet || git commit -q -m "[NEW] Write the forge workflow of this run" -m "Writes the rapid-check workflow the framework under test renders."
n=$(gh api "repos/$repo/rulesets" --jq 'length' 2>/dev/null || echo 0)
[ "$n" -ge 4 ] && check C1b ok "$n rulesets on the forge" || check C1b fail "$n rulesets: $(tail -n 3 "$W/remote.log")"
# the branch namespaces: safety anchors, vault branches and branches are kept by rulesets an admin alone bypasses
miss=""; for rn in rapid-safety-lockdown rapid-vault-readonly rapid-branch-deletions; do
  rid=$(gh api "repos/$repo/rulesets" --jq ".[] | select(.name == \"$rn\") | .id" 2>/dev/null | sed -n 1p)
  [ -n "$rid" ] && [ "$(gh api "repos/$repo/rulesets/$rid" --jq '[.bypass_actors[] | select(.actor_type == "RepositoryRole" and .actor_id == 5)] | length' 2>/dev/null)" = 1 ] || miss="$miss $rn"
done
[ -z "$miss" ] && check C1c ok "safety-lockdown, vault-readonly and branch-deletions on the forge, admins alone bypass" || check C1c fail "missing or without the admin bypass:$miss"
body "$W/body" "Keeps the forge rules current." "rulesets and workflow"
rapid land -F "$W/body" >"$W/land1.log" 2>&1 && check C1c ok "forge branch landed and pushed" || check C1c fail "land: $(tail -n 3 "$W/land1.log")"
# C2: dev cannot be forced back or deleted, even past the hooks
if git push -q --no-verify --force origin dev~1:refs/heads/dev >"$W/c2a" 2>&1; then check C2a fail "a force push to dev was accepted"; else check C2a ok "force push refused: $(grep -m1 -iE 'rule|denied|refus|declin|protected' "$W/c2a" | tr -s ' ')"; fi
if git push -q --no-verify origin :refs/heads/dev >"$W/c2b" 2>&1; then check C2b fail "deleting dev was accepted"; else check C2b ok "deletion refused: $(grep -m1 -iE 'rule|denied|refus|declin|protected' "$W/c2b" | tr -s ' ')"; fi
# C3: version tags are immutable
v=$(git describe --tags --abbrev=0 --match 'v*' dev)
if git push -q --no-verify --force origin "dev~1:refs/tags/$v" >"$W/c3a" 2>&1; then check C3a fail "moving $v was accepted"; else check C3a ok "moving $v refused"; fi
if git push -q --no-verify origin ":refs/tags/$v" >"$W/c3b" 2>&1; then check C3b fail "deleting $v was accepted"; else check C3b ok "deleting $v refused"; fi
# C4: a branch never landed stays a branch, listed as not landed yet, its safety anchor on the forge
branch feature not-landed "A branch not landed yet of run $run stays a branch." "not-landed-$run.txt"
c4rc=0; rapid sync --push >"$W/c4-push.log" 2>&1 || c4rc=$?
anchor="safety/${BRANCH#pool/}"
if [ "$c4rc" != 0 ] || [ -z "$(git ls-remote origin "refs/heads/$BRANCH")" ]; then check C4 fail "the branch not landed yet did not reach the forge as $BRANCH (rapid sync --push exit $c4rc): $(tail -n 4 "$W/c4-push.log" | tr '\n' ' ')"
elif [ -z "$(git ls-remote origin "refs/heads/$anchor")" ]; then check C4 fail "the forge holds no $anchor"
elif ! grep -q "branches not landed yet: .*$BRANCH" <<<"$(rapid status 2>/dev/null)"; then check C4 fail "rapid status does not list $BRANCH as not landed yet"
else check C4 ok "$BRANCH stays a branch, listed as not landed yet, its anchor $anchor on the forge"; fi
git switch -q dev 2>/dev/null || git switch -q --detach origin/dev
# C5: the workflow's jobs on a pushed branch
branch feature widget "A widget branch of run $run runs the forge jobs green." "widget-$run.txt"
rapid sync --push >"$W/c5-push.log" 2>&1 || check C5 fail "the widget branch did not reach the forge: $(tail -n 4 "$W/c5-push.log" | tr '\n' ' ')"
res=$(wait_runs "$(git rev-parse HEAD)" rapid-check commit-audit rapid-linux)
case "$res" in *"rapid-check=completed/success"*"commit-audit=completed/success"*"rapid-linux=completed/success"*) check C5 ok "$res" ;; *) check C5 fail "$res" ;; esac
body "$W/body" "Adds the widget of the run." "the widget file"
rapid land -F "$W/body" >"$W/land2.log" 2>&1 || check C5b fail "land widget: $(tail -n 3 "$W/land2.log")"
# C6: the owner releases (land_pr=optional)
if rapid release >"$W/rel1.log" 2>&1 && [ "$(git rev-parse "$(git ls-remote origin refs/heads/main | cut -f1)^2" 2>/dev/null)" = "$(git rev-parse dev)" ]; then
  check C6 ok "main is at the release merge of dev's tip"; else check C6 fail "release: $(tail -n 3 "$W/rel1.log")"; fi
# C7, C8: under land_pr=required
branch refactor review "Lands of run $run go through review on the forge." "review-$run.txt"
printf 'land_pr=required\nland_approvals=0\n' >> .rapid/conf; git add .rapid/conf
git commit -q -m "[MODE] Require review before a land" -m "Turns on the review rule that checks C7 and C8 exercise."
body "$W/body" "Requires review for the run." "every land goes through a pull request"
rapid land -F "$W/body" >"$W/land3.log" 2>&1 || check C7a fail "landing the policy: $(tail -n 3 "$W/land3.log")"
rapid setup --remote >>"$W/remote.log" 2>&1 || say "! setup --remote: $(tail -n 3 "$W/remote.log" | tr '\n' ' ')"
for id in $(gh api "repos/$repo/rulesets" --jq '.[].id' 2>/dev/null); do gh api "repos/$repo/rulesets/$id" --jq '.rules[].type'; done > "$W/rules" 2>/dev/null || true
grep -qx pull_request "$W/rules" && check C7a ok "dev's ruleset carries the review rule" || check C7a fail "no pull_request rule: $(tr '\n' ' ' < "$W/rules")"
branch feature gadget "A gadget branch of run $run lands through its pull request." "gadget-$run.txt"
rc=$(land_pr_branch gadget "Adds the gadget of the run." "the gadget file" "${BRANCH#pool/}")
if [ "$rc" = 0 ] && [ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$(git rev-parse dev)" ]; then
  check C7b ok "land --pr landed through the PR ($(cat "$W/pr-gadget.runs" 2>/dev/null))"
else
  check C7b fail "land --pr exit $rc: $(tail -n 4 "$W/pr-gadget.log" | tr '\n' ' ') $(cat "$W/pr-gadget.runs" 2>/dev/null)"
fi
if rapid release >"$W/rel2.log" 2>&1 && [ "$(git rev-parse "$(git ls-remote origin refs/heads/main | cut -f1)^2" 2>/dev/null)" = "$(git rev-parse dev)" ]; then
  check C8 ok "the owner released under land_pr=required"
else
  check C8 fail "release under land_pr=required: $(tail -n 4 "$W/rel2.log" | tr '\n' ' ')"
fi
# C9: back to land_pr=optional (the review rule is lifted by the owner's admin step first)
if restore_optional "Run $run puts lands back to optional review." unreview; then check C9 ok "land_pr back to optional"
else check C9 fail "the canary is left at land_pr=required: $(tail -n 3 "$W/pr-unreview.log" | tr '\n' ' ')"; fi
say "---- run $run: C1 to C9, $fails failed; repository $repo"
[ "$fails" = 0 ] || exit 1
