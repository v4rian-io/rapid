#!/usr/bin/env bash
# vault branches: rapid land writes the branch vault/v<series>/<name> on the branch's tip as it landed,
# in the land's atomic push, so every branch keeps a pointer to its start (safety/) and its end
# (vault/) after the branch itself is deleted; an offline land's vault ref is published by rapid
# sync --dev; pre-push refuses deleting or moving one and the agent guard denies it, preflight or not.
. "$(dirname "$0")/../lib.sh"
# the tools of rapid live in the installed clone, never in the repository
command -v python3 >/dev/null || fail "python3 is required by the agent guard"
mkrepo "$T/r" origin; cd "$T/r"
rapid branch feature kept >/dev/null; commit k.txt; L=$(lname kept); tip=$(git rev-parse HEAD)
rapid land >/dev/null || fail "land"
v="refs/heads/vault/${L#pool/}"
git rev-parse -q --verify "$v" >/dev/null || fail "land wrote no vault branch $v"
[ "$(git rev-parse "$v")" = "$tip" ] && [ "$(git rev-parse dev^2)" = "$tip" ] || fail "the vault ref is not the landed branch tip"
[ "$(git ls-remote origin "$v" | cut -f1)" = "$(git rev-parse "$v")" ] || fail "the vault ref did not reach origin with the land"
[ "$(git describe --exact-match "$(git rev-list --first-parent --ancestry-path "$v..dev" | tail -n 1)")" = "$(git describe --exact-match dev)" ] || fail "the vault tip's merge carries no version"
[ -z "$(rbranch origin kept)" ] || fail "land did not delete the branch"
[ -n "$(git ls-remote origin "refs/heads/safety/${L#pool/}")" ] || fail "the start pointer is gone"
# never deleted or moved
refused git push -q origin ":$v"
grep -q 'never deleted' "$T/err" || fail "a vault deletion passed: $(cat "$T/err")"
refused git push -q --force origin "dev:$v"
grep -q 'never moved' "$T/err" || fail "a vault move passed: $(cat "$T/err")"
# an offline land: rapid sync --dev publishes its vault ref
git config remote.origin.url "$T/offline.git"
rapid branch feature away >/dev/null 2>&1; commit a.txt; A=$(lname away); rapid land >/dev/null 2>&1 || fail "offline land"
git config remote.origin.url "$T/origin.git"; rapid sync --dev >/dev/null || fail "sync --dev"
[ -n "$(git ls-remote origin "refs/heads/vault/${A#pool/}")" ] || fail "sync --dev did not publish the offline vault ref"
# the agent guard
export GUARD_TMP_ROOTS="$T/throwaway" RAPID_BAKS_DIR="$T/baks"; mkdir -p "$T/throwaway"
guard() { python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$T/r" | "$TOOL/agent/guard-destructive.sh"; }
"$TOOL/agent/git-preflight.sh" "$T/r" "before probing the vault rules" >/dev/null || fail "preflight"
for c in "git update-ref -d $v" "git update-ref $v HEAD" "git push origin :$v" "git push origin --delete $v" "git push origin HEAD:$v"; do
  out=$(guard "$c"); grep -q 'Safety anchors stay forever' <<<"$out" || fail "the guard allowed '$c': $out"
done
history_clean
