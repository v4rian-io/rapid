#!/usr/bin/env bash
# rapid setup --remote --dry-run says what it would do on the forge and does none of it: one line
# per ruleset (create, or update with the id the forge already holds), one for the workflow, no
# write call to gh and no file written. A repository it cannot name is refused with exit 2. The real run
# writes the workflow template byte for byte: each job takes rapid from the base, or installs the pinned release.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
B="$T/bin"; mkdir -p "$B"
# a gh that records every call and already holds the ruleset rapid-main under id 7
cat > "$B/gh" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >> "$T/gh.log"
case "\$*" in
  "api -X "*) exit 0 ;;
  api*'"rapid-main"'*) echo 7 ;;
esac
exit 0
STUB
chmod +x "$B/gh"
n=$(ls "$RAPID_SRC"/remote/*.json | wc -l | tr -d ' ')
[ "$n" -ge 1 ] || fail "the framework ships no ruleset"
PATH="$B:$PATH" rapid setup --remote --repo acme/app --dry-run > "$T/out" 2>"$T/err" || fail "setup --remote --dry-run: $(cat "$T/err")"
[ "$(grep -c '^dry run: would ' "$T/out")" = $((n + 1)) ] || fail "want $n ruleset lines and the workflow line: $(cat "$T/out")"
grep -qFx 'dry run: would update ruleset 7 rapid-main on acme/app' "$T/out" || fail "the ruleset the forge holds is not an update: $(cat "$T/out")"
grep -qFx 'dry run: would create ruleset rapid-branch-deletions on acme/app' "$T/out" || fail "a new ruleset is not a create: $(cat "$T/out")"
grep -qFx 'dry run: would create ruleset rapid-safety-lockdown on acme/app' "$T/out" || fail "safety-lockdown is not named: $(cat "$T/out")"
grep -qFx 'dry run: would write .github/workflows/rapid-check.yml' "$T/out" || fail "the workflow line is missing: $(cat "$T/out")"
! grep -q '^api -X ' "$T/gh.log" || fail "a dry run wrote to the forge: $(grep '^api -X ' "$T/gh.log")"
[ ! -e .github ] || fail "a dry run wrote the workflow"
[ -z "$(git status --porcelain)" ] || fail "a dry run changed the work tree: $(git status --porcelain)"
# the real run then writes: the held ruleset by PUT, the others by POST, and the workflow file
: > "$T/gh.log"
PATH="$B:$PATH" rapid setup --remote --repo acme/app > "$T/out" 2>"$T/err" || fail "setup --remote: $(cat "$T/err")"
[ "$(grep -c '^api -X PUT repos/acme/app/rulesets/7 ' "$T/gh.log")" = 1 ] || fail "the held ruleset was not updated: $(cat "$T/gh.log")"
[ "$(grep -c '^api -X POST repos/acme/app/rulesets ' "$T/gh.log")" = $((n - 1)) ] || fail "the other rulesets were not created: $(cat "$T/gh.log")"
grep -qFx 'updated ruleset rapid-main (7) on acme/app' "$T/out" || fail "the update is not reported: $(cat "$T/out")"
cmp -s "$RAPID_SRC/remote/check.yml" .github/workflows/rapid-check.yml || fail "the workflow was not written"
# the workflow written is the template byte for byte, and each of its three jobs carries both ways to get
# rapid: the .rapid the base holds, or the documented installer for a repository that pins a release
[ "$(grep -c 'git archive --format=tar' .github/workflows/rapid-check.yml)" = 3 ] || fail "a job lost the checker taken from the base"
[ "$(grep -cF 'curl -fsSL "https://raw.githubusercontent.com/v4rian-io/rapid/refs/tags/$pin/.rapid/install.sh" | bash' .github/workflows/rapid-check.yml)" = 3 ] || fail "a job lacks the documented installer"
[ "$(grep -cF 'RAPID_HOME="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/rapid"' .github/workflows/rapid-check.yml)" = 3 ] || fail "a job installs rapid outside the runner's temp directory"
[ "$(grep -c 'persist-credentials: false' .github/workflows/rapid-check.yml)" = 3 ] || fail "a job persists its credentials"
[ "$(grep -cF 'printf '"'"'%s\n'"'"' "$pin" > .rapid/version' .github/workflows/rapid-check.yml)" = 3 ] || fail "a job does not run the checker at the pin of the base"
PATH="$B:$PATH" rapid setup --remote --repo acme/app --dry-run > "$T/out" 2>&1 || fail "the second dry run"
grep -qFx '.github/workflows/rapid-check.yml is current' "$T/out" || fail "a current workflow is not said to be current: $(cat "$T/out")"
# a repository it cannot name: exit 2, nothing asked of the forge
: > "$T/gh.log"
rc=0; PATH="$B:$PATH" rapid setup --remote --dry-run >"$T/out" 2>"$T/err" || rc=$?
[ "$rc" = 2 ] && grep -qF 'no origin; pass --repo OWNER/REPO' "$T/err" || fail "no origin and no --repo: rc $rc $(cat "$T/err")"
rc=0; PATH="$B:$PATH" rapid setup --remote --repo nowhere --dry-run >"$T/out" 2>"$T/err" || rc=$?
[ "$rc" = 2 ] && grep -qF "cannot tell OWNER/REPO from 'nowhere'" "$T/err" || fail "a repo that is no OWNER/REPO: rc $rc $(cat "$T/err")"
[ ! -s "$T/gh.log" ] || fail "a refused setup --remote called gh: $(cat "$T/gh.log")"
# a credential in origin's URL is never printed by the refusal
git remote add origin "https://someone:sekret-token@forge.test/a/b/c"
rc=0; PATH="$B:$PATH" rapid setup --remote --dry-run >"$T/out" 2>"$T/err" || rc=$?
[ "$rc" = 2 ] && grep -qF "cannot tell OWNER/REPO from 'https://forge.test/a/b/c'" "$T/err" || fail "an origin that is no OWNER/REPO: rc $rc $(cat "$T/err")"
! grep -q 'sekret-token' "$T/out" "$T/err" || fail "the refusal printed the credential of origin's URL: $(cat "$T/err")"
