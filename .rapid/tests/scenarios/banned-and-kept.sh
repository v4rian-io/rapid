#!/usr/bin/env bash
# banned files and kept branches, for humans too: pre-commit refuses a staged secret, key,
# certificate, build output, node_modules, .env, archive or backup on any branch (an .env.example
# passes, deleting a banned file passes); land and a branch push refuse one committed past the hook.
# Developers never delete branches: pre-push refuses deleting a branch on the remote by hand while
# land's deletion passes, and the agent guard denies deleting or renaming dev, main or a branch,
# preflight or not.
. "$(dirname "$0")/../lib.sh"
# the tools of rapid live in the installed clone, never in the repository
command -v python3 >/dev/null || fail "python3 is required by the agent guard"
actor "Human Dev" human@team.test
mkrepo "$T/r" origin; cd "$T/r"
rapid branch feature files >/dev/null; commit ok.txt
for f in .env config/.env.production keys/deploy.txt certs/app.pem ios/dist.mobileprovision build/app.o \
         build-mac/x.o web/node_modules/a/index.js out.zip notes.bak .DS_Store .auth/sa.json api.p8; do
  mkdir -p "$(dirname "$f")"; printf 'x\n' > "$f"; git add -f -- "$f"
  refused git commit -q -m "[NEW] Add a file the list bans"
  grep -qF "banned file(s) staged: $f" "$T/err" || fail "pre-commit let $f through: $(cat "$T/err")"
  git restore --staged -- "$f"
done
mkdir -p cfg; printf 'KEY=\n' > cfg/.env.example; printf 'b\n' > build-history.md; git add cfg/.env.example build-history.md
git commit -q -m "[NEW] Add an env template near a build history note" || fail "a template or a look-alike name was refused"
# on dev or any branch too (the commit is refused before commit-msg's own refusal)
git switch -q -c scratch dev 2>/dev/null; printf 's\n' > s.pem; git add s.pem
refused git commit -q -m "[NEW] Add a key on a scratch branch"
grep -q 'banned file' "$T/err" || fail "pre-commit skipped a non-branch: $(cat "$T/err")"
git restore --staged s.pem; git switch -q "$(lname files)"; git branch -q -D scratch
# committed past the hook: a branch push and land refuse it; deleting it is fine
printf 'secret\n' > .env; git add -f .env; git commit -q --no-verify -m "[NEW] Add an env file past the hook"
refused git push -q origin "$(lname files)"
grep -q 'adds banned file(s): .env' "$T/err" || fail "pre-push let a banned file through: $(cat "$T/err")"
refused rapid land
grep -q 'the branch adds banned file(s): .env' "$T/err" || fail "land let a banned file through: $(cat "$T/err")"
git rm -q --cached .env; git commit -q -m "[FIX] Remove the env file from the branch" -m "Cause: the env file was committed past the hook." -m "Fix: remove it from the branch." || fail "deleting a banned file was refused"
refused rapid land
grep -q 'banned' "$T/err" || fail "land took a branch whose history adds a banned file: $(cat "$T/err")"
git switch -q dev; git branch -q -D "$(lname files)"
# developers never delete a branch on the remote; land's and close's moves pass
rapid branch feature kept >/dev/null; commit k.txt; git push -q origin "$(lname kept)"
settle
r=$(rbranch origin kept)
refused git push -q origin ":$r"
grep -q 'never deleted by hand' "$T/err" || fail "a hand deletion of a branch passed: $(cat "$T/err")"
refused git push -q origin --delete "$r"
[ -n "$(rbranch origin kept)" ] || fail "the branch was deleted on origin"
rapid land >/dev/null || fail "land the kept branch"
[ -z "$(rbranch origin kept)" ] || fail "land did not delete the landed branch on origin"
# the agent guard: no deletion or rename of dev, main or a branch, preflight or not
export GUARD_TMP_ROOTS="$T/throwaway" RAPID_BAKS_DIR="$T/baks"; mkdir -p "$T/throwaway"
guard() { python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$T/r" | "$TOOL/agent/guard-destructive.sh"; }
rapid branch feature open >/dev/null; commit o.txt; L=$(lname open); git switch -q dev
"$TOOL/agent/git-preflight.sh" "$T/r" "before probing the branch rules" >/dev/null || fail "preflight"
for c in "git branch -D $L" "git branch -d $L" "git branch -m $L pool/v2026.0/feature.other" "git branch -D dev" \
         "git update-ref -d refs/heads/$L" "git push origin :$L" "git push origin --delete $L" \
         "git push origin :refs/heads/pool/v2026.0/feature.x" "git push origin --delete main"; do
  out=$(guard "$c"); grep -q 'Developers never delete branches' <<<"$out" || fail "the guard allowed '$c': $out"
done
git branch scratch dev
out=$(guard "git branch -D scratch"); [ -z "$out" ] || fail "deleting a scratch branch after a preflight was denied: $out"
history_clean
