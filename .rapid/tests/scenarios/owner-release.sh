#!/usr/bin/env bash
# main is production: only the owner, an admin listed in .rapid/admins, promotes dev to main. rapid
# release refuses a human who is no admin, before its gate; a
# dry run reports the refusal as its last line, never "would release", and changes nothing; the
# agent guard denies an agent's rapid release in every spelling and allows --dry-run; a branch on dev
# granting itself release_list cannot release, since main's own policy rules; a hand-made release
# by anyone else is refused by pre-push (and a lightweight one too) and flagged I5 by doctor; the
# owner releases, and the tag says Released-By.
. "$(dirname "$0")/../lib.sh"
# the tools of rapid live in the installed clone, never in the repository
command -v python3 >/dev/null || fail "python3 is required by the agent guard"
actor "Owner One" owner@team.test
mkrepo "$T/r" origin; cd "$T/r"
! git cat-file -e main:.rapid/admins 2>/dev/null || fail "the root commit holds .rapid/admins"
[ "$(grep -v '^#' .rapid/admins)" = 'owner@team.test # Owner One' ] || fail "setup names no owner in the working copy: $(cat .rapid/admins 2>&1)"
actor "Human Two" human@team.test
rapid branch feature export >/dev/null; commit export.txt; rapid land >/dev/null || fail "land as the human"
main0=$(git rev-parse main); v=$(git describe --exact-match dev)
refused rapid release
grep -q 'main is production; only owner@team.test promotes dev to main' "$T/err" || fail "a human who is no admin was not refused: $(cat "$T/err")"
rapid release --dry-run > "$T/dry" 2>&1 || fail "a dry run by one who may not release was refused: $(cat "$T/dry")"
grep -q 'the release itself would be refused' "$T/dry" || fail "the dry run hid the refusal: $(cat "$T/dry")"
# the refusal is the dry run's last word: no line says it would release
grep -q 'the release itself would be refused' <<<"$(tail -n 1 "$T/dry")" || fail "the dry run does not end with the refusal: $(cat "$T/dry")"
if grep -q 'would release' "$T/dry"; then fail "a refused dry run says it would release: $(cat "$T/dry")"; fi
[ "$(git rev-parse main)" = "$main0" ] && [ -z "$(git tag -l 'release/*')" ] || fail "a refused release moved main or tagged"
[ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$main0" ] || fail "origin main moved"
# the agent guard: an agent never runs rapid release, however it is spelled; --dry-run stays allowed
export GUARD_TMP_ROOTS="$T/throwaway" RAPID_BAKS_DIR="$T/baks"; mkdir -p "$T/throwaway"
guard() { python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$T/r" | "$TOOL/agent/guard-destructive.sh"; }
for c in "rapid release" ".rapid/rapid release $v" "$T/r/.rapid/rapid release" "bash .rapid/rapid release" "sh -c '.rapid/rapid release'" "cd $T/r && .rapid/rapid release"; do
  out=$(guard "$c"); grep -q '"deny"' <<<"$out" || fail "the guard allowed '$c': $out"
  grep -q "owner's decision" <<<"$out" || fail "the deny for '$c' does not say why: $out"
done
for c in "rapid release --dry-run" ".rapid/rapid release --dry-run" ".rapid/rapid status"; do
  out=$(guard "$c"); [ -z "$out" ] || fail "the guard denied '$c': $out"
done
# a branch on dev cannot grant itself the right: main's policy decides (the flip is the admin's, on dev)
actor "Owner One" owner@team.test
rapid branch refactor release-list -r "Let the human release through release_list." >/dev/null
printf 'release_who=list\nrelease_list=human@team.test\n' >> .rapid/conf; git add .rapid/conf
git commit -q -m "[MODE] Let the human release from dev"
rapid land >/dev/null || fail "land the release_list change"
actor "Human Two" human@team.test
v=$(git describe --exact-match dev)
refused rapid release
grep -q 'only owner@team.test promotes' "$T/err" || fail "a release_list landed on dev granted the right: $(cat "$T/err")"
# a hand-made release by the human, pushed past rapid release: pre-push refuses it
git tag -a "release/$v" -m "hand release" dev
hm=$(git commit-tree "$(git rev-parse dev^{tree})" -p main -p dev -m "[MERGE] dev into main: $v")
refused git push --atomic origin "$hm:refs/heads/main" "refs/tags/release/$v"
grep -q "release/$v was tagged by 'human@team.test'" "$T/err" || fail "pre-push let a foreign release reach main: $(cat "$T/err")"
[ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$main0" ] || fail "origin main moved"
git tag -d "release/$v" >/dev/null; git tag "release/$v" dev
refused git push --atomic origin "$hm:refs/heads/main" "refs/tags/release/$v"
grep -q 'annotated' "$T/err" || fail "pre-push let a lightweight release tag through: $(cat "$T/err")"
git tag -d "release/$v" >/dev/null
# made locally past every hook: doctor names it
git tag -a "release/$v" -m "hand release" dev; git update-ref refs/heads/main "$(git rev-parse dev)"
rapid doctor --history-only > "$T/doc" 2>&1 && fail "doctor missed the foreign release"
grep -q "^doctor: I5 .* release/$v tagged by 'human@team.test'" "$T/doc" || fail "no I5 for the foreign release: $(cat "$T/doc")"
git update-ref refs/heads/main "$main0"; git tag -d "release/$v" >/dev/null
# the owner releases
actor "Owner One" owner@team.test
rapid release > "$T/out" 2>&1 || fail "the owner's release: $(cat "$T/out")"
git cat-file -p "release/$v" | grep -Fx 'Released-By: owner@team.test' >/dev/null || fail "the release tag names no releaser: $(git cat-file -p "release/$v")"
[ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$(git rev-parse main)" ] && [ "$(git rev-parse main^2)" = "$(git rev-parse dev)" ] \
  || fail "origin main is not the release merge of dev"
history_clean
# a checkout that names no admin (a CI runner) leaves the owner of a release to the forge: its history check passes
git clone -q -b dev "$T/origin.git" "$T/ci"; cd "$T/ci"; git branch -q main origin/main; git fetch -q origin "+refs/notes/*:refs/notes/*"
rapid doctor --history-only > "$T/ci.out" 2>&1 || fail "a checkout with no admin failed doctor on a valid release: $(cat "$T/ci.out")"
