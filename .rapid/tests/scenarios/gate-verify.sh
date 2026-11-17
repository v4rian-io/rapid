#!/usr/bin/env bash
# gate test records are re-verified: a hand-built merge claiming Gates: pass over a failing tree is
# refused by pre-push (its fast gate is rerun, also when it carries a close note another clone
# wrote) and, planted past the hook, reported by doctor --verify with the test record it claimed;
# a dev push without the merge's version tag is refused; a release tag records its gate and tree.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/a" origin; cd "$T/a"
rapid branch feature good >/dev/null; commit good.txt; rapid land >/dev/null || fail "land good"
d=$(git rev-parse dev)
git switch -q -c pool/v2026.0/feature.red dev
printf '# feature/red\n\nBreak the gate while claiming it passed.\n' > .rapid/requirements/red.md
git add .rapid/requirements/red.md; commit x.bad bad "[NEW] Add a file that breaks the gate"
tree=$(git rev-parse HEAD^{tree})
printf '[MERGE] pool/v2026.0/feature.red into dev: v2026.0.2\n\nForges a green test record.\n\n- Files.\n    - x.bad: breaks the gate.\n\nBranch-Base: %s\nRequirement: .rapid/requirements/red.md\nGates: fast=pass full=pass\nTested-Tree: %s\nBranch-Number: n9\n' "$d" "$tree" > "$T/msg"
m=$(git commit-tree "$tree" -p "$d" -p HEAD -F "$T/msg")
git tag -a v2026.0.2 -m forged "$m"
refused git push origin "$m:refs/heads/dev" refs/tags/v2026.0.2
grep -q 'fails its fast gate' "$T/err" || fail "a forged green test record passed pre-push: $(cat "$T/err")"
# a close note written by another clone (fetched, copied or forged) never skips the rerun
git notes --ref=rapid-close add -f -m "fast=pass full=pass tree=$tree clone=0123456789abcdef" "$m"
refused git push origin "$m:refs/heads/dev" refs/tags/v2026.0.2
grep -q 'fails its fast gate' "$T/err" || fail "a foreign close note skipped the gate rerun: $(cat "$T/err")"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$d" ] || fail "origin dev moved"
git push -q --no-verify origin "$m:refs/heads/dev" refs/tags/v2026.0.2
git clone -q "$T/origin.git" "$T/c"; cd "$T/c"; git switch -q dev; rapid setup >/dev/null
refused rapid doctor --verify
grep -q "P1 $m gate fast fails" "$T/out" || fail "doctor --verify missed the forged test record: $(cat "$T/out" "$T/err")"
grep -q "P1 $m gate fast fails on the merge tree (test record says pass)" "$T/out" || fail "doctor --verify misread the test record: $(cat "$T/out")"
rapid doctor --verify "$m" >/dev/null || fail "doctor --verify after the forged merge should find nothing newer"
# a dev push without the merge's tag is refused
cd "$T/a"; git switch -q dev; git reset -q --hard "$d"; git tag -d v2026.0.2 >/dev/null
git config remote.origin.url "$T/offline.git"
rapid branch feature solo >/dev/null; commit solo.txt; rapid land >/dev/null 2>&1 || fail "offline land"
git config remote.origin.url "$T/origin2.git"; git init -q --bare "$T/origin2.git"
git push -q --no-verify origin "$d:refs/heads/dev" "$(git rev-parse main):refs/heads/main"
refused git push origin dev
grep -q 'without its tag' "$T/err" || fail "a dev push without its tag passed: $(cat "$T/err")"
rapid sync --dev >/dev/null || fail "sync --dev publishes dev with its tag"
[ -n "$(git ls-remote origin refs/tags/v2026.0.2)" ] || fail "the tag did not reach origin"
# the release tag records its gate and tested tree
rapid release >/dev/null || fail "release"
grep -q '^Gates: release=pass$' <<<"$(git cat-file -p release/v2026.0.2)" || fail "release tag has no gate test record"
grep -q "^Tested-Tree: $(git rev-parse dev^{tree})$" <<<"$(git cat-file -p release/v2026.0.2)" || fail "release tag has no tested tree"
history_clean
