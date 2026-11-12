#!/usr/bin/env bash
# two clones land offline, then reconnect: the first publishes, the second
# re-lands onto it with a new version, and no commit is lost.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/a" origin; cd "$T/a"
git clone -q "$T/origin.git" "$T/b"; ( cd "$T/b" && git switch -q dev && rapid setup >/dev/null )
for c in a b; do git -C "$T/$c" config remote.origin.url "$T/offline.git"; done
actor "Human Dev" human@team.test
rapid branch feature notes >/dev/null; commit notes.txt
rapid land > "$T/out" 2>&1 || fail "A lands offline: $(cat "$T/out")"
grep -q 'origin unreachable, landed locally' "$T/out" || fail "offline land message: $(cat "$T/out")"
cd "$T/b"; actor "Agent Two" agent2@team.test
rapid branch feature tags-filter >/dev/null; commit filter.txt f "[NEW] Add the tag filter"
rapid land >/dev/null 2>&1 || fail "B lands offline"
b_old=$(git rev-parse dev); b_branch=$(git rev-parse dev^2)
for c in a b; do git -C "$T/$c" config remote.origin.url "$T/origin.git"; done
cd "$T/a"; actor "Human Dev" human@team.test
rapid sync --dev >/dev/null || fail "A publishes"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$(git rev-parse dev)" ] || fail "A's land not on origin"
cd "$T/b"; actor "Agent Two" agent2@team.test
rapid sync --dev > "$T/out" 2>&1 || fail "B re-lands: $(cat "$T/out")"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$(git rev-parse dev)" ] || fail "B's re-land not on origin"
[ "$(git describe --exact-match dev)" = v2026.0.2 ] || fail "B's re-land is $(git describe --exact-match dev 2>&1), want v2026.0.2"
st=$(git for-each-ref --format='%(refname)' 'refs/heads/safety/dev-*')
[ -n "$st" ] && [ "$(git rev-parse "$st")" = "$b_old" ] || fail "B's old dev is not kept in a snapshot branch safety/dev-<timestamp>: $st"
git merge-base --is-ancestor "$b_branch" "$st" || fail "B's old branch commit was lost"
[ "$(git show dev:filter.txt)" = f ] || fail "B's change is not on dev"
[ "$(git ls-remote origin "$st" | cut -f1)" = "$b_old" ] || fail "the snapshot branch of the replaced dev was not published"
history_clean
cd "$T/a"; rapid sync --dev >/dev/null || fail "A catches up"
[ "$(git rev-parse dev)" = "$(git -C "$T/b" rev-parse dev)" ] || fail "A did not fast-forward"
history_clean
