#!/usr/bin/env bash
# rapid version answers from history and stores nothing: no version before the first land, the last
# version on dev after each land, --next the version the next land takes (the next number, the next
# series after a release, a new year's first), --at the version of the land that brought a commit
# into dev, even after later lands; a commit dev does not hold is refused; no ref or file changes.
. "$(dirname "$0")/../lib.sh"
actor "Owner One" owner@team.test
mkrepo "$T/r"; cd "$T/r"
refused rapid version
grep -q 'dev carries no version yet' "$T/err" || fail "a dev without a version gave no reason: $(cat "$T/err")"
[ "$(rapid version --next)" = v2026.0.1 ] || fail "the first land's version is not v2026.0.1: $(rapid version --next)"
rapid branch feature export >/dev/null; commit export.txt; ca=$(git rev-parse HEAD); rapid land >/dev/null || fail "land export"
[ "$(rapid version)" = v2026.0.1 ] || fail "the last version is not v2026.0.1: $(rapid version)"
[ "$(rapid version --next)" = v2026.0.2 ] || fail "the next version is not v2026.0.2"
rapid branch fix crlf >/dev/null; commit crlf.txt; cb=$(git rev-parse HEAD); rapid land >/dev/null || fail "land crlf"
refs0=$(git for-each-ref)
[ "$(rapid version)" = v2026.0.2 ] || fail "the last version is not v2026.0.2"
[ "$(rapid version --at "$ca")" = v2026.0.1 ] || fail "--at an older branch commit is not its land's version: $(rapid version --at "$ca" 2>&1)"
[ "$(rapid version --at "$cb")" = v2026.0.2 ] || fail "--at the newer branch commit is not v2026.0.2"
[ "$(rapid version --at dev)" = v2026.0.2 ] || fail "--at dev's tip is not v2026.0.2"
[ "$(rapid version --at v2026.0.1)" = v2026.0.1 ] || fail "--at a landed merge is not its own version"
# after a release the next land opens the next series; a new year starts over
rapid release >/dev/null 2>&1 || fail "release"
refs0=$(git for-each-ref)
[ "$(rapid version)" = v2026.0.2 ] || fail "a release changed the last version"
[ "$(rapid version --next)" = v2026.1.1 ] || fail "the land after a release is not v2026.1.1: $(rapid version --next)"
[ "$(RAPID_YEAR=2027 rapid version --next)" = v2027.0.1 ] || fail "a new year's first land is not v2027.0.1"
# a commit dev does not hold has no version
rapid branch feature import >/dev/null; commit import.txt
refs0=$(git for-each-ref)
refused rapid version --at HEAD
grep -q 'dev does not hold HEAD' "$T/err" || fail "a commit not landed yet was given a version: $(cat "$T/err")"
rc=0; rapid version --at no-such-rev >/dev/null 2>&1 || rc=$?; [ "$rc" = 2 ] || fail "an unknown revision: exit $rc, want 2"
rc=0; rapid version --bump >/dev/null 2>&1 || rc=$?; [ "$rc" = 2 ] || fail "an unknown flag: exit $rc, want 2"
grep -q '^  rapid version ' <<<"$(rapid version -h)" || fail "version -h is not version's usage"
[ "$(git for-each-ref)" = "$refs0" ] && [ -z "$(git status --porcelain)" ] || fail "rapid version changed the repository"
[ ! -e version.build ] || fail "a counter file was written"
history_clean
