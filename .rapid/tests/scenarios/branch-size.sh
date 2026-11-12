#!/usr/bin/env bash
# fast
# a branch over max_commits is refused before anything changes: its last commit is refused at
# commit, and made past the hooks the branch is refused by land.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
rapid branch refactor cap >/dev/null
sed -i.bak 's/^max_commits=.*/max_commits=3/' .rapid/conf && rm -f .rapid/conf.bak
git add .rapid/conf; git commit -q -m "[MODE] Lower the branch size cap to three"
rapid land >/dev/null || fail "landing the cap change"
rapid branch feature big >/dev/null
for i in 1 2 3; do commit "f$i.txt" "$i" "[NEW] Add part $i of the big change"; done
printf '4\n' > f4.txt; git add f4.txt
refused git commit -q -m "[NEW] Add part 4 of the big change"
grep -q 'max_commits=3' "$T/err" || fail "commit 4 was not refused at commit: $(cat "$T/err")"
git -c core.hooksPath=/dev/null commit -q -m "[NEW] Add part 4 of the big change"
before=$(git rev-parse dev)
refused rapid land
grep -q 'above max_commits=3' "$T/err" || fail "size refusal text: $(cat "$T/err")"
[ "$(git rev-parse dev)" = "$before" ] || fail "dev moved"
[ -z "$(git tag -l v2026.0.2)" ] || fail "a tag was made"
history_clean
