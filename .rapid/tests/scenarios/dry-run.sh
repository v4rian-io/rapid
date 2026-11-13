#!/usr/bin/env bash
# a dry run changes nothing: with origin's dev ahead, rapid land --dry-run and rapid release
# --dry-run leave local dev, its work tree and the release tags where they were, and say to sync first.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/a" origin; cd "$T/a"
git clone -q "$T/origin.git" "$T/b"; ( cd "$T/b" && git switch -q dev && rapid setup >/dev/null )
rapid branch feature mine >/dev/null; commit mine.txt; ml=$(git branch --show-current)
cd "$T/b"; actor "Agent Two" agent2@team.test
rapid branch feature ahead >/dev/null; commit ahead.txt; rapid land >/dev/null || fail "B lands"
cd "$T/a"; actor "Agent One" agent1@team.test
d0=$(git rev-parse dev)
refused rapid land --dry-run
grep -q 'a dry run never moves dev' "$T/err" || fail "land --dry-run gave no reason: $(cat "$T/err")"
[ "$(git rev-parse dev)" = "$d0" ] || fail "land --dry-run moved local dev"
git switch -q dev
refused rapid release --dry-run
grep -q 'a dry run never moves dev' "$T/err" || fail "release --dry-run gave no reason: $(cat "$T/err")"
[ "$(git rev-parse dev)" = "$d0" ] && [ -z "$(git tag -l "release/*")" ] || fail "release --dry-run moved dev or tagged"
[ ! -f ahead.txt ] || fail "the work tree followed a dry run"
rapid sync --dev >/dev/null || fail "sync --dev"
git switch -q "$ml"; rapid sync >/dev/null || fail "sync the branch"
rapid land --dry-run >/dev/null || fail "a dry run on a current dev"
history_clean
