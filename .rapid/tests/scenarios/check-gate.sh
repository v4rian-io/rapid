#!/usr/bin/env bash
# rapid check runs one gate on the work tree and says how it ended: the fast gate by default,
# the gate --gate names otherwise; "pass" with exit 0, "fail" with exit 1 and the end of the
# gate's own output, "none" for a gate the conf leaves unset or sets to none. It lands nothing.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
d0=$(git rev-parse dev)
rapid branch feature probe >/dev/null; commit probe.txt
[ "$(rapid check)" = "gate fast: pass" ] || fail "rapid check: $(rapid check 2>&1)"
for g in fast full release; do
  [ "$(rapid check --gate "$g")" = "gate $g: pass" ] || fail "check --gate $g: $(rapid check --gate "$g" 2>&1)"
done
# a gate the conf does not set runs nothing and says so
[ "$(rapid check --gate each)" = "gate each: none" ] || fail "an unset gate: $(rapid check --gate each 2>&1)"
[ "$(rapid check --gate commit)" = "gate commit: none" ] || fail "an unset commit gate: $(rapid check --gate commit 2>&1)"
# a failing gate: exit 1, the gate named, the end of its output shown
printf '#!/bin/sh\necho "the project test says no"\nexit 7\n' > check.sh
rc=0; rapid check >"$T/out" 2>"$T/err" || rc=$?
[ "$rc" = 1 ] || fail "a failing gate exited $rc, not 1"
grep -qF 'X rapid: gate fast: fail' "$T/err" || fail "the failing gate is not named: $(cat "$T/err")"
grep -qF '| the project test says no' "$T/err" || fail "the gate's own output is not shown: $(cat "$T/err")"
rc=0; rapid check --gate full >"$T/out" 2>"$T/err" || rc=$?
[ "$rc" = 1 ] && grep -qF 'X rapid: gate full: fail' "$T/err" || fail "check --gate full on a failing tree: rc $rc $(cat "$T/err")"
git checkout -q -- check.sh
[ "$(rapid check --gate full)" = "gate full: pass" ] || fail "the gate did not pass again on the restored tree"
[ "$(git rev-parse dev)" = "$d0" ] && [ -z "$(git tag -l 'v[0-9]*')" ] || fail "rapid check moved dev or tagged"
