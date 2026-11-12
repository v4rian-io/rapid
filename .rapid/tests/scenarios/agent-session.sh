#!/usr/bin/env bash
# an agent session is an agent whatever identity it exports: with CLAUDECODE or a
# variable conf agent_env names set, a release is refused, even under the admin's identity, while
# commits and lands pass. rapid doctor names rapid setup --agent
# until the guard is installed for Claude Code.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
# Agent One (agent1@team.test) is the human who ran setup, so the first admin
rapid branch refactor marker -r "A MY_AGENT variable marks an agent session too." >/dev/null
printf 'agent_env=MY_AGENT\n' >> .rapid/conf; git add .rapid/conf
git commit -q -m "[MODE] Mark MY_AGENT sessions as agents" || fail "the admin could not flip policy"
rapid land >/dev/null || fail "land the agent_env flip"
# ordinary work passes in an agent session
rapid branch feature probe >/dev/null
printf 'a\n' > a.txt; git add a.txt
CLAUDECODE=1 git commit -q -m "[NEW] Add the probe file to the project" || fail "an agent session could not commit ordinary work"
CLAUDECODE=1 rapid land >/dev/null || fail "an agent session could not land ordinary work"
# release: refused in an agent session even under the admin's identity; the admin outside one may
CLAUDECODE=1 refused rapid release
grep -q 'agent session (CLAUDECODE is set)' "$T/err" || fail "an agent session released as the admin: $(cat "$T/err")"
MY_AGENT=1 refused rapid release
grep -q 'agent session (MY_AGENT is set)' "$T/err" || fail "an agent_env session released as the admin: $(cat "$T/err")"
CLAUDECODE=1 rapid release --dry-run > "$T/dry" 2>&1 || true
grep -q 'would be refused: .*agent session' "$T/dry" || fail "the dry run hid the agent session refusal: $(cat "$T/dry")"
out=$(rapid release --dry-run 2>&1); grep -q 'would release' <<<"$out" || fail "the admin outside an agent session may not release"
[ "$(git rev-parse main)" != "$(git rev-parse dev)" ] || fail "main moved"
# doctor: an agent session without the guard is named, and the fix with it
export CLAUDE_CONFIG_DIR="$T/home/.claude"; mkdir -p "$CLAUDE_CONFIG_DIR"
CLAUDECODE=1 rapid doctor > "$T/doc" 2>&1 || true
grep -q 'agent guard is not installed; run rapid setup --agent' "$T/doc" || fail "doctor did not name the missing guard: $(cat "$T/doc")"
rapid setup --agent claude --prefix "$T/home" >/dev/null 2>&1 || fail "install the guard"
CLAUDECODE=1 rapid doctor > "$T/doc" 2>&1 || true
grep -q 'agent guard is not installed' "$T/doc" && fail "doctor warned with the guard installed: $(cat "$T/doc")"
rapid doctor > "$T/doc" 2>&1 || true
grep -q 'agent guard' "$T/doc" && fail "doctor warned outside an agent session: $(cat "$T/doc")"
history_clean
