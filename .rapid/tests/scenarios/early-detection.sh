#!/usr/bin/env bash
# detection at commit and at branch push: the commit that would push a branch past max_commits is
# refused before it is written (an amend passes); a branch's first commit carrying the placeholder
# requirement is refused; with gates_commit set a staged tree that fails it is refused at commit;
# a branch push above max_commits is refused (a red branch commit is transport: see push-is-transport).
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r" origin; cd "$T/r"
rapid branch refactor cap -r "Lower the branch size cap to two and gate every commit." >/dev/null
sed -i.bak 's/^max_commits=.*/max_commits=2/' .rapid/conf && rm -f .rapid/conf.bak
printf 'gates_commit=sh check.sh\n' >> .rapid/conf
git add .rapid/conf; git commit -q -m "[MODE] Cap branches at two gated commits"
rapid land >/dev/null || fail "land the cap"
# the cap: commit three is refused before it is written; an amend of commit two passes
rapid branch feature big >/dev/null
commit a.txt; commit b.txt
printf 'c\n' > c.txt; git add c.txt
refused git commit -q -m "[NEW] Add a third file to the big branch"
grep -q 'already carries 2 commits (max_commits=2); this one would be 3' "$T/err" || fail "commit 3 was not refused: $(cat "$T/err")"
git commit -q --amend -m "[NEW] Add two files to the project" || fail "an amend at the cap was refused"
# gates_commit: a staged tree that fails it is refused at commit
git switch -q dev; rapid branch fix red >/dev/null
printf 'x\n' > boom.bad; git add boom.bad
refused git commit -q -m "[FIX] Add a file that breaks the gate" -m "Cause: the defect this scenario plants." -m "Fix: the repair this scenario makes."
grep -q 'gates_commit fails on the staged tree' "$T/err" || fail "a red staged tree was committed: $(cat "$T/err")"
git commit -q --no-verify -m "[FIX] Add a file that breaks the gate" -m "Cause: the defect this scenario plants." -m "Fix: the repair this scenario makes."
# a branch above max_commits made past the hooks is refused at push
git switch -q dev; rapid branch feature over >/dev/null
for i in 1 2 3; do printf '%s\n' "$i" > "o$i.txt"; git add "o$i.txt"; git -c core.hooksPath=/dev/null commit -q -m "[NEW] Add over file $i to the project"; done
refused git push -q origin "$(lname over)"
grep -q 'carries 3 commits, above max_commits=2' "$T/err" || fail "pre-push let an oversized branch through: $(cat "$T/err")"
# the placeholder requirement is refused at the branch's first commit
git switch -q dev; command rapid branch feature vague --test v.txt >/dev/null
commit v.txt v "[NEW] Add a file of no stated purpose" 2>"$T/err" && fail "a first commit with the placeholder requirement was accepted"
grep -q 'still holds the placeholder' "$T/err" || fail "placeholder refusal text: $(cat "$T/err")"
