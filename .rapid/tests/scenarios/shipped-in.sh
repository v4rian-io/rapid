#!/usr/bin/env bash
# rapid release --of names the release that first shipped a commit: a branch commit, its landed merge, a
# version tag or the release merge on main answer the first release/<v> at or after that land, and keep answering it after a
# later release; a land no release holds yet and a commit dev does not hold answer "unreleased";
# nothing is tagged, merged or moved by asking.
. "$(dirname "$0")/../lib.sh"
actor "Owner One" owner@team.test
mkrepo "$T/r"; cd "$T/r"
rapid branch feature export >/dev/null; commit export.txt; ca=$(git rev-parse HEAD); rapid land >/dev/null || fail "land export"
rapid branch fix crlf >/dev/null; commit crlf.txt; cb=$(git rev-parse HEAD); rapid land >/dev/null || fail "land crlf"
[ "$(rapid release --of "$ca")" = "unreleased ($ca landed as v2026.0.1; no release holds it yet)" ] || fail "before any release: $(rapid release --of "$ca" 2>&1)"
rapid release >/dev/null 2>&1 || fail "release"
rapid branch feature import >/dev/null; commit import.txt; cc=$(git rev-parse HEAD); rapid land >/dev/null || fail "land import"
rapid branch feature notes >/dev/null; commit notes.txt
refs0=$(git for-each-ref); main0=$(git rev-parse main)
[ "$(rapid release --of "$ca")" = release/v2026.0.2 ] || fail "the first branch's release: $(rapid release --of "$ca" 2>&1)"
[ "$(rapid release --of "$cb")" = release/v2026.0.2 ] || fail "the second branch's release: $(rapid release --of "$cb" 2>&1)"
[ "$(rapid release --of v2026.0.1)" = release/v2026.0.2 ] || fail "a version tag's release: $(rapid release --of v2026.0.1 2>&1)"
[ "$(rapid release --of main)" = release/v2026.0.2 ] || fail "the release merge on main: $(rapid release --of main 2>&1)"
[ "$(rapid release --of "$cc")" = "unreleased ($cc landed as v2026.1.1; no release holds it yet)" ] || fail "a land after the release: $(rapid release --of "$cc" 2>&1)"
# a commit dev does not hold
[ "$(rapid release --of HEAD)" = "unreleased (HEAD is not on dev)" ] || fail "a commit not landed yet: $(rapid release --of HEAD 2>&1)"
rc=0; rapid release --of no-such-rev >/dev/null 2>&1 || rc=$?; [ "$rc" = 2 ] || fail "an unknown revision: exit $rc, want 2"
rc=0; rapid release --of >/dev/null 2>&1 || rc=$?; [ "$rc" = 2 ] || fail "no revision: exit $rc, want 2"
[ "$(git for-each-ref)" = "$refs0" ] || fail "release --of moved a ref"
[ "$(git rev-parse main)" = "$main0" ] && [ "$(git tag -l 'release/*')" = release/v2026.0.2 ] || fail "release --of released something"
# the next release ships the later land; the earlier answer stays
git switch -q dev
rapid release >/dev/null 2>&1 || fail "the second release"
[ "$(rapid release --of "$cc")" = release/v2026.1.1 ] || fail "the later land's release: $(rapid release --of "$cc" 2>&1)"
[ "$(rapid release --of "$ca")" = release/v2026.0.2 ] || fail "the first answer changed after a later release"
history_clean
