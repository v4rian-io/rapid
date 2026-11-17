#!/usr/bin/env bash
# land integrity: a coworker's commit on a shared branch is never discarded, the requirement and
# merge body must be real, a landed requirement is never edited or deleted, and an empty body file
# is refused by name.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/a" origin; cd "$T/a"
# H1: a shared branch; B pushes a commit A has not fetched
rapid branch feature shared -r "Both agents add a file to one branch." >/dev/null
commit s1.txt one "[NEW] Add the first shared file"
git push -q origin "$(lname shared)"
settle
git clone -q "$T/origin.git" "$T/b"; cd "$T/b"; actor "Agent Two" agent2@team.test
rapid setup >/dev/null; git switch -q "$(git ls-remote origin "refs/heads/pool/*" | cut -f2 | sed -n "s#^refs/heads/##; /shared$/p")"
commit s2.txt two "[NEW] Add the second shared file"; git push -q origin "$(lname shared)"
settle
cd "$T/a"; actor "Agent One" agent1@team.test
refused rapid land
grep -q 'holds commits this clone lacks' "$T/err" || fail "a land over a coworker's commit was not refused: $(cat "$T/err")"
[ -n "$(rbranch origin shared)" ] || fail "the shared branch was deleted on origin"
git -c core.hooksPath=/dev/null pull -q --rebase origin "$(lname shared)"
rapid land >/dev/null || fail "land after fetching the coworker's commit"
git cat-file -e dev:s2.txt 2>/dev/null || fail "the coworker's commit is not on dev"
[ -z "$(rbranch origin shared)" ] || fail "the landed branch was not deleted on origin"
# M3: placeholder requirement and an unruled body are refused
command rapid branch feature vague --test v.txt >/dev/null; printf 'v\n' > v.txt; git add v.txt
refused git commit -q -m "[NEW] Add a file of no stated purpose"
grep -q 'placeholder' "$T/err" || fail "the placeholder requirement was committed: $(cat "$T/err")"
git -c core.hooksPath=/dev/null commit -q -m "[NEW] Add a file of no stated purpose"
refused rapid land
grep -q 'placeholder' "$T/err" || fail "the placeholder requirement landed: $(cat "$T/err")"
printf '# feature/vague\n\nAdd v.txt so the scenario has a stated purpose.\n' > .rapid/requirements/vague.md
git add .rapid/requirements/vague.md; git commit -q -m "[DOCS] State the requirement of the vague branch"
printf 'x\n' > "$T/body"
refused rapid land -F "$T/body"
grep -q 'merge body' "$T/err" || fail "an unruled merge body landed: $(cat "$T/err")"
: > "$T/empty"
refused rapid land -F "$T/empty"
grep -q 'is empty' "$T/err" || fail "an empty body file gave no reason: $(cat "$T/err")"
printf 'Adds v.txt to the tree.\n\n- One file, v.txt.\n    - v.txt: the stated file.\n' > "$T/body"
rapid land -F "$T/body" >/dev/null || fail "land with a ruled body"
# M5: a landed requirement is never deleted or edited
rapid branch fix drop-req -r "Try to delete a landed requirement." >/dev/null
git rm -q .rapid/requirements/vague.md; git commit -q -m "[FIX] Drop the requirement of the vague branch" -m "Cause: the defect this scenario plants." -m "Fix: the repair this scenario makes."
refused rapid land
grep -q 'never edited or deleted' "$T/err" || fail "deleting a landed requirement landed: $(cat "$T/err")"
git switch -q dev
rapid branch fix edit-req -r "Try to edit a landed requirement." >/dev/null
printf 'changed\n' >> .rapid/requirements/vague.md; git add .rapid/requirements/vague.md
git commit -q -m "[FIX] Edit the requirement of the vague branch" -m "Cause: the defect this scenario plants." -m "Fix: the repair this scenario makes."
refused rapid land
grep -q 'never edited or deleted' "$T/err" || fail "editing a landed requirement landed: $(cat "$T/err")"
git switch -q dev
history_clean
