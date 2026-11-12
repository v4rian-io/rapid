#!/usr/bin/env bash
# a clone never builds on an unverified dev: a commit pushed onto origin dev past the hooks is
# named, with its author and the invariant it breaks, and refused by rapid branch, rapid land, rapid sync and
# rapid sync --dev, which leave local dev where it was; plain rapid doctor names it too. Once origin dev
# is repaired, the clone proceeds.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/a" origin; cd "$T/a"
rapid branch feature base >/dev/null; commit base.txt; rapid land >/dev/null || fail "land base"
good=$(git rev-parse dev)
git clone -q "$T/origin.git" "$T/b"; ( cd "$T/b" && git switch -q dev && rapid setup >/dev/null )
cd "$T/b"; rapid branch feature waiting >/dev/null; commit waiting.txt
# a coworker skips every hook and pushes a plain commit onto origin dev
cd "$T/a"; actor "Mallory" mallory@team.test
git switch -q dev; printf 'x\n' > evil.txt; git add evil.txt
git commit -q --no-verify -m "wip"
git push -q --no-verify origin dev || fail "the bare origin refused the bypassing push"
evil=$(git rev-parse --short dev)
cd "$T/b"; actor "Agent One" agent1@team.test
before=$(git rev-parse dev)
refused rapid land
grep -q "origin dev holds $evil" "$T/err" || fail "land built on an unverified dev: $(cat "$T/err")"
grep -q 'mallory@team.test' "$T/err" && grep -q 'I1' "$T/err" || fail "the refusal names no author or invariant: $(cat "$T/err")"
[ "$(git rev-parse dev)" = "$before" ] || fail "local dev moved onto the unverified commit"
refused rapid sync
grep -q "origin dev holds $evil" "$T/err" || fail "sync built on an unverified dev: $(cat "$T/err")"
git switch -q dev
refused rapid branch feature honest
grep -q "origin dev holds $evil" "$T/err" || fail "branch started on an unverified dev: $(cat "$T/err")"
refused rapid sync --dev
grep -q "origin dev holds $evil" "$T/err" || fail "sync --dev took an unverified dev: $(cat "$T/err")"
[ "$(git rev-parse dev)" = "$before" ] || fail "local dev moved"
git fetch -q origin
refused rapid doctor
grep -q "doctor: origin dev holds $evil" "$T/out" || fail "plain doctor did not name the unverified commit: $(cat "$T/out")"
# the owner repairs origin dev; the clone proceeds
git push -q --no-verify --force origin "$good:refs/heads/dev"
git switch -q "$(lname waiting)"
rapid land >/dev/null || fail "land after origin was repaired"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$(git rev-parse dev)" ] || fail "origin dev differs"
history_clean
