#!/usr/bin/env bash
# a [FIX] may name its existing test instead of touching a test path: with real test_paths, a [FIX]
# that changes behaviour only and carries 'Test: <test path>' naming a test its tree holds commits
# and lands; one naming a missing file is refused at commit, and made past the hook is refused by
# land; a [FIX] with neither a test path nor a Test: is refused with the trailer named.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
rapid branch refactor audit-policy -r "The commit audit runs with real test paths." >/dev/null
sed -i.bak '/^test_paths=/d' .rapid/conf; rm -f .rapid/conf.bak; printf 'test_paths=tests/*\n' >> .rapid/conf
git add .rapid/conf; git commit -q -m "[MODE] Set real test paths" || fail "the policy commit"
rapid land >/dev/null || fail "land the policy"
rapid branch feature sum -r "The sum helper adds two integers." >/dev/null
mkdir -p src tests
printf 'echo $(( $1 + $2 ))\n' > src/sum.sh; printf '[ "$(sh src/sum.sh 2 3)" = 5 ]\n' > tests/sum_test.sh
git add src/sum.sh tests/sum_test.sh; git commit -q -m "[NEW] Add the sum helper to the project" || fail "the helper with its test"
rapid land >/dev/null || fail "land the helper"
rapid branch fix sum-args -r "Missing sum arguments count as zero." >/dev/null
printf 'echo $(( ${1:-0} + ${2:-0} ))\n' > src/sum.sh; git add src/sum.sh
refused git commit -q -m "[FIX] Sum missing arguments as zero" -m "Cause: the helper read unset arguments." -m "Fix: default each argument to zero."
grep -qF "Test: <test path or scenario name>" "$T/err" || fail "a [FIX] with no test and no test was not refused with the trailer named: $(cat "$T/err")"
refused git commit -q -m "[FIX] Sum missing arguments as zero" -m "Cause: the helper read unset arguments." -m "Fix: default each argument to zero." -m "Test: tests/missing_test.sh"
grep -qF "names Test: tests/missing_test.sh, which is no test path its tree holds" "$T/err" || fail "a [FIX] naming a missing test was committed: $(cat "$T/err")"
refused git commit -q -m "[FIX] Sum missing arguments as zero" -m "Cause: the helper read unset arguments." -m "Fix: default each argument to zero." -m "Test: src/sum.sh"
grep -qF "names Test: src/sum.sh, which is no test path" "$T/err" || fail "a [FIX] naming a non-test test was committed: $(cat "$T/err")"
git commit -q -m "[FIX] Sum missing arguments as zero" -m "Cause: the helper read unset arguments." -m "Fix: default each argument to zero." \
  -m "Test: tests/sum_test.sh" 2>"$T/err" || fail "a [FIX] naming its existing test was refused: $(cat "$T/err")"
# made past the hook, a missing test is refused by land
git commit -q --amend --no-verify -m "[FIX] Sum missing arguments as zero" -m "Cause: the helper read unset arguments." -m "Fix: default each argument to zero." -m "Test: tests/missing_test.sh"
refused rapid land
grep -qF "names Test: tests/missing_test.sh" "$T/err" || fail "land took a [FIX] naming a missing test: $(cat "$T/err")"
git commit -q --amend -m "[FIX] Sum missing arguments as zero" -m "Cause: the helper read unset arguments." -m "Fix: default each argument to zero." -m "Test: tests/sum_test.sh"
rapid land >/dev/null 2>"$T/err" || fail "a [FIX] naming its existing test did not land: $(cat "$T/err")"
history_clean
