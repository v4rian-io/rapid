#!/usr/bin/env bash
# land with a remote: one atomic push carries dev, the tag and the branch deletion.
. "$(dirname "$0")/../lib.sh"
actor "Human Dev" human@team.test
mkrepo "$T/r"; cd "$T/r"
git remote add origin "$(mkremote origin)"
rapid setup >/dev/null
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$(git rev-parse dev)" ] || fail "setup did not seed origin dev"
rapid branch fix login -r "Accept a trailing newline in the token file." >/dev/null
commit tok.txt t "[FIX] Accept a trailing newline in the token file"
git push -q origin "$(lname login)"
settle
rapid land >/dev/null || fail "land with a remote"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$(git rev-parse dev)" ] || fail "origin dev differs"
[ -n "$(git ls-remote origin refs/tags/v2026.0.1)" ] || fail "tag not on origin"
[ -z "$(rbranch origin login)" ] || fail "remote branch not deleted"
# a fresh clone sees the same history and passes doctor
git clone -q "$T/origin.git" "$T/c"; cd "$T/c"; git switch -q dev; rapid setup >/dev/null
history_clean
