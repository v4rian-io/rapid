#!/usr/bin/env bash
# rapid commit --smart, opt-in: a stub smart_commit_cmd receives the staged diff fenced as data, and
# its message is committed through the hooks; a message the
# hooks refuse is shown and nothing is committed; nothing staged, and no CLI and no command, both
# fail cleanly; --message-only prints without committing. The claude CLI gets no tool, user settings
# only, and runs from its private HOME, never the work tree.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
rapid branch refactor smart-cmd -r "Compose commit messages with the stub command of this scenario." >/dev/null
printf 'smart_commit_cmd=sh %s/stub.sh\n' "$T" >> .rapid/conf; git add .rapid/conf; git commit -q -m "[MODE] Use the stub message command"
rapid land >/dev/null || fail "land smart_commit_cmd"
cat > "$T/stub.sh" <<STUB
cat > "$T/prompt"
cat "$T/reply"
STUB
rapid branch feature smart >/dev/null
printf 'x\n' > a.txt; git add a.txt
printf '[NEW] Add the a file to the project\n\nThe a file holds the first value of the project.\n' > "$T/reply"
rapid commit --smart --message-only > "$T/out" || fail "message-only: $(cat "$T/out")"
grep -q '^\[NEW\] Add the a file' "$T/out" || fail "message-only printed no message: $(cat "$T/out")"
[ -n "$(git diff --cached --name-only)" ] || fail "message-only committed"
grep -q 'BEGIN DATA-' "$T/prompt" && grep -q '^+x$' "$T/prompt" || fail "the staged diff did not reach the command fenced: $(cat "$T/prompt")"
rapid commit --smart > "$T/out" 2>&1 || fail "smart commit: $(cat "$T/out")"
[ "$(git log -1 --format=%s)" = "[NEW] Add the a file to the project" ] || fail "the composed message was not committed"
printf 'y\n' > b.txt; git add b.txt
printf 'added the b file and some other things\n' > "$T/reply"
refused rapid commit --smart
grep -q 'the hooks refused the composed message' "$T/err" || fail "a refused message gave no reason: $(cat "$T/err")"
grep -q 'added the b file' "$T/out" || fail "the refused message was not shown: $(cat "$T/out")"
[ "$(git log -1 --format=%s)" = "[NEW] Add the a file to the project" ] || fail "a refused message committed"
git reset -q b.txt
refused rapid commit --smart
grep -q 'nothing is staged' "$T/err" || fail "an empty index was not refused: $(cat "$T/err")"
refused rapid commit
grep -q 'only composes messages (--smart)' "$T/err" || fail "plain rapid commit was not refused: $(cat "$T/err")"
# no command and no claude CLI: a clean failure
mkrepo "$T/n"; cd "$T/n"; rapid branch feature none >/dev/null; printf 'z\n' > z.txt; git add z.txt
PATH="/usr/bin:/bin" refused "$(type -P rapid)" commit --smart
grep -q 'no claude CLI on PATH and no smart_commit_cmd' "$T/err" || fail "no CLI gave no clean failure: $(cat "$T/err")"
[ -n "$(git diff --cached --name-only)" ] || fail "the failure touched the index"
# the claude CLI itself: no tool at all, user settings only, run from the private HOME, never the work tree
mkdir -p "$T/bin"
cat > "$T/bin/claude" <<'STUB'
#!/bin/sh
cat >/dev/null; d=$(dirname "$0"); pwd -P > "$d/cwd"; : > "$d/argv"
for a in "$@"; do printf '<%s>\n' "$a" >> "$d/argv"; done
printf '[NEW] Add the z file to the project\n\nThe z file holds the last value of the project.\n'
STUB
chmod +x "$T/bin/claude"
PATH="$T/bin:$PATH" command rapid commit --smart --message-only > "$T/out" 2>&1 || fail "smart commit through the claude CLI: $(cat "$T/out")"
grep -q '^\[NEW\] Add the z file' "$T/out" || fail "the CLI's message was not printed: $(cat "$T/out")"
[ "$(tr -d '\n' < "$T/bin/argv")" = "<-p><--permission-mode><default><--setting-sources><user><--add-dir><$(git rev-parse --show-toplevel)><--tools><>" ] || fail "smart argv: $(cat "$T/bin/argv")"
! grep -F -e allowedTools -e Read "$T/bin/argv" >/dev/null || fail "the composer was given a tool: $(cat "$T/bin/argv")"
case "$(cat "$T/bin/cwd")" in */rapid-smart.*) ;; *) fail "the composer did not run from its private HOME: $(cat "$T/bin/cwd")" ;; esac
