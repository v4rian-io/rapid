#!/usr/bin/env bash
# fast
# version math is a pure function of the history: series and year
# rollover, table-driven, no clock read.
. "$(dirname "$0")/../lib.sh"
. "$RAPID_SRC/lib/version.sh"
check() { got=$(rapid_version_next "$1" "$2" "$3"); [ "$got" = "$4" ] || fail "next($1, released=$2, $3) = $got, want $4"; }
check ""          0 2026 v2026.0.1
check -           0 2026 v2026.0.1
check v2026.0.1   0 2026 v2026.0.2
check v2026.0.9   0 2026 v2026.0.10
check v2026.0.9   1 2026 v2026.1.1
check v2026.3.12  1 2026 v2026.4.1
check v2026.3.12  0 2027 v2027.0.1
check v2026.3.12  1 2027 v2027.0.1
rapid_version_next v2026.x 0 2026 2>/dev/null && fail "a malformed version was accepted"
# end to end: a land in a new year starts the year's first series
mkrepo "$T/r"; cd "$T/r"
rapid branch feature dec >/dev/null; commit dec.txt; RAPID_YEAR=2026 rapid land >/dev/null || fail "land 2026"
rapid branch feature jan >/dev/null; commit jan.txt; RAPID_YEAR=2027 rapid land >/dev/null || fail "land 2027"
[ "$(git describe --exact-match dev)" = v2027.0.1 ] || fail "new-year land is $(git describe --exact-match dev)"
history_clean
