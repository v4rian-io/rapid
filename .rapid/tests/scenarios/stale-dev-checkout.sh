#!/usr/bin/env bash
# a branch started from a checked-out dev that origin moved never stages the reversal of a
# coworker's land: Ann lands and stays on dev, Bob lands, Ann's next rapid branch fast-forwards dev in
# her work tree, starts clean and lands with Bob's work kept; the same when dev is checked out in a
# linked worktree and the branch is started from another one; a branch is refused, not started, when
# the dev work tree it starts from cannot follow.
. "$(dirname "$0")/../lib.sh"
actor "Ann" ann@team.test
mkrepo "$T/a" origin; cd "$T/a"
git clone -q "$T/origin.git" "$T/b"; ( cd "$T/b" && git switch -q dev && rapid setup >/dev/null )
rapid branch feature one >/dev/null; commit one.txt; rapid land >/dev/null || fail "Ann lands one"
[ "$(git symbolic-ref --short HEAD)" = dev ] || fail "Ann is not on dev after her land"
cd "$T/b"; actor "Bob" bob@team.test
git pull -q --ff-only origin dev
rapid branch feature bobs-work >/dev/null; commit bob.txt; rapid land >/dev/null || fail "Bob lands"
cd "$T/a"; actor "Ann" ann@team.test
rapid branch feature two >/dev/null || fail "Ann's next branch"
[ -z "$(git status --porcelain --untracked-files=no | grep -v '.rapid/requirements/two.md' || true)" ] \
  || fail "the new branch stages a change of its own: $(git status --porcelain)"
[ -f bob.txt ] && [ -f .rapid/requirements/bobs-work.md ] || fail "Bob's land is missing from Ann's work tree"
commit two.txt; rapid land >/dev/null || fail "Ann lands two"
git cat-file -e dev:bob.txt 2>/dev/null && git cat-file -e dev:.rapid/requirements/bobs-work.md 2>/dev/null || fail "Ann's land reverted Bob's work"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$(git rev-parse dev)" ] || fail "origin dev differs"
history_clean
# dev checked out in a linked worktree; the branch starts from another one
git worktree add -q "$T/dev-wt" --detach HEAD; git switch -q --detach HEAD
git -C "$T/dev-wt" switch -q dev
cd "$T/b"; actor "Bob" bob@team.test
git switch -q dev; git pull -q --ff-only origin dev
rapid branch feature bob-again >/dev/null; commit bob2.txt; rapid land >/dev/null || fail "Bob lands again"
cd "$T/a"; actor "Ann" ann@team.test
rapid branch feature three >/dev/null || fail "Ann's branch from another worktree"
[ -z "$(git -C "$T/dev-wt" status --porcelain --untracked-files=no)" ] || fail "dev's linked worktree stages a reversal: $(git -C "$T/dev-wt" status --porcelain)"
[ -f "$T/dev-wt/bob2.txt" ] || fail "dev's linked worktree did not follow dev"
commit three.txt; rapid land >/dev/null || fail "Ann lands three"
git cat-file -e dev:bob2.txt 2>/dev/null || fail "the land reverted Bob's second land"
history_clean
# dev's work tree cannot follow (an untracked file is in the way): the branch is refused, the file kept
cd "$T/dev-wt"; printf 'mine\n' > bob3.txt
cd "$T/b"; actor "Bob" bob@team.test; git switch -q dev; git pull -q --ff-only origin dev
rapid branch feature bob-third >/dev/null; commit bob3.txt; rapid land >/dev/null || fail "Bob lands a third time"
cd "$T/dev-wt"; actor "Ann" ann@team.test
refused rapid branch feature four
grep -q 'dev moved under' "$T/err" || fail "a branch started on a dev work tree that could not follow: $(cat "$T/err")"
[ "$(cat bob3.txt)" = mine ] || fail "the untracked file was overwritten"
if [ -n "$(lref four)" ]; then fail "the refused branch was created"; fi
