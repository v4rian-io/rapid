#!/usr/bin/env bash
# every static land check runs before any gate and one refusal lists them all: a branch with four
# violations (a broken commit message, a banned file, a requirement that states nothing and a thin -F merge body),
# all made past the hooks, is refused once, naming all four, and no gate ran; fixed, it lands. rapid check --land checks
# ten branches at once, by name or branch, ok or every reason per branch, read-only.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
rapid branch feature four >/dev/null
# the gate leaves a mark when it runs, so a refusal before any gate is visible
printf '#!/bin/sh\ntouch "%s/gate-ran"\n! ls *.bad >/dev/null 2>&1\n' "$T" > check.sh; git add check.sh
mkdir -p .rapid/requirements; printf '# feature/four\n\nShort.\n' > .rapid/requirements/four.md; git add .rapid/requirements/four.md
git commit -q --no-verify -m "[NEW] Mark every gate run in the project test"
printf 'x\n' > a.txt; git add a.txt; git commit -q --no-verify -m "added a file"
printf 'SECRET=1\n' > .env; git add -f .env; git commit -q --no-verify -m "[NEW] Add the environment settings file"
printf 'Short.\n\n- x\n' > "$T/body"
rm -f "$T/gate-ran"
refused rapid land -F "$T/body"
[ "$(grep -c '^  - ' "$T/err")" = 4 ] || fail "the refusal does not list four reasons: $(cat "$T/err")"
grep -q 'refused for 4 reason' "$T/err" || fail "the refusal does not count four: $(cat "$T/err")"
for w in 'breaks the message rules' 'banned file' 'states no requirement' 'merge body list needs an item of two words'; do
  grep -qF "$w" "$T/err" || fail "the refusal does not name '$w': $(cat "$T/err")"
done
[ ! -e "$T/gate-ran" ] || fail "a gate ran before the static checks refused"
[ "$(git rev-list --count dev)" = "$(git rev-list --count main)" ] || fail "dev moved"
# fix all four in one pass, then it lands
git reset -q --soft dev; git rm -q --cached .env; rm -f .env
printf '# feature/four\n\nThe project test marks every gate run.\n' > .rapid/requirements/four.md; git add .rapid/requirements/four.md
git commit -q -m "[NEW] Mark every gate run in the project test" || fail "the fixed commit"
printf 'The branch adds the a file.\n\n- Adds the a file\n' > "$T/body"
rapid land -F "$T/body" >/dev/null 2>"$T/err" || fail "the fixed branch did not land: $(cat "$T/err")"
[ -e "$T/gate-ran" ] || fail "the gates did not run on the fixed branch"
# rapid check --land: ten branches at once, read-only
for i in 0 1 2 3 4 5 6 7 8 9; do
  git switch -q dev; rapid branch feature "p$i" -r "Branch p$i adds its own file to the project." >/dev/null; commit "p$i.txt"
done
git switch -q dev; rapid branch feature bad >/dev/null; printf "x\n" > bad.txt; printf 'SECRET=1\n' > .env; git add -f bad.txt .env; git commit -q --no-verify -m "added bad"
before=$(git for-each-ref | git hash-object --stdin)
s0=$(date +%s)
refused rapid check --land p0 p1 p2 p3 p4 p5 p6 p7 p8 "$(lname p9)" bad
secs=$(( $(date +%s) - s0 ))
[ "$(grep -c '^ok .* may land$' "$T/out")" = 10 ] || fail "check --land did not pass the ten clean branches: $(cat "$T/out")"
grep -qE '^X pool/v2026[.]0/n[0-9]+[.]feature[.]bad: 2 reason' "$T/out" || fail "check --land did not name both reasons of the bad branch: $(cat "$T/out")"
[ "$(sed -n 11p "$T/out" | cut -c1-2)" = 'X ' ] || fail "check --land did not print in the order named: $(cat "$T/out")"
[ "$(git for-each-ref | git hash-object --stdin)" = "$before" ] || fail "check --land changed a ref"
echo "check --land of 11 branches took ${secs}s" >&2
[ "$secs" -lt "${RAPID_TEST_CHECK_LAND_MAX:-30}" ] || fail "check --land of 11 branches took ${secs}s"
rapid check --land p3 >/dev/null || fail "check --land of one clean branch failed"
