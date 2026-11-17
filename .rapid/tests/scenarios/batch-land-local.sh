#!/usr/bin/env bash
# batch-land-local: a plain rapid land always lands into the open batch: five branches land with no
# gate run and no push, offline; one rapid land gates the final tree and pushes it all in one
# push; a close with no batch open says so.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/a" origin; cd "$T/a"
d0=$(git rev-parse dev)
# origin counts the pushes that carry dev or a version tag
printf '#!/bin/sh\nwhile read -r o n r; do case "$r" in refs/heads/dev|refs/tags/v*) echo push >> "%s/pushes"; break ;; esac; done\n' "$T" > "$T/origin.git/hooks/pre-receive"
chmod +x "$T/origin.git/hooks/pre-receive"
land() { command rapid land --batch "$@"; }
rapid branch feature one >/dev/null
printf '#!/bin/sh\necho gate >> "%s/gates"\n! ls *.bad >/dev/null 2>&1\n' "$T" > check.sh; git add check.sh; commit one.txt
land >"$T/out" 2>&1 || fail "land one: $(cat "$T/out")"
grep -q 'in the batch; its close tests it' "$T/out" || fail "the land did not say it went into the batch: $(cat "$T/out")"
for s in two three four five; do
  git switch -q dev; rapid branch feature "$s" >/dev/null; commit "$s.txt"
  land >"$T/out" 2>&1 || fail "land $s: $(cat "$T/out")"
done
[ "$(git rev-list --first-parent --count "$d0..dev")" = 5 ] || fail "five lands are not five merges on dev"
[ ! -e "$T/gates" ] || fail "a land ran a gate ($(wc -l < "$T/gates" | tr -d ' ') runs)"
[ ! -e "$T/pushes" ] || fail "a land pushed"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$d0" ] || fail "origin's dev moved before the close"
command rapid land >"$T/out" 2>&1 || fail "close: $(cat "$T/out")"
[ -s "$T/gates" ] || fail "the close ran no gate"
[ "$(wc -l < "$T/pushes" | tr -d ' ')" = 1 ] || fail "the close pushed $(wc -l < "$T/pushes" | tr -d ' ') times; a batch is one push"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$(git rev-parse dev)" ] || fail "the close did not push dev"
history_clean
command rapid land > "$T/out" 2>&1 || fail "a land with nothing owed failed: $(cat "$T/out")"
grep -qF 'nothing to land; no close is owed' "$T/out" || fail "a land with nothing owed said: $(cat "$T/out")"
history_clean
ok "every land goes into the batch; one close tests and pushes"
