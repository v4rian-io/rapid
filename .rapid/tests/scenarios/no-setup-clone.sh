#!/usr/bin/env bash
# a clone that never ran rapid setup says so: rapid branch, land, sync and release refuse and name
# rapid setup instead of working unguarded; status names the missing setup and prints no raw git
# error; check, bisect and doctor --history-only stay usable without it (the forge's runner case);
# after rapid setup the same clone works.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/a" origin; cd "$T/a"
rapid branch feature base >/dev/null; commit base.txt; rapid land >/dev/null || fail "land base"
git clone -q "$T/origin.git" "$T/b"; cd "$T/b"
rapid status > "$T/st" 2>&1 || fail "status failed: $(cat "$T/st")"
grep -q 'fatal:' "$T/st" && fail "status printed a raw git error: $(cat "$T/st")"
grep -q "setup: .*run 'rapid setup'" "$T/st" || fail "status did not name the missing setup: $(cat "$T/st")"
refused rapid branch feature unguarded
grep -q "run 'rapid setup' first" "$T/err" || fail "branch worked in a clone without setup: $(cat "$T/err")"
for v in land sync release; do
  refused rapid "$v"
  grep -q "run 'rapid setup' first" "$T/err" || fail "$v did not name rapid setup: $(cat "$T/err")"
done
git switch -q dev
rapid doctor --history-only >/dev/null || fail "doctor --history-only needs setup"
rapid check --gate fast >/dev/null || fail "check needs setup"
rapid setup >/dev/null || fail "setup in the clone"
rapid branch feature guarded >/dev/null || fail "branch after setup"
commit g.txt; rapid land >/dev/null || fail "land after setup"
history_clean
