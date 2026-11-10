#!/usr/bin/env bash
# branch numbers: rapid branch names every branch pool/v<series>/n<N>.<kind>.<name>, N one more than any number
# known, never shared. The number is carried by the branch's safety anchor (safety/v<series>/n<N>.<kind>.<name>), which
# origin holds once the branch is pushed, so another clone counts past it; offline a clone still writes n<N>, and a branch whose
# number another clone published first takes the next free number at its land; a closed branch keeps its number in
# the creation order; a landed merge carries Branch-Number:; a branch made by hand takes the next number
# at land; a hand-made name reusing a number is refused at land and flagged I7.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/a" origin; cd "$T/a"
git clone -q "$T/origin.git" "$T/b"; ( cd "$T/b" && git switch -q dev && rapid setup >/dev/null )
rapid branch feature alpha >/dev/null
[[ "$(lname alpha)" =~ ^pool/v2026[.]0/(n1)[.]feature[.]alpha$ ]] || fail "the first branch is $(lname alpha), want pool/v2026.0/n1.feature.alpha"
an="${BASH_REMATCH[1]}"
# opening a branch never pushes: the anchor carries the number in this clone and origin holds nothing yet
git rev-parse -q --verify "refs/heads/safety/v2026.0/$an.feature.alpha" >/dev/null || fail "alpha has no anchor carrying $an here"
[ -z "$(git ls-remote origin 'refs/heads/safety/*' 'refs/heads/pool/*')" ] || fail "opening a branch pushed"
commit alpha.txt
# the branch's push carries its anchor, which carries the number
git push -q origin "$(lname alpha)" || fail "A pushes alpha"
settle
[ "$(git ls-remote origin "refs/heads/safety/v2026.0/$an.feature.alpha" | cut -f1)" = "$(git rev-parse refs/heads/safety/v2026.0/$an.feature.alpha)" ] \
  || fail "$an did not reach origin with alpha's anchor"
# another clone, which never saw alpha's branch, counts past the numbers origin holds
cd "$T/b"; actor "Agent Two" agent2@team.test
rapid branch feature beta >/dev/null; commit beta.txt
[[ "$(lname beta)" =~ ^pool/v2026[.]0/n2[.]feature[.]beta$ ]] || fail "B's branch is $(lname beta), want n2"
git push -q origin "$(lname beta)" || fail "B pushes beta"
settle
cd "$T/a"; actor "Agent One" agent1@team.test
git switch -q dev; rapid branch feature gamma >/dev/null; commit gamma.txt
[[ "$(lname gamma)" =~ ^pool/v2026[.]0/n3[.]feature[.]gamma$ ]] || fail "A's second branch is $(lname gamma), want n3"
# offline, a clone still writes n<N>: two clones may count the same N, and the branch whose number
# another clone published first takes the next free number at its land
for c in a b; do git -C "$T/$c" config remote.origin.url "$T/offline.git"; done
git switch -q dev; rapid branch feature delta >/dev/null 2>&1; da=$(lname delta)
cd "$T/b"; actor "Agent Two" agent2@team.test
git switch -q dev; rapid branch feature epsilon >/dev/null 2>&1; eb=$(lname epsilon)
[[ "$da" =~ ^pool/v2026[.]0/n4[.]feature[.]delta$ ]] || fail "A's offline branch is $da"
[[ "$eb" =~ ^pool/v2026[.]0/n3[.]feature[.]epsilon$ ]] || fail "B's offline branch is $eb"
for c in a b; do git -C "$T/$c" config remote.origin.url "$T/origin.git"; done
commit e.txt; git push -q origin "$eb" || fail "B pushes its offline branch"
settle
[ -n "$(git ls-remote origin 'refs/heads/safety/v2026.0/n3.*')" ] || fail "no anchor carrying n3 is on origin"
cd "$T/a"; actor "Agent One" agent1@team.test
commit d.txt; git switch -q "$(lname gamma)"; rapid land > "$T/renum" 2>&1 || fail "A lands its offline branch: $(cat "$T/renum")"
grep -q 'branch number n3 was published by another clone first' "$T/renum" || fail "the taken number was not said: $(cat "$T/renum")"
grep -q '^\[MERGE\] pool/v2026[.]0/n5[.]feature[.]gamma into dev: ' <<<"$(git log -1 --format=%s dev)" || fail "gamma did not land under the next free number: $(git log -1 --format=%s dev)"# the closed branch keeps its place: every number ever taken, in order, names its branch
order=$(git for-each-ref --format='%(refname)' refs/heads/safety/v2026.0 | sed -nE 's#.*/(n[0-9]+)[.]feature[.]([a-z]+)$#\1 \2#p' | sort -t n -k 2 -n | tr '\n' ' ')
[[ "$order" == "n1 alpha n4 delta n5 gamma "* ]] || fail "the numbers in creation order read '$order'"
# a land carries the number
git switch -q "$(lname alpha)"; rapid land >/dev/null || fail "land alpha"
[ "$(git log -1 --format=%B dev | sed -nE 's/^Branch-Number: (.*)$/\1/p')" = "$an" ] || fail "alpha's merge carries no Branch-Number: $an"
# a branch made by hand takes the next number at land, carried by its merge
git switch -q -c pool/v2026.0/feature.hand dev; mkdir -p .rapid/requirements
commit .rapid/requirements/hand.md "# feature/hand

A branch made by hand takes its number at land." "[NEW] State the requirement of the hand-made branch"
rapid land >/dev/null || fail "land the hand-made branch"
hn=$(git log -1 --format=%B dev | sed -nE 's/^Branch-Number: (.*)$/\1/p')
[[ "$hn" =~ ^n[0-9]+$ ]] || fail "the hand-made branch landed with Branch-Number '$hn'"
[ -n "$(git ls-remote origin refs/heads/safety/v2026.0/feature.hand)" ] || fail "land did not push the hand branch's anchor"
# a hand-made name that reuses a number is refused at land and flagged I7
git switch -q -c "pool/v2026.0/$an.feature.fake" dev
commit .rapid/requirements/fake.md "# feature/fake

A reused number is refused at land." "[NEW] State the requirement of the fake branch"
refused rapid land
grep -q "$an belongs to another branch" "$T/err" || fail "a reused number was landed: $(cat "$T/err")"
rapid doctor --history > "$T/doc" 2>&1 && fail "doctor missed a reused number"
grep -q "I7 - branch number '$an' names more than one branch" "$T/doc" || fail "doctor: $(cat "$T/doc")"
git switch -q dev; git branch -q -D "pool/v2026.0/$an.feature.fake"
# a number lock whose holder is gone is lifted, and the lift is logged
lk="$(git rev-parse --git-common-dir)/rapid/number.lock"; sleep 0 & dead=$!; wait "$dead"; echo "$dead" > "$lk"
git switch -q dev; rapid branch feature after-crash >/dev/null || fail "rapid branch with a stale number lock"
[ ! -e "$lk" ] || fail "the stale number lock stayed"
grep -qE "lifted number.lock: holder pid $dead gone \(rapid branch" "$(git rev-parse --git-common-dir)/rapid/log" || fail "the lift is not logged: $(cat "$(git rev-parse --git-common-dir)/rapid/log" 2>&1)"
history_clean
