#!/usr/bin/env bash
# fast
# docs against code: the framework's own docs pass lint/docs.sh, and each kind of drift fails
# it by name: a stale verb count, a flag missing from README's table, a word that is no verb, an
# invariant id or range the code lacks, a conf key the code lacks or the docs miss, a stale scenario
# range or id, kinds printed differently from the code, and a doc that no longer states that main
# is production.
. "$(dirname "$0")/../lib.sh"
mkdir -p "$T/pristine"; cp -R "$RAPID_SRC" "$T/pristine/.rapid"
( cd "$T/pristine" && bash .rapid/lint/docs.sh ) > "$T/out" 2>&1 || fail "the framework's docs do not match its code: $(cat "$T/out")"
# drift FILE PERL_EXPR WANT: in a fresh copy, edit FILE, and the lint must fail naming WANT
drift() {
  local d; d=$(mktemp -d "$T/drift.XXXXXX"); cp -R "$T/pristine/.rapid" "$d/.rapid"
  perl -0pi -e "$2" "$d/.rapid/$1"
  if ( cd "$d" && bash .rapid/lint/docs.sh ) > "$T/out" 2>&1; then fail "drift in $1 ($2) passed the lint"; fi
  grep -qF -- "$3" "$T/out" || fail "drift in $1 ($2) not named '$3': $(cat "$T/out")"
}
drift DESIGN.md 's/\z/It has seven verbs.\n/' "'seven verbs'; rapid has"
drift README.md 's/`--merge` the forge/the forge/' "rapid check does not name --merge"
drift FLOWS.md 's/\z/Run `rapid frobnicate` first.\n/' "'rapid frobnicate', which is not a verb"
drift RULES.md 's/\z/See I12.\n/' "names I12"
drift DESIGN.md 's/\z/Invariants I1 to I7 hold.\n/' "'I1 to I7' for the whole set"
drift RULES.md 's/^\| I3 \|.*\n//m' "no row for I3"
drift RULES.md 's/^\| `land_approvals` \|.*\n//m' "lacks conf key land_approvals"
drift RULES.md 's/^(\| `forge_repo` \|.*)$/$1\n| `secret_gate` | x | y |/m' "names secret_gate, which the code does not know"
drift conf 's/\z/bogus_key=1\n/' "sets bogus_key"
drift FLOWS.md 's/\z/The scenario `no-such-thing` verifies it.\n/' "names scenario no-such-thing"
drift skill/SKILL.md 's/feature fix r&d refactor/feature r&d refactor/' "SKILL.md does not list the kinds"
drift skill/SKILL.md 's/main is production/main is the default/' "SKILL.md does not state that main is production"
drift RULES.md 's/main is production/main is a branch/g' "RULES.md does not state that main is production"
