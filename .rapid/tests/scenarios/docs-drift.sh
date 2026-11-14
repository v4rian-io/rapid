#!/usr/bin/env bash
# docs cannot drift, in the framework and in a consumer: on a copy of the framework each planted
# drift fails lint/docs.sh by name (a subject limit, the max_commits default, an exit code the usage
# no longer explains, the Release section of FLOWS removed, a lib file DESIGN's Layout does not name);
# in a consumer with docs_rules a branch changing src/ without docs/ is refused, with the doc it lands
# and the merge names it, and Docs: none (<reason>) in the requirement lands too.
. "$(dirname "$0")/../lib.sh"
mkdir -p "$T/pristine"; cp -R "$RAPID_SRC" "$T/pristine/.rapid"
( cd "$T/pristine" && bash .rapid/lint/docs.sh ) > "$T/out" 2>&1 || fail "the framework's docs do not match its code: $(cat "$T/out")"
drift() {
  local d; d=$(mktemp -d "$T/drift.XXXXXX"); cp -R "$T/pristine/.rapid" "$d/.rapid"
  perl -0pi -e "$2" "$d/.rapid/$1"
  if ( cd "$d" && bash .rapid/lint/docs.sh ) > "$T/out" 2>&1; then fail "drift in $1 ($2) passed the lint"; fi
  grep -qF -- "$3" "$T/out" || fail "drift in $1 ($2) not named '$3': $(cat "$T/out")"
}
drift lib/message.sh 's/^RAPID_SUBJ_MAX=72\n/RAPID_SUBJ_MAX=80\n/m' "says subjects are 12 to 72 chars; message.sh says 12 to 80"
drift lib/policy.sh 's/^RAPID_MAX_COMMITS_DEFAULT=20\n/RAPID_MAX_COMMITS_DEFAULT=50\n/m' "gives max_commits a default other than 50"
drift rapid 's/ 2 usage,//' "rapid exits 2; the usage's Exit codes line"
drift FLOWS.md 's/^## Release\n/## Shipping\n/m' "lost the section '## Release'"
d=$(mktemp -d "$T/drift.XXXXXX"); cp -R "$T/pristine/.rapid" "$d/.rapid"; printf '# new\n' > "$d/.rapid/lib/newlib.sh"
if ( cd "$d" && bash .rapid/lint/docs.sh ) > "$T/out" 2>&1; then fail "an unnamed lib file passed the lint"; fi
grep -qF "Layout does not name lib/newlib.sh" "$T/out" || fail "the new lib file was not named: $(cat "$T/out")"
# a consumer's own docs rule
mkrepo "$T/r"; cd "$T/r"
rapid branch refactor docs-rule -r "Code under src/ is described by docs/; they change together." >/dev/null
printf 'docs_rules=src/*=docs/*\n' >> .rapid/conf; git add .rapid/conf; git commit -q -m "[MODE] Tie src to its docs"
rapid land >/dev/null || fail "land docs_rules"
rapid branch feature api >/dev/null
mkdir -p src docs; printf 'f\n' > src/api.txt; git add src/api.txt; git commit -q -m "[NEW] Add the api source"
refused rapid land
grep -q 'changes code its docs describe and no doc: src/\*=docs/\*' "$T/err" || fail "code without its doc landed: $(cat "$T/err")"
printf 'api\n' > docs/api.md; git add docs/api.md; git commit -q -m "[DOCS] Describe the api"
rapid land >/dev/null || fail "land code with its doc"
git log -1 --format='%(trailers:key=Docs,valueonly)' dev | grep -Fx 'docs/api.md' >/dev/null || fail "the merge does not name its doc: $(git log -1 --format=%B dev)"
rapid branch fix api-typo -r "Fix a typo in the api source.

Docs: none (a typo the docs never quoted)" >/dev/null
printf 'g\n' > src/api.txt; git add src/api.txt; git commit -q -m "[FIX] Fix the api typo" -m "A typo in the api source." -m "Cause: a misspelt word." -m "Fix: spell it right."
rapid land >/dev/null || fail "land with Docs: none"
git log -1 --format='%(trailers:key=Docs,valueonly)' dev | grep -Fx 'none (a typo the docs never quoted)' >/dev/null || fail "the merge does not record Docs: none: $(git log -1 --format=%B dev)"
history_clean
