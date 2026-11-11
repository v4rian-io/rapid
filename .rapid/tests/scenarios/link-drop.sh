#!/usr/bin/env bash
# the link drops between the merge and the push: nothing changes locally or
# on origin, and the next land resumes without a duplicate tag.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r" origin; cd "$T/r"
rapid branch feature sync-icon >/dev/null; commit icon.txt
# the remote refuses the next push once, as a dropped link would
printf '#!/bin/sh\nif [ -f "%s/drop" ]; then rm -f "%s/drop"; exit 1; fi\n' "$T" "$T" > "$T/origin.git/hooks/pre-receive"
chmod +x "$T/origin.git/hooks/pre-receive"; : > "$T/drop"
dev0=$(git rev-parse dev)
refused rapid land
grep -q 'nothing was published, nothing changed locally' "$T/err" || fail "drop message: $(cat "$T/err")"
# the batch stays as it was: its merge and tag local, origin untouched, the branch kept until the close
[ "$(git rev-parse dev^1)" = "$dev0" ] || fail "the refused close did not keep the batch's merge"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$dev0" ] || fail "origin dev moved"
[ -n "$(lname sync-icon)" ] || fail "branch was lost"
rapid land > "$T/out" 2>&1 || fail "close after the link is back: $(cat "$T/out")"
grep -q 'already passed its gate' "$T/out" || fail "the second close tested the same tree again: $(cat "$T/out")"
[ "$(git tag -l 'v*' | wc -l | tr -d ' ')" = 1 ] || fail "duplicate tags: $(git tag -l 'v*')"
[ -n "$(git ls-remote origin refs/tags/v2026.0.1)" ] || fail "tag not on origin"
[ -z "$(lname sync-icon)" ] || fail "the closed batch kept its branch"
history_clean
