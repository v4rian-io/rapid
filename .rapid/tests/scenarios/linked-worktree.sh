#!/usr/bin/env bash
# land from a linked worktree while dev is checked out in the main one: that
# work tree follows the new dev.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
git switch -q dev
git branch pool/v2026.0/feature.widget dev
git worktree add -q "$T/wt" pool/v2026.0/feature.widget
cd "$T/wt"
mkdir -p .rapid/requirements; printf '# feature/widget\n\nAdd the widget.\n' > .rapid/requirements/widget.md; git add .rapid/requirements/widget.md
commit widget.txt w "[NEW] Add the widget"
rapid land >/dev/null || fail "land from the linked worktree"
cd "$T/r"
[ "$(git rev-parse HEAD)" = "$(git rev-parse dev)" ] || fail "main worktree HEAD is not dev's tip"
[ -z "$(git status --porcelain)" ] || fail "main worktree is dirty after land: $(git status --porcelain)"
[ -f widget.txt ] || fail "main worktree files did not follow dev"
history_clean
