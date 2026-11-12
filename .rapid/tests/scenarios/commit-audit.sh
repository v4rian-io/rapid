#!/usr/bin/env bash
# the deterministic commit audit (the required commit-audit status): commit-msg
# refuses a subject joined by 'and', 'with', 'plus', 'or', 'then', 'beside', '+' or ',', a [FIX] without Cause: then Fix:, a
# commit above max_commit_lines and a [NEW] or [FIX] that changes behaviour without touching a test
# path (the commit after a Red: commit excepted). A smelly commit made past the hook is named by rapid
# check --audit and --each, refused by land and pre-push, and flagged by I4. The forge's commit-audit
# job runs rapid check --audit with dev's checker, and under land_pr=required dev's ruleset requires it.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r" origin; cd "$T/r"
# the audit's own policy: a small size cap and real test paths
rapid branch refactor audit-policy -r "The commit audit runs with a small cap and real test paths." >/dev/null
sed -i.bak '/^test_paths=/d' .rapid/conf; rm -f .rapid/conf.bak
printf 'max_commit_lines=6\ntest_paths=tests/*\n' >> .rapid/conf
# the project test also runs every tests/*_test.sh, so a red test is red
printf '#!/bin/sh\n! ls *.bad >/dev/null 2>&1 || exit 1\nfor t in tests/*_test.sh; do [ -f "$t" ] || continue; sh "$t" || exit 1; done\n' > check.sh
git add check.sh; git commit -q -m "[NEW] Run the tests directory in the project test" || fail "the project test commit"
git add .rapid/conf; git commit -q -m "[MODE] Set the commit audit policy" || fail "the policy commit"
rapid land >/dev/null || fail "land the audit policy"
rapid branch feature sum >/dev/null
mkdir -p src tests
printf 'echo $(( $1 + $2 ))\n' > src/sum.sh; git add src/sum.sh
# joiners in the subject
for s in "[NEW] Add the sum helper and its test" "[NEW] Add the sum helper with its test" \
         "[NEW] Add the sum helper plus its test" "[NEW] Add the sum helper + its test" "[NEW] Add the sum, then its test"; do
  refused git commit -q -m "$s"
  grep -qF "subject joins two concerns" "$T/err" || fail "'$s' was not refused as two concerns: $(cat "$T/err")"
done
# a behaviour change with no test path
refused git commit -q -m "[NEW] Add the sum helper to the project"
grep -qF "touches no test path" "$T/err" || fail "a [NEW] without its test was accepted: $(cat "$T/err")"
printf '[ "$(sh src/sum.sh 2 3)" = 5 ]\n' > tests/sum_test.sh; git add tests/sum_test.sh
git commit -q -m "[NEW] Add the sum helper to the project" || fail "the change with its test was refused"
# a [REFACTOR] changes no behaviour and needs no test
printf '# sums two integers\necho $(( $1 + $2 ))\n' > src/sum.sh; git add src/sum.sh
git commit -q -m "[REFACTOR] Name what the sum helper does" || fail "a refactor without a test was refused"
# a [FIX] carries Cause: then Fix:
printf '# sums two integers\necho $(( ${1:-0} + ${2:-0} ))\n' > src/sum.sh; printf '[ "$(sh src/sum.sh)" = 0 ]\n' >> tests/sum_test.sh
git add src/sum.sh tests/sum_test.sh
refused git commit -q -m "[FIX] Sum missing arguments as zero" -m "Missing arguments crashed the helper."
grep -qF "Cause:' paragraph, then a 'Fix:'" "$T/err" || fail "a [FIX] without Cause and Fix was accepted: $(cat "$T/err")"
refused git commit -q -m "[FIX] Sum missing arguments as zero" -m "Fix: default to zero." -m "Cause: no default."
git commit -q -m "[FIX] Sum missing arguments as zero" -m "Missing arguments crashed the helper." \
  -m "Cause: the arithmetic read empty operands." -m "Fix: each operand defaults to zero." || fail "a [FIX] with Cause and Fix was refused"
# the size cap
printf '%s\n' 1 2 3 4 5 6 7 > tests/big_test.sh; git add tests/big_test.sh
refused git commit -q -m "[TEST] Add a large test fixture"
grep -qF "changes 7 lines (max_commit_lines=6)" "$T/err" || fail "a commit above the cap was accepted: $(cat "$T/err")"
git reset -q tests/big_test.sh; rm -f tests/big_test.sh
# a Red: test, then the change that turns it green without touching a test
printf '[ "$(sh src/sum.sh 1 2 3)" = 6 ]\n' > tests/three_test.sh; git add tests/three_test.sh
git commit -q -m "[TEST] Expect the sum of three arguments" -m "Red: tests/three_test.sh" || fail "the red test"
printf '# sums up to three integers\necho $(( ${1:-0} + ${2:-0} + ${3:-0} ))\n' > src/sum.sh; git add src/sum.sh
git commit -q -m "[NEW] Sum a third argument" || fail "the commit after a Red: commit needs no test path"
rapid check --audit >"$T/out" || fail "check --audit fails a clean branch: $(cat "$T/out")"
# a smelly commit made past the hook: named by check --audit and --each, refused by land and pre-push, flagged by I4
printf 'x\n' > src/extra.sh; git add src/extra.sh
git commit -q --no-verify -m "[NEW] Add an extra script and a note"
bad=$(git rev-parse HEAD)
refused rapid check --audit; grep -qF "subject joins two concerns" "$T/out" || fail "check --audit: $(cat "$T/out")"
grep -qF "touches no test path" "$T/out" || fail "check --audit missed the test smell: $(cat "$T/out")"
refused rapid check --each; grep -qF "fails the commit audit" "$T/err" || fail "check --each: $(cat "$T/err")"
refused rapid land; grep -qF "fails the commit audit" "$T/err" || grep -qF "joins two concerns" "$T/err" || fail "land: $(cat "$T/err")"
refused git push -q origin "$(lname sum)"; grep -qF "joins two concerns" "$T/err" || fail "pre-push: $(cat "$T/err")"
m=$(git commit-tree "HEAD^{tree}" -p dev -p HEAD -m "[MERGE] pool/v2026.0/feature.sum into dev: v2026.0.9")
L="$RAPID_SRC/lib" bash -c '. "$L/core.sh"; for l in message version policy history audit; do . "$L/$l.sh"; done; rapid_check_merge "$1" "" 0' _ "$m" > "$T/i4"
grep -qF "I4 $bad subject joins two concerns" "$T/i4" || fail "I4 subject: $(cat "$T/i4")"
grep -qF "I4 $bad a [NEW] commit changes behaviour" "$T/i4" || fail "I4 test smell: $(cat "$T/i4")"
rapid check --audit "$m" >/dev/null 2>&1 && fail "check --audit passed a merge whose branch holds the smelly commit"
# the honest branch lands once the smelly commit is gone
git reset -q --hard "$bad^"
rapid land >/dev/null || fail "land the audited branch"
# the forge: the commit-audit job takes dev's checker and runs check --audit; the ruleset requires it
WF="$RAPID_SRC/remote/check.yml"
awk '/^  commit-audit:/ { f = 1 } f && /check --audit/ { ok = 1 } END { exit !ok }' "$WF" || fail "no commit-audit job running check --audit"
awk '/^  commit-audit:/ { f = 1 } f && /git archive/ { ok = 1 } END { exit !ok }' "$WF" || fail "the commit-audit job does not take dev's checker"
mkdir -p "$T/bin"; printf '#!/bin/sh\ncase "$1 $2" in "api -X") while [ $# -gt 0 ]; do [ "$1" = --input ] && cat "$2" >> "%s"; shift; done ;; api*) echo "" ;; esac\n' "$T/rulesets" > "$T/bin/gh"
chmod +x "$T/bin/gh"; export PATH="$T/bin:$PATH"
rapid branch refactor review -r "Lands go through review; the commit audit is a required status." >/dev/null
printf 'land_pr=required\nforge_repo=acme/app\n' >> .rapid/conf; git add .rapid/conf
git commit -q -m "[MODE] Require review before a land"
rapid land >/dev/null || fail "land the review policy"
rapid setup --remote --repo acme/app >/dev/null || fail "setup --remote"
grep -qF '"context": "commit-audit"' "$T/rulesets" || fail "dev's ruleset does not require commit-audit: $(cat "$T/rulesets")"
history_clean
