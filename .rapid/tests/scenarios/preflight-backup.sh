#!/usr/bin/env bash
# the agent tool git-preflight.sh: one run writes a backup ref of the whole work tree (untracked
# files in, secrets and dependency trees out) and a zip, with the branch and the index untouched;
# a second run on the same tree reuses them; RAPID_GIT_BAKS_DIR is the fallback of RAPID_BAKS_DIR,
# RAPID_BAKS_MIRROR takes a copy of every zip, PREFLIGHT_KEEP bounds the zips kept and the
# older ones go to RAPID_TRASH_DIR, never deleted. With a remote the backup still stays in this clone:
# nothing is pushed, and the agent guard takes the local ref.
. "$(dirname "$0")/../lib.sh"
# the tools of rapid live in the installed clone, never in the repository
command -v zip >/dev/null && command -v unzip >/dev/null || fail "zip and unzip are required by git-preflight.sh"
mkrepo "$T/r"; cd "$T/r"
PF="$TOOL/agent/git-preflight.sh"
unset RAPID_BAKS_DIR
export RAPID_GIT_BAKS_DIR="$T/gb" RAPID_BAKS_MIRROR="$T/mirror" RAPID_TRASH_DIR="$T/trash" PREFLIGHT_KEEP=1
mkdir -p "$T/mirror" keys web/node_modules/a
printf 'kept\n' > notes.txt; printf 'SECRET=1\n' > .env; printf 'key\n' > keys/k.pem; printf 'x\n' > web/node_modules/a/index.js
head0=$(git rev-parse HEAD); br0=$(git symbolic-ref --short HEAD); st0=$(git status --porcelain | cksum)
"$PF" "$T/r" "before the test" > "$T/out" 2>&1 || fail "preflight: $(cat "$T/out")"
day=$(date +%Y-%m-%d); ref="refs/heads/preflight-bak-$day/01"
grep -qE "^preflight: preflight-bak-$day/01 \([0-9a-f]{40}, local-only\); zip $T/gb/r-bak-[0-9TZ]+\.zip " "$T/out" || fail "the report is not the ref and the zip: $(cat "$T/out")"
git rev-parse -q --verify "$ref" >/dev/null || fail "no backup ref"
[ "$(git rev-parse "$ref^")" = "$head0" ] || fail "the backup ref does not sit on HEAD"
grep -qx 'preflight backup before before the test' <<<"$(git log -1 --format=%B "$ref")" || fail "the backup does not carry its reason: $(git log -1 --format=%B "$ref")"
tree=$(git ls-tree -r --name-only "$ref")
grep -qx 'notes.txt' <<<"$tree" || fail "an untracked file is not in the backup ref"
! grep -qE '^\.env$|^keys/|node_modules/' <<<"$tree" || fail "a secret or a dependency tree is in the backup ref: $tree"
z=$(ls "$T/gb"/r-bak-*.zip); [ "$(wc -l <<<"$z" | tr -d ' ')" = 1 ] || fail "want one zip in the fallback dir: $z"
zl=$(unzip -Z1 "$z")
grep -qx 'r/notes.txt' <<<"$zl" || fail "the zip lacks the untracked file"
! grep -qE '^r/\.env$|^r/keys/|node_modules/|^r/\.git/' <<<"$zl" || fail "the zip holds a secret, a dependency tree or the git dir"
cmp -s "$z" "$T/mirror/$(basename "$z")" || fail "the mirror did not take a copy of the zip"
[ "$(git rev-parse HEAD)" = "$head0" ] && [ "$(git symbolic-ref --short HEAD)" = "$br0" ] && [ "$(git status --porcelain | cksum)" = "$st0" ] \
  || fail "the preflight touched the branch or the index"
# the same HEAD and work tree: reused, nothing new written
"$PF" "$T/r" > "$T/out" 2>&1 || fail "second preflight: $(cat "$T/out")"
grep -qE "^preflight: reused preflight-bak-$day/01 \(" "$T/out" || fail "an unchanged tree was not reused: $(cat "$T/out")"
[ -z "$(git for-each-ref "refs/heads/preflight-bak-$day/02")" ] || fail "a reuse wrote a second ref"
[ "$(ls "$T/gb" | wc -l | tr -d ' ')" = 1 ] || fail "a reuse wrote a second zip"
# a changed tree: a new ref and zip; with PREFLIGHT_KEEP=1 the older zip goes to the trash dir
sleep 1; printf 'more\n' >> notes.txt
"$PF" "$T/r" "before the second test" > "$T/out" 2>&1 || fail "third preflight: $(cat "$T/out")"
grep -qE "^preflight: preflight-bak-$day/02 \(" "$T/out" || fail "a changed tree did not get the next ref: $(cat "$T/out")"
[ "$(ls "$T/gb" | wc -l | tr -d ' ')" = 1 ] || fail "PREFLIGHT_KEEP=1 kept $(ls "$T/gb" | wc -l | tr -d ' ') zips"
[ "$(ls "$T/mirror" | wc -l | tr -d ' ')" = 1 ] || fail "the mirror kept more than PREFLIGHT_KEEP zips"
[ -f "$T/trash/$(basename "$z")" ] || fail "the older zip was not moved to RAPID_TRASH_DIR: $(ls "$T/trash" 2>&1)"
git rev-parse -q --verify "$ref" >/dev/null || fail "the first backup ref was dropped"
# RAPID_BAKS_DIR wins over its fallback
sleep 1; printf 'again\n' >> notes.txt
RAPID_BAKS_DIR="$T/baks" "$PF" "$T/r" > "$T/out" 2>&1 || fail "fourth preflight: $(cat "$T/out")"
[ "$(ls "$T/baks"/r-bak-*.zip | wc -l | tr -d ' ')" = 1 ] || fail "RAPID_BAKS_DIR did not take the zip: $(cat "$T/out")"
[ "$(ls "$T/gb" | wc -l | tr -d ' ')" = 1 ] || fail "the fallback dir took a zip while RAPID_BAKS_DIR was set"
# a repository with a remote: the backup stays in this clone (only dev, main, pool, safety and vault
# branches go to a remote), and the agent guard takes the local ref as the preflight
command -v python3 >/dev/null || fail "python3 is required by the agent guard"
mkrepo "$T/o" origin; cd "$T/o"; printf 'w\n' > w.txt
export RAPID_BAKS_DIR="$T/ob" GUARD_TMP_ROOTS="$T/throwaway"; mkdir -p "$T/throwaway"
guard() { python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$T/o" | "$TOOL/agent/guard-destructive.sh"; }
out=$(guard "git reset --hard HEAD"); grep -q '"deny"' <<<"$out" || fail "a reset --hard without a preflight was allowed: $out"
"$TOOL/agent/git-preflight.sh" "$T/o" "before a reset" > "$T/out" 2>&1 || fail "preflight with a remote: $(cat "$T/out")"
grep -qE "^preflight: preflight-bak-$day/01 \([0-9a-f]{40}, local-only\); zip " "$T/out" || fail "the report with a remote: $(cat "$T/out")"
[ -n "$(git for-each-ref "refs/heads/preflight-bak-$day/01")" ] || fail "no local backup ref"
[ -z "$(git ls-remote origin 'refs/heads/preflight-bak-*')" ] || fail "the preflight pushed its backup branch to origin: $(git ls-remote origin 'refs/heads/preflight-bak-*')"
out=$(guard "git reset --hard HEAD"); [ -z "$out" ] || fail "the guard did not take the local preflight of a repository with a remote: $out"
