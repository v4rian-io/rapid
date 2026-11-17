#!/usr/bin/env bash
# a close removes only its own marker: the marker of a close under test carries that close's own id.
# An older close that ends while a newer close holds the batch leaves the newer marker in place,
# publishes nothing in its name and stops, so the newer close alone answers for the batch.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/a" origin; cd "$T/a"
d0=$(git rev-parse dev)
rapid branch feature one >/dev/null
printf 'while [ ! -e "%s/go" ] && [ -d "%s" ]; do sleep 0.2; done\n' "$T" "$T" > check.sh; git add check.sh; commit one.txt
rapid land --batch >/dev/null || fail "land one"
git switch -q dev
m="$(git rev-parse --git-common-dir)/rapid/batch.closing"
( rc=0; rapid land >"$T/close1" 2>&1 || rc=$?; echo "$rc" > "$T/close1.rc" ) &
older=$!
for _ in $(seq 1 100); do [ -s "$m" ] && break; sleep 0.2; done
[ -s "$m" ] || fail "the close never started testing"
read -r _ tip id < "$m" || true; first=$(cat "$m")
# a newer close takes the batch: its marker replaces the older one while the older close still tests
newer=$$   # a live process that outlives this test: the scenario's own shell
printf '%s %s newer-close\n' "$newer" "$tip" > "$m"
touch "$T/go"; wait "$older" 2>/dev/null || true
[ "$(cat "$T/close1.rc")" != 0 ] || fail "the older close ended well under a newer close's marker: $(cat "$T/close1")"
grep -q 'batch gates pass' "$T/close1" && fail "the older close published under a newer close's marker"
[ "$(cat "$m" 2>/dev/null)" = "$newer $tip newer-close" ] || fail "the older close removed the newer close's marker: $(cat "$m" 2>&1)"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$d0" ] || fail "the older close pushed"
[ -n "${id:-}" ] || fail "the marker carries no id of its close: $first"
rm -f "$m"
rapid land >/dev/null 2>&1 || fail "the next close"
[ ! -e "$m" ] || fail "a finished close left its own marker behind"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$(git rev-parse dev)" ] || fail "the next close did not push the final tree"
history_clean
