#!/usr/bin/env bash
# fast
# no personal data in tracked files: a home path and a real email address fail the lint by
# file and line; placeholder paths and reserved-domain addresses pass; untracked files are ignored.
# .rapid/admins at the repository root is the one file exempt from the email rule, and only from it:
# the same address in a copy of it under another name or directory is refused, and a home path in
# it is refused as anywhere else.
. "$(dirname "$0")/../lib.sh"
lint="$RAPID_SRC/lint/personal.sh"
mkdir -p "$T/r"; cd "$T/r"; git init -q
u="Us""ers"
printf 'see /%s/someone/project for the notes\n' "$u" > notes.txt
printf 'contact someone@gmail''.com\n' > contact.txt
printf 'see <workspace>/project, mail team@lab.test or bot@users.noreply.github.com\n' > ok.txt
printf 'private /%s/someone/x\n' "$u" > untracked.txt
git add notes.txt contact.txt ok.txt
refused bash "$lint"
grep -q 'notes.txt:1' "$T/out" || fail "the home path is not named: $(cat "$T/out")"
grep -q 'contact.txt:1' "$T/out" || fail "the email is not named: $(cat "$T/out")"
! grep -q 'ok.txt\|untracked.txt' "$T/out" || fail "a placeholder or untracked file was flagged: $(cat "$T/out")"
git rm -q --cached notes.txt contact.txt
bash "$lint" >/dev/null || fail "a clean tree failed the lint"
# .rapid/admins at the root is the one place an address belongs
d="owner-domain.i""o"; addr="first@$d"
mkdir -p .rapid docs sub/.rapid
for f in .rapid/admins .rapid/admins.bak sub/.rapid/admins docs/admins; do printf '%s\n' "$addr" > "$f"; done
printf 'owner: %s\n' "$addr" > notes2.txt
git add .rapid docs sub notes2.txt
refused bash "$lint"
for f in .rapid/admins.bak sub/.rapid/admins docs/admins; do
  grep -qF "personal email: $f:1: $addr" "$T/out" || fail "the address in $f was not refused: $(cat "$T/out")"
done
grep -qF "personal email: notes2.txt:1: $addr" "$T/out" || fail "the address in notes2.txt was not refused: $(cat "$T/out")"
! grep -qF 'email: .rapid/admins:' "$T/out" || fail "the admins file's own line was refused: $(cat "$T/out")"
git rm -q --cached .rapid/admins.bak docs/admins sub/.rapid/admins notes2.txt
bash "$lint" > "$T/out" 2>&1 || fail "the admins file alone failed the lint: $(cat "$T/out")"
bash "$lint" ./.rapid/admins > "$T/out" 2>&1 || fail "the admins named as ./.rapid/admins failed: $(cat "$T/out")"
( cd .rapid && bash "$lint" admins ) > "$T/out" 2>&1 || fail "the admins named from .rapid/ failed: $(cat "$T/out")"
# the exemption is the email rule only: a home path in the admins is still refused
printf '# notes in /%s/someone/x\n' "$u" >> .rapid/admins
refused bash "$lint"
grep -qF 'personal path: .rapid/admins:2' "$T/out" || fail "a home path in the admins passed: $(cat "$T/out")"
