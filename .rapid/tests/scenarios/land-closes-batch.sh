#!/usr/bin/env bash
# rapid land lands its branch and closes the open batch: the branches landed with --batch before it
# stayed local, the close tests the final tree once and one push carries every merge. With no batch
# open it is a batch of one, through the same path. Run again it redoes nothing: a close origin refused
# runs again from the landed branch, or from dev, without testing the same tree twice. rapid land --halt
# stops the close under test and keeps the batch, and says so when no close is under test.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/a" origin; cd "$T/a"
R="$(type -P rapid)"
d0=$(git rev-parse dev)
count_hook() { printf '#!/bin/sh\nwhile read -r o n r; do case "$r" in refs/heads/dev|refs/tags/v*) echo push >> "%s/pushes"; break ;; esac; done\n' "$T" > "$T/origin.git/hooks/pre-receive"; chmod +x "$T/origin.git/hooks/pre-receive"; }
refuse_hook() { printf '#!/bin/sh\necho "forge rule: frozen today" >&2; exit 1\n' > "$T/origin.git/hooks/pre-receive"; chmod +x "$T/origin.git/hooks/pre-receive"; }
count() { if [ -e "$T/$1" ]; then wc -l < "$T/$1" | tr -d ' '; else echo 0; fi; }
count_hook
rapid branch feature one >/dev/null
printf '#!/bin/sh\necho gate >> "%s/gates"\nwhile [ -e "%s/wait" ] && [ ! -e "%s/go" ]; do sleep 0.2; done\n! ls *.bad >/dev/null 2>&1\n' "$T" "$T" "$T" > check.sh; git add check.sh; commit one.txt
"$R" land --batch >/dev/null 2>&1 || fail "land --batch one"
git switch -q dev; rapid branch feature two >/dev/null; commit two.txt; "$R" land --batch >/dev/null 2>&1 || fail "land --batch two"
[ "$(count gates)" = 0 ] && [ "$(count pushes)" = 0 ] || fail "a land --batch ran a gate or pushed"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$d0" ] || fail "origin's dev moved before the close"
# the last branch lands without --batch: the batch closes in the same command
git switch -q dev; rapid branch feature three >/dev/null; commit three.txt
"$R" land > "$T/out" 2>&1 || fail "land: $(cat "$T/out")"
grep -q 'landed feature/three as ' "$T/out" || fail "the land did not land its branch: $(cat "$T/out")"
grep -qF 'published the batch in one push: 3 merges' "$T/out" || fail "the land did not close the batch of three: $(cat "$T/out")"
[ "$(count gates)" = 1 ] || fail "the close ran its gate $(count gates) times"
[ "$(count pushes)" = 1 ] || fail "the land pushed $(count pushes) times; a batch is one push"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$(git rev-parse dev)" ] || fail "the land did not publish dev"
[ ! -e "$(git rev-parse --git-common-dir)/rapid/batch" ] || fail "the batch is still open after the land"
history_clean
# no batch open: a batch of one, through the same path
git switch -q dev; rapid branch feature four >/dev/null; commit four.txt
"$R" land > "$T/out" 2>&1 || fail "land with no batch open: $(cat "$T/out")"
grep -qF 'published the batch in one push: 1 merges' "$T/out" || fail "a land alone is not a batch of one: $(cat "$T/out")"
grep -qE '^Gates: deferred to the close of batch [0-9a-f]+$' <<<"$(git log -1 --format=%B dev)" || fail "the test record of a batch of one: $(git log -1 --format=%B dev)"
[ "$(count gates)" = 2 ] && [ "$(count pushes)" = 2 ] || fail "a batch of one ran $(count gates) gates and $(count pushes) pushes in all"
# a close origin refuses is owed: rapid land again, from the landed branch, publishes without a second test
git switch -q dev; rapid branch feature five >/dev/null; commit five.txt; five=$(git branch --show-current)
refuse_hook
rc=0; "$R" land > "$T/out" 2> "$T/err" || rc=$?
[ "$rc" = 1 ] || fail "a land whose push origin refuses exited $rc"
grep -qF 'origin refused the batch push' "$T/err" || fail "the refusal was not named: $(cat "$T/err")"
m5=$(git rev-parse dev); [ "$(git ls-remote origin refs/heads/dev | cut -f1)" != "$m5" ] || fail "a refused push moved origin"
count_hook
git switch -q "$five"
"$R" land > "$T/out" 2>&1 || fail "land again from the landed branch: $(cat "$T/out")"
grep -q 'already passed its gate; publishing it' "$T/out" || fail "the owed close tested the same tree again: $(cat "$T/out")"
[ "$(git rev-parse dev)" = "$m5" ] || fail "land again landed the branch a second time"
[ "$(count gates)" = 3 ] || fail "the owed close ran the gate again ($(count gates) runs in all)"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$m5" ] || fail "land again did not publish"
# the same from dev
git switch -q dev; rapid branch feature six >/dev/null; commit six.txt
refuse_hook; refused "$R" land; count_hook
git switch -q dev; m6=$(git rev-parse dev)
"$R" land > "$T/out" 2>&1 || fail "land from dev with a close owed: $(cat "$T/out")"
[ "$(git rev-parse dev)" = "$m6" ] && [ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$m6" ] || fail "land from dev did not publish the owed batch"
history_clean
# with nothing landed and nothing owed, land on dev says so and exits 0
"$R" land > "$T/out" 2>&1 || fail "land on dev with nothing owed failed: $(cat "$T/out")"; grep -qF "nothing to land; no close is owed" "$T/out" || fail "land on dev with nothing owed said: $(cat "$T/out")"
# --halt: nothing to halt is said by name
refused "$R" land --halt
grep -qF 'no batch is open; nothing to halt' "$T/err" || fail "halt with no batch: $(cat "$T/err")"
rapid branch feature seven >/dev/null; commit seven.txt; "$R" land --batch >/dev/null 2>&1 || fail "land --batch seven"
refused "$R" land --halt
grep -qF 'no close of this batch is under test; nothing to halt' "$T/err" || fail "halt with no close under test: $(cat "$T/err")"
# --halt stops the close under test and keeps the batch
git switch -q dev; b7=$(git rev-parse dev); touch "$T/wait"
( rc=0; "$R" land > "$T/close1" 2>&1 || rc=$?; echo "$rc" > "$T/close1.rc" ) &
closer=$!
mk="$(git rev-parse --git-common-dir)/rapid/batch.closing"
for _ in $(seq 1 100); do [ -s "$mk" ] && break; sleep 0.2; done
[ -s "$mk" ] || fail "the close never started testing"
"$R" land --halt > "$T/out" 2>&1 || fail "land --halt: $(cat "$T/out")"
grep -q "halted the close testing dev $(git rev-parse --short "$b7"); the batch stays open" "$T/out" || fail "halt did not say what it did: $(cat "$T/out")"
wait "$closer" 2>/dev/null || true
[ "$(cat "$T/close1.rc")" != 0 ] || fail "a halted close ended well"
grep -q 'batch gates pass' "$T/close1" && fail "a halted close published"
[ -s "$(git rev-parse --git-common-dir)/rapid/batch" ] || fail "halt dropped the batch"
[ ! -e "$mk" ] || fail "halt left the marker of the close"
[ "$(git rev-parse dev)" = "$b7" ] || fail "halt moved dev"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$m6" ] || fail "a halted close pushed"
rm -f "$T/wait"
"$R" land >/dev/null 2>&1 || fail "the land after a halt"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$b7" ] || fail "the land after a halt did not publish the batch"
history_clean
# flags that do not combine are usage errors
git switch -q dev; rapid branch feature eight >/dev/null; commit eight.txt
rc=0; "$R" land --batch --failed-gates-only > "$T/out" 2> "$T/err" || rc=$?
[ "$rc" = 2 ] || fail "land --batch --failed-gates-only exited $rc"
grep -qF 'land: --failed-gates-only goes with the close, which --batch defers' "$T/err" || fail "land --batch --failed-gates-only: $(cat "$T/err")"
rc=0; "$R" land --batch --pr > "$T/out" 2> "$T/err" || rc=$?
[ "$rc" = 2 ] || fail "land --batch --pr exited $rc"
[ "$(git rev-parse dev)" = "$b7" ] || fail "a usage error landed the branch"
