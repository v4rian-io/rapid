#!/usr/bin/env bash
# Red: cannot hide broken work: a Red: trailer on any commit but a [TEST] one is refused at
# commit; a chain of Red: commits and a stale Red: marker on a passing commit are named by check
# --each, and land refuses the chain (a static check; it runs no gate); a hand-made merge carrying a Red: chain or a non-test Red: is flagged
# I4 by doctor. A single red [TEST] commit turned green by the next commit still lands (marked-red).
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
rapid branch fix crash >/dev/null
printf 'x\n' > a.bad; git add a.bad
refused git commit -q -m "[NEW] Add the crash reproduction" -m "Red: nothing"
grep -q 'marks a \[TEST\] commit only' "$T/err" || fail "a Red: on a [NEW] commit was accepted: $(cat "$T/err")"
git commit -q -m "[TEST] Reproduce the crash on empty input" -m "Red: empty input"
printf 'y\n' > b.bad; git add b.bad
git commit -q -m "[TEST] Reproduce the crash on a second input" -m "Red: second input"
git rm -q a.bad b.bad; git commit -q -m "[FIX] Handle both inputs without a crash" -m "Cause: the defect this scenario plants." -m "Fix: the repair this scenario makes."
chain=$(git rev-parse --short HEAD~1)
refused rapid check --each
grep -q "FAIL  $chain .*follows a Red: commit" "$T/out" || fail "check --each missed the Red: chain: $(cat "$T/out")"
refused rapid land
git switch -q dev; git branch -q -D "$(lname crash)"
rapid branch fix stale >/dev/null
commit s.txt s "[TEST] Cover the stale marker case" "Red: not really"
commit t.txt t "[FIX] Handle the stale marker case"
stale=$(git rev-parse --short HEAD~1)
refused rapid check --each
grep -q "FAIL  $stale .*stale Red: marker" "$T/out" || fail "check --each missed the stale marker: $(cat "$T/out")"
# a stale marker needs the gate to show: a land runs none (batch-land-local), so only check --each names it
git switch -q dev; git branch -q -D "$(lname stale)"
# made past every hook and landed by hand: doctor names both shapes
git switch -q -c pool/v2026.0/fix.hand dev
mkdir -p .rapid/requirements; printf '# fix/hand\n\nA hand-made branch that hides red commits.\n' > .rapid/requirements/hand.md
printf 'h\n' > h1.txt; git add .rapid/requirements/hand.md h1.txt
git commit -q --no-verify -m "[NEW] Add the first hand file" -m "Red: hidden"
printf 'h\n' > h2.txt; git add h2.txt; git commit -q --no-verify -m "[TEST] Add the second hand file" -m "Red: chained"
printf 'h\n' > h3.txt; git add h3.txt; git commit -q -m "[FIX] Add the third hand file" -m "Cause: the defect this scenario plants." -m "Fix: the repair this scenario makes."
git switch -q dev; git -c core.hooksPath=/dev/null merge -q --no-ff pool/v2026.0/fix.hand -m "[MERGE] pool/v2026.0/fix.hand into dev: v2026.0.1"
rapid doctor --history-only > "$T/doc" 2>&1 && fail "doctor missed the hidden reds"
grep -q '^doctor: I4 .*marks a \[TEST\] commit only' "$T/doc" || fail "no I4 for a non-test Red: $(cat "$T/doc")"
grep -q '^doctor: I4 .*follows a Red: commit' "$T/doc" || fail "no I4 for the Red: chain: $(cat "$T/doc")"
