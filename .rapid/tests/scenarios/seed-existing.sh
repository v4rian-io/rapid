#!/usr/bin/env bash
# seed an empty origin from existing history: main stays at the initial
# commit, dev arrives with every tag it carries, in one atomic push.
. "$(dirname "$0")/../lib.sh"
actor "Human Dev" human@team.test
mkrepo "$T/r"; cd "$T/r"
rapid setup >/dev/null
rapid branch fix login -r "Accept a trailing newline in the token file." >/dev/null
commit tok.txt t "[FIX] Accept a trailing newline in the token file"
rapid land >/dev/null || fail "local land"
seed=$(git rev-parse main)
git remote add origin "$(mkremote origin)"
rapid setup >/dev/null || fail "setup did not seed an empty origin from existing history"
[ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$seed" ] || fail "origin main is not the initial commit"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$(git rev-parse dev)" ] || fail "origin dev differs"
[ -n "$(git ls-remote origin refs/tags/v2026.0.1)" ] || fail "dev's tag not on origin"
[ "$(git rev-parse main)" = "$seed" ] || fail "setup moved local main"
git clone -q "$T/origin.git" "$T/c"; cd "$T/c"; git switch -q dev; rapid setup >/dev/null
history_clean
