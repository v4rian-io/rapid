#!/usr/bin/env bash
# fast
# merge bodies and requirements say something: land refuses a requirement under three words, a
# body paragraph under three words and a list without an item of two words, and a body that sets a
# trailer land writes itself; a body's final paragraph of 'Key: value' lines becomes real trailers.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
command rapid branch feature thin -r "Too short." >/dev/null; commit thin.txt t "[NEW] Add the thin file to the project"
refused rapid land
grep -q 'states no requirement' "$T/err" || fail "a two-word requirement landed: $(cat "$T/err")"
printf '# feature/thin\n\nAdd the thin file so the body rules have a branch.\n' > .rapid/requirements/thin.md
git add .rapid/requirements/thin.md; git commit -q -m "[DOCS] State the requirement of the thin branch"
printf 'x\n\n- y\n' > "$T/body"
refused rapid land -F "$T/body"
grep -q 'says too little' "$T/err" || fail "a one-word paragraph landed: $(cat "$T/err")"
printf 'Adds the thin file.\n\n- y\n' > "$T/body"
refused rapid land -F "$T/body"
grep -q 'item of two words' "$T/err" || fail "a one-word list landed: $(cat "$T/err")"
printf 'Adds the thin file.\n\n- The thin file.\n\nGates: fast=pass\n' > "$T/body"
refused rapid land -F "$T/body"
grep -q 'sets a trailer rapid land writes itself' "$T/err" || fail "a body set Gates: $(cat "$T/err")"
printf 'Adds the thin file.\n\n- The thin file, for the body rules.\n\nReplays: pool/n1.example\nRefs: notes/body-rules\n' > "$T/body"
rapid land -F "$T/body" >/dev/null || fail "land with a body and its trailers"
[ "$(git log -1 --format='%(trailers:key=Replays,valueonly)' dev | sed '/^$/d')" = pool/n1.example ] \
  || fail "Replays: is not a trailer: $(git log -1 --format=%B dev)"
[ "$(git log -1 --format='%(trailers:key=Refs,valueonly)' dev | sed '/^$/d')" = notes/body-rules ] || fail "Refs: is not a trailer"
[ "$(git log -1 --format='%(trailers:key=Merge-Tree,valueonly)' dev | sed '/^$/d')" = "$(git rev-parse dev^{tree})" ] || fail "rapid's trailers were displaced"
history_clean
