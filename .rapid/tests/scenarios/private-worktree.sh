#!/usr/bin/env bash
# fast
# a gate never runs in the caller's work tree: when no private work tree can be made (the temp
# directory is gone, as under a disk sweep), check --each and land refuse,
# and a push from a linked work tree (git exports GIT_DIR to the hook) leaves that work tree as it was;
# the caller's branch and files stay as they were; while a gate runs, its private work tree's root
# is kept fresh (a heartbeat), so a sweeper of idle work trees never takes it.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
git remote add origin "$(mkremote origin)"; rapid setup >/dev/null
rapid branch feature keep >/dev/null; commit k1.txt; commit k2.txt k2 "[NEW] Add the second keep file"
branch=$(lname keep); tip=$(git rev-parse HEAD)
for cmd in "check --each" "land"; do
  TMPDIR="$T/gone" command rapid $cmd >/dev/null 2>"$T/err" && fail "rapid $cmd passed with no private work tree"
  [ "$(git symbolic-ref --short -q HEAD || echo detached)" = "$branch" ] || fail "rapid $cmd moved the caller off its branch: $(git symbolic-ref -q HEAD || git rev-parse HEAD)"
  [ "$(git rev-parse HEAD)" = "$tip" ] && [ -z "$(git status --porcelain)" ] || fail "rapid $cmd changed the caller's work tree"
done
# a push from a linked work tree: git exports GIT_DIR to the hook, which must not reach the gate's work trees
git switch -q dev; git worktree add -q "$T/w2" "$branch"
( cd "$T/w2" && git push -q origin HEAD ) >/dev/null 2>"$T/err" || fail "the push from a linked work tree: $(cat "$T/err")"
[ "$(git -C "$T/w2" symbolic-ref --short -q HEAD || echo detached)" = "$branch" ] || fail "the push detached the linked work tree"
[ -z "$(git -C "$T/w2" status --porcelain)" ] || fail "the push changed the linked work tree's files"
git worktree remove --force "$T/w2"; git switch -q "$branch"
# a long gate writes nothing in its work tree; the heartbeat keeps the tree's root fresh
printf '#!/bin/sh\ntouch -t 200001010000 "$PWD"; sleep 3\nm=$(stat -f %%m "$PWD" 2>/dev/null || stat -c %%Y "$PWD")\n[ "$m" -gt 1000000000 ]\n' > "$T/busy.sh"
git switch -q dev; rapid branch refactor busy >/dev/null
sed -i.bak "s#^gates_full=.*#gates_full=sh check.sh \&\& sh $T/busy.sh#" .rapid/conf && rm -f .rapid/conf.bak
git add .rapid/conf; git commit -q -m "[MODE] Make the full gate check its tree is kept fresh"
# the close already runs the new gate (it gates the final tree under its own conf)
RAPID_BUSY_EVERY=1 rapid land >/dev/null || fail "landing the busy gate"
git switch -q "$branch"; rapid sync >/dev/null
RAPID_BUSY_EVERY=1 rapid land >/dev/null 2>"$T/err" || fail "the land's tree went stale while its gate ran: $(cat "$T/err")"
history_clean
