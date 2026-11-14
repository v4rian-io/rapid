#!/usr/bin/env bash
# fast
# the agent skill keeps every agent lens rule and loads lazily: SKILL.md stays compact and holds
# a task table naming one lens file per task, every lens file is named there and exists, and the rule
# map lists every rule of the 16 agent lenses with a home that exists. The rules that bind every task
# (evidence, landing on the owner's word, fix forward, never another's commit) are in SKILL.md itself;
# each task's rules are in its lens. The docs lint fails when a lens drops out of the table or a map
# home vanishes.
. "$(dirname "$0")/../lib.sh"
S="$RAPID_SRC/skill"
[ -f "$S/SKILL.md" ] || fail "no SKILL.md"
b=$(wc -c < "$S/SKILL.md" | tr -d ' '); [ "$b" -le 6000 ] || fail "SKILL.md is $b bytes; the always-loaded part stays under 6000"
for l in commit merge history forge verify rebuild; do
  grep -qF "\`lenses/$l.md\`" "$S/SKILL.md" || fail "the task table does not name lenses/$l.md"
  [ -f "$S/lenses/$l.md" ] || fail "lenses/$l.md is missing"
done
# the always rules live in the skill itself
for w in "Evidence first" "Land only after the owner" "Fixes: <merge>" "not yours" "lens row"; do
  grep -qF "$w" "$S/SKILL.md" || fail "SKILL.md lacks the always rule '$w'"
done
# each lens holds its task's rules (a sample from every agent lens)
chk() { grep -qF "$2" "$S/lenses/$1" || fail "lenses/$1 lacks '$2'"; }
chk commit.md "Evidence:"; chk commit.md "Never fabricate a symbol"; chk commit.md "Cleanup is \`[REFACTOR]\`"
chk commit.md "Plan the branches before the first commit"; chk merge.md "This merge only"; chk merge.md "manual pole"
chk history.md "diff layer"; chk history.md "sort -c -n"; chk history.md "in doubt"
chk forge.md "gh run watch"; chk forge.md "x-oauth-scopes"; chk verify.md "fresh clone"; chk verify.md "diff -r --brief"
chk rebuild.md "Zip chains"; chk rebuild.md "Folder snapshots"; chk rebuild.md "Old repositories"
# the rule map: 16 lenses, every rule with a home
m="$S/lenses/RULE-MAP.md"
[ "$(grep -c '^## ' "$m")" = 16 ] || fail "the rule map does not cover the 16 agent lenses"
n=$(grep -cE '^\| [a-z-]+\.[0-9]+ \|' "$m"); [ "$n" -ge 300 ] || fail "the rule map lists only $n rules"
awk -F'|' '/^\| [a-z-]+\.[0-9]+ \|/ { gsub(/^ +| +$/, "", $4); if ($4 == "") { print; bad = 1 } } END { exit bad }' "$m" \
  || fail "a rule has no home in the map"
# the docs lint fails when the loader or the map stops resolving
mkdir -p "$T/r"; cp -R "$RAPID_SRC" "$T/r/.rapid"; cd "$T/r"
sh .rapid/lint/docs.sh >/dev/null || fail "the docs lint fails on the framework: $(sh .rapid/lint/docs.sh)"
[ -f .rapid/skill/lenses/commit.md ] || fail "the framework lacks the lenses"
sed -i.bak '/lenses\/forge.md/d' .rapid/skill/SKILL.md
refused sh .rapid/lint/docs.sh; grep -qF "lenses/forge.md is not in SKILL.md's lens table" "$T/out" || fail "lint: $(cat "$T/out")"
mv .rapid/skill/SKILL.md.bak .rapid/skill/SKILL.md
mv .rapid/skill/lenses/verify.md "$T/verify.md"
refused sh .rapid/lint/docs.sh; grep -qF "names lenses/verify.md, which does not exist" "$T/out" || fail "lint: $(cat "$T/out")"
grep -qF "RULE-MAP.md names verify.md as a home" "$T/out" || fail "lint did not check the map's homes: $(cat "$T/out")"
mv "$T/verify.md" .rapid/skill/lenses/verify.md
