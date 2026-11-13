#!/usr/bin/env bash
# a hand-made commit pushed to dev, a force-push, a moved tag, a stray
# branch and the deletion of a branch not landed yet are refused by pre-push; doctor flags a direct
# commit that bypassed it.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r" origin; cd "$T/r"
rapid branch feature alpha >/dev/null; commit a.txt; rapid land >/dev/null
# direct commit on dev (hooks off to get past commit-msg), then push
git switch -q dev
echo d > d.txt; git add d.txt; git -c core.hooksPath=/dev/null commit -q -m "[NEW] Add a direct commit on dev"
refused git push origin dev
grep -q 'dev only takes merges made by rapid land' "$T/err" || fail "direct push text: $(cat "$T/err")"
git reset -q --hard HEAD~1
# force-push dev backwards
refused git push -f origin HEAD~1:refs/heads/dev
grep -q 'only moves forward' "$T/err" || fail "force-push text: $(cat "$T/err")"
# move a tag
git tag -f -a v2026.0.1 -m moved HEAD~1 >/dev/null
refused git push -f origin v2026.0.1
git tag -f -a v2026.0.1 -m "rapid land feature/alpha" dev >/dev/null
# a stray branch name
refused git push origin dev:refs/heads/hotfix-now
# a branch not landed yet on origin is never deleted
rapid branch feature later >/dev/null; commit p.txt; git push -q origin "$(lname later)"
settle
[ -n "$(rbranch origin later)" ] || fail "the branch not landed yet is not on origin"
refused git push origin ":$(rbranch origin later)"
grep -q 'never deleted' "$T/err" || fail "branch not landed yet deletion text: $(cat "$T/err")"
git switch -q dev
# bypassed: doctor names the direct commit
echo e > e.txt; git add e.txt; git -c core.hooksPath=/dev/null commit -q -m "[NEW] Add a bypassing commit on dev"
rapid doctor --history > "$T/doc" 2>&1 && fail "doctor missed the direct commit"
grep -q '^doctor: I1 ' "$T/doc" || fail "doctor did not report I1: $(cat "$T/doc")"
