#!/usr/bin/env bash
# the CLI's usage contract: rapid -h and --help print the whole usage, opening with the product's
# positioning (a software development lifecycle tool), and exit 0; no verb and an
# unknown verb print it and exit 2; a verb's -h prints that verb's lines alone; an argument a verb
# does not know is refused by name with exit 2 and changes nothing.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
R="$(command -v rapid)"
rc() { local c=0; "$@" >"$T/out" 2>"$T/err" || c=$?; printf '%s' "$c"; }
for h in -h --help; do
  [ "$(rc "$R" "$h")" = 0 ] || fail "rapid $h did not exit 0"
  grep -q '^Usage:' "$T/out" || fail "rapid $h prints no usage: $(sed -n 1,3p "$T/out")"
  [ "$(sed -n 1p "$T/out")" = "rapid - software development lifecycle tool: branches in, one merge out, history as the database." ] \
    || fail "rapid $h does not open with the product's positioning: $(sed -n 1p "$T/out")"
  for v in setup branch check commit land sync release changelog version queue bisect status doctor upgrade; do
    grep -q "^  rapid $v" "$T/out" || fail "rapid $h does not list $v"
  done
  grep -q '^Exit codes: 0 done, 1 refused or failed' "$T/out" || fail "rapid $h does not state the exit codes"
done
[ "$(rc "$R")" = 2 ] || fail "rapid with no verb did not exit 2"
grep -q '^Usage:' "$T/out" || fail "rapid with no verb prints no usage"
[ "$(rc "$R" frobnicate)" = 2 ] || fail "an unknown verb did not exit 2"
grep -q '^Usage:' "$T/out" || fail "an unknown verb prints no usage"
# a verb's -h is that verb's lines alone
[ "$(rc "$R" land --help)" = 0 ] || fail "land --help"
for l in 'rapid land \[-F BODY\] \[--dry-run\] \[--failed-gates-only\]' 'rapid land --batch ' 'rapid land --halt ' 'rapid land --prune ' 'rapid land --pr '; do
  grep -q "^  $l" "$T/out" || fail "land --help does not print '$l': $(cat "$T/out")"
done
grep -q -- '--failed-gates-only runs again only the' "$T/out" || fail "land --help drops its continuation lines"
! grep -q '^  rapid sync\|^  rapid setup' "$T/out" || fail "land --help prints other verbs"
[ "$(rc "$R" setup -h)" = 0 ] || fail "setup -h"
[ "$(grep -c '^  rapid setup' "$T/out")" = 7 ] || fail "setup -h does not print its seven forms: $(cat "$T/out")"
grep -q '^  rapid setup --owner EMAIL' "$T/out" || fail "setup -h does not name --owner"
# an unknown argument is refused by name, exit 2, nothing changes
d0=$(git rev-parse dev); refs0=$(git for-each-ref | cksum)
rapid branch feature probe >/dev/null; commit probe.txt; refs1=$(git for-each-ref | cksum)
unk() { # unk LABEL ARGS...: the last argument is the unknown one
  local label="$1" last; shift; for last in "$@"; do :; done
  [ "$(rc "$R" "$@")" = 2 ] || fail "rapid $* did not exit 2 (stderr: $(cat "$T/err"))"
  grep -qF "X rapid: $label: unknown argument $last" "$T/err" || fail "rapid $* does not name the argument: $(cat "$T/err")"
}
unk land land --nope
unk land land --prune extra
unk land land --halt extra
unk sync sync --nope
unk "sync --dev" sync --dev --nope
unk check check --nope
unk setup setup --nope
unk "setup --remote" setup --remote --nope
unk release release --nope
unk changelog changelog --nope
unk status status --nope
unk queue queue --nope
unk version version --nope
unk branch branch feature other --nope
unk commit commit --nope
[ "$(rc "$R" bisect dev)" = 2 ] || fail "bisect without its command did not exit 2"
grep -qF 'usage: rapid bisect GOOD BAD -- CMD' "$T/err" || fail "bisect does not print its usage: $(cat "$T/err")"
[ "$(git rev-parse dev)" = "$d0" ] && [ "$(git for-each-ref | cksum)" = "$refs1" ] || fail "a refused argument changed a ref"
[ -z "$(lref other)" ] || fail "a refused branch command opened a branch"
: "$refs0"
