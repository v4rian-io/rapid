#!/usr/bin/env bash
# parallel-history: doctor --history checks the merges at once, one worker per core (RAPID_HISTORY_JOBS
# overrides), and prints the findings in history order: over scripted merges whose check is slowed to
# one second each, the serial walk runs one check at a time, the parallel walk runs several of them at
# the same moment and prints the same lines, and a planted violation still names its merge. (A refused push prints the remote's own line:
# push-is-transport.)
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
rapid branch feature alpha >/dev/null; commit a.txt; rapid land >/dev/null || fail "land alpha"
fixture_merges 10
m8=$(git rev-parse "v2026.0.8^{commit}")
[ -n "$m8" ] || fail "no fixture merge v2026.0.8"
cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu)
[ "$(L="$RAPID_SRC/lib" bash -c '. "$L/core.sh"; . "$L/history.sh"; rapid_jobs')" = "$cores" ] || fail "the default worker count is not one per core ($cores)"
# a git whose merge check (rev-list --parents -n1) takes one second and says how many such checks are
# running while it runs (a marker each, counted at its start): the walk is check-bound, and the count
# tells a serial walk from a parallel one whatever the load of the machine
real=$(command -v git); mkdir -p "$T/bin"
cat > "$T/bin/git" <<SHIM
#!/bin/sh
if [ "\$1 \$2 \$3" = "rev-list --parents -n1" ] && [ -n "\${WALK_MARKS:-}" ]; then
  mkdir "\$WALK_MARKS/run.\$\$"
  n=0; for m in "\$WALK_MARKS"/run.*; do [ -d "\$m" ] && n=\$((n + 1)); done
  echo "\$n" >> "\$WALK_MARKS/running"
  sleep 1
  rmdir "\$WALK_MARKS/run.\$\$"
fi
exec "$real" "\$@"
SHIM
chmod +x "$T/bin/git"
# walk JOBS OUT MARKS: the walk with JOBS workers; MARKS takes the count each slowed check saw
walk() { mkdir -p "$3"; PATH="$T/bin:$PATH" WALK_MARKS="$3" RAPID_HISTORY_JOBS="$1" command rapid doctor --history --all > "$2" 2>&1 || true; }
# most MARKS: the most slowed checks that ran at the same moment
most() { sort -n "$1/running" | tail -n 1; }
t0=$(date +%s); walk 1 "$T/serial" "$T/marks.serial"; ts=$(( $(date +%s) - t0 ))
walk 12 "$T/par" "$T/marks.par"
diff "$T/serial" "$T/par" >"$T/diff" || fail "the parallel walk printed other lines: $(cat "$T/diff")"
grep -qF 'doctor: ok (history I1-I9 hold)' "$T/par" || fail "the walk did not pass: $(cat "$T/par")"
[ "$ts" -ge 10 ] || fail "the serial walk took $ts s; the slowed check should make it 10 s or more"
[ "$(wc -l < "$T/marks.serial/running" | tr -d ' ')" -ge 10 ] || fail "the serial walk slowed $(wc -l < "$T/marks.serial/running" | tr -d ' ') checks, not one per merge"
[ "$(most "$T/marks.serial")" = 1 ] || fail "the serial walk ran $(most "$T/marks.serial") checks at the same moment"
[ "$(wc -l < "$T/marks.par/running" | tr -d ' ')" = "$(wc -l < "$T/marks.serial/running" | tr -d ' ')" ] || fail "the parallel walk did not run the checks the serial walk ran"
[ "$(most "$T/marks.par")" -ge 4 ] || fail "the parallel walk ran at most $(most "$T/marks.par") checks at the same moment; twelve workers over eleven merges run them together"
# a violation names its merge: tag v2026.0.8 deleted, I2 names that merge
git tag -d v2026.0.8 >/dev/null
walk 12 "$T/par" "$T/marks.again"
grep -q "^doctor: I2 $m8 carries 0 version tags" "$T/par" || fail "no I2 for the untagged merge: $(cat "$T/par")"
