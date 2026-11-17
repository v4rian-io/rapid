#!/usr/bin/env bash
# rapid sync --push: rapid sync rebases the branch locally and never pushes by itself, so origin's copy
# stays where it was; --push then sends the branch to origin with a lease on the copy origin held, or
# creates it, and says what it pushed; a push origin refuses exits 1 with the remote's own reason; with
# no origin --push is refused by name; while a batch is open the push is refused like every other push.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r" origin; cd "$T/r"
R="$(type -P rapid)"
rapid branch feature keep >/dev/null; commit k1.txt
keep=$(lname keep)
# --push creates the branch on origin
"$R" sync --push > "$T/out" 2>&1 || fail "sync --push of a new branch: $(cat "$T/out")"
grep -qF "pushed $keep (lease on <none>)" "$T/out" || fail "sync --push did not say what it pushed: $(cat "$T/out")"
o1=$(git rev-parse HEAD)
[ "$(git ls-remote origin "refs/heads/$keep" | cut -f1)" = "$o1" ] || fail "sync --push did not create the branch on origin"
# a plain sync never pushes: origin's copy stays
commit k2.txt
"$R" sync > "$T/out" 2>&1 || fail "sync: $(cat "$T/out")"
[ "$(git ls-remote origin "refs/heads/$keep" | cut -f1)" = "$o1" ] || fail "rapid sync pushed the branch"
# --push moves origin's copy, with a lease on the copy it held
"$R" sync --push > "$T/out" 2>&1 || fail "sync --push: $(cat "$T/out")"
grep -qF "pushed $keep (lease on $(git rev-parse --short "$o1"))" "$T/out" || fail "sync --push named no lease: $(cat "$T/out")"
[ "$(git ls-remote origin "refs/heads/$keep" | cut -f1)" = "$(git rev-parse HEAD)" ] || fail "sync --push left origin's branch behind"
# nothing to send: no push, no word of one
"$R" sync --push > "$T/out" 2>&1 || fail "sync --push with nothing new: $(cat "$T/out")"
grep -q 'pushed ' "$T/out" && fail "sync --push pushed a branch origin already holds: $(cat "$T/out")"
# a push origin refuses exits 1 with the remote's own reason
commit k3.txt
printf '#!/bin/sh\necho "forge rule: branches are frozen today" >&2; exit 1\n' > "$T/origin.git/hooks/pre-receive"; chmod +x "$T/origin.git/hooks/pre-receive"
rc=0; "$R" sync --push > "$T/out" 2> "$T/err" || rc=$?
[ "$rc" = 1 ] || fail "a refused sync --push exited $rc"
grep -qF 'forge rule: branches are frozen today' "$T/err" || fail "the remote's refusal text was not shown: $(cat "$T/err")"
[ "$(git ls-remote origin "refs/heads/$keep" | cut -f1)" != "$(git rev-parse HEAD)" ] || fail "a refused push moved origin's branch"
rm -f "$T/origin.git/hooks/pre-receive"
# while a batch is open the push is refused like every other push
git switch -q dev; rapid branch feature other >/dev/null; commit o1.txt; "$R" land --batch >/dev/null || fail "land other"
git switch -q "$keep"
refused "$R" sync --push
[ "$(git ls-remote origin "refs/heads/$keep" | cut -f1)" != "$(git rev-parse HEAD)" ] || fail "sync --push went out while a batch is open"
"$R" land >/dev/null 2>&1 || fail "close"
# no origin: refused by name
mkrepo "$T/n"; cd "$T/n"
rapid branch feature lone >/dev/null; commit l1.txt
refused command rapid sync --push
grep -qF 'sync --push: no origin to push to' "$T/err" || fail "sync --push without origin: $(cat "$T/err")"
