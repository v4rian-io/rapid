#!/usr/bin/env bash
# a branch landing into a batch whose close is testing stops that test: the close exits without
# pushing and its gate is gone with everything it started, the branch lands, and the next close
# tests the new final tree and pushes it all; a gate that reads its input finds none; while a close publishes
# the batch a land refuses, and a marker left by a close that is gone is stale.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/a" origin; cd "$T/a"
d0=$(git rev-parse dev)
rapid branch feature one >/dev/null; printf 'echo $$ > "%s/gate.pid"; sleep 90 & echo $! > "%s/gate.child"; wait\n' "$T" "$T" > check.sh; git add check.sh; commit one.txt
rapid land --batch >/dev/null || fail "batch land one"
git switch -q dev
( rapid land >"$T/close1" 2>&1 ) &
for _ in $(seq 1 50); do [ -s "$(git rev-parse --git-common-dir)/rapid/batch.closing" ] && break; sleep 0.2; done
[ -s "$(git rev-parse --git-common-dir)/rapid/batch.closing" ] || fail "the close never started testing"
# the next gate reads its input: a gate has none, so it must see the end of input at once
rapid branch feature two >/dev/null
printf 'if read -r x; then echo "read:$x"; else echo eof; fi > "%s/gate.stdin"\nexit 0\n' "$T" > check.sh; git add check.sh; commit two.txt
s0=$(date +%s)
rapid land --batch >"$T/out" 2>&1 || fail "batch land two: $(cat "$T/out")"
grep -q 'stopped the close testing' "$T/out" || fail "the land did not stop the running close"
wait
grep -q 'batch gates pass' "$T/close1" && fail "the stopped close reported success"
# the gate of the stopped close is gone with everything it started
for f in gate.pid gate.child; do
  [ -s "$T/$f" ] || fail "the gate never recorded $f"
  ! kill -0 "$(cat "$T/$f")" 2>/dev/null || fail "the gate of the stopped close is still running ($f $(cat "$T/$f"))"
done
[ $(( $(date +%s) - s0 )) -lt 75 ] || fail "the stopped close's test ran on"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$d0" ] || fail "the stopped close pushed"
printf 'a line no gate may read\n' | rapid land >/dev/null || fail "the second close"
[ "$(cat "$T/gate.stdin" 2>/dev/null)" = eof ] || fail "the gate read the input of rapid land instead of none: $(cat "$T/gate.stdin" 2>&1)"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$(git rev-parse dev)" ] || fail "the second close did not push the final tree"
# once the close passed and publishes the batch, a land refuses until that close ends; a marker
# left by a close that is gone is stale and the land goes on
pub="$(git rev-parse --git-common-dir)/rapid/batch.publishing"
sleep 60 & live=$!; echo "$live" > "$pub"
rapid branch feature three >/dev/null; commit three.txt
if rapid land --batch > "$T/out" 2>&1; then fail "a land joined a batch whose close is publishing"; fi
grep -qF "a close is publishing the batch; land again when it ends" "$T/out" || fail "the land did not name the publishing close: $(cat "$T/out")"
kill "$live" 2>/dev/null; wait "$live" 2>/dev/null || true
rapid land --batch >/dev/null || fail "a land after the publishing close ended"
[ ! -e "$pub" ] || fail "the stale publishing marker stayed"
grep -qF "lifted batch.publishing: holder pid $live gone (rapid land" "$(git rev-parse --git-common-dir)/rapid/log" || fail "the lift of the publishing marker is not logged"
ok "a branch joining a batch stops its running close"
