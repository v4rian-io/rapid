#!/usr/bin/env bash
# setup never advances main and names the owner: setup writes the setup author as the
# first admin in .rapid/admins, the working copy's own file, never in the seed (an agent session setting up writes none); after setup, ten lands and setup again in a second
# clone (which names its runner as admin from git's user.email and user.name), main is still the root commit locally and on origin; a clone that checked out dev alone takes its
# main from origin, never from the tip of dev; a clone that checked out main alone takes its dev from origin,
# never from main; where no main exists anywhere, main is the seed of dev,
# and an origin that refuses the seed push is said so, the hooks and the local main staying.
. "$(dirname "$0")/../lib.sh"
actor "Owner One" owner@team.test
mkrepo "$T/r" origin; cd "$T/r"
root=$(git rev-parse main)
[ "$(git rev-list --count main)" = 1 ] || fail "main is not the root commit after setup"
! git cat-file -e main:.rapid/admins 2>/dev/null || fail "the root commit holds .rapid/admins"
[ "$(grep -v '^#' .rapid/admins)" = 'owner@team.test # Owner One' ] || fail "setup names no owner in the working copy: $(cat .rapid/admins 2>&1)"
for i in 1 2 3 4 5 6 7 8 9 10; do
  rapid branch feature "step-$i" >/dev/null; commit "step$i.txt"; rapid land >/dev/null || fail "land $i"
done
[ "$(git rev-parse main)" = "$root" ] || fail "lands moved main"
[ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$root" ] || fail "lands moved origin main"
git clone -q "$T/origin.git" "$T/c"; cd "$T/c"; git switch -q dev
rapid setup >/dev/null || fail "setup in a second clone"
[ "$(git rev-parse main)" = "$root" ] || fail "setup in a second clone moved main"
# the clone names no admin yet: setup writes its human runner from git's user.email and user.name
me="$(git var GIT_AUTHOR_IDENT | sed -E 's/^(.*) <([^>]*)>.*$/\2 # \1/')"
[ "$(grep -v '^#' .rapid/admins 2>/dev/null)" = "$me" ] || fail "setup in a second clone named no admin from git's user.email and user.name ($me): $(cat .rapid/admins 2>&1)"
[ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$root" ] || fail "setup in a second clone moved origin main"
history_clean
# a clone that checked out dev alone holds no main of its own: setup takes the main of origin
git clone -q -b dev "$T/origin.git" "$T/d"; cd "$T/d"
! git rev-parse -q --verify refs/heads/main >/dev/null || fail "the clone of dev alone already holds a main"
rapid setup >/dev/null || fail "setup in a clone of dev alone"
[ "$(git rev-parse main)" = "$root" ] || fail "setup in a clone of dev alone put main at $(git rev-parse --short main), not at the main of origin"
history_clean
# a clone that checked out main holds no dev of its own: setup takes the dev of origin, never main
git clone -q -b main "$T/origin.git" "$T/m"; cd "$T/m"
! git rev-parse -q --verify refs/heads/dev >/dev/null || fail "the clone of main already holds a dev"
rapid setup > "$T/out" 2>&1 || fail "setup in a clone of main: $(cat "$T/out")"
[ "$(git rev-parse dev)" = "$(git ls-remote origin refs/heads/dev | cut -f1)" ] || fail "setup in a clone of main put dev at $(git rev-parse --short dev), not at the dev of origin"
! grep -q 'created dev at main' "$T/out" || fail "setup in a clone of main said it created dev at main"
history_clean
# a dev that has merges, with no main anywhere: setup puts main at the seed of dev, never at its tip
cd "$T/r"; git init -q --bare "$T/nomain.git"
git push -q --no-verify "$T/nomain.git" dev refs/notes/gates $(git tag -l 'v*' | sed 's#^#refs/tags/#') || fail "the origin without a main was not filled"
# an origin that refuses the seed push: setup says so, and what it did locally stays
printf '#!/bin/sh\nexit 1\n' > "$T/nomain.git/hooks/pre-receive"; chmod +x "$T/nomain.git/hooks/pre-receive"
git clone -q -b dev "$T/nomain.git" "$T/n0"; cd "$T/n0"
refused rapid setup
grep -q 'X rapid: origin refused the push; nothing was published' "$T/err" || fail "a refused seed push is not said by rapid: $(cat "$T/err")"
[ "$(git rev-parse main)" = "$root" ] && [ -n "$(git config core.hooksPath)" ] || fail "a refused seed push undid the local setup"
[ -z "$(git ls-remote origin refs/heads/main)" ] || fail "a refused seed push left a main on origin"
rm -f "$T/nomain.git/hooks/pre-receive"
git clone -q -b dev "$T/nomain.git" "$T/n"; cd "$T/n"
rapid setup >/dev/null || fail "setup where no main exists anywhere"
[ "$(git rev-parse main)" = "$root" ] || fail "setup with no main anywhere put main at $(git rev-parse --short main), not at the seed of dev"
history_clean
actor "Agent Two" agent2@team.test
CLAUDECODE=1 _mkrepo_build "$T/a"; cd "$T/a"
[ ! -e .rapid/admins ] || fail "an agent session setting up was written as admin"
history_clean
