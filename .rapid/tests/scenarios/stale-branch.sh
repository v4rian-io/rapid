#!/usr/bin/env bash
# fast
# a branch behind dev lands: land rebases it onto dev itself, behind a preflight ref, and takes N+1.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
rapid branch feature one >/dev/null; commit one.txt
git switch -q dev; rapid branch feature two >/dev/null; commit two.txt
git switch -q "$(lname one)"; rapid land >/dev/null || fail "first land"
git switch -q "$(lname two)"; t2=$(git rev-parse HEAD)
rapid land >"$T/out" || fail "the stale branch did not land"
grep -q 'rebased .* onto dev' "$T/out" || fail "land did not say it rebased: $(cat "$T/out")"
pf=$(git for-each-ref --format='%(refname)' refs/rapid/preflight/two)
[ -n "$pf" ] && [ "$(git rev-parse "$pf")" = "$t2" ] || fail "no preflight ref at the branch tip before the rebase"
[ "$(git describe --exact-match dev)" = v2026.0.2 ] || fail "second land not v2026.0.2"
history_clean
