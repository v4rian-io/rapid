#!/usr/bin/env bash
# batch-close-one-gate: rapid land runs one gate on the batch's final tree, gates_full, never the
# fast gate first: a close of two branches starts the project test once.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/a" origin; cd "$T/a"
rapid branch feature one >/dev/null
printf '#!/bin/sh\necho gate >> "%s/gates"\n! ls *.bad >/dev/null 2>&1\n' "$T" > check.sh; git add check.sh; commit one.txt
command rapid land --batch >/dev/null 2>&1 || fail "land one"
git switch -q dev; rapid branch feature two >/dev/null; commit two.txt
command rapid land --batch >/dev/null 2>&1 || fail "land two"
[ ! -e "$T/gates" ] || fail "a land ran a gate"
command rapid land >"$T/out" 2>&1 || fail "close: $(cat "$T/out")"
[ "$(wc -l < "$T/gates" | tr -d ' ')" = 1 ] || fail "the close ran the test $(wc -l < "$T/gates" | tr -d ' ') times; one gate runs once"
grep -q -- '-> batch gate full on dev' "$T/out" || fail "the close did not run gates_full: $(cat "$T/out")"
grep -q -- '-> batch gate fast' "$T/out" && fail "the close ran the fast gate"
history_clean
ok "a close runs one gate once"
