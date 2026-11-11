#!/usr/bin/env bash
# the search for the branch that broke a close makes its private work trees one after another: git
# adds one work tree at a time, so no two of them are ever added at once (a git that reports every
# overlapping worktree add verifies it), and the search still names the right branch among several.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/a" origin; cd "$T/a"
land() { command rapid land --batch "$@"; }
for s in one two; do git switch -q dev; rapid branch feature "$s" >/dev/null; commit "$s.txt"; land >/dev/null 2>&1 || fail "land $s"; done
git switch -q dev; rapid branch feature broken >/dev/null; commit crash.bad; pb=$(lname broken); land >/dev/null 2>&1 || fail "land broken"
for s in four five; do git switch -q dev; rapid branch feature "$s" >/dev/null; commit "$s.txt"; land >/dev/null 2>&1 || fail "land $s"; done
git switch -q dev
# a git that holds a lock for the length of every worktree add and reports an add that meets the lock
real=$(command -v git); mkdir -p "$T/bin"
cat > "$T/bin/git" <<SHIM
#!/bin/sh
case " \$* " in *" worktree add "*)
  if ! mkdir "$T/wt.lock" 2>/dev/null; then echo overlap >> "$T/overlap"; exec "$real" "\$@"; fi
  sleep 0.5; "$real" "\$@"; rc=\$?; rmdir "$T/wt.lock" 2>/dev/null; exit \$rc ;;
esac
exec "$real" "\$@"
SHIM
chmod +x "$T/bin/git"
PATH="$T/bin:$PATH" refused command rapid land
grep -qF "broke the close: $pb (" "$T/out" || fail "the failed close did not name the broken branch: $(cat "$T/out" "$T/err")"
[ ! -e "$T/overlap" ] || fail "the search added $(wc -l < "$T/overlap" | tr -d ' ') work tree(s) while another add was running"
[ -z "$(git worktree list --porcelain | grep -c 'rapid-broke' | grep -v '^0$' || true)" ] || fail "the search left a private work tree behind"
