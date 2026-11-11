#!/usr/bin/env bash
# fast
# push-is-transport: a branch push runs no gate, so a branch holding a red commit reaches origin as it is,
# and the close, which tests the tree it pushes, refuses it with origin's dev untouched; rapid sync
# rebases locally and never pushes (origin's copy of the branch stays where it was); the branch goes
# to origin by a plain git push, and a refused push prints the remote's own reason.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r" origin; cd "$T/r"
d0=$(git rev-parse dev)
# a red commit made past pre-commit: the push is transport, no gate, it reaches origin
rapid branch fix red >/dev/null; commit r1.txt
printf 'x\n' > boom.bad; git add boom.bad
git commit -q --no-verify -m "[FIX] Add a file that breaks the gate" -m "Cause: the defect this scenario plants." -m "Fix: the repair this scenario makes."
red=$(git rev-parse HEAD); branch=$(lname red)
git push -q origin "$branch" >/dev/null 2>"$T/err" || fail "a branch push ran a gate: $(cat "$T/err")"
settle
[ "$(git ls-remote origin "refs/heads/$branch" | cut -f1)" = "$red" ] || fail "the red branch did not reach origin"
# the close tests the tree it pushes: it refuses the red branch and pushes nothing
rapid land --batch >/dev/null 2>"$T/err" || fail "the batch land refused the red branch before its close: $(cat "$T/err")"
refused rapid land
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$d0" ] || fail "a red close pushed dev"
command rapid land --prune >/dev/null || fail "land --prune"
# sync never pushes: origin's copy stays until the branch is pushed
git switch -q dev; rapid branch feature keep >/dev/null; commit k1.txt
keep=$(lname keep); git push -q origin "$keep"; o1=$(git rev-parse HEAD)
settle
commit k2.txt
rapid sync >/dev/null || fail "sync"
[ "$(git ls-remote origin "refs/heads/$keep" | cut -f1)" = "$o1" ] || fail "rapid sync pushed the branch"
git push -q origin "$keep" >/dev/null 2>"$T/err" || fail "the branch push after a sync: $(cat "$T/err")"
settle
[ "$(git ls-remote origin "refs/heads/$keep" | cut -f1)" = "$(git rev-parse HEAD)" ] || fail "the push left origin's branch behind"
# a refused push shows the remote's reason
commit k3.txt
printf '#!/bin/sh\necho "forge rule: branches are frozen today" >&2; exit 1\n' > "$T/origin.git/hooks/pre-receive"; chmod +x "$T/origin.git/hooks/pre-receive"
refused git push origin "$keep"
grep -qF 'forge rule: branches are frozen today' "$T/err" || fail "the remote's refusal text was not shown: $(cat "$T/err")"
