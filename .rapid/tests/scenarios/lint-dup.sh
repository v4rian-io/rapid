#!/usr/bin/env bash
# fast
# no doubled line: the framework passes lint/dup.sh, and each shape a conflict resolution
# leaves fails it by name: a top-level variable assigned twice in a lib, two echo help lines that
# differ by one token in a hook, two near-identical lines in a doc code block, and a prose passage
# repeated a few lines further in a doc.
. "$(dirname "$0")/../lib.sh"
mkdir -p "$T/pristine"; cp -R "$RAPID_SRC" "$T/pristine/.rapid"
( cd "$T/pristine" && bash .rapid/lint/dup.sh ) > "$T/out" 2>&1 || fail "the framework has a doubled line: $(cat "$T/out")"
# plant FILE PERL_EXPR WANT: in a fresh copy, edit FILE, and the lint must fail naming WANT
plant() {
  local d; d=$(mktemp -d "$T/plant.XXXXXX"); cp -R "$T/pristine/.rapid" "$d/.rapid"
  perl -0pi -e "$2" "$d/.rapid/$1"
  if ( cd "$d" && bash .rapid/lint/dup.sh ) > "$T/out" 2>&1; then fail "a doubled line in $1 ($2) passed the lint"; fi
  grep -qF -- "$3" "$T/out" || fail "the doubled line in $1 ($2) was not named '$3': $(cat "$T/out")"
}
plant lib/message.sh 's/^(RAPID_SUBJ_MIN=12\n)/RAPID_TAGS="NEW FIX"\n$1/m' "assigned twice: .rapid/lib/message.sh"
plant hooks/commit-msg 's/^(\s*echo "  A test-first commit.*\n)/$1    echo "  A test-first commit that fails its test on purpose carries one line: Red: <test name>." >&2\n/m' "doubled help: .rapid/hooks/commit-msg"
plant README.md 's/^(rapid branch fix login-timeout\n)/$1rapid branch fix login-timeout two\n/m' "doubled doc: .rapid/README.md"
plant skill/SKILL.md 's/^(2\. Commit one concern at a time.*\n.*\n.*\n)/$1   `[NEW|FIX|REFACTOR|DOCS|TEST|REVERT|HOTFIX] Capitalised summary`, 12 to 72\n/m' "doubled doc: .rapid/skill/SKILL.md"
