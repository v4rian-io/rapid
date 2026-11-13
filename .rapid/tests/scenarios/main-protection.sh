#!/usr/bin/env bash
# owner-only promotion: with land_pr=required, setup --remote puts GitHub's
# review rule and the rapid-check status on the dev-only rapid-review ruleset and on no ruleset that covers
# main (there it would refuse the owner's release push), and rapid-release-tags lets only the admins
# create a release/* tag. A release tag pushed on its own by anyone but the owner, which would open
# the next series without main, is refused by pre-push; the owner's passes. The agent guard denies
# an agent's release/* tag through git tag, update-ref and push, and the skill says so.
. "$(dirname "$0")/../lib.sh"
command -v python3 >/dev/null || fail "python3 is required by the agent guard"
actor "Owner One" owner@team.test
mkrepo "$T/r" origin; cd "$T/r"
actor "Human Two" human@team.test
rapid branch feature export >/dev/null; commit export.txt; rapid land >/dev/null || fail "land as the human"
v=$(git describe --exact-match dev)
# a release tag alone, by a non-owner: pre-push refuses it (it would open the next series)
git tag -a "release/$v" -m "hand release" dev
refused git push origin "refs/tags/release/$v"
grep -q "release tag release/$v was tagged by 'human@team.test'" "$T/err" || fail "pre-push let a foreign release tag through: $(cat "$T/err")"
[ -z "$(git ls-remote origin "refs/tags/release/*")" ] || fail "a foreign release tag reached origin"
git tag -d "release/$v" >/dev/null
# the owner's own release tag passes the same check
actor "Owner One" owner@team.test
git tag -a "release/$v" -m "owner release" dev
git push -q origin "refs/tags/release/$v" 2>"$T/err" || fail "pre-push refused the owner's release tag: $(cat "$T/err")"
# the agent guard: no release/* tag from an agent, in any spelling
export GUARD_TMP_ROOTS="$T/throwaway" RAPID_BAKS_DIR="$T/baks"; mkdir -p "$T/throwaway"
guard() { python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$T/r" | "$TOOL/agent/guard-destructive.sh"; }
for c in "git tag -a release/v2026.9.9 -m x dev" "git tag release/v2026.9.9" "git update-ref refs/tags/release/v2026.9.9 HEAD" \
         "git push origin refs/tags/release/$v" "git push origin release/$v"; do
  out=$(guard "$c"); grep -q '"deny"' <<<"$out" || fail "the guard allowed '$c': $out"
  grep -q "owner's release" <<<"$out" || fail "the deny for '$c' does not say why: $out"
done
for c in "git tag -l 'release/*'" "git tag v-note-x"; do
  out=$(guard "$c"); [ -z "$out" ] || fail "the guard denied '$c': $out"
done
grep -q 'never push, merge into or tag main' "$TOOL"/skill/SKILL.md || fail "the skill does not say main moves only by the owner"
grep -q 'release/<v>` tag' "$TOOL"/skill/SKILL.md || fail "the skill does not forbid release tags"
# the forge: review on dev only, never on a ruleset covering main
rapid branch refactor review -r "Require review before a land, on a forge." >/dev/null
printf 'land_pr=required\nland_approvals=1\nforge_repo=acme/app\n' >> .rapid/conf
git add .rapid/conf; git commit -q -m "[MODE] Require one approval before a land"
rapid land >/dev/null || fail "land the review policy"
P="$T/forge"; mkdir -p "$P/rs" "$T/bin"
cat > "$T/bin/gh" <<STUB
#!/bin/sh
case "\$1 \$2" in
  "api repos/acme/app/rulesets") echo "" ;;
  "api -X") while [ \$# -gt 0 ]; do [ "\$1" = --input ] && { tr -d '\n' < "\$2"; echo; } >> "$P/rulesets"; shift; done ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$T/bin/gh"
PATH="$T/bin:$PATH" rapid setup --remote --repo acme/app > "$T/out" 2>&1 || fail "setup --remote: $(cat "$T/out")"
[ "$(wc -l < "$P/rulesets" | tr -d ' ')" = 8 ] || fail "eight rulesets expected: $(cat "$P/rulesets")"
while IFS= read -r r; do
  if grep -q '"refs/heads/main"' <<<"$r"; then
    grep -q '"pull_request"\|"required_status_checks"' <<<"$r" && fail "a ruleset covering main carries dev's review rule: $r"
  fi
done < "$P/rulesets"
grep '"name": "rapid-review"' "$P/rulesets" > "$T/review" || fail "no rapid-review ruleset: $(cat "$P/rulesets")"
grep -q '"include": \["refs/heads/dev"\]' "$T/review" || fail "rapid-review covers more than dev: $(cat "$T/review")"
grep -q '"type": "pull_request", "parameters": { "required_approving_review_count": 1' "$T/review" || fail "rapid-review lacks the review rule: $(cat "$T/review")"
grep -q '"context": "rapid-check"' "$T/review" || fail "rapid-review lacks the rapid-check status: $(cat "$T/review")"
grep '"name": "rapid-release-tags"' "$P/rulesets" > "$T/rt" || fail "no rapid-release-tags ruleset: $(cat "$P/rulesets")"
grep -q '"refs/tags/release/\*"' "$T/rt" && grep -q '"type": "creation"' "$T/rt" && grep -q '"actor_type": "RepositoryRole"' "$T/rt" \
  || fail "rapid-release-tags does not keep release/* tag creation to the admins: $(cat "$T/rt")"
history_clean
