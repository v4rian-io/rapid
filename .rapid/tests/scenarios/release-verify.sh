#!/usr/bin/env bash
# a release test record is re-verified and attributed: doctor --verify reruns each release's gate on
# the released tree, so a release tag saying release=pass on a tree whose release gate fails is
# named; the owner's honest release verifies clean and names its releaser.
. "$(dirname "$0")/../lib.sh"
actor "Owner One" owner@team.test
mkrepo "$T/r"; cd "$T/r"
rapid branch refactor release-check -r "The release suite fails while RELEASE-BLOCKER exists." >/dev/null
sed -i.bak 's/^gates_release=.*/gates_release=sh release-check.sh/' .rapid/conf && rm -f .rapid/conf.bak
printf '#!/bin/sh\n[ ! -f RELEASE-BLOCKER ]\n' > release-check.sh
git add release-check.sh; git commit -q -m "[NEW] Add the release check"
git add .rapid/conf; git commit -q -m "[MODE] Gate releases on the release check"
rapid land >/dev/null || fail "land the release check"
rapid release >/dev/null || fail "the owner's release"
git cat-file -p "release/$(git tag --points-at dev -l 'v*')" | grep -Fx 'Released-By: owner@team.test' >/dev/null || fail "the release names no releaser"
rapid doctor --verify > "$T/out" 2>&1 || fail "an honest release does not verify: $(cat "$T/out")"
rapid branch feature blocker >/dev/null; commit RELEASE-BLOCKER b "[NEW] Mark the beta flag as blocking release"
rapid land >/dev/null || fail "land the blocker"
v=$(git tag --points-at dev -l 'v*')
# a release tag made by hand that claims the gate passed
git tag -a "release/$v" -m "rapid release $v

Gates: release=pass
Tested-Tree: $(git rev-parse dev^{tree})
Released-By: owner@team.test" dev
git update-ref refs/heads/main "$(git rev-parse dev)"
rapid doctor --verify > "$T/out" 2>&1 && fail "doctor --verify trusted a false release test record"
grep -q "P1 $(git rev-parse dev) release gate fails on the tree of release/$v (its tag says release=pass)" "$T/out" || fail "the false release test record was not named: $(cat "$T/out")"
