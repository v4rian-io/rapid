#!/usr/bin/env bash
# the agent guard checks git by rule, never by who commits: a forced push without a lease, a push to
# main, a moved or deleted safety anchor and a branch deleted by hand are denied, each by its rule;
# a commit, a merge and a cherry-pick pass under any identity, however it is set, because repository
# access decides who commits; reads are never checked.
. "$(dirname "$0")/../lib.sh"
command -v python3 >/dev/null || fail "python3 is required by the agent guard"
mkrepo "$T/r" origin; cd "$T/r"
export GUARD_TMP_ROOTS="$T/throwaway" RAPID_BAKS_DIR="$T/baks"; mkdir -p "$T/throwaway"
rapid branch feature probe >/dev/null; commit a.txt; P=$(lname probe); S=$(lref probe safety); git switch -q dev
[ -n "$S" ] || fail "rapid branch wrote no safety anchor"
guard() { python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$PWD" | "$TOOL/agent/guard-destructive.sh"; }
deny() { out=$(guard "$1"); grep -q '"deny"' <<<"$out" || fail "the guard allowed '$1': $out"; grep -qF "$2" <<<"$out" || fail "the deny for '$1' does not say '$2': $out"; }
allow() { out=$(guard "$1"); [ -z "$out" ] || fail "the guard denied '$1': $out"; }
deny "git push origin +dev" "bare force push"
deny "git push origin dev:main" "main is production"
deny "git branch -D $P" "Developers never delete branches"
deny "git push origin :$P" "Developers never delete branches"
deny "git branch -D $S" "Safety anchors stay forever"
deny "git branch -f $S HEAD" "Safety anchors stay forever"
deny "git update-ref -d refs/heads/$S" "Safety anchors stay forever"
# who commits is not the guard's business
for c in "git commit -m x" "GIT_AUTHOR_NAME=Anyone GIT_AUTHOR_EMAIL=anyone@else.test git commit -m x" "git -c user.name=Other -c user.email=other@else.test commit -m x" \
    "git commit --author='Human One <human@team.test>' -m x" "git merge --no-ff $P" "git cherry-pick HEAD"; do
  allow "$c"
done
allow "git log -1"
allow "git status"
