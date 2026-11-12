#!/usr/bin/env bash
# fast
# a test-first commit marked Red: and followed by the green fix lands; a
# Red: commit at the branch tip does not.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
rapid branch fix empty >/dev/null
commit empty.bad x "[TEST] Reproduce the crash on empty input" "Red: empty input test"
refused rapid land
grep -q 'cannot be the branch tip\|fails the fast gate' "$T/err" "$T/out" || fail "red tip refusal: $(cat "$T/err")"
git rm -q empty.bad; git commit -q -m "[FIX] Handle empty input without a crash" -m "Cause: the defect this scenario plants." -m "Fix: the repair this scenario makes."
rapid check --each > "$T/each" || fail "check --each with a marked red commit"
grep -q '^  red ' "$T/each" || fail "the red commit is not reported as marked"
rapid land >/dev/null || fail "land with a marked red commit"
[ "$(git rev-list --count dev^1..dev^2)" = 2 ] || fail "both commits landed"
history_clean
