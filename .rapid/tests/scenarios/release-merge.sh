#!/usr/bin/env bash
# a release is a --no-ff merge of dev into main, "[MERGE] dev into main: <v>", made by the owner's
# rapid release: its second parent is the released dev tip, its tree that tip's, its body the branches
# landed since the last release, so git log --first-parent main lists the releases. pre-push refuses
# main moving to a dev commit, to a merge whose tree is not the released one and to a merge without
# the release subject; doctor flags a forged main (I5). A main fast-forwarded before release merges
# takes the next release merge on top, and the history holds.
. "$(dirname "$0")/../lib.sh"
actor "Owner One" owner@team.test
mkrepo "$T/r" origin; cd "$T/r"
root=$(git rev-parse main)
rapid branch feature export >/dev/null; commit export.txt; rapid land >/dev/null || fail "land 1"
rapid branch fix export-crlf >/dev/null; commit crlf.txt c "[FIX] Write CRLF line endings on export"; rapid land >/dev/null || fail "land 2"
rapid release > "$T/out" 2>&1 || fail "release 1: $(cat "$T/out")"
m1=$(git rev-parse main)
[ "$(git log -1 --format=%s main)" = "[MERGE] dev into main: v2026.0.2" ] || fail "release subject: $(git log -1 --format=%s main)"
[ "$(git rev-list --parents -n1 main)" = "$m1 $root $(git rev-parse dev)" ] || fail "the release merge's parents are not old main and dev's tip"
[ "$(git rev-parse main^{tree})" = "$(git rev-parse dev^{tree})" ] || fail "the release merge's tree is not dev's"
git log -1 --format=%B main | grep -Fx '    - v2026.0.1 feature/export' >/dev/null && git log -1 --format=%B main | grep -Fx '    - v2026.0.2 fix/export-crlf' >/dev/null \
  || fail "the release body does not list the branches: $(git log -1 --format=%B main)"
git log -1 --format=%B main | grep -Fx 'Release: release/v2026.0.2' >/dev/null || fail "no Release: trailer"
[ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$m1" ] || fail "origin main is not the release merge"
rapid branch feature import >/dev/null; commit import.txt; rapid land >/dev/null || fail "land 3"
rapid release >/dev/null 2>&1 || fail "release 2"
[ "$(git log --first-parent --format=%s main)" = "[MERGE] dev into main: v2026.1.1
[MERGE] dev into main: v2026.0.2
[NEW] Seed the rapid workflow" ] || fail "main's first-parent line is not the release list: $(git log --first-parent --format=%s main)"
git log -1 --format=%B main | grep -Fx '    - v2026.1.1 feature/import' >/dev/null || fail "release 2 lists more than its own branches"
[ "$(git log -1 --format=%B main | grep -c '^    - v')" = 1 ] || fail "release 2 lists earlier branches"
history_clean
m2=$(git rev-parse main)
# pre-push: main never moves to a dev commit, nor by a hand merge that is not the release
rapid branch feature extra >/dev/null; commit extra.txt; rapid land >/dev/null || fail "land 4"
v=$(git describe --exact-match dev); git tag -a "release/$v" -m "owner release by hand" dev
refused git push --atomic origin dev:refs/heads/main "refs/tags/release/$v"
bad=$(git commit-tree "$m2^{tree}" -p "$m2" -p dev -m "[MERGE] dev into main: $v")
refused git push --atomic origin "$bad:refs/heads/main" "refs/tags/release/$v"
grep -q "tree is not the released dev commit's tree" "$T/err" || fail "pre-push let a wrong-tree release through: $(cat "$T/err")"
bad=$(git commit-tree "$(git rev-parse dev^{tree})" -p "$m2" -p dev -m "[MERGE] Ship it")
refused git push --atomic origin "$bad:refs/heads/main" "refs/tags/release/$v"
grep -q "subject is not '\[MERGE\] dev into main: $v'" "$T/err" || fail "pre-push let a misnamed release through: $(cat "$T/err")"
[ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$m2" ] || fail "origin main moved"
# forged locally past every hook: doctor names it
git update-ref refs/heads/main "$(git commit-tree "$(git rev-parse dev^{tree})" -p "$m2" -m "[NEW] Forge main by hand")"
rapid doctor --history-only > "$T/doc" 2>&1 && fail "doctor missed a forged main"
grep -q '^doctor: I5 .* neither a release merge nor a released dev commit' "$T/doc" || fail "no I5 for the forged main: $(cat "$T/doc")"
git update-ref refs/heads/main "$m2"; git tag -d "release/$v" >/dev/null
# a main still at the root never moves to a dev commit: pre-push refuses it by name
mkrepo "$T/f"; cd "$T/f"; git remote add origin "$(mkremote f)"; rapid setup >/dev/null
rapid branch feature one >/dev/null; commit one.txt; rapid land >/dev/null || fail "land in f"
git tag -a release/v2026.0.1 -m "owner release by hand" dev
refused git push --atomic origin dev:refs/heads/main refs/tags/release/v2026.0.1
grep -q 'main only moves by a release merge' "$T/err" || fail "pre-push let main fast-forward to dev: $(cat "$T/err")"
# a main fast-forwarded before release merges takes the next release merge on top
mkrepo "$T/old"; cd "$T/old"
rapid branch feature one >/dev/null; commit one.txt; rapid land >/dev/null || fail "old land"
git tag -a release/v2026.0.1 -m "rapid release v2026.0.1 (before release merges)" dev; git update-ref refs/heads/main dev
history_clean
rapid branch feature two >/dev/null; commit two.txt; rapid land >/dev/null || fail "land after the old release"
rapid release >/dev/null 2>&1 || fail "release on a fast-forwarded main"
[ "$(git rev-parse main^1)" = "$(git rev-parse release/v2026.0.1^{commit})" ] && [ "$(git log -1 --format=%s main)" = "[MERGE] dev into main: v2026.1.1" ] \
  || fail "the release merge does not sit on the old main: $(git log --first-parent --format='%h %s' main)"
history_clean
