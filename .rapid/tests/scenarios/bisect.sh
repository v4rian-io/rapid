#!/usr/bin/env bash
# bisect finds a regression planted in one of 30 landed branches: the branch
# first, then the commit, skipping a marked Red: commit before it. A command
# exit of 125 skips a commit it cannot test; a skipped commit that may have broken it is named.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
good=$(git rev-parse dev)
for i in $(seq 1 30); do
  rapid branch feature "step-$i" >/dev/null
  if [ "$i" = 17 ]; then
    commit probe.bad p "[TEST] Probe the calculator rounding" "Red: rounding probe"
    git rm -q probe.bad; printf 'total=BUG\n' > calc.txt; git add calc.txt
    git commit -q -m "[FIX] Round totals in the calculator" -m "Cause: the defect this scenario plants." -m "Fix: the repair this scenario makes."
    broke=$(git rev-parse HEAD)
    commit after.txt a "[NEW] Add the calculator footer"
  else
    commit "f$i.txt" "$i" "[NEW] Add step $i of the rollout"
  fi
  rapid land >/dev/null || fail "land $i"
done
rapid bisect "$good" dev -- sh -c '! grep -q BUG calc.txt 2>/dev/null && ! ls *.bad >/dev/null 2>&1' > "$T/out" || fail "bisect: $(cat "$T/out")"
grep -qx "broke $broke" "$T/out" || fail "wrong commit: $(cat "$T/out")"
grep -qx "branch feature/step-17" "$T/out" || fail "wrong branch: $(cat "$T/out")"
grep -q '1 marked red commit(s) skipped' "$T/out" || fail "red commit not skipped: $(cat "$T/out")"
m() { git log --first-parent --format='%H %s' dev | sed -nE "s/^([0-9a-f]+) \[MERGE\] pool\/[^ ]*[.]feature[.]step-$1 into dev: .*/\1/p"; }
m15=$(m 15); m17=$(m 17)
# exit 125 on the first merge the search visits (step 15): skipped, and the right commit is still found
rapid bisect "$good" dev -- sh -c "[ \"\$(git rev-parse HEAD)\" = $m15 ] && exit 125; ! grep -q BUG calc.txt 2>/dev/null && ! ls *.bad >/dev/null 2>&1" > "$T/out" || fail "bisect with a skip: $(cat "$T/out")"
grep -qx "broke $broke" "$T/out" || fail "a skip changed the commit found: $(cat "$T/out")"
grep -q ' 1 skipped (exit 125)' "$T/out" || fail "the 125 skip is not reported: $(cat "$T/out")"
# exit 125 on the very merge that broke it: the report names it as one that may have broken it
rapid bisect "$good" dev -- sh -c "[ \"\$(git rev-parse HEAD)\" = $m17 ] && exit 125; ! grep -q BUG calc.txt 2>/dev/null && ! ls *.bad >/dev/null 2>&1" > "$T/out" || fail "bisect skipping the commit that broke it: $(cat "$T/out")"
grep -q "ambiguous: the commit that broke it may also be the skipped commit(s) $(git rev-parse --short "$m17")" "$T/out" || fail "a skipped commit that may have broken it is not named: $(cat "$T/out")"
[ -z "$(git worktree list --porcelain | grep -c '^worktree ' | grep -vx 1)" ] || fail "bisect left a worktree behind"
history_clean
