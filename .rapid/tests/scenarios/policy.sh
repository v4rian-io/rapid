#!/usr/bin/env bash
# fast
# land_who=list refuses a lander not on the list; anyone allows any lander.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
rapid branch refactor policy >/dev/null
sed -i.bak -e 's/^land_who=.*/land_who=list/' .rapid/conf && rm -f .rapid/conf.bak
printf 'land_list=lead@team.test\n' >> .rapid/conf
git add .rapid/conf; git commit -q -m "[MODE] Restrict landing to the team lead"
rapid land >/dev/null || fail "landing the policy (dev still allows anyone)"
rapid branch feature extra >/dev/null; commit x.txt
refused rapid land
grep -q 'not in land_list' "$T/err" || fail "refusal text: $(cat "$T/err")"
actor "Team Lead" lead@team.test
rapid land >/dev/null || fail "the listed lead may land"
history_clean
