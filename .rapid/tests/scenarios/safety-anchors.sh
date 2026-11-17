#!/usr/bin/env bash
# safety anchors stay forever: rapid branch writes the branch safety/v<series>/<number>.<kind>.<name>, an anchor commit
# on the fork point; a sync and a rename never move it (a rename adds the new
# name's anchor); a branch push carries it and a coworker sharing the branch takes origin's, a land pushes it with its atomic push, an
# offline land publishes it with rapid sync --dev; pre-push refuses deleting, moving or forging one,
# and the agent guard denies it even after a preflight.
. "$(dirname "$0")/../lib.sh"
command -v python3 >/dev/null || fail "python3 is required by the agent guard"
mkrepo "$T/r" origin; cd "$T/r"
fork=$(git rev-parse dev)
rapid branch feature probe >/dev/null
P=$(lname probe); a="refs/heads/safety/${P#pool/}"
[ "$(git rev-parse -q --verify "$a^1" || true)" = "$fork" ] || fail "rapid branch wrote no anchor at the fork point"
[ "$(git rev-list --parents -n1 "$a" | wc -w | tr -d ' ')" = 2 ] && [[ "$(git log -1 --format=%s "$a")" == "rapid branch v2026.0/"*".feature.probe: fork point $fork" ]] \
  || fail "the anchor is not the anchor commit on the fork point"
commit p.txt
# dev moves; the branch syncs onto it; the anchor stays at the fork point
git switch -q dev; rapid branch fix other >/dev/null; commit o.txt; rapid land >/dev/null || fail "land other"
git switch -q "$P"; rapid sync >/dev/null || fail "sync probe"
[ "$(git rev-parse "$a^1")" = "$fork" ] || fail "sync moved the anchor"
o=$(git for-each-ref --format="%(refname)" "refs/heads/safety/*/*.fix.*"); [ -n "$o" ] && [ "$(git ls-remote origin "$o" | cut -f1)" = "$(git rev-parse "$o")" ] \
  || fail "land did not push the landed branch's anchor"
# a plain push of the branch carries its anchor
git push -q origin "$P" || fail "branch push"
settle
[ "$(git ls-remote origin "$a" | cut -f1)" = "$(git rev-parse "$a")" ] || fail "the branch push did not carry its anchor"
# a coworker's clone that shares the branch takes origin's anchor, never a second one
git clone -q "$T/origin.git" "$T/c"
( cd "$T/c" && git switch -q dev && rapid setup >/dev/null && git switch -q "$P" \
  && commit c.txt && git push -q origin "$P" ) || fail "the coworker could not push the shared branch"
settle
[ "$(git -C "$T/c" rev-parse "$a")" = "$(git rev-parse "$a")" ] || fail "the coworker's clone wrote a second anchor"
git -c core.hooksPath=/dev/null pull -q --rebase origin "$P"
# deleting, moving or forging an anchor on the remote is refused
refused git push -q origin ":$a"
grep -q 'never deleted' "$T/err" || fail "an anchor deletion was not refused: $(cat "$T/err")"
refused git push -q --force origin "dev:$a"
grep -q 'never moved' "$T/err" || fail "an anchor move was not refused: $(cat "$T/err")"
refused git push -q origin "dev:refs/heads/safety/v2026.0/feature.forged"
grep -q 'anchor commit rapid branch writes' "$T/err" || fail "a forged anchor was not refused: $(cat "$T/err")"
[ "$(git ls-remote origin "$a" | cut -f1)" = "$(git rev-parse "$a")" ] || fail "the remote anchor changed"
# a rename adds the new name's anchor at the same fork point; the old one stays
rapid branch --rename probe-two >/dev/null || fail "rename"
[ "$(git rev-parse "refs/heads/safety/${P#pool/}"-two^1)" = "$fork" ] || fail "rename wrote no anchor at the fork point"
git rev-parse -q --verify "$a" >/dev/null || fail "rename deleted the old anchor"
# a branch landed offline: rapid sync --dev publishes its anchor
git switch -q dev; git config remote.origin.url "$T/offline.git"
rapid branch feature offline >/dev/null 2>&1; commit off.txt; rapid land >/dev/null 2>&1 || fail "offline land"
git config remote.origin.url "$T/origin.git"; rapid sync --dev >/dev/null || fail "sync --dev"
o=$(git for-each-ref --format="%(refname)" "refs/heads/safety/*/*.offline"); [ -n "$o" ] && [ -n "$(git ls-remote origin "$o")" ] || fail "sync --dev did not publish the offline branch's anchor"
# the agent guard: no deletion, move or hand-write, even after a fresh preflight
export GUARD_TMP_ROOTS="$T/throwaway" RAPID_BAKS_DIR="$T/baks"; mkdir -p "$T/throwaway"
guard() { python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$T/r" | "$TOOL/agent/guard-destructive.sh"; }
"$TOOL/agent/git-preflight.sh" "$T/r" "before probing the anchor rules" >/dev/null || fail "preflight"
for c in "git update-ref -d $a" "git update-ref $a HEAD" "git push origin :$a" "git push origin --delete $a" \
         "git push --force-with-lease origin HEAD:$a" "git push origin HEAD:refs/heads/safety/v2026.0/feature.x" "git branch -D ${a#refs/heads/}" "git branch -f ${a#refs/heads/} HEAD"; do
  out=$(guard "$c"); grep -q 'Safety anchors stay forever' <<<"$out" || fail "the guard allowed '$c': $out"
done
out=$(guard "git push origin $a"); [ -z "$out" ] || fail "pushing an anchor as it is was denied: $out"
history_clean
