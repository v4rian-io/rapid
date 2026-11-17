#!/usr/bin/env bash
# one name in two clones: the second is refused by I7 with a rename hint and lands after renaming.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/a" origin; cd "$T/a"
git clone -q "$T/origin.git" "$T/b"; ( cd "$T/b" && git switch -q dev && rapid setup >/dev/null )
rapid branch feature search >/dev/null; commit a.txt
cd "$T/b"; rapid branch feature search >/dev/null; commit b.txt b "[NEW] Add the search box"
cd "$T/a"; rapid land >/dev/null || fail "first land"
cd "$T/b"
refused rapid sync
grep -q 'already landed' "$T/err" && grep -q 'rapid branch --rename' "$T/err" || fail "no rename hint: $(cat "$T/err")"
rapid branch --rename search-box >/dev/null || fail "rename"
[ "$(git rev-list --count dev..HEAD)" = 1 ] || fail "rename changed the commit count"
git cat-file -e HEAD:.rapid/requirements/search-box.md || fail "renamed requirement missing"
rapid sync >/dev/null || fail "sync after rename"
rapid land >/dev/null || fail "land after rename"
grep -Eq '^\[MERGE\] pool/v2026[.]0/n[0-9]+[.]feature[.]search-box into dev: v2026[.]0[.]2$' <<<"$(git log -1 --format=%s dev)" || fail "subject: $(git log -1 --format=%s dev)"
history_clean
