#!/usr/bin/env bash
# rapid land --failed-gates-only runs again only the gates the previous close of this batch failed: the
# merges that close verified on their own tree are not verified again, a merge landed since is, and the
# failed gate of the final tree runs once. With no failed close of the batch on record it is refused by
# name and runs nothing. The default close runs every gate on every merge, after a failed close too.
# The close and the doctor print their progress live on stderr: one counted line per merge.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/a" origin; cd "$T/a"
R="$(type -P rapid)"
# the gates count their runs: gates_each names the merge it ran on, the full gate fails while a *.bad file exists
rapid branch feature tools >/dev/null
printf '#!/bin/sh\ngit rev-parse HEAD >> "%s/each"\n' "$T" > each.sh
printf '#!/bin/sh\necho gate >> "%s/gates"\n! ls *.bad >/dev/null 2>&1\n' "$T" > check.sh
git add each.sh check.sh; commit tools.txt
"$R" land --batch >/dev/null 2>&1 || fail "land the tools"
git switch -q dev; rapid branch refactor each -r "Every merge of a batch runs each.sh on its own tree." >/dev/null
printf 'gates_each=sh each.sh\n' >> .rapid/conf; git add .rapid/conf
git commit -q -m "[MODE] Verify every merge of a batch on its own tree"
"$R" land --batch >/dev/null 2>&1 || fail "land the gates_each flip"
"$R" land >/dev/null 2>&1 || fail "close the first batch"
count() { if [ -e "$T/$1" ]; then wc -l < "$T/$1" | tr -d ' '; else echo 0; fi; }
unbreak() { git switch -q dev; rapid branch fix "$1" >/dev/null; git rm -q "$2"
  git commit -q -m "[FIX] Remove the file that breaks the gate" -m "Cause: the defect this scenario plants." -m "Fix: the repair this scenario makes."; }
# no failed close on record: refused by name, nothing runs
rm -f "$T/each" "$T/gates"; d0=$(git rev-parse dev)
git switch -q dev; rapid branch feature one >/dev/null; commit one.txt; "$R" land --batch >/dev/null 2>&1 || fail "land one"
rc=0; "$R" land --failed-gates-only > "$T/out" 2> "$T/err" || rc=$?
[ "$rc" = 1 ] || fail "land --failed-gates-only with no failed close exited $rc"
grep -qF 'land --failed-gates-only: no close of this batch has failed a gate' "$T/err" || fail "no clear refusal: $(cat "$T/err")"
[ "$(count each)" = 0 ] && [ "$(count gates)" = 0 ] || fail "a refused close ran a gate"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$d0" ] || fail "a refused close pushed"
# a close fails the gate of the final tree: every merge was verified on its own tree
git switch -q dev; rapid branch feature broken >/dev/null; commit crash.bad; "$R" land --batch >/dev/null 2>&1 || fail "land broken"
refused "$R" land
! grep -E 'batch gate each on|\] each v' "$T/out" "$T/err" >/dev/null || fail "a close without --verbose printed progress lines: $(cat "$T/out" "$T/err")"
[ "$(count each)" = 2 ] || fail "the failed close verified $(count each) merges, not 2"
# the fix lands; only the failed gates run again
rm -f "$T/each" "$T/gates"
unbreak unbreak crash.bad; "$R" land --batch >/dev/null 2>&1 || fail "land the fix"
"$R" land --failed-gates-only --verbose > "$T/out" 2>&1 || fail "land --failed-gates-only: $(cat "$T/out")"
grep -qF 'only the gates the previous close failed run again: full' "$T/out" || fail "the close did not name the gates it runs again: $(cat "$T/out")"
[ "$(count each)" = 1 ] || fail "gates_each ran on $(count each) merges; only the merge landed since is unverified"
# --verbose: the per-merge test is announced, then one counted line per merge as its gate ends
grep -qxF -- '-> batch gate each on 1 merge trees' "$T/out" || fail "the per-merge test is not announced: $(cat "$T/out")"
grep -qE '^   \[1/1\] each v[0-9.]+ pass [0-9]+s$' "$T/out" || fail "no counted line for the merge verified: $(cat "$T/out")"
[ "$(cat "$T/each")" = "$(git rev-parse dev)" ] || fail "gates_each ran on a merge the previous close had verified"
[ "$(count gates)" = 1 ] || fail "the failed gate ran $(count gates) times"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$(git rev-parse dev)" ] || fail "the close did not publish the batch"
history_clean
# the doctor prints no progress without --verbose; with it, it counts the merges it checks, on stderr; its
# result stays the last line of stdout
"$R" doctor --history-only > "$T/dout" 2> "$T/derr" || fail "doctor --history-only: $(cat "$T/dout" "$T/derr")"
! grep 'doctor: history: \[' "$T/dout" "$T/derr" >/dev/null || fail "the doctor printed progress without --verbose: $(cat "$T/derr")"
"$R" doctor --history-only --verbose > "$T/dout" 2> "$T/derr" || fail "doctor --history-only: $(cat "$T/dout" "$T/derr")"
grep -qE '^doctor: history: \[1/[0-9]+\] v[0-9.]+$' "$T/derr" || fail "the doctor does not count the merges it checks: $(cat "$T/derr")"
[ "$(tail -n 1 "$T/dout")" = "doctor: ok (history I1-I9 hold)" ] || fail "the doctor result is not the last line: $(cat "$T/dout")"
# a batch closed well keeps no record: the flag is refused again
git switch -q dev; rapid branch feature two >/dev/null; commit two.txt; "$R" land --batch >/dev/null 2>&1 || fail "land two"
refused "$R" land --failed-gates-only
grep -qF 'no close of this batch has failed a gate' "$T/err" || fail "the record of a closed batch was kept: $(cat "$T/err")"
# the default runs all, after a failed close too
git switch -q dev; rapid branch feature bad2 >/dev/null; commit crash2.bad; "$R" land --batch >/dev/null 2>&1 || fail "land bad2"
refused "$R" land
rm -f "$T/each" "$T/gates"
unbreak unbreak2 crash2.bad; "$R" land --batch >/dev/null 2>&1 || fail "land the second fix"
"$R" land > "$T/out" 2>&1 || fail "the default close: $(cat "$T/out")"
[ "$(count each)" = 3 ] || fail "the default close verified $(count each) merges, not all 3"
[ "$(count gates)" = 1 ] || fail "the default close ran the full gate $(count gates) times"
history_clean
