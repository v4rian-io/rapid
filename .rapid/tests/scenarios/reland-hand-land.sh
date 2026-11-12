#!/usr/bin/env bash
# a hand rapid land during a re-land never wedges it: while sync --dev's plan is pending a plain
# rapid land is refused with the --continue/--abort instruction; a plan head already landed by hand
# (an older rapid allowed it) is dropped by --continue, which re-lands the rest, and --abort never
# keeps a landed name as a branch not landed yet, so I7 holds and no land is lost.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/a" origin; cd "$T/a"
git clone -q "$T/origin.git" "$T/b"; ( cd "$T/b" && git switch -q dev && rapid setup >/dev/null )
# offline_lands NAME...: in B, offline, land each NAME; the first changes shared.txt
offline_lands() {
  local s first=1
  cd "$T/b"; actor "Agent Two" agent2@team.test; git config remote.origin.url "$T/offline.git"
  for s in "$@"; do
    rapid branch feature "$s" >/dev/null
    if [ "$first" = 1 ]; then commit shared.txt "$s" "[NEW] Change the shared file from $s"; first=0
    else commit "$s.txt" "$s" "[NEW] Add the file of branch $s"; fi
    rapid land >/dev/null 2>&1 || fail "B lands $s offline"
  done
}
# online_conflict NAME: A lands a change of shared.txt online; B comes back and sync --dev stops
online_conflict() {
  cd "$T/a"; actor "Agent One" agent1@team.test; rapid sync --dev >/dev/null 2>&1 || true
  rapid branch feature "$1" >/dev/null; commit shared.txt "$1" "[NEW] Change the shared file from $1"
  rapid land >/dev/null || fail "A lands $1"
  cd "$T/b"; actor "Agent Two" agent2@team.test; git config remote.origin.url "$T/origin.git"
  refused rapid sync --dev
  grep -q -- '--continue' "$T/err" || fail "the conflict does not name --continue: $(cat "$T/err")"
  printf 'resolved %s\n' "$1" > shared.txt; git add shared.txt
  GIT_EDITOR=true git -c core.hooksPath=/dev/null cherry-pick --continue >/dev/null 2>&1 || fail "cherry-pick --continue"
}
offline_lands b-one b-two b-three
online_conflict a-one
refused rapid land
grep -q 'in progress' "$T/err" && grep -q -- '--continue' "$T/err" && grep -q -- '--abort' "$T/err" \
  || fail "a hand land during a re-land was not refused with the instruction: $(cat "$T/err")"
# the wedge an older rapid allowed: the plan head landed by hand
RAPID_RELAND_STEP=1 rapid land --batch >/dev/null 2>&1 || fail "hand-land b-one past the refusal"
rapid sync --dev --continue > "$T/out" 2>&1 || fail "--continue after a hand land: $(cat "$T/out")"
grep -q 'b-one is already on dev' "$T/out" || fail "the landed plan head was not dropped: $(cat "$T/out")"
for f in b-two.txt b-three.txt; do git cat-file -e "dev:$f" 2>/dev/null || fail "$f was dropped from dev"; done
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$(git rev-parse dev)" ] || fail "dev is not published"
history_clean
# --abort with a landed plan head: the rest is kept as branches not landed yet, the landed name is not
offline_lands b-four b-five
online_conflict a-two
RAPID_RELAND_STEP=1 rapid land >/dev/null 2>&1 || fail "hand-land b-four past the refusal"
rapid sync --dev --abort > "$T/out" 2>&1 || fail "--abort: $(cat "$T/out")"
[ -z "$(lref b-four)" ] || fail "a landed name was kept as a branch not landed yet"
[ -n "$(lref b-five)" ] || fail "b-five was not kept"
history_clean
