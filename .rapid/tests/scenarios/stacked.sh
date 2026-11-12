#!/usr/bin/env bash
# stacked branches: B starts on A, A lands, B syncs and lands without duplicating A's commits.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
rapid branch feature base-api >/dev/null; commit api.txt api "[NEW] Add the base API"
git switch -q -c pool/v2026.0/feature.client
printf '# feature/client\n\nUse the base API from a client.\n' > .rapid/requirements/client.md
git add .rapid/requirements/client.md; commit client.txt client "[NEW] Add the API client"
git switch -q "$(lname base-api)"; rapid land >/dev/null || fail "land A"
git switch -q pool/v2026.0/feature.client
rapid sync >/dev/null || fail "sync B"
[ "$(git rev-list --count dev..HEAD)" = 1 ] || fail "B carries $(git rev-list --count dev..HEAD) commits after sync (want 1)"
rapid land >/dev/null || fail "land B"
[ "$(git rev-list --count dev^1..dev^2)" = 1 ] || fail "B's merge duplicates A's commits"
[ "$(git log --format=%s dev | grep -c 'Add the base API')" = 1 ] || fail "A's commit appears twice"
history_clean
