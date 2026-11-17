#!/usr/bin/env bash
# fast
# an unmarked red commit in a branch is named by check --each; a land runs no gate
# (batch-land-local), so the close tests the final tree, which is green.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
rapid branch fix crash >/dev/null
commit crash.bad x "[TEST] Reproduce the crash on empty input"
commit fix.txt y "[FIX] Handle empty input without a crash"
git rm -q crash.bad; git commit -q -m "[FIX] Remove the crash reproduction marker" -m "Cause: the defect this scenario plants." -m "Fix: the repair this scenario makes."
bad=$(git rev-parse --short HEAD~2)
refused rapid check --each
grep -q "FAIL  $bad" "$T/out" || fail "check --each did not name $bad: $(cat "$T/out")"
d0=$(git rev-parse dev)
rapid land >/dev/null || fail "the land of a green final tree"
[ "$(git rev-parse dev^1)" = "$d0" ] || fail "dev did not take the one merge"
history_clean
