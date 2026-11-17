#!/usr/bin/env bash
# release dev's tip, then the next land opens a new series; main takes it by a release merge (I5). The
# release tag lists the branches still open, oldest first, with their first and last commit dates.
. "$(dirname "$0")/../lib.sh"
actor "Human Dev" human@team.test
mkrepo "$T/r" origin; cd "$T/r"
rapid branch feature export >/dev/null; commit export.txt; rapid land >/dev/null || fail "land 1"
rapid branch fix export-crlf >/dev/null; commit crlf.txt c "[FIX] Write CRLF line endings on export"; rapid land >/dev/null || fail "land 2"
# two open branches, one only on origin (a coworker's), the older one first in the report
git switch -q -c pool/v2026.0/feature.later dev; commit later.txt l "[NEW] Add the later open branch file"
commit later2.txt l "[NEW] Add a second later open branch file"
git switch -q -c pool/v2026.0/feature.older dev; GIT_AUTHOR_DATE=2026-02-01T10:00:00Z git commit -q --allow-empty -m "[NEW] Start the older open branch early"
GIT_AUTHOR_DATE=2026-02-03T10:00:00Z git commit -q --allow-empty -m "[NEW] Continue the older open branch"
git push -q origin pool/v2026.0/feature.older; git switch -q dev; git branch -q -D pool/v2026.0/feature.older
settle
main0=$(git rev-parse main)
rapid release v2026.0.2 > "$T/out" || fail "release: $(cat "$T/out")"
[ "$(git rev-parse main^2)" = "$(git rev-parse dev)" ] && [ "$(git rev-parse main^{tree})" = "$(git rev-parse dev^{tree})" ] \
  || fail "main is not the release merge of dev's tip"
[ "$(git rev-parse main^1)" = "$main0" ] || fail "the release merge does not sit on the old main"
git rev-parse -q --verify refs/tags/release/v2026.0.2 >/dev/null || fail "no release tag"
rep=$(git cat-file -p release/v2026.0.2 | sed -n '/^Open branches/,/^$/p')
[ "$(sed -n 2p <<<"$rep")" = "- pool/v2026.0/feature.older 2026-02-01 - 2026-02-03 (2 commits)" ] || fail "release report: $rep"
grep -q '^- pool/v2026.0/feature.later .* (2 commits)$' <<<"$(sed -n 3p <<<"$rep")" || fail "release report misses the later branch: $rep"
[ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$(git rev-parse main)" ] || fail "origin main differs"
[ -n "$(git ls-remote origin refs/tags/release/v2026.0.2)" ] || fail "release tag not on origin"
refused rapid release
grep -q 'already released' "$T/err" || fail "second release text: $(cat "$T/err")"
rapid branch feature import >/dev/null; commit import.txt; rapid land >/dev/null || fail "land after release"
[ "$(git describe --exact-match dev)" = v2026.1.1 ] || fail "next land is $(git describe --exact-match dev), want v2026.1.1"
history_clean
