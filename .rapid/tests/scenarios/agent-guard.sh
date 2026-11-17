#!/usr/bin/env bash
# agent guard: a destructive git command without a preflight is denied
# with the exact command to run; after the preflight it is allowed. A hand-written
# rapid-close note is denied. The tooling lives in the installed clone: in a repository an agent writes
# the project's data under .rapid (requirements, tests, version), conf and admins stay editable, a copy of
# the framework is never planted or edited there, and
# rapid setup --agent installs and removes the hooks without touching other ones. The guard names
# rapid's own tooling, never another framework's. git's hooks never move off the stubs rapid setup wrote and a version
# tag never moves. git send-pack is checked as a push, a chmod on a hook stub is denied, and
# so are the RAPID_BATCH_CLOSE_PUSH and RAPID_DEVEXEC prefixes.
. "$(dirname "$0")/../lib.sh"
command -v python3 >/dev/null || fail "python3 is required by the agent guard"
mkrepo "$T/r"; cd "$T/r"
A="$TOOL/agent"
# GUARD_TMP_ROOTS narrows the temp exemption, so this scratch repo counts as real
export GUARD_TMP_ROOTS="$T/throwaway" RAPID_BAKS_DIR="$T/baks" RAPID_TRASH_DIR="$T/trash"
mkdir -p "$T/throwaway"
rapid branch feature probe >/dev/null; commit a.txt; git switch -q dev; git branch scratch dev
# guard COMMAND [DIR], write PATH [DIR]: the two hooks, asked from DIR (default the installed repository)
guard() { python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "${2:-$T/r}" | "$A/guard-destructive.sh"; }
write() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "${2:-$T/r}" | "$A/guard-write.sh"; }
out=$(guard "git branch -D scratch")
grep -q '"deny"' <<<"$out" || fail "branch -D without a preflight was allowed: $out"
grep -q 'git-preflight.sh' <<<"$out" || fail "the deny does not name the preflight command: $out"
out=$(guard "git branch -D $(lname probe)"); grep -q 'Developers never delete branches' <<<"$out" || fail "a branch deletion was not denied by the branch rule: $out"
out=$(guard "git push origin dev:main"); grep -q '"deny"' <<<"$out" || fail "a push to main was allowed"
out=$(guard "git log --oneline -1"); [ -z "$out" ] || fail "a read-only command was denied: $out"
out=$(guard "git notes --ref=rapid-close add -f -m fast=pass HEAD"); grep -q '"deny"' <<<"$out" || fail "a hand-written close note was allowed: $out"
out=$(guard "git update-ref refs/notes/rapid-close HEAD"); grep -q '"deny"' <<<"$out" || fail "a hand-set test ref was allowed: $out"
out=$(guard "git notes --ref=rapid-close show HEAD"); [ -z "$out" ] || fail "reading the close note was denied: $out"
# git's hooks stay at the stubs rapid setup wrote, and a version tag never moves
stubs=$(git config --get core.hooksPath); [ -f "$stubs/pre-push" ] || fail "rapid setup wrote no hook stub at core.hooksPath ($stubs)"
# the hooks path rule takes the stubs rapid setup wrote, never a hooks directory of a framework the repository does not hold
hp() { PYTHONDONTWRITEBYTECODE=1 python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import guard_destructive as g; sys.exit(0 if g._hookspath_ok(sys.argv[2], sys.argv[3]) else 1)' "$A" "$1" "$2"; }
hp "$stubs" "$T/r" || fail "the hooks path rule refuses the stubs rapid setup wrote ($stubs)"
! hp .rapid/hooks "$T/r" || fail "the hooks path rule takes .rapid/hooks in a repository that holds no rapid"
for c in "git config core.hooksPath .rapid/hooks" "git config core.hooksPath /dev/null" "git config --unset core.hooksPath" "git config --file .git/config core.hooksPath x" \
    "git -c core.hooksPath=/dev/null commit -m x" "git config set core.hooksPath elsewhere" "git tag -f v2026.0.1" \
    "git tag --force v2026.0.1 HEAD" "git update-ref refs/tags/v2026.0.1 HEAD"; do
  out=$(guard "$c"); grep -q '"deny"' <<<"$out" || fail "the guard allowed: $c"
done
# push by another name, a hook made unrunnable, and rapid's own two switches set by hand
for c in "git send-pack ../o.git dev:main" "chmod -x $stubs/pre-push" \
    "RAPID_BATCH_CLOSE_PUSH=1 git push origin dev" "RAPID_DEVEXEC=x git push origin dev"; do
  out=$(guard "$c"); grep -q '"deny"' <<<"$out" || fail "the guard allowed: $c"
done
out=$(guard "git send-pack ../o.git dev:main"); grep -q 'Push to main blocked' <<<"$out" || fail "send-pack to main was not denied as a push to main: $out"
out=$(guard "RAPID_DEVEXEC=x git push origin dev"); grep -q 'RAPID_DEVEXEC blocked' <<<"$out" || fail "the RAPID_DEVEXEC prefix was not denied by name: $out"
for c in "git config --get core.hooksPath" "git tag -l v2026.*" "chmod +x check.sh" "git push origin dev"; do
  out=$(guard "$c"); [ -z "$out" ] || fail "the guard denied: $c: $out"
done
"$A/git-preflight.sh" "$T/r" "before deleting the scratch branch" >/dev/null || fail "preflight failed"
out=$(guard "git branch -D scratch"); [ -z "$out" ] || fail "branch -D after a fresh preflight was denied: $out"
ls "$T/baks"/*.zip >/dev/null 2>&1 || fail "the preflight left no zip"
[ -n "$(git for-each-ref --format=x 'refs/heads/preflight-bak-*/*')" ] || fail "the preflight left no backup ref"
# the project's data under .rapid is the project's to write; the tooling is never planted in the repository
for f in .rapid/requirements/probe.md .rapid/version .rapid/tests/probe.sh .rapid/conf .rapid/admins; do
  out=$(write "$T/r/$f"); [ -z "$out" ] || fail "an edit to $f was denied: $out"
done
out=$(write "$T/r/.rapid/rapid"); grep -q '"deny"' <<<"$out" || fail "a copy of rapid could be planted in the repository"
[ -x "$stubs/pre-push" ] || fail "the stub lost its mode"
# a copy of the framework standing in another repository is never edited, its hooks keep their mode
mkdir -p "$T/s"; git -C "$T/s" init -q; cp -R "$RAPID_SRC" "$T/s/.rapid"
[ -f "$T/s/.rapid/rapid" ] && [ -f "$T/s/.rapid/hooks/pre-push" ] || fail "the copy of the framework is not there"
out=$(write "$T/s/.rapid/rapid" "$T/s"); grep -q '"deny"' <<<"$out" || fail "an edit to a copy of the framework was allowed"
for c in "chmod -x .rapid/hooks/pre-push" "git update-index --chmod=-x .rapid/hooks/pre-push"; do
  out=$(guard "$c" "$T/s"); grep -q '"deny"' <<<"$out" || fail "the guard allowed in a copy of the framework: $c"
done
hp .rapid/hooks "$T/s" || fail "the hooks path rule refuses .rapid/hooks where the repository holds rapid itself"
# install and uninstall into a fake home; the user's own hook stays
H="$T/home"; mkdir -p "$H/.claude"
printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"mine.sh"}]}]}}\n' > "$H/.claude/settings.json"
cp "$H/.claude/settings.json" "$T/orig.json"
rapid setup --agent claude --prefix "$H" >/dev/null || fail "setup --agent claude failed"
python3 - "$H/.claude/settings.json" "$H/.claude/hooks/rapid" <<'PY' || fail "the guard is not wired into settings.json"
import json, sys
d = json.load(open(sys.argv[1])); cmds = [h["command"] for g in d["hooks"]["PreToolUse"] for h in g["hooks"]]
assert "mine.sh" in cmds, cmds
assert any(c.startswith(sys.argv[2] + "/guard-destructive.sh") for c in cmds), cmds
assert all(h.get("onFailure") == "block" for g in d["hooks"]["PreToolUse"] for h in g["hooks"] if h["command"] != "mine.sh"), d
PY
rapid setup --agent claude --prefix "$H" --uninstall >/dev/null || fail "uninstall failed"
cmp -s "$H/.claude/settings.json" "$T/orig.json" || fail "uninstall did not restore settings.json"
[ ! -e "$H/.claude/hooks/rapid" ] || fail "uninstall left the hook dir"
grep -q 'not a security boundary' "$A/guard_destructive.py" || fail "the guard does not state its scope"
# the guard speaks rapid: no tooling outside rapid is named in its rules or denials
if grep -nE 'claim-dev-merge|claim flow|claim tags|close-up|pool branch|connected mode|githooks/' "$A/guard_destructive.py" > "$T/stale"; then
  fail "the guard names tooling outside rapid: $(cat "$T/stale")"
fi
history_clean
