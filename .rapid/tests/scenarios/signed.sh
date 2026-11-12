#!/usr/bin/env bash
# signed=required, the answer to one person committing under another's address: an unsigned commit is
# refused at commit (commit.gpgsign off), by land and at branch push; signed with a key git verifies, the
# branch lands with a signed merge and a signed version tag, and a hand-made merge of an unsigned commit
# is flagged I4. A policy flip is signed by an admin (keys from .rapid/signers on dev): one under the
# admin's email signed by another key is refused at commit, land and push, and flagged I4.
. "$(dirname "$0")/../lib.sh"
command -v ssh-keygen >/dev/null || fail "ssh-keygen is required for the signing scenario"
mkrepo "$T/r" origin; cd "$T/r"
ssh-keygen -q -t ed25519 -N '' -C agent1@team.test -f "$T/key"
printf 'agent1@team.test %s\n' "$(cat "$T/key.pub")" > "$T/allowed"
git config gpg.format ssh; git config user.signingkey "$T/key.pub"; git config gpg.ssh.allowedSignersFile "$T/allowed"
rapid branch refactor sign -r "Every commit, merge and tag of this repository is signed." >/dev/null
printf 'signed=required\n' >> .rapid/conf; git add .rapid/conf; git commit -q -m "[MODE] Require signed commits"
rapid land >/dev/null || fail "land signed=required"
rapid branch feature unsigned >/dev/null; printf 'u\n' > u.txt; git add u.txt
refused git commit -q -m "[NEW] Add an unsigned file to the project"
grep -q 'commit.gpgsign is not true' "$T/err" || fail "an unsigned commit was accepted: $(cat "$T/err")"
git commit -q --no-verify -m "[NEW] Add an unsigned file to the project"
refused rapid land
grep -q 'is not signed with a key git verifies' "$T/err" || fail "land took an unsigned commit: $(cat "$T/err")"
refused git push -q origin "$(git branch --show-current)"
grep -q 'is not signed' "$T/err" || fail "pre-push let an unsigned commit through: $(cat "$T/err")"
git config commit.gpgsign true
git commit -q --amend --no-edit -S || fail "sign the commit"
rapid land >/dev/null || fail "land a signed branch"
[ "$(git log -1 --format=%G? dev)" = G ] || fail "the merge is not signed: $(git log -1 --format=%G? dev)"
git tag -v "$(git describe --exact-match dev)" >/dev/null 2>&1 || fail "the version tag is not signed"
history_clean
# an email is whatever its author types: under signed=required a policy flip is signed by an admin, the
# signer read with the keys of .rapid/signers on dev. The admin's own flip lands.
ssh-keygen -q -t ed25519 -N '' -C bob@team.test -f "$T/bob"
rapid branch feature signers -r "The signing keys of the team are committed so signers verify against them." >/dev/null
printf 'agent1@team.test %s\nbob@team.test %s\n' "$(cat "$T/key.pub")" "$(cat "$T/bob.pub")" > .rapid/signers
git add .rapid/signers; git commit -q -m "[NEW] Commit the signing keys of the team"
rapid land >/dev/null || fail "land the signers file"
rapid branch refactor cap -r "The admin raises the branch size cap." >/dev/null
sed -i.bak 's/^max_commits=.*/max_commits=30/' .rapid/conf && rm -f .rapid/conf.bak; git add .rapid/conf
git commit -q -m "[MODE] Raise the branch size cap to thirty" || fail "the admin's signed flip was refused at commit"
rapid land >/dev/null || fail "the admin's signed flip did not land"
# Bob is no admin: he types the admin's email and signs with his own key, which his git config trusts
# under that address. Refused at commit, at land, at push; forced onto dev, doctor names it I4.
git config user.signingkey "$T/bob.pub"
printf 'agent1@team.test %s\n' "$(cat "$T/bob.pub")" > "$T/bob-allowed"; git config gpg.ssh.allowedSignersFile "$T/bob-allowed"
rapid branch refactor spoof -r "A flip under the admin's email signed by another key." >/dev/null; lb=$(git branch --show-current)
sed -i.bak 's/^max_commits=.*/max_commits=99/' .rapid/conf && rm -f .rapid/conf.bak; git add .rapid/conf
refused git commit -q -m "[MODE] Raise the branch size cap to ninety"
grep -q "the policy flip is signed by 'bob@team.test': 'bob@team.test' is not an admin" "$T/err" || fail "commit-msg let a non-admin key flip policy under the admin's email: $(cat "$T/err")"
git commit -q --no-verify -m "[MODE] Raise the branch size cap to ninety"
[ "$(git log -1 --format='%ae %G?')" = "agent1@team.test G" ] || fail "the spoofed flip is not what this scenario plants: $(git log -1 --format='%ae %G?')"
refused rapid land
grep -q "the policy flip is signed by 'bob@team.test'" "$T/err" || fail "land let a non-admin key flip policy: $(cat "$T/err")"
refused git push -q origin "$lb"
grep -q "the policy flip is signed by 'bob@team.test'" "$T/err" || fail "pre-push let a non-admin key flip policy: $(cat "$T/err")"
d0=$(git rev-parse dev); v=$(git describe --exact-match dev); v="${v%.*}.$(( ${v##*.} + 1 ))"
m=$(git commit-tree "$(git rev-parse HEAD^{tree})" -p "$d0" -p HEAD -m "[MERGE] $lb into dev: $v

Forced past the hooks.

- Policy flip forced under the admin's email.

Branch-Base: $d0
Requirement: .rapid/requirements/spoof.md
Gates: fast=pass full=pass
Tested-Tree: $(git rev-parse HEAD^{tree})")
git -c tag.gpgsign=false tag -a "$v" -m forced "$m"; git update-ref refs/heads/dev "$m"
rapid doctor --history-only > "$T/doc" 2>&1 && fail "doctor missed the flip signed by a non-admin"
grep -q "^doctor: I4 .*the policy flip is signed by 'bob@team.test'" "$T/doc" || fail "no I4 for the flip signed by a non-admin: $(cat "$T/doc")"
git update-ref refs/heads/dev "$d0"; git tag -d "$v" >/dev/null
git switch -q dev; git branch -q -D "$lb"
[ "$(git show dev:.rapid/conf | sed -n 's/^max_commits=//p')" = 30 ] || fail "the spoofed flip is on dev"
git config user.signingkey "$T/key.pub"; git config gpg.ssh.allowedSignersFile "$T/allowed"
history_clean
git config commit.gpgsign false
git switch -q -c pool/v2026.0/feature.hand dev
printf '# feature/hand\n\nAn unsigned commit merged by hand.\n' > .rapid/requirements/hand.md; git add .rapid/requirements/hand.md
git commit -q --no-verify -m "[NEW] Add an unsigned hand commit"
v=$(git describe --exact-match dev); n=${v##*.}
git switch -q dev; git -c core.hooksPath=/dev/null merge -q --no-ff pool/v2026.0/feature.hand -m "[MERGE] pool/v2026.0/feature.hand into dev: ${v%.*}.$((n + 1))"
rapid doctor --history-only > "$T/doc" 2>&1 && fail "doctor missed the unsigned commit"
grep -q '^doctor: I4 .*is not signed' "$T/doc" || fail "no I4 for the unsigned commit: $(cat "$T/doc")"
