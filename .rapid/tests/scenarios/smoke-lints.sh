#!/usr/bin/env bash
# the cheap test and the lint runner: tests/smoke.sh passes on a tree whose shell files parse,
# whose CLI prints its help and whose lints pass, and fails naming the shell file that does not
# parse or the lints that fail, with what bash said; a bash that could not start (no process available)
# is said as that, never as a file that does not parse; lint/run.sh runs every lint of .rapid/lint and
# fails on any finding.
. "$(dirname "$0")/../lib.sh"
P="$T/pristine"; mkdir -p "$P"; cp -R "$RAPID_SRC" "$P/.rapid"
cd "$P"; git init -q; git add -- .rapid; git commit -q --no-verify -m "[NEW] Vendor the framework"
sh .rapid/tests/smoke.sh > "$T/out" 2>&1 || fail "the smoke fails on the framework's own tree: $(cat "$T/out")"
bash .rapid/lint/run.sh > "$T/out" 2>&1 || fail "the lints fail on the framework's own tree: $(cat "$T/out")"
# a shell file that does not parse: named, exit 1
printf 'if then fi (\n' >> .rapid/lib/version.sh
rc=0; sh .rapid/tests/smoke.sh > "$T/out" 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "the smoke exited $rc on a file that does not parse"
grep -qF "X smoke: $P/.rapid/lib/version.sh does not parse" "$T/out" || fail "the file is not named: $(cat "$T/out")"
grep -qF 'X smoke: rapid --help fails' "$T/out" || fail "a CLI that cannot start is not named: $(cat "$T/out")"
grep -E '^    \| .*version\.sh: line [0-9]+: syntax error' "$T/out" >/dev/null || fail "what bash said of the file is not shown: $(cat "$T/out")"
git checkout -q -- .rapid/lib/version.sh
# a bash that cannot start (no process available): said as that, never as a file that does not parse
mkdir -p "$T/nobash"; printf '#!/bin/sh\necho "bash: fork: Resource temporarily unavailable" >&2\nexit 254\n' > "$T/nobash/bash"; chmod +x "$T/nobash/bash"
rc=0; PATH="$T/nobash:$PATH" sh .rapid/tests/smoke.sh > "$T/out" 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "the smoke exited $rc when bash could not start"
grep -F "X smoke: bash could not start on $P/.rapid/lib/version.sh: bash: fork: Resource temporarily unavailable" "$T/out" >/dev/null || fail "a bash that could not start is not said: $(cat "$T/out")"
grep -F 'X smoke: rapid --help could not start: bash: fork: Resource temporarily unavailable' "$T/out" >/dev/null || fail "a CLI that could not start is not said: $(cat "$T/out")"
! grep -E 'does not parse|rapid --help fails' "$T/out" >/dev/null || fail "a bash that could not start is named a parse failure: $(cat "$T/out")"
# a lint finding: lint/run.sh fails with the finding, and so does the smoke
u="Us""ers"; printf 'see /%s/someone/project\n' "$u" > notes.txt; git add notes.txt
rc=0; bash .rapid/lint/run.sh > "$T/out" 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "lint/run.sh exited $rc on a personal path"
grep -qF 'X personal path: notes.txt:1' "$T/out" || fail "the lint finding is not shown: $(cat "$T/out")"
rc=0; sh .rapid/tests/smoke.sh > "$T/out" 2>&1 || rc=$?
[ "$rc" = 1 ] && grep -qF 'X smoke: the lints fail' "$T/out" || fail "the smoke passed a tree whose lints fail: rc $rc $(cat "$T/out")"
git rm -q --cached notes.txt; rm -f notes.txt
# every lint runs: a finding of another lint fails the run too
printf '#!/bin/sh\nprintf "a\\n" %s grep -q a\n' '|' > probe.sh; git add probe.sh
rc=0; bash .rapid/lint/run.sh > "$T/out" 2>&1 || rc=$?
[ "$rc" = 1 ] && grep -qF 'probe.sh:2' "$T/out" || fail "lint/run.sh did not run the quiet grep lint: rc $rc $(cat "$T/out")"
git rm -q --cached probe.sh; rm -f probe.sh
sh .rapid/tests/smoke.sh > "$T/out" 2>&1 || fail "the smoke fails on the restored tree: $(cat "$T/out")"
