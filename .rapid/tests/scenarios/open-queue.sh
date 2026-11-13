#!/usr/bin/env bash
# rapid queue lists the open branches in landing order and changes nothing: each branch with its commits,
# how far it is behind dev, whether it merges into dev's tip cleanly and which other open branches change
# a file it changes; once one of two branches that wrote the same file lands, the other is listed with
# that file as its conflict; --json carries the same facts; two branches that
# each state a requirement share no file; no ref, tag or file moves.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
rapid branch feature alpha >/dev/null; commit shared.txt alpha "[NEW] Add the shared file from alpha"; pa=$(git branch --show-current)
git switch -q dev
rapid branch feature beta >/dev/null; commit shared.txt beta "[NEW] Add the shared file from beta"; pb=$(git branch --show-current)
git switch -q dev
rapid branch fix gamma >/dev/null; commit other.txt gamma "[FIX] Repair the other file in gamma"; pg=$(git branch --show-current)
refs0=$(git for-each-ref)
rapid queue > "$T/q" || fail "rapid queue"
grep -q '^queue: 3 open branch(es) in landing order' "$T/q" || fail "the queue does not count three branches: $(cat "$T/q")"
[ "$(grep -oE 'pool/[^ ]+' "$T/q" | awk '!s[$0]++' | sed -n '1,3p' | tr '\n' ' ')" = "$pa $pb $pg " ] || fail "the branches are not in landing order: $(cat "$T/q")"
[ "$(grep -c 'merge into dev: clean' "$T/q")" = 3 ] || fail "three branches that each merge cleanly are not all clean: $(cat "$T/q")"
grep -q "shares files with: $pb\$" <<<"$(grep -A2 "^  $pa " "$T/q")" || fail "alpha does not name beta as sharing a file: $(cat "$T/q")"
grep -q 'shares files with: none$' <<<"$(grep -A2 "^  $pg " "$T/q")" || fail "gamma shares a file with a branch: $(cat "$T/q")"
# sharing is by the files a branch itself changes: the two that wrote shared.txt name each other and only each
# other
grep -q "shares files with: $pa\$" <<<"$(grep -A2 "^  $pb " "$T/q")" || fail "beta does not name alpha as sharing a file: $(cat "$T/q")"
[ "$(grep -c 'shares files with: none$' "$T/q")" = 1 ] || fail "a branch that shares no file names another: $(cat "$T/q")"
rapid queue --json > "$T/j" || fail "rapid queue --json before a land"
grep -q "{\"branch\": \"$pa\", [^}]*\"shares_files_with\": \[\"$pb\"\]}" "$T/j" || fail "the JSON does not say alpha shares with beta alone: $(cat "$T/j")"
grep -q "{\"branch\": \"$pg\", [^}]*\"shares_files_with\": \[\]}" "$T/j" || fail "the JSON says gamma shares a file: $(cat "$T/j")"
[ "$(git for-each-ref)" = "$refs0" ] && [ -z "$(git status --porcelain)" ] || fail "rapid queue changed the repository"
# alpha lands: beta now conflicts with dev in the file both wrote, gamma stays clean
git switch -q "$pa"; rapid land >/dev/null || fail "land alpha"
refs0=$(git for-each-ref)
rapid queue > "$T/q" || fail "rapid queue after a land"
grep -q '^queue: 2 open branch(es)' "$T/q" || fail "the landed branch is still queued: $(cat "$T/q")"
grep -q 'merge into dev: conflicts in: shared.txt$' <<<"$(grep -A1 "^  $pb  1 commit(s), 2 behind dev" "$T/q")" || fail "beta's conflict is not named: $(cat "$T/q")"
grep -q 'merge into dev: clean$' <<<"$(grep -A1 "^  $pg  1 commit(s), 2 behind dev" "$T/q")" || fail "gamma is not clean: $(cat "$T/q")"
rapid queue --json > "$T/j" || fail "rapid queue --json"
grep -q "{\"branch\": \"$pb\", \"number\": \"[^\"]*\", \"commits\": 1, \"behind\": 2, \"merge\": \"conflict\", \"conflicts\": \\[\"shared.txt\"\\], \"shares_files_with\": \\[\\]}" "$T/j" \
  || fail "the JSON does not carry beta's conflict: $(cat "$T/j")"
grep -q "{\"branch\": \"$pg\", [^}]*\"merge\": \"clean\", \"conflicts\": \\[\\]" "$T/j" || fail "the JSON does not carry gamma: $(cat "$T/j")"
[ "$(git for-each-ref)" = "$refs0" ] && [ -z "$(git status --porcelain)" ] || fail "rapid queue changed the repository"
# two branches opened with a requirement each write their own requirement file: they share no file, in
# the list as in the JSON
mkrepo "$T/q2"; cd "$T/q2"
rapid branch feature delta -r "The delta file exists in the project tree." >/dev/null; commit delta.txt delta "[NEW] Add the delta file to the project"; pd=$(git branch --show-current)
git switch -q dev
rapid branch feature epsilon -r "The epsilon file exists in the project tree." >/dev/null; commit epsilon.txt epsilon "[NEW] Add the epsilon file to the project"; pe=$(git branch --show-current)
rapid queue > "$T/q" || fail "rapid queue with two requirement branches"
[ "$(grep -c 'shares files with: none$' "$T/q")" = 2 ] || fail "two unrelated branches are listed as sharing a file: $(cat "$T/q")"
[ "$(grep -c 'merge into dev: clean$' "$T/q")" = 2 ] || fail "two unrelated branches do not both merge cleanly: $(cat "$T/q")"
rapid queue --json > "$T/j" || fail "rapid queue --json with two requirement branches"
[ "$(grep -o '"shares_files_with": \[\]' "$T/j" | wc -l | tr -d ' ')" = 2 ] || fail "the JSON lists unrelated branches as sharing a file: $(cat "$T/j")"
cd "$T/r"
# an unknown flag is a usage error; the verb answers -h with its own usage
refused rapid queue --merge
grep -q '^  rapid queue ' <<<"$(rapid queue -h)" || fail "queue -h is not queue's usage"
history_clean
