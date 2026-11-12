#!/usr/bin/env bash
# no Co-Authored-By trailer of any kind: a commit carrying one is refused at commit and, made
# past the hook, by land; a hand-made merge of one is flagged I4.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
rapid branch feature pair >/dev/null
printf 'p\n' > p.txt; git add p.txt
refused git commit -q -m "[NEW] Add the pairing file to the project" -m "Co-Authored-By: Somebody Else <else@team.test>"
grep -q 'no Co-Authored-By: trailer' "$T/err" || fail "a Co-Authored-By trailer was accepted: $(cat "$T/err")"
git commit -q --no-verify -m "[NEW] Add the pairing file to the project" -m "Co-Authored-By: Somebody Else <else@team.test>"
refused rapid land
grep -q 'no Co-Authored-By: trailer' "$T/err" || fail "land took a Co-Authored-By trailer: $(cat "$T/err")"
pl=$(git branch --show-current)
git switch -q dev; git -c core.hooksPath=/dev/null merge -q --no-ff "$pl" -m "[MERGE] pool/v2026.0/feature.pair into dev: v2026.0.1"
rapid doctor --history-only > "$T/doc" 2>&1 && fail "doctor missed the trailer"
grep -q '^doctor: I4 .*no Co-Authored-By: trailer' "$T/doc" || fail "no I4 for the trailer: $(cat "$T/doc")"
