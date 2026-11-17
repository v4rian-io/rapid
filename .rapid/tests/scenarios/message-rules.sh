#!/usr/bin/env bash
# fast
# commit-msg refusals: each rule refuses with its fix named and the subject help printed once
# with every tag, nothing is rewritten.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
rapid branch refactor rules >/dev/null
echo a > a.txt; git add a.txt
bad=(
  "add a file without a tag:subject must start"
  "[WIP] Add a file with an unknown tag:subject must start"
  "[NEW] add a lower case subject here:capital letter"
  "[NEW] Short:12 to 72"
  "[NEW] Add a subject that ends in a period.:without a period"
  "[NEW] Add a file $(printf '\xe2\x80\x94') holding a dash:em or en dash"
)
for b in "${bad[@]}"; do
  msg="${b%%:*}"; why="${b#*:}"
  refused git commit -q -m "$msg"
  grep -q "$why" "$T/err" || fail "'$msg' refusal lacks '$why': $(cat "$T/err")"
  # the subject help prints once, naming every tag message.sh holds
  [ "$(grep -c '  Subject: ' "$T/err")" = 1 ] || fail "'$msg' refusal prints the subject help more than once: $(cat "$T/err")"
  grep -qF '  Subject: [NEW|FIX|REFACTOR|DOCS|TEST|REVERT|HOTFIX|MODE] ' "$T/err" || fail "'$msg' help lacks a tag: $(cat "$T/err")"
done
refused git commit -q -m "[NEW] Add a file carrying a co-author" -m "Co-Authored-By: Claude <x@y>"
refused git commit -q -m "[TEST] Add two red markers here" -m "Red: one
Red: two"
[ "$(git rev-list --count dev..HEAD)" = 0 ] || fail "a refused commit landed"
git commit -q -m "[NEW] Add a file under a ruled message" || fail "a ruled message was refused"
history_clean
