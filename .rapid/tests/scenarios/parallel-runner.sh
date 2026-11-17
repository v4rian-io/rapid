#!/usr/bin/env bash
# The scenario runner runs scenarios concurrently: with -j 3, three scenarios that each take
# two seconds finish together in well under the six seconds a serial run needs, the results print
# in file order whatever order they finish in, each scenario has its own TMPDIR removed with the
# run, a failing scenario is named with its output tail and fails the run, and -j 1 still runs
# serially with the same verdicts; a failure is reported live and starts RAPID_TEST_ON_FAIL at once;
# with --verbose each scenario prints a progress line [n/total] the moment it ends, without it none.
. "$(dirname "$0")/../lib.sh"
src="$(cd "$(dirname "$0")/.." && pwd)"
m="$T/m/tests"; mkdir -p "$m/scenarios"
cp "$src/run.sh" "$src/gen-scenarios.sh" "$m/"
printf '#!/usr/bin/env bash\n# A slow pass.\necho "$TMPDIR" > "%s/tmp.a"; sleep 2\n' "$T" > "$m/scenarios/01-a.sh"
printf '#!/usr/bin/env bash\n# A slow failure.\nsleep 1; echo "boom from b"; exit 1\n' > "$m/scenarios/02-b.sh"
printf '#!/usr/bin/env bash\n# A quick pass.\necho "$TMPDIR" > "%s/tmp.c"; sleep 2\n' "$T" > "$m/scenarios/03-c.sh"
bash "$m/gen-scenarios.sh"
s0=$(date +%s)
if out=$(bash "$m/run.sh" --verbose -j 3 2>&1); then fail "a failing scenario must fail the run"; fi
took=$(( $(date +%s) - s0 ))
# compared with -j 1 below, not against a clock, so a loaded machine cannot fail it
order=$(printf '%s\n' "$out" | awk '/^(PASS|FAIL)/ { print $2 }' | tr '\n' ' ')
[ "$order" = "01-a 02-b 03-c " ] || fail "results not in file order: $order"
printf '%s\n' "$out" | grep -E '^FAIL +02-b' >/dev/null || fail "the failure is not named"
# --verbose: one progress line per scenario the moment it ends, counted 1 to 3 of 3, with its time and the time elapsed
for n in 1 2 3; do
  grep -E "^\[$n/3\] (PASS|FAIL)  0[123]-[abc]  [0-9]+s, [0-9]+s elapsed$" <<<"$out" >/dev/null || fail "no progress line $n of 3: $out"
done
grep -E '^\[[0-9]/3\] FAIL  02-b  ' <<<"$out" >/dev/null || fail "the progress line of the failure does not say FAIL: $out"
printf '%s\n' "$out" | grep 'boom from b' >/dev/null || fail "the failure's output tail is missing"
printf '%s\n' "$out" | grep -E '^---- 2 passed, 1 failed .*\(3 at once\)' >/dev/null || fail "summary wrong: $(printf '%s\n' "$out" | tail -n 1)"
# each scenario has its own TMPDIR, inside the run's directory, removed with the run
ta=$(cat "$T/tmp.a"); tc=$(cat "$T/tmp.c")
[ -n "$ta" ] && [ "$ta" != "$tc" ] || fail "two scenarios shared a TMPDIR ($ta, $tc)"
case "$ta" in */01-a.tmp) ;; *) fail "the TMPDIR of 01-a is not its own: $ta" ;; esac
[ ! -e "$ta" ] && [ ! -e "$tc" ] || fail "a scenario TMPDIR outlived the run"
# a failure prints the moment it happens and starts RAPID_TEST_ON_FAIL on it at once
if RAPID_TEST_ON_FAIL='printf "%s %s\n" "$1" "$2" >> "'"$T"'/fixers"' bash "$m/run.sh" -j 3 >/dev/null 2>"$T/live"; then fail "the run with a failure passed"; fi
grep -q '^!! FAIL 02-b' "$T/live" || fail "the failure was not reported live: $(cat "$T/live")"
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$T/fixers" ] && break; sleep 0.3; done
grep -q '^02-b ' "$T/fixers" || fail "RAPID_TEST_ON_FAIL did not start on the failure"
[ "$(wc -l < "$T/fixers" | tr -d ' ')" = 1 ] || fail "RAPID_TEST_ON_FAIL ran for a passing scenario"
# -j 1 is serial and gives the same verdicts
s1=$(date +%s)
if out1=$(bash "$m/run.sh" -j 1 2>&1); then fail "-j 1 must fail the run too"; fi
serial=$(( $(date +%s) - s1 ))
[ "$took" -lt "$serial" ] || fail "-j 3 took ${took}s, no faster than -j 1 (${serial}s): the scenarios did not run together"
printf '%s\n' "$out1" | grep -E '^---- 2 passed, 1 failed .*\(1 at once\)' >/dev/null || fail "-j 1 summary wrong"
! grep -E '^\[[0-9]+/3\] ' <<<"$out1" >/dev/null || fail "a run without --verbose printed progress lines: $out1"
# a bad -j value is refused
if bash "$m/run.sh" -j x >/dev/null 2>&1; then fail "-j x must be refused"; fi
ok "scenarios run concurrently, in file order, with the same verdicts"
