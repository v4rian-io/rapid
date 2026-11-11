#!/usr/bin/env bash
# batch landing: rapid land --batch lands each branch exactly as a single land does (its own merge,
# version tag and test record) but locally and without gates; rapid land gates the final dev
# tree once and pushes everything in one atomic push. When that gate fails the batch stays: dev, the tags and
# the branches are kept, the branch that broke the close is named, nothing is pushed (the pre-push guard refuses any push while
# the batch is open), and rapid land --prune is the rollback.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/a" origin; cd "$T/a"
d0=$(git rev-parse dev)
rapid branch feature one >/dev/null; commit one.txt; l1=$(git branch --show-current)
rapid land --batch >/dev/null || fail "batch land one"
# a branch that landed into the open batch takes no more commits: more work goes on a new branch
git switch -q "$l1"; printf 'more\n' > more.txt; git add more.txt
if git commit -q -m "[NEW] Add more to a landed branch" -m "This commit lands after its branch already landed." 2> "$T/err"; then fail "a landed branch took a commit"; fi
grep -qF "landed into the open batch; more work goes on a new branch" "$T/err" || fail "the refusal does not name the landed branch: $(cat "$T/err")"
git reset -q; rm -f more.txt
git switch -q dev; rapid branch feature two >/dev/null; commit two.txt; l2=$(git branch --show-current)
rapid land --batch >/dev/null || fail "batch land two"
[ "$(git rev-list --first-parent --count "$d0..dev")" = 2 ] || fail "two batch lands are not two merges on dev"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$d0" ] || fail "a batch land pushed before its close"
[ -z "$(git ls-remote origin "refs/heads/$l1" "refs/heads/$l2")" ] || fail "a batch land pushed a branch before its close"
git log -1 --format=%B dev | grep -E '^Gates: deferred to the close of batch [0-9a-f]+$' >/dev/null || fail "the test record does not defer to the close of its batch"
printf '#!/bin/sh\necho push >> "%s/pushes"\n' "$T" > "$T/origin.git/hooks/pre-receive"; chmod +x "$T/origin.git/hooks/pre-receive"
rapid land >/dev/null || fail "batch close"
[ "$(wc -l < "$T/pushes" | tr -d ' ')" = 1 ] || fail "the close pushed $(wc -l < "$T/pushes" | tr -d ' ') times; a batch is one push"
[ -n "$(git ls-remote origin "refs/heads/vault/*")" ] && [ -n "$(git ls-remote origin "refs/heads/safety/*")" ] || fail "the close's one push left out the vault or safety branches"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$(git rev-parse dev)" ] || fail "the close did not push dev"
[ -n "$(git ls-remote origin "refs/tags/$(git describe --tags --abbrev=0 dev)")" ] || fail "the close did not push the tags"
history_clean
# a failing batch gate: the batch stays, the branch that broke the close is named, nothing is pushed
d1=$(git rev-parse dev)
git switch -q dev; rapid branch feature three >/dev/null; printf 'exit 1\n' > check.sh; git add check.sh; commit three.txt
l3=$(git branch --show-current); t3=$(git rev-parse HEAD)
rapid land --batch >/dev/null || fail "batch land three"
v3=$(git describe --tags --exact-match dev); d3=$(git rev-parse dev)
refused rapid land
grep -q 'nothing was pushed and the batch stays open' "$T/err" || fail "a failing close gave no reason: $(cat "$T/err")"
grep -qF "broke the close: $l3 ($v3" "$T/out" || fail "a failing close did not name the branch that broke the close: $(cat "$T/out")"
[ "$(git rev-parse dev)" = "$d3" ] && [ -n "$(git tag -l "$v3")" ] || fail "a failing close did not keep the batch"
[ -s "$(git rev-parse --git-common-dir)/rapid/batch" ] || fail "a failing close closed the batch"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$d1" ] || fail "a failing close pushed"
[ "$(git rev-parse "$l3")" = "$t3" ] || fail "a failing close changed the branch"
# while the batch is open nothing is pushed but by its close
refused git push -q origin dev
grep -q 'a batch is open' "$T/err" || fail "a push during an open batch was not refused by the guard: $(cat "$T/err")"
# rapid land --prune is the rollback: dev back, the tags and vault branches gone, the branch as it was
command rapid land --prune >/dev/null || fail "land --prune"
[ "$(git rev-parse dev)" = "$d1" ] || fail "land --prune left dev moved"
[ -z "$(git tag -l "$v3")" ] || fail "land --prune kept the batch's tag $v3"
[ "$(git rev-parse "$l3")" = "$t3" ] || fail "land --prune changed the branch"
[ -z "$(git for-each-ref "refs/heads/vault/*/${l3##*/}")" ] || fail "land --prune kept the vault branch of a branch it put back"
[ ! -e "$(git rev-parse --git-common-dir)/rapid/batch.branches" ] || fail "land --prune left its list of batch branches behind"
# run again on dev with no batch open: nothing is owed, which is no failure
git switch -q dev; rapid land > "$T/out" 2>&1 || fail "rapid land with nothing owed failed: $(cat "$T/out")"
grep -qF "nothing to land; no close is owed" "$T/out" || fail "rapid land with nothing owed said: $(cat "$T/out")"
ok "batch lands defer the gates to one close"
