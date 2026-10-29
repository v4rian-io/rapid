#!/usr/bin/env bash
# the scenario runner's knobs: --fast runs the scenarios marked fast alone, a FILTER word runs the
# scenarios whose name holds it, RAPID_TEST_JOBS sets how many run at once when -j does not,
# RAPID_TEST_ONLY runs the named scenarios alone, RAPID_TEST_FAIL_DIR receives the output of a
# failing scenario for the command RAPID_TEST_ON_FAIL starts, and a stale SCENARIOS.md stops the run.
. "$(dirname "$0")/../lib.sh"
# this test drives its own small matrix: the knobs of the run that holds it do not reach it
unset RAPID_TEST_JOBS RAPID_TEST_ONLY RAPID_TEST_ON_FAIL RAPID_TEST_FAIL_DIR
src="$(cd "$(dirname "$0")/.." && pwd)"
m="$T/m/tests"; mkdir -p "$m/scenarios"
cp "$src/run.sh" "$src/gen-scenarios.sh" "$m/"
printf '#!/usr/bin/env bash\n# fast\n# A quick pass.\ntrue\n' > "$m/scenarios/01-a.sh"
printf '#!/usr/bin/env bash\n# A failure.\necho "boom from b"; exit 1\n' > "$m/scenarios/02-b.sh"
printf '#!/usr/bin/env bash\n# A pass.\ntrue\n' > "$m/scenarios/03-c.sh"
bash "$m/gen-scenarios.sh"
grep -qF '| 01-a | yes | A quick pass. |' "$m/SCENARIOS.md" || fail "the matrix does not mark 01-a fast: $(cat "$m/SCENARIOS.md")"
grep -qF '| 02-b |  | A failure. |' "$m/SCENARIOS.md" || fail "the matrix does not hold 02-b: $(cat "$m/SCENARIOS.md")"
names() { awk '/^(PASS|FAIL)/ { printf "%s:%s ", $1, $2 }' "$1"; }
# --fast: the marked scenarios alone
bash "$m/run.sh" --fast > "$T/out" 2>&1 || fail "--fast failed: $(cat "$T/out")"
[ "$(names "$T/out")" = "PASS:01-a " ] || fail "--fast ran $(names "$T/out")"
grep -qE '^---- 1 passed, 0 failed .*\(1 at once\)$' "$T/out" || fail "--fast summary: $(tail -n 1 "$T/out")"
# FILTER: the scenarios whose name holds the word
bash "$m/run.sh" 3-c > "$T/out" 2>&1 || fail "the filter run failed: $(cat "$T/out")"
[ "$(names "$T/out")" = "PASS:03-c " ] || fail "the filter ran $(names "$T/out")"
# RAPID_TEST_JOBS: how many at once when -j is not given; -j wins over it
if RAPID_TEST_JOBS=1 bash "$m/run.sh" > "$T/out" 2>&1; then fail "a run holding a failure passed"; fi
[ "$(names "$T/out")" = "PASS:01-a FAIL:02-b PASS:03-c " ] || fail "the whole matrix ran as $(names "$T/out")"
grep -qE '^---- 2 passed, 1 failed .*\(1 at once\) \(failed: 02-b\)$' "$T/out" || fail "RAPID_TEST_JOBS=1 summary: $(tail -n 1 "$T/out")"
if RAPID_TEST_JOBS=1 bash "$m/run.sh" -j 2 > "$T/out" 2>&1; then fail "a run holding a failure passed"; fi
grep -qE '\(2 at once\)' "$T/out" || fail "-j did not win over RAPID_TEST_JOBS: $(tail -n 1 "$T/out")"
if bash "$m/run.sh" > "$T/out" 2>&1; then fail "a run holding a failure passed"; fi
grep -qE '\(3 at once\)' "$T/out" || fail "the default is not every scenario at once: $(tail -n 1 "$T/out")"
rc=0; RAPID_TEST_JOBS=many bash "$m/run.sh" > "$T/out" 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "a RAPID_TEST_JOBS that is no number exited $rc, not 2"
# RAPID_TEST_ONLY: the named scenarios alone
RAPID_TEST_ONLY="01-a 03-c" bash "$m/run.sh" > "$T/out" 2>&1 || fail "RAPID_TEST_ONLY run failed: $(cat "$T/out")"
[ "$(names "$T/out")" = "PASS:01-a PASS:03-c " ] || fail "RAPID_TEST_ONLY ran $(names "$T/out")"
# RAPID_TEST_FAIL_DIR: where the failing scenario's output is kept for the command started on it
mkdir -p "$T/fails"
if RAPID_TEST_FAIL_DIR="$T/fails" RAPID_TEST_ON_FAIL='printf "%s %s\n" "$1" "$2" >> "'"$T"'/fixers"' bash "$m/run.sh" > "$T/out" 2>&1; then fail "a run holding a failure passed"; fi
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -s "$T/fixers" ] && break; sleep 0.3; done
[ "$(cat "$T/fixers" 2>/dev/null)" = "02-b $T/fails/rapid-fail-02-b.log" ] || fail "the command did not get the scenario and its kept output: $(cat "$T/fixers" 2>&1)"
grep -qx 'boom from b' "$T/fails/rapid-fail-02-b.log" || fail "the kept output is not the scenario's: $(cat "$T/fails/rapid-fail-02-b.log" 2>&1)"
[ "$(ls "$T/fails" | wc -l | tr -d ' ')" = 1 ] || fail "a passing scenario left an output file: $(ls "$T/fails")"
# a stale matrix stops the run before any scenario starts
printf '#!/usr/bin/env bash\n# A late one.\ntouch "%s/late-ran"\n' "$T" > "$m/scenarios/04-d.sh"
rc=0; bash "$m/run.sh" > "$T/out" 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "a stale SCENARIOS.md exited $rc, not 1"
grep -qF 'tests/SCENARIOS.md is stale' "$T/out" || fail "the stale matrix is not named: $(cat "$T/out")"
[ ! -e "$T/late-ran" ] && [ -z "$(names "$T/out")" ] || fail "scenarios ran under a stale matrix"
