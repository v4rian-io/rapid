#!/usr/bin/env bash
# rapid branch --reject closes a branch's open PR as a rejection and keeps the branch: the one comment
# carries the reason, the reviewer, the logins to notify and a record line; the close never asks the
# forge to delete the branch, and the branch and its safety anchor stay here and on origin; a missing
# reason, a branch without an open PR and a branch that is no branch are refused; --dry-run closes nothing.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r" origin; cd "$T/r"
# forge mock: PR 7 while $P/num exists; the close records its comment and removes the PR
P="$T/forge"; mkdir -p "$P" "$T/bin"
cat > "$T/bin/gh" <<STUB
#!/bin/sh
printf '%s\n' "\$1 \$2 \$3" >> "$P/log"
case "\$1 \$2" in
  "pr list") [ -f "$P/num" ] && cat "$P/num"; exit 0 ;;
  "pr close") n="\$3"; while [ \$# -gt 0 ]; do [ "\$1" = --comment ] && printf '%s\n' "\$2" > "$P/comment"; [ "\$1" = --delete-branch ] && echo yes > "$P/deleted"; shift; done
              rm -f "$P/num"; echo "\$n" > "$P/closed" ;;
  "api user") echo reviewer1 ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$T/bin/gh"; export PATH="$T/bin:$PATH"
rapid branch refactor forge-conf -r "The forge repository is named." >/dev/null
printf 'forge_repo=acme/app\n' >> .rapid/conf; git add .rapid/conf; git commit -q -m "[MODE] Name the forge repository in the conf"
rapid land >/dev/null || fail "land the conf"
rapid branch feature widget >/dev/null; commit widget.txt w "[NEW] Add the widget to the project"; p=$(git branch --show-current)
git push -q origin "$p" || fail "push the branch"
settle
tip=$(git rev-parse HEAD); anchor="refs/heads/safety/${p#pool/}"
git rev-parse -q --verify "$anchor" >/dev/null || fail "the branch has no safety anchor"
# refusals
rc=0; rapid branch --reject >"$T/out" 2>"$T/err" || rc=$?
[ "$rc" = 2 ] && grep -q -- '--reason is required' "$T/err" || fail "a rejection without a reason: exit $rc: $(cat "$T/err")"
rc=0; rapid branch --reject --reason "   " >"$T/out" 2>"$T/err" || rc=$?; [ "$rc" = 2 ] || fail "a blank reason: exit $rc, want 2"
refused rapid branch --reject --reason "The widget has no test"
grep -q 'has no open PR' "$T/err" || fail "a branch without a PR was rejected: $(cat "$T/err")"
rc=0; rapid branch --reject dev --reason "Not a branch" >"$T/out" 2>"$T/err" || rc=$?; [ "$rc" = 2 ] || fail "rejecting dev: exit $rc, want 2: $(cat "$T/err")"
# a dry run closes nothing
echo 7 > "$P/num"
rapid branch --reject --reason "The widget has no test" --dry-run > "$T/out" || fail "the dry run"
grep -q "dry run: would close PR #7 on acme/app, keeping $p" "$T/out" && grep -q '  | Reason: The widget has no test' "$T/out" || fail "the dry run does not show the rejection: $(cat "$T/out")"
[ -f "$P/num" ] && [ ! -f "$P/closed" ] || fail "the dry run closed the PR"
# the rejection: one comment, the PR closed, the branch kept
rapid branch --reject --reason "The widget has no test" --mention alice --mention @bob > "$T/out" || fail "the rejection"
grep -q "PR #7 on acme/app is rejected; $p and its safety anchor are kept" "$T/out" || fail "the rejection is not reported: $(cat "$T/out")"
[ "$(cat "$P/closed")" = 7 ] || fail "PR 7 was not closed"
[ ! -f "$P/deleted" ] || fail "the close asked the forge to delete the branch"
grep -qx '## REJECTION' "$P/comment" && grep -qx 'Reason: The widget has no test' "$P/comment" && grep -qx 'Reviewer: @reviewer1' "$P/comment" \
  || fail "the comment lacks the heading, reason or reviewer: $(cat "$P/comment")"
grep -qx "Branch: $p (kept on origin: push fixes to it, then rapid land --pr again)" "$P/comment" || fail "the comment does not say the branch is kept"
grep -qx 'Notify: @alice @bob' "$P/comment" || fail "the comment does not notify the logins: $(cat "$P/comment")"
grep -qE "^<!-- rejection pr=7 reviewer=reviewer1 branch=$p at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z -->\$" "$P/comment" || fail "the record line is missing: $(cat "$P/comment")"
[ "$(git rev-parse "$p")" = "$tip" ] && [ "$(git ls-remote origin "refs/heads/$p" | cut -f1)" = "$tip" ] || fail "the branch moved or left origin"
git rev-parse -q --verify "$anchor" >/dev/null || fail "the safety anchor is gone"
# by name, from dev
git switch -q dev; echo 8 > "$P/num"; rm -f "$P/closed"
rapid branch --reject widget --reason "Still no test" >/dev/null || fail "the rejection by name"
[ "$(cat "$P/closed")" = 8 ] || fail "the branch named by name was not rejected"
history_clean
