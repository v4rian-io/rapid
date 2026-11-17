#!/usr/bin/env bash
# a branch is checked by dev's framework, never by its own copy: a branch that rewrites the message
# rules in its own .rapid still has a bad message refused at commit, at land and at push, by the
# framework committed on dev, which rapid keeps exported under the git dir for that purpose.
. "$(dirname "$0")/../lib.sh"
# the framework's own repository: it holds its rapid, so the copy dev holds checks its branches
selfhosted "$T/r" origin; cd "$T/r"
d0=$(git rev-parse dev)
rapid branch feature loosen >/dev/null; b=$(lname loosen)
# the branch's own copy of the rules accepts any message
printf '\nrapid_msg_violations() { :; }\n' >> .rapid/lib/message.sh
git add .rapid/lib/message.sh; git commit -q -m "[NEW] Loosen the message rules of this branch" || fail "a ruled commit was refused"
( . .rapid/lib/core.sh; . .rapid/lib/message.sh; printf 'bad message\n' > "$T/m"; [ -z "$(rapid_msg_violations "$T/m")" ] ) || fail "the branch's own copy still refuses a bad message: the test verifies nothing"
# commit: refused by dev's rules
printf 'a\n' > a.txt; git add a.txt
refused git commit -q -m "bad message"
grep -qF 'X commit-msg: the commit breaks the rules' "$T/err" || fail "commit-msg ran the branch's own rules: $(cat "$T/err")"
dd="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)/rapid/devexec/$(git rev-parse dev:.rapid)"
[ -x "$dd/.rapid/hooks/commit-msg" ] && [ -f "$dd/.rapid/rapid" ] || fail "dev's framework is not kept under the git dir: $(ls "$dd" 2>&1)"
cmp -s "$dd/.rapid/lib/message.sh" <(git show dev:.rapid/lib/message.sh) || fail "the kept framework is not dev's"
# made past the hooks: land and push refuse it by dev's rules too
git commit -q --no-verify -m "bad message"
refused "$PWD/.rapid/rapid" land --batch
grep -qF 'breaks the message rules' "$T/err" || fail "land ran the branch's own rules: $(cat "$T/err")"
[ "$(git rev-parse dev)" = "$d0" ] || fail "the refused land moved dev"
refused git push origin "HEAD:refs/heads/$b"
grep -qF 'breaks the message rules' "$T/err" || fail "pre-push ran the branch's own rules: $(cat "$T/err")"
[ -z "$(git ls-remote origin "refs/heads/$b")" ] || fail "the refused push reached origin"
# with a ruled message the same branch lands
git commit -q --amend -m "[NEW] Add the a file to the project"
"$PWD/.rapid/rapid" land --batch >/dev/null 2>"$T/err" || fail "the ruled branch did not land: $(cat "$T/err")"
