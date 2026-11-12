#!/usr/bin/env bash
# a re-land that hits a conflict keeps every offline land: three offline lands (the second
# naming the first with Fixes:) meet a conflicting online land; sync --dev stops, the plan survives,
# doctor reports it, --continue re-lands all three with Fixes: following the new sha; --abort keeps
# the rest as branches not landed yet and nothing is lost.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/a" origin; cd "$T/a"
rapid branch feature base >/dev/null; commit shared.txt 0 "[NEW] Add the shared file"
rapid land >/dev/null || fail "A lands base"
git clone -q "$T/origin.git" "$T/b"; ( cd "$T/b" && git switch -q dev && rapid setup >/dev/null )
cd "$T/b"; actor "Agent Two" agent2@team.test
git config remote.origin.url "$T/offline.git"
rapid branch feature b-one >/dev/null; commit shared.txt b "[NEW] Change the shared file from B"
b1=$(git rev-parse HEAD); rapid land >/dev/null 2>&1 || fail "B lands b-one offline"
rapid branch fix b-two >/dev/null; commit b2.txt two "[FIX] Add the second file from B" "Fixes: $b1"
rapid land >/dev/null 2>&1 || fail "B lands b-two offline: $(rapid land 2>&1 | tail -2)"
rapid branch feature b-three >/dev/null; commit b3.txt three "[NEW] Add the third file from B"
rapid land >/dev/null 2>&1 || fail "B lands b-three offline"
cd "$T/a"; actor "Agent One" agent1@team.test
rapid branch feature a-one >/dev/null; commit shared.txt a "[NEW] Change the shared file from A"
rapid land >/dev/null || fail "A lands a-one online"
cd "$T/b"; actor "Agent Two" agent2@team.test
git config remote.origin.url "$T/origin.git"
refused rapid sync --dev
grep -q -- '--continue' "$T/err" || fail "the conflict does not name --continue: $(cat "$T/err")"
refused rapid sync --dev
grep -q 'in progress' "$T/err" || fail "a plain sync --dev during a re-land was not refused: $(cat "$T/err")"
refused rapid doctor
printf 'a and b\n' > shared.txt; git add shared.txt
GIT_EDITOR=true git -c core.hooksPath=/dev/null cherry-pick --continue >/dev/null 2>&1 || fail "cherry-pick --continue"
rapid sync --dev --continue > "$T/out" 2>&1 || fail "--continue: $(cat "$T/out")"
for f in b2.txt b3.txt; do git cat-file -e "dev:$f" 2>/dev/null || fail "$f was dropped from dev"; done
[ "$(git show dev:shared.txt)" = "a and b" ] || fail "the resolution is not on dev"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$(git rev-parse dev)" ] || fail "dev is not published"
fx=$(git log --format='%(trailers:key=Fixes,valueonly)' dev | sed '/^$/d' | sed -n 1p)
git merge-base --is-ancestor "$fx" dev || fail "Fixes: $fx does not name a commit on dev"
[ "$fx" != "$b1" ] || fail "Fixes: still names the old sha"
[ "$(git log -1 --format=%B "$fx" | sed -n 1p)" = "[NEW] Change the shared file from B" ] || fail "Fixes: names the wrong commit"
sb=$(git for-each-ref --format='%(refname)' 'refs/heads/safety/dev-*')
[ "$(wc -l <<<"$sb" | tr -d ' ')" = 1 ] && [ -n "$sb" ] || fail "want one snapshot branch of the replaced dev: $sb"
[ "$(git rev-list --first-parent --count "$sb" --not dev)" = 3 ] || fail "the snapshot branch does not hold the three replaced merges"
[ "$(git ls-remote origin "$sb" | cut -f1)" = "$(git rev-parse "$sb")" ] || fail "the snapshot branch of the replaced dev is not on origin"
history_clean
# --abort: two more offline lands meet another conflict; abort keeps both as branches not landed yet.
git config remote.origin.url "$T/offline.git"
rapid branch feature b-four >/dev/null; commit shared.txt bb "[NEW] Change the shared file again from B"
rapid land >/dev/null 2>&1 || fail "B lands b-four offline"
rapid branch feature b-five >/dev/null; commit b5.txt five "[NEW] Add the fifth file from B"
rapid land >/dev/null 2>&1 || fail "B lands b-five offline"
b5=$(git rev-parse dev^2)
cd "$T/a"; actor "Agent One" agent1@team.test; rapid sync --dev >/dev/null
rapid branch feature a-two >/dev/null; commit shared.txt aa "[NEW] Change the shared file again from A"
rapid land >/dev/null || fail "A lands a-two"
cd "$T/b"; actor "Agent Two" agent2@team.test; git config remote.origin.url "$T/origin.git"
refused rapid sync --dev
rapid sync --dev --abort > "$T/out" 2>&1 || fail "--abort: $(cat "$T/out")"
for l in b-four b-five; do [ -n "$(lref "$l")" ] || fail "$l not kept as a branch not landed yet"; done
[ "$(git rev-parse "$(lname b-five)")" = "$b5" ] || fail "b-five's commits are not the kept ones"
rapid status > "$T/out" 2>&1; grep -q "branches not landed yet: .*b-five" "$T/out" || fail "status does not list the branches not landed yet: $(cat "$T/out")"
[ "$(git rev-parse dev)" = "$(git ls-remote origin refs/heads/dev | cut -f1)" ] || fail "dev is not origin's after --abort"
history_clean
