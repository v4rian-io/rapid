#!/usr/bin/env bash
# several suite runs at once on one machine, sharing TMPDIR: every run
# passes and none leaves a temp directory behind.
. "$(dirname "$0")/../lib.sh"
run="$RAPID_SRC/tests/run.sh"
shared="$T/tmp"; mkdir -p "$shared"
for i in 1 2 3; do ( TMPDIR="$shared" bash "$run" land-local > "$T/run$i.out" 2>&1; echo $? > "$T/run$i.rc" ) & done
( TMPDIR="$shared" bash "$run" stale-branch > "$T/run4.out" 2>&1; echo $? > "$T/run4.rc" ) &
wait
for i in 1 2 3 4; do
  [ "$(cat "$T/run$i.rc")" = 0 ] || fail "parallel run $i failed: $(cat "$T/run$i.out")"
done
[ -z "$(ls -A "$shared")" ] || fail "temp left behind: $(ls -A "$shared")"
