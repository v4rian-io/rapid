#!/usr/bin/env bash
# a failing release gate leaves main and the tags unchanged, here and on origin; the gate is announced
# and its output is printed live on stderr, once.
. "$(dirname "$0")/../lib.sh"
actor "Human Dev" human@team.test
mkrepo "$T/r" origin; cd "$T/r"
# the release gate changes through a branch, like any conf change
rapid branch refactor release-check >/dev/null
sed -i.bak 's/^gates_release=.*/gates_release=sh release-check.sh/' .rapid/conf && rm -f .rapid/conf.bak
printf '#!/bin/sh\n# the release suite: fails while RELEASE-BLOCKER exists\necho release-check-running\n[ ! -f RELEASE-BLOCKER ]\n' > release-check.sh
git add release-check.sh; git commit -q -m "[NEW] Add the release check"
git add .rapid/conf; git commit -q -m "[MODE] Gate releases on the release check"
rapid land >/dev/null || fail "land the release check"
rapid branch feature beta-flag >/dev/null; commit RELEASE-BLOCKER b "[NEW] Mark the beta flag as blocking release"; rapid land >/dev/null || fail "land"
main0=$(git rev-parse main); o0=$(git ls-remote origin refs/heads/main | cut -f1)
refused rapid release
grep -q 'release gate fails' "$T/err" || fail "gate failure text: $(cat "$T/err")"
# without --verbose no progress: the gate is not announced
! grep '^-> release gate on' "$T/err" >/dev/null || fail "the release gate is announced without --verbose: $(cat "$T/err")"
# --verbose: the long gate is followed as it runs: announced, its own output on stderr, not printed a second time as a tail
refused rapid release --verbose
grep -q 'release gate fails' "$T/err" || fail "gate failure text under --verbose: $(cat "$T/err")"
grep -qE '^-> release gate on v[0-9.]+ [0-9a-f]+$' "$T/err" || fail "the release gate is not announced: $(cat "$T/err")"
[ "$(grep -c 'release-check-running' "$T/err")" = 1 ] || fail "the gate output is not printed live, once: $(cat "$T/err")"
[ "$(git rev-parse main)" = "$main0" ] || fail "main moved"
[ -z "$(git tag -l 'release/*')" ] || fail "a release tag was made"
[ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$o0" ] || fail "origin main moved"
history_clean
