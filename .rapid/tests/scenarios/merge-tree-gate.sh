#!/usr/bin/env bash
# fast
# the full gate fails on the merge tree although every branch commit passes
# the fast gate: dev and the tags stay unchanged.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
rapid branch refactor gate >/dev/null
sed -i.bak 's/^gates_full=.*/gates_full=sh check.sh \&\& ! test -f slow-fail.txt/' .rapid/conf && rm -f .rapid/conf.bak
git add .rapid/conf; git commit -q -m "[MODE] Add a slower full gate to the conf"
rapid land >/dev/null || fail "landing the gate change"
rapid branch feature risky >/dev/null; commit slow-fail.txt x "[NEW] Add a file only the full gate rejects"
rapid check --each >/dev/null || fail "the fast gate should pass every branch commit"
before=$(git rev-parse dev)
refused rapid land
grep -q 'batch gate full fails on the final tree' "$T/err" || fail "refusal text: $(cat "$T/err")"
[ "$(git rev-parse dev)" = "$before" ] && [ -z "$(git tag -l v2026.0.2)" ] || fail "dev or tags changed"
history_clean
