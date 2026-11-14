#!/usr/bin/env bash
# rapid doctor --deep runs the doctor, then the scenarios this install carries: an install without
# them fails and says so; green scenarios pass with their counts; a failed scenario is named and
# fails the doctor; a broken install fails although its scenarios pass; the flags after --deep reach
# the doctor.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
# the scratch install carries no scenarios
refused rapid doctor --deep
grep -q '^doctor: ok' "$T/out" || fail "the doctor itself did not run first: $(cat "$T/out")"
grep -q 'doctor: deep: .rapid/tests/run.sh is not in this install' "$T/out" || fail "missing scenarios are not named: $(cat "$T/out")"
# green scenarios
mkdir -p .rapid/tests
printf '%s\n' '#!/bin/sh' 'echo ran >> "$(dirname "$0")/ran"' 'echo "PASS  one                                  1s"' \
  'echo "---- 1 passed, 0 failed in 1s (1 at once)"' > .rapid/tests/run.sh
rapid doctor --deep > "$T/out" || fail "a green deep doctor: $(cat "$T/out")"
grep -q 'doctor: deep: ok (1 passed, 0 failed in 1s (1 at once))' "$T/out" || fail "the counts are not reported: $(cat "$T/out")"
[ "$(wc -l < .rapid/tests/ran | tr -d " ")" = 1 ] || fail "the scenarios did not run once"
rapid doctor --deep --history > "$T/out" || fail "a deep doctor with --history: $(cat "$T/out")"
grep -q 'history I1-I9 hold' "$T/out" || fail "--history did not reach the doctor: $(cat "$T/out")"
# a broken install fails although its scenarios pass
hp0=$(git config --get core.hooksPath); git config core.hooksPath elsewhere
refused rapid doctor --deep
grep -q "core.hooksPath is 'elsewhere'" "$T/out" && grep -q 'doctor: deep: ok' "$T/out" || fail "a broken install: $(cat "$T/out")"
git config core.hooksPath "$hp0"
# a failed scenario is named
printf '%s\n' '#!/bin/sh' 'echo "PASS  one                                  1s"' 'echo "FAIL  broken                               2s"' \
  'echo "      FAIL: it broke"' 'echo "---- 1 passed, 1 failed in 2s (2 at once) (failed: broken)"' 'exit 1' > .rapid/tests/run.sh
refused rapid doctor --deep
grep -q '^doctor: deep: FAIL  broken' "$T/out" || fail "the failed scenario is not named: $(cat "$T/out")"
grep -q 'doctor: deep: failed (1 passed, 1 failed' "$T/out" || fail "the failure is not reported: $(cat "$T/out")"
rm -rf .rapid/tests
[ -z "$(git status --porcelain)" ] || fail "the deep doctor left files behind: $(git status --porcelain)"
history_clean
