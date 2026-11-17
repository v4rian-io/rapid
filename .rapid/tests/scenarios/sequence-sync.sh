#!/usr/bin/env bash
# fast
# two branches in two worktrees land in sequence; the second, behind dev, is rebased by land and takes N+1.
. "$(dirname "$0")/../lib.sh"
actor "Human Dev" human@team.test
mkrepo "$T/r" origin; cd "$T/r"
rapid branch feature one >/dev/null; commit one.txt
git switch -q dev; rapid branch feature two >/dev/null; commit two.txt
git switch -q dev
git worktree add -q "$T/w1" "$(lname one)"; git worktree add -q "$T/w2" "$(lname two)"
actor "Agent One" agent1@team.test
( cd "$T/w1" && rapid land >/dev/null ) || fail "first land"
cd "$T/w2"
rapid land >/dev/null || fail "second land"
[ -n "$(git for-each-ref --format=x refs/rapid/preflight/two)" ] || fail "no preflight ref"
[ "$(git describe --exact-match dev)" = v2026.0.2 ] || fail "second land not v2026.0.2"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$(git rev-parse dev)" ] || fail "origin dev differs"
history_clean
