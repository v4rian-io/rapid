#!/usr/bin/env bash
# no lazy commit or requirement: with commit_body at its default and requirement_test=required, a
# bodiless [FIX] commit is refused at commit and, made past the hook, by land and I4; a subject
# repeated as the body does not count, a Cause: line then a Fix: line does; the requirement "fix
# the bug" is refused at land; a Test: naming a file the branch lacks is refused; a stated
# requirement with its test lands with a Test: trailer, and rapid branch --test writes the line.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
rapid branch refactor strict -r "Every change commit and requirement says what it does and how it is verified." >/dev/null
grep -vE '^(commit_body|requirement_test)=' .rapid/conf > c && mv c .rapid/conf; printf 'requirement_test=required\n' >> .rapid/conf; git add .rapid/conf
git commit -q -m "[MODE] Require every documentation rule" -m "Commit bodies and requirement tests are required from now on."
rapid land >/dev/null || fail "land the default rules"
command rapid branch fix thing -r "fix the bug" >/dev/null
printf 'f\n' > fix.txt; git add fix.txt
refused git commit -q -m "[FIX] Handle the empty input case"
grep -q 'needs a body' "$T/err" || fail "a bodiless fix was committed: $(cat "$T/err")"
refused git commit -q -m "[FIX] Handle the empty input case" -m "Handle the empty input case"
grep -q 'needs a body' "$T/err" || fail "the subject repeated counted as a body: $(cat "$T/err")"
# the documented [FIX] shape alone, a Cause: line then a Fix: line, is a body
git commit -q -m "[FIX] Handle the empty input case" -m "Cause: the parser read the first token before checking the input length." \
  -m "Fix: return an empty list when the input is empty." 2>"$T/err" || fail "a Cause: and Fix: body was refused: $(cat "$T/err")"
git reset -q --soft HEAD~1
git commit -q --no-verify -m "[FIX] Handle the empty input case"
refused rapid land
grep -q 'needs a body' "$T/err" || fail "land took a bodiless fix: $(cat "$T/err")"
git commit -q --amend -m "[FIX] Handle the empty input case" -m "Empty input crashed the parser on its first token." -m "Cause: the parser read the first token before checking the input length." -m "Fix: return an empty list when the input is empty."
refused rapid land
grep -q 'says too little' "$T/err" || fail "the requirement 'fix the bug' landed: $(cat "$T/err")"
printf '# fix/thing\n\nThe parser returns an empty list for empty input instead of crashing.\n\nTest: tests/empty.t\n' > .rapid/requirements/thing.md
git add .rapid/requirements/thing.md; git commit -q -m "[DOCS] State the requirement of the thing branch"
refused rapid land
grep -q 'Test: tests/empty.t, which the branch tip does not hold' "$T/err" || fail "a Test: naming a missing file landed: $(cat "$T/err")"
mkdir -p tests; printf 'empty\n' > tests/empty.t; git add tests/empty.t
git commit -q -m "[TEST] Cover the empty input case"
rapid land >/dev/null || fail "land a stated, verified requirement"
[ "$(git log -1 --format='%(trailers:key=Test,valueonly)' dev | sed '/^$/d')" = tests/empty.t ] || fail "the merge has no Test: trailer: $(git log -1 --format=%B dev)"
command rapid branch feature next -r "The next change is stated in eight words or more." --test check.sh >/dev/null
grep -Fx 'Test: check.sh' .rapid/requirements/next.md >/dev/null || fail "branch --test wrote no Test: line: $(cat .rapid/requirements/next.md)"
git rm -q --cached .rapid/requirements/next.md; mv .rapid/requirements/next.md "$T/next.md"
git switch -q dev; git branch -q -D "$(lname next)"
history_clean
git switch -q -c pool/v2026.0/fix.hand dev
printf '# fix/hand\n\nA hand-made branch whose commit has no body at all.\n' > .rapid/requirements/hand.md; git add .rapid/requirements/hand.md
git commit -q --no-verify -m "[FIX] Add a hand-made change"
v=$(git describe --exact-match dev); n=${v##*.}
git switch -q dev; git -c core.hooksPath=/dev/null merge -q --no-ff pool/v2026.0/fix.hand -m "[MERGE] pool/v2026.0/fix.hand into dev: ${v%.*}.$((n + 1))"
rapid doctor --history-only > "$T/doc" 2>&1 && fail "doctor missed the bodiless commit"
grep -q '^doctor: I4 .*needs a body' "$T/doc" || fail "no I4 for the bodiless commit: $(cat "$T/doc")"
