#!/bin/sh
# tests/smoke.sh - the cheap test that a tree starts: every shell file parses, the CLI
# prints its help, the lints pass. rapid land runs it on the own tree of every merge of a
# batch, all merges at once (conf gates_each), so every point of history runs. A failure
# prints what bash said; a bash that could not start (no process available) is said as
# that, never as a file that does not parse.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
rc=0
# nostart ERR: true when ERR is empty or names a failure to start a process
nostart() {
  case "$1" in
    ""|*fork*|*"Resource temporarily unavailable"*|*"Cannot allocate"*) return 0 ;;
  esac
  return 1
}
said() { printf '%s\n' "$1" | sed 's/^/    | /' >&2; }
for f in "$here"/rapid "$here"/install.sh "$here"/lib/*.sh "$here"/hooks/* "$here"/lint/*.sh "$here"/tests/*.sh "$here"/tests/scenarios/*.sh "$here"/agent/*.sh; do
  [ -f "$f" ] || continue
  err=$(bash -n "$f" 2>&1) || {
    if nostart "$err"; then echo "X smoke: bash could not start on $f: ${err:-no output}" >&2
    else echo "X smoke: $f does not parse" >&2; said "$err"; fi
    rc=1; }
done
if [ -f "$here/rapid" ]; then
  err=$(bash "$here/rapid" --help 2>&1 >/dev/null) || {
    if nostart "$err"; then echo "X smoke: rapid --help could not start: ${err:-no output}" >&2
    else echo "X smoke: rapid --help fails" >&2; said "$err"; fi
    rc=1; }
fi
if [ -f "$here/lint/run.sh" ]; then
  (cd "$here/.." && sh .rapid/lint/run.sh) || { echo "X smoke: the lints fail" >&2; rc=1; }
fi
exit "$rc"
