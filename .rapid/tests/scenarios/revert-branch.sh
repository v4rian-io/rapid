#!/usr/bin/env bash
# a landed branch that broke dev is reverted by a branch of its own whose
# commit links the merge it undoes (Fixes:); the fixed work lands again as a
# new branch linking the revert. A Fixes: that names no commit on dev is refused.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
rapid branch feature totals >/dev/null; commit calc.txt "total=round(x)" "[NEW] Add totals to the calculator"
rapid land >/dev/null || fail "land totals"
bad=$(git rev-parse dev)
rapid branch fix revert-totals >/dev/null
git revert --no-commit -m 1 "$bad" >/dev/null
git checkout -q "$bad" -- .rapid/requirements/totals.md   # a revert keeps the branch's requirement (I8)
git commit -q -m "[REVERT] Revert the totals branch that rounds the wrong way" -m "Fixes: $bad"
rapid land >/dev/null || fail "land the revert"
rev=$(git rev-parse dev^2)
[ "$(git show dev:calc.txt 2>/dev/null || echo gone)" = gone ] || fail "the revert did not take totals out"
rapid branch feature totals-fixed >/dev/null
commit calc.txt "total=round_half_even(x)" "[FIX] Round totals half to even" "Fixes: deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
refused rapid land
grep -q 'names no commit on dev' "$T/err" || fail "a Fixes: naming no commit landed: $(cat "$T/err")"
git commit -q --amend -m "[FIX] Round totals half to even" -m "Cause: the defect this scenario plants." -m "Fix: the repair this scenario makes." -m "Fixes: $rev"
rapid land >/dev/null || fail "land the fixed totals"
fx=$(git rev-parse dev^2)
[ "$(git log -1 --format=%B "$fx" | git interpret-trailers --parse | sed -n 's/^Fixes: //p')" = "$rev" ] || fail "the fix does not link the revert"
[ "$(git log -1 --format=%B "$rev" | git interpret-trailers --parse | sed -n 's/^Fixes: //p')" = "$bad" ] || fail "the revert does not link the merge it undoes"
[ "$(git log --first-parent --format=%s dev | grep -c '^\[MERGE\]')" = 3 ] || fail "want three landed branches"
history_clean
