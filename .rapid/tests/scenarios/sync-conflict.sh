#!/usr/bin/env bash
# fast
# two branches change one file: sync stops with instructions and the preflight ref restores the branch.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
rapid branch feature one >/dev/null; commit shared.txt "one" "[NEW] Write the shared file from branch one"
git switch -q dev; rapid branch feature two >/dev/null; commit shared.txt "two" "[NEW] Write the shared file from branch two"
before=$(git rev-parse HEAD)
git switch -q "$(lname one)"; rapid land >/dev/null || fail "first land"
git switch -q "$(lname two)"
refused rapid sync
grep -q 'conflict in: shared.txt' "$T/err" || fail "conflict not named: $(cat "$T/err")"
grep -q 'git rebase --continue' "$T/err" || fail "no instructions: $(cat "$T/err")"
pf=$(git for-each-ref --format='%(refname)' refs/rapid/preflight/two)
[ "$(git rev-parse "$pf")" = "$before" ] || fail "preflight ref is not the branch tip before sync"
git rebase --abort
[ "$(git rev-parse HEAD)" = "$before" ] || fail "abort did not restore the branch"
# resolving: keep both lines, continue, land
rapid sync >/dev/null 2>&1 || true
printf 'one\ntwo\n' > shared.txt; git add shared.txt
GIT_EDITOR=true git -c core.hooksPath=/dev/null rebase --continue >/dev/null
rapid land >/dev/null || fail "land after resolving"
[ "$(git show dev:shared.txt)" = "$(printf 'one\ntwo')" ] || fail "resolution lost"
history_clean
