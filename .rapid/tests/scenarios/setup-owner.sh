#!/usr/bin/env bash
# rapid setup --owner: the one who initializes a repository is often not its owner, and an agent never
# is. An agent session runs rapid setup --owner EMAIL --owner-name NAME: .rapid/admins (the working copy's own
# file, excluded from history) names that person, never the runner, as the first admin, the name beside the address. The owner
# then flips policy and releases; the runner, who is no admin, does neither. A word that is no email, a missing address and a
# working copy whose admins file already names one are refused; in a seeded clone that names nobody, setup --owner names the owner.
. "$(dirname "$0")/../lib.sh"
actor "Agent One" agent1@team.test
mkdir -p "$T/n/.rapid"; git -C "$T/n" init -q
printf 'land_who=anyone\nmax_commits=20\ntest_paths=*\ncommit_body=optional\nrequirement_test=optional\ngates_fast=none\ngates_full=none\ngates_release=none\n' > "$T/n/.rapid/conf"
cd "$T/n"; git remote add origin "$(mkremote origin)"
CLAUDECODE=1 refused rapid setup --owner
grep -q -- '--owner needs an email' "$T/err" || fail "a missing address passed: $(cat "$T/err")"
CLAUDECODE=1 refused rapid setup --owner nobody
grep -q "is not an email" "$T/err" || fail "a word that is no email was named owner: $(cat "$T/err")"
git rev-parse -q --verify HEAD >/dev/null && fail "a refused setup --owner seeded the repository"
[ ! -e .rapid/admins ] || fail "a refused setup --owner wrote .rapid/admins"
CLAUDECODE=1 refused rapid setup --owner-name "Owner One"
grep -q -- '--owner-name needs --owner EMAIL' "$T/err" || fail "a name without an owner passed: $(cat "$T/err")"
CLAUDECODE=1 refused rapid setup --owner owner@team.test --owner-name
grep -q -- '--owner-name needs a name' "$T/err" || fail "a missing name passed: $(cat "$T/err")"
CLAUDECODE=1 rapid setup --owner owner@team.test --owner-name "Owner One" > "$T/out" 2>&1 || fail "setup --owner in an agent session: $(cat "$T/out")"
[ "$(grep -v '^#' .rapid/admins)" = 'owner@team.test # Owner One' ] || fail "the owner's row does not carry the name: $(cat .rapid/admins 2>&1)"
[ "$(grep -v '^#' .rapid/admins | awk '{ print $1 }')" = owner@team.test ] || fail "setup does not name the owner alone as the first admin: $(cat .rapid/admins 2>&1)"
! git cat-file -e main:.rapid/admins 2>/dev/null || fail "the root commit holds .rapid/admins"
grep -Fx .rapid/admins "$(git rev-parse --git-common-dir)/info/exclude" >/dev/null || fail "setup did not exclude .rapid/admins: $(cat "$(git rev-parse --git-common-dir)/info/exclude" 2>&1)"
CLAUDECODE=1 refused rapid setup --owner other@team.test
grep -q 'setup --owner: .rapid/admins already names an admin' "$T/err" || fail "a working copy that names an admin took a second owner: $(cat "$T/err")"
# a seeded repository whose working copy names nobody: setup --owner names the owner there
git clone -q -b dev "$T/origin.git" "$T/c"
( cd "$T/c" && CLAUDECODE=1 rapid setup --owner owner@team.test ) > "$T/out" 2>&1 || fail "setup --owner in a seeded clone: $(cat "$T/out")"
[ "$(grep -v '^#' "$T/c/.rapid/admins")" = owner@team.test ] || fail "setup --owner in a seeded clone named no owner: $(cat "$T/c/.rapid/admins" 2>&1)"
# the runner works, and neither flips policy nor releases
CLAUDECODE=1 rapid branch feature export >/dev/null; CLAUDECODE=1 commit export.txt; CLAUDECODE=1 rapid land >/dev/null || fail "land a branch as the agent"
main0=$(git rev-parse main)
CLAUDECODE=1 refused rapid release
grep -q 'promotes dev to main' "$T/err" || fail "the agent released: $(cat "$T/err")"
[ "$(git rev-parse main)" = "$main0" ] && [ -z "$(git tag -l 'release/*')" ] || fail "a refused release moved main or tagged"
CLAUDECODE=1 rapid branch refactor cap -r "The branch size cap rises to forty commits." >/dev/null
sed -i.bak 's/^max_commits=.*/max_commits=40/' .rapid/conf && rm -f .rapid/conf.bak; git add .rapid/conf
CLAUDECODE=1 refused git commit -q -m "[MODE] Raise the branch size cap to forty"
grep -q "'agent1@team.test' is not an admin" "$T/err" || fail "the runner, who is no admin, flipped policy: $(cat "$T/err")"
# the owner does both
actor "Owner One" owner@team.test
git commit -q -m "[MODE] Raise the branch size cap to forty" || fail "the named owner could not flip policy"
rapid land >/dev/null || fail "the named owner's flip did not land"
[ "$(git show dev:.rapid/conf | sed -n 's/^max_commits=//p')" = 40 ] || fail "the flip is not on dev"
v=$(git describe --exact-match dev)
rapid release > "$T/out" 2>&1 || fail "the named owner's release: $(cat "$T/out")"
git cat-file -p "release/$v" | grep -Fx "Released-By: owner@team.test" >/dev/null || fail "the release tag names no releaser: $(git cat-file -p "release/$v")"
[ "$(git rev-parse main^2)" = "$(git rev-parse dev)" ] || fail "main did not take the release merge of dev"
history_clean
