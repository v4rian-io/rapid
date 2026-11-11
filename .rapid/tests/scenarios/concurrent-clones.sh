#!/usr/bin/env bash
# two clones land concurrently: the loser's atomic close push is refused with
# nothing half-published; land --prune puts its dev back, then sync and land succeed as N+1.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/a" origin; cd "$T/a"
git clone -q "$T/origin.git" "$T/b"; ( cd "$T/b" && git switch -q dev && rapid setup >/dev/null )
git clone -q --bare "$T/origin.git" "$T/stale.git"
rapid branch feature alpha >/dev/null; commit alpha.txt
cd "$T/b"; actor "Agent Two" agent2@team.test
rapid branch feature beta >/dev/null; commit beta.txt beta "[NEW] Add the beta file"
# B reads a snapshot taken before A lands, so both build their merge on the same dev
git config remote.origin.url "$T/stale.git"; git config remote.origin.pushurl "$T/origin.git"
cd "$T/a"; actor "Agent One" agent1@team.test; rapid land >/dev/null || fail "A lands"
cd "$T/b"; actor "Agent Two" agent2@team.test
refused rapid land
[ "$(git ls-remote "$T/origin.git" 'refs/tags/v*' | grep -vc '\^{}$')" = 1 ] || fail "origin holds a half-published tag"
rapid land --prune >/dev/null || fail "B aborts its batch"
git rev-parse -q --verify refs/tags/v2026.0.1 >/dev/null && fail "B kept a local tag after the prune"
[ -n "$(lname beta)" ] || fail "B's branch is gone"; git switch -q "$(lname beta)"
git config remote.origin.url "$T/origin.git"; git config --unset remote.origin.pushurl
rapid sync >/dev/null || fail "B sync"
rapid land >/dev/null || fail "B lands after sync"
[ "$(git describe --exact-match dev)" = v2026.0.2 ] || fail "B is not v2026.0.2"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$(git rev-parse dev)" ] || fail "origin dev differs"
history_clean
