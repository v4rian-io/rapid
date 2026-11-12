#!/usr/bin/env bash
# policy flips are the admins': rapid setup writes the setup author into .rapid/admins, the working
# copy's own file (excluded, never in the seed); a change to a policy file (.rapid/conf) must be its own
# [MODE] commit, touching only policy files, authored and committed by an admin listed in .rapid/admins. commit-msg, land and
# pre-push refuse a flip that is not [MODE], mixes other files, or comes from a non-admin;
# a [MODE] commit that flips nothing is refused; a flip forced onto dev
# past the hooks is flagged I4 by doctor, and one hidden in the tree of a hand-made merge over a clean
# branch commit is flagged I1 and refused at push (a merge adds nothing of its own). An admin's flip lands, and an admin can name another. A
# repository with no admins refuses a flip until rapid setup --owner EMAIL names the owner, whose flip lands; an admin
# may share the excluded list by committing it in a [MODE] commit.
. "$(dirname "$0")/../lib.sh"
actor "Owner One" owner@team.test
mkrepo "$T/r" origin; cd "$T/r"
! git cat-file -e main:.rapid/admins 2>/dev/null || fail "the root commit holds .rapid/admins"
[ "$(grep -v '^#' .rapid/admins)" = 'owner@team.test # Owner One' ] || fail "setup names no admin in the working copy: $(cat .rapid/admins 2>&1)"
rapid branch feature base >/dev/null; commit base.txt; rapid land >/dev/null || fail "land a first branch"
# a non-admin human: refused at commit, at land, at push
actor "Human Two" human@team.test
rapid branch refactor no-gates -r "Empty the fast gate." >/dev/null; lb=$(git branch --show-current)
sed -i.bak 's/^gates_fast=.*/gates_fast=/' .rapid/conf && rm -f .rapid/conf.bak; git add .rapid/conf
refused git commit -q -m "[NEW] Drop the fast gate from the conf"
grep -q 'policy flip: give it its own \[MODE\] commit' "$T/err" || fail "commit-msg let a policy change through without [MODE]: $(cat "$T/err")"
refused git commit -q -m "[MODE] Drop the fast gate from the conf"
grep -q "'human@team.test' is not an admin" "$T/err" || fail "commit-msg let a non-admin flip policy: $(cat "$T/err")"
git commit -q --no-verify -m "[MODE] Drop the fast gate from the conf"
refused rapid land
grep -q "'human@team.test' is not an admin" "$T/err" || fail "land let a non-admin flip policy: $(cat "$T/err")"
refused git push origin "HEAD:refs/heads/$lb"
grep -q "'human@team.test' is not an admin" "$T/err" || fail "pre-push let a non-admin flip policy: $(cat "$T/err")"
# forced onto dev past every hook: doctor names it
d0=$(git rev-parse dev); v=$(git describe --abbrev=0 --tags --match "v[0-9]*" dev); v="${v%.*}.$(( ${v##*.} + 1 ))"
m=$(git commit-tree "$(git rev-parse HEAD^{tree})" -p "$d0" -p HEAD -m "[MERGE] $lb into dev: $v

Forced past the hooks.

- Policy flip forced.

Branch-Base: $d0
Requirement: .rapid/requirements/no-gates.md
Gates: fast=none full=pass
Tested-Tree: $(git rev-parse HEAD^{tree})")
git tag -a "$v" -m forced "$m"; git update-ref refs/heads/dev "$m"
rapid doctor --history-only > "$T/doc" 2>&1 && fail "doctor missed the non-admin flip"
grep -q "^doctor: I4 .*'human@team.test' is not an admin" "$T/doc" || fail "no I4 for the non-admin flip: $(cat "$T/doc")"
git update-ref refs/heads/dev "$d0"; git tag -d "$v" >/dev/null
git switch -q dev; git branch -q -D "$lb"
# the flip hidden in the merge commit itself, over a clean branch commit: a merge adds nothing of its own, so
# doctor names it I1 and pre-push refuses it (no branch commit holds the change the other checks walk)
rapid branch feature clean -r "A clean branch whose merge is written by hand." >/dev/null; commit clean.txt; lb=$(git branch --show-current)
num=$(sed -nE 's#^pool/v[0-9.]+/(n[0-9]+)[.].*#\1#p' <<<"$lb")
cp .git/index "$T/idx"
{ cat .rapid/admins; echo human@team.test; } > "$T/admins"; git show dev:.rapid/conf | sed 's/^gates_full=.*/gates_full=none/' > "$T/conf"
GIT_INDEX_FILE="$T/idx" git update-index --add --cacheinfo "100644,$(git hash-object -w "$T/admins"),.rapid/admins" --cacheinfo "100644,$(git hash-object -w "$T/conf"),.rapid/conf"
tree=$(GIT_INDEX_FILE="$T/idx" git write-tree)
m=$(git commit-tree "$tree" -p "$d0" -p HEAD -m "[MERGE] $lb into dev: $v

Lands a clean branch by hand.

- The merge tree itself names a new admin.

Branch-Base: $d0
Requirement: .rapid/requirements/clean.md
Gates: fast=pass full=pass
Tested-Tree: $tree
Branch-Number: $num")
[ "$(git diff --name-only HEAD "$m" | tr '\n' ' ')" = ".rapid/admins .rapid/conf " ] || fail "the hand-made merge does not carry the flip alone: $(git diff --name-only HEAD "$m")"
git tag -a "$v" -m forced "$m"; git update-ref refs/heads/dev "$m"
rapid doctor --history-only > "$T/doc" 2>&1 && fail "doctor missed the flip hidden in the merge tree: $(cat "$T/doc")"
grep -q "^doctor: I1 $m tree is not the tree merging its branch gives" "$T/doc" || fail "no I1 for the merge that changes files itself: $(cat "$T/doc")"
refused git push -q origin dev "refs/tags/$v"
grep -q "I1 $m tree is not the tree merging its branch gives" "$T/err" || fail "pre-push let the merge-tree flip through: $(cat "$T/err")"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$d0" ] || fail "the merge-tree flip reached origin"
git update-ref refs/heads/dev "$d0"; git tag -d "$v" >/dev/null
git switch -q dev; git branch -q -D "$lb"
# the admin: a flip that mixes other files, or a [MODE] that flips nothing, is refused
actor "Owner One" owner@team.test
rapid branch refactor cap -r "The admin raises the branch size cap." >/dev/null
printf 'notes\n' > notes.txt; sed -i.bak 's/^max_commits=.*/max_commits=40/' .rapid/conf && rm -f .rapid/conf.bak
git add notes.txt .rapid/conf
refused git commit -q -m "[MODE] Raise the branch size cap to forty"
grep -q 'a \[MODE\] commit changes only policy files' "$T/err" || fail "a mixed [MODE] commit passed: $(cat "$T/err")"
git reset -q notes.txt; git commit -q -m "[MODE] Raise the branch size cap to forty"
git add notes.txt; git commit -q --no-verify -m "[MODE] Add the team notes"
refused rapid land
grep -q 'this one changes none' "$T/err" || fail "a [MODE] commit that flips nothing landed: $(cat "$T/err")"
git reset -q --soft HEAD^; git commit -q -m "[NEW] Add the team notes"
rapid land >/dev/null || fail "the admin's flip did not land"
[ "$(git show dev:.rapid/conf | sed -n 's/^max_commits=//p')" = 40 ] || fail "the flip is not on dev"
# the admin names a second admin, who may then flip
printf 'human@team.test\n' >> .rapid/admins
[ -z "$(git status --porcelain -- .rapid/admins)" ] || fail ".rapid/admins is not excluded: $(git status --porcelain -- .rapid/admins)"
actor "Human Two" human@team.test
rapid branch refactor human-flip -r "The human lowers the cap again." >/dev/null
sed -i.bak 's/^max_commits=.*/max_commits=20/' .rapid/conf && rm -f .rapid/conf.bak; git add .rapid/conf
git commit -q -m "[MODE] Lower the branch size cap to twenty" || fail "a named admin could not flip"
rapid land >/dev/null || fail "land the human admin's flip"
history_clean
# a repository with no admins (set up in an agent session): a flip is refused until setup --owner names the owner
mkdir -p "$T/n/.rapid"; git -C "$T/n" init -q
printf 'land_who=anyone\nmax_commits=20\ntest_paths=*\ncommit_body=optional\nrequirement_test=optional\ngates_fast=none\ngates_full=none\ngates_release=none\n' > "$T/n/.rapid/conf"
cd "$T/n"; CLAUDECODE=1 rapid setup >/dev/null 2>&1
[ ! -e .rapid/admins ] || fail "an agent session setting up was written as admin"
rapid branch refactor admins -r "The first admin of the repository." >/dev/null
sed -i.bak 's/^max_commits=.*/max_commits=40/' .rapid/conf && rm -f .rapid/conf.bak; git add .rapid/conf
refused git commit -q -m "[MODE] Raise the branch size cap to forty"
grep -q 'no admin is listed in .rapid/admins; rapid setup --owner EMAIL names the owner' "$T/err" || fail "a flip of the conf passed with no admin listed: $(cat "$T/err")"
actor "Human Three" human3@crew.test
rapid setup --owner human3@crew.test > "$T/out" 2>&1 || fail "setup --owner in a seeded repository with no admin: $(cat "$T/out")"
git commit -q -m "[MODE] Raise the branch size cap to forty" || fail "the named owner could not flip"
rapid land >/dev/null || fail "land the named owner's flip"
# an admin may share the list: the excluded file goes in with git add -f as a [MODE] commit
rapid branch refactor share-admins >/dev/null
git add -f .rapid/admins; git commit -q -m "[MODE] Share the admins list across clones" 2> "$T/err" || fail "the owner could not commit the admins list: $(cat "$T/err")"
rapid land >/dev/null || fail "land the shared admins"
git cat-file -e dev:.rapid/admins || fail "dev does not hold the shared admins list"
history_clean
