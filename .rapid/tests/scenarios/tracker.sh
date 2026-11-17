#!/usr/bin/env bash
# tracker contract: with no tracker a ticket id still travels from the
# branch to the merge trailer; a command adapter from operator settings is read,
# linked and moved to done; a command tracker in the committed conf, or one
# the repository tracks, is refused.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
# none
refused rapid branch feature exports --ticket kb12
grep -q 'must look like CODE-123' "$T/err" || fail "a bad ticket id was accepted"
rapid branch feature exports --ticket KB-12 -r "Export reports as CSV." >/dev/null
grep -qx 'Ticket: KB-12' .rapid/requirements/exports.md || fail "the ticket is not in the requirement"
commit export.txt e "[NEW] Export reports as CSV"
rapid land >/dev/null || fail "land with a ticket and no tracker"
[ "$(rapid_t() { git log -1 --format=%B dev | git interpret-trailers --parse | sed -n 's/^Ticket: //p'; }; rapid_t)" = KB-12 ] || fail "the merge has no Ticket trailer"
# command adapter from operator settings, kept outside the repository
A="$T/adapter"; L="$T/adapter.log"
cat > "$A" <<STUB
#!/bin/sh
echo "\$*" >> "$L"
case "\$1" in
  get) printf '{"key": "%s", "title": "Import reports from CSV"}\n' "\$2" ;;
  link|transition) printf '{"ok": true}\n' ;;
  *) exit 2 ;;
esac
STUB
chmod +x "$A"
export RAPID_TRACKER="command:$A"
rapid branch feature imports --ticket KB-13 >/dev/null || fail "branch with a command tracker"
grep -q 'Import reports from CSV' .rapid/requirements/imports.md || fail "the ticket title did not become the requirement"
grep -qx "link KB-13 --branch $(lname imports)" "$L" || fail "the branch was not linked: $(cat "$L")"
commit import.txt i "[NEW] Import reports from CSV"
rapid land >/dev/null || fail "land with a command tracker"
v=$(git describe --exact-match --tags dev)
grep -qx "transition KB-13 --to done --ref $v" "$L" || fail "the ticket was not moved to done: $(cat "$L")"
unset RAPID_TRACKER
# a command tracker in the committed conf is refused
rapid branch refactor tracker-conf >/dev/null
printf 'tracker=command:%s\n' "$A" >> .rapid/conf; git add .rapid/conf; git commit -q -m "[MODE] Name a tracker command in the conf"
rapid land >/dev/null || fail "land the conf change"
refused rapid branch feature notes --ticket KB-14
grep -q 'set it in RAPID_TRACKER' "$T/err" || fail "a committed command tracker was honoured: $(cat "$T/err")"
# a tracked adapter is refused even from operator settings
git config rapid.tracker "command:check.sh"
RAPID_TRACKER= refused rapid branch feature notes --ticket KB-14
grep -q 'a file this repository tracks' "$T/err" || fail "a tracked adapter was run: $(cat "$T/err")"
git config --unset rapid.tracker
history_clean
