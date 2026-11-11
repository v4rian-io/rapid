#!/usr/bin/env bash
# batch-one-push: a batch is exactly one push. Opening a branch pushes nothing, a land pushes nothing,
# the pre-push guard refuses every push while the batch is open (dev, a landed branch, a new branch), and
# rapid land sends one atomic push holding dev, the tags, the safety and the vault branches. A failed
# close keeps the batch and names the branch that broke it among several; the fix lands as one more
# branch and the next close is the batch's one push.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/a" origin; cd "$T/a"
d0=$(git rev-parse dev)
# origin counts every push, whatever it carries
printf '#!/bin/sh\necho push >> "%s/pushes"\n' "$T" > "$T/origin.git/hooks/pre-receive"; chmod +x "$T/origin.git/hooks/pre-receive"
refs0=$(git ls-remote origin | sort)
land() { command rapid land --batch "$@"; }
for s in one two three; do
  git switch -q dev; rapid branch feature "$s" >/dev/null; commit "$s.txt"
  [ ! -e "$T/pushes" ] || fail "opening branch $s pushed"
  land >/dev/null 2>&1 || fail "land $s"
done
[ ! -e "$T/pushes" ] || fail "a land pushed"
[ "$(git ls-remote origin | sort)" = "$refs0" ] || fail "origin changed before the close"
# the guard: nothing is pushed while the batch is open
p1=$(lname one)
refused git push -q origin dev
grep -q 'a batch is open' "$T/err" || fail "a dev push during the batch was not refused: $(cat "$T/err")"
refused git push -q origin "$p1"
grep -q 'a batch is open' "$T/err" || fail "a branch push during the batch was not refused: $(cat "$T/err")"
git switch -q dev; rapid branch feature side >/dev/null; commit side.txt
refused git push -q origin "$(lname side)"
grep -q 'a batch is open' "$T/err" || fail "a new branch's push during the batch was not refused: $(cat "$T/err")"
[ ! -e "$T/pushes" ] || fail "a refused push reached origin"
git switch -q dev
# the close is the one push: dev, tags, safety and vault together
command rapid land >"$T/out" 2>&1 || fail "close: $(cat "$T/out")"
[ "$(wc -l < "$T/pushes" | tr -d ' ')" = 1 ] || fail "the batch took $(wc -l < "$T/pushes" | tr -d ' ') pushes; a batch is one push"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$(git rev-parse dev)" ] || fail "the close did not push dev"
[ "$(git ls-remote origin 'refs/tags/v*' | grep -vc '\^{}')" = 3 ] || fail "the close did not push the three tags"
[ "$(git ls-remote origin 'refs/heads/vault/*' | wc -l | tr -d ' ')" = 3 ] || fail "the close did not push the three vault branches"
[ -n "$(git ls-remote origin "refs/heads/safety/${p1#pool/}")" ] || fail "the close did not push the safety anchors"
history_clean
# a failed close keeps the batch and names the branch that broke the close among several branches
rm -f "$T/pushes"; d1=$(git rev-parse dev)
git switch -q dev; rapid branch feature good >/dev/null; commit good.txt; land >/dev/null 2>&1 || fail "land good"
git switch -q dev; rapid branch feature broken >/dev/null; commit crash.bad; pb=$(lname broken); land >/dev/null 2>&1 || fail "land broken"
git switch -q dev; rapid branch feature later >/dev/null; commit later.txt; land >/dev/null 2>&1 || fail "land later"
tip=$(git rev-parse dev)
refused command rapid land
grep -qF "broke the close: $pb (" "$T/out" || fail "the failed close did not name the broken branch: $(cat "$T/out" "$T/err")"
[ "$(git rev-parse dev)" = "$tip" ] || fail "the failed close moved dev"
[ ! -e "$T/pushes" ] || fail "the failed close pushed"
# the fix lands as one more branch on top; the next close tests the new final tree and pushes once
git switch -q dev; rapid branch fix unbreak >/dev/null
git rm -q crash.bad; git commit -q -m "[FIX] Remove the crash reproduction marker" -m "Cause: the defect this scenario plants." -m "Fix: the repair this scenario makes."
land >"$T/out" 2>&1 || fail "land the fix: $(cat "$T/out")"
command rapid land >"$T/out" 2>&1 || fail "the second close: $(cat "$T/out")"
[ "$(wc -l < "$T/pushes" | tr -d ' ')" = 1 ] || fail "the second batch took $(wc -l < "$T/pushes" | tr -d ' ') pushes"
[ "$(git rev-list --first-parent --count "$d1..origin/dev" 2>/dev/null || git rev-list --first-parent --count "$d1..dev")" = 4 ] || fail "the batch is not four merges"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$(git rev-parse dev)" ] || fail "the second close did not push dev"
history_clean
ok "one batch, one push"
