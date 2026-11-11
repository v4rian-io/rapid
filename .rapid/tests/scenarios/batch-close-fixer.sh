#!/usr/bin/env bash
# conf test_on_fail at a close: when the batch gate is the project's scenario run, the command the
# conf names starts on a failing scenario the moment it fails, with the scenario's name and its
# kept output; the close fails, pushes nothing and keeps the batch, the fix lands as one more
# branch and the next close passes without starting the command again.
. "$(dirname "$0")/../lib.sh"
# the batch gate here is a scenario run of its own: the knobs of the run that holds it do not reach it
unset RAPID_TEST_JOBS RAPID_TEST_ONLY RAPID_TEST_ON_FAIL RAPID_TEST_FAIL_DIR
mkrepo "$T/a" origin; cd "$T/a"
o0=$(git ls-remote origin refs/heads/dev | cut -f1)
# the project's own small scenario matrix: its b scenario fails until mt/fixed exists
rapid branch feature suite >/dev/null
mkdir -p mt/scenarios; cp "$RAPID_SRC/tests/run.sh" "$RAPID_SRC/tests/gen-scenarios.sh" mt/
printf '#!/usr/bin/env bash\n# A pass.\ntrue\n' > mt/scenarios/01-a.sh
printf '#!/usr/bin/env bash\n# Fails until the fix lands.\necho "boom from b"; test -e "$(dirname "$0")/../fixed"\n' > mt/scenarios/02-b.sh
bash mt/gen-scenarios.sh
git add mt; git commit -q -m "[NEW] Add the project scenario matrix"
rapid land --batch >/dev/null || fail "land the matrix"
rapid land >/dev/null 2>&1 || fail "the close before the matrix is the gate"
o1=$(git ls-remote origin refs/heads/dev | cut -f1); [ "$o1" != "$o0" ] || fail "the first close did not push"
# the conf makes the matrix the batch gate and names the command started on a failure
rapid branch refactor gate -r "The batch gate is the project scenario matrix, with a command started on a failure." >/dev/null; pb=$(lname gate)
grep -v '^gates_full=' .rapid/conf > c && mv c .rapid/conf
printf 'gates_full=bash mt/run.sh\n' >> .rapid/conf
printf 'test_on_fail=printf "%%s %%s\\n" "$1" "$2" >> "%s/fixers"\n' "$T" >> .rapid/conf
git add .rapid/conf; git commit -q -m "[MODE] Run the project matrix at the close"
rapid land --batch >/dev/null || fail "land the gate flip"
tip=$(git rev-parse dev)
rc=0; rapid land >"$T/out" 2>"$T/err" || rc=$?
[ "$rc" = 1 ] || fail "a close whose gate fails exited $rc: $(cat "$T/out" "$T/err")"
grep -q '^!! FAIL 02-b' "$T/out" "$T/err" || fail "the failure was not reported the moment it happened: $(cat "$T/out" "$T/err")"
grep -qF "broke the close: $pb (" "$T/out" || fail "the close did not name the branch: $(cat "$T/out")"
grep -qF 'the batch gate full fails on the final tree; nothing was pushed and the batch stays open' "$T/err" || fail "the close did not say what it kept: $(cat "$T/err")"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -s "$T/fixers" ] && break; sleep 0.3; done
[ "$(wc -l < "$T/fixers" | tr -d ' ')" = 1 ] || fail "test_on_fail did not start once: $(cat "$T/fixers" 2>&1)"
read -r fname flog < "$T/fixers"
[ "$fname" = 02-b ] || fail "test_on_fail got the scenario '$fname', not 02-b"
case "$flog" in */rapid-fail-02-b.log) ;; *) fail "test_on_fail got no kept output file: $flog" ;; esac
[ "$(git rev-parse dev)" = "$tip" ] || fail "the failed close moved dev"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$o1" ] || fail "the failed close pushed"
[ -s "$(git rev-parse --git-common-dir)/rapid/batch" ] || fail "the failed close dropped the batch"
# the fix lands as one more branch; the next close passes and starts no command
git switch -q dev; rapid branch fix suite-fixed >/dev/null
commit mt/fixed fixed "[FIX] Repair the b scenario of the matrix"
rapid land --batch >/dev/null || fail "land the fix"
rapid land >"$T/out" 2>"$T/err" || fail "the close after the fix: $(cat "$T/out" "$T/err")"
grep -qE '^---- 2 passed, 0 failed ' "$T/out" || fail "the close did not run the matrix: $(cat "$T/out")"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$(git rev-parse dev)" ] || fail "the close after the fix did not push"
[ ! -e "$(git rev-parse --git-common-dir)/rapid/batch" ] || fail "a passed close left the batch open"
[ "$(wc -l < "$T/fixers" | tr -d ' ')" = 1 ] || fail "test_on_fail started on a passing run"
history_clean
