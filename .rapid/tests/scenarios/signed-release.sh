#!/usr/bin/env bash
# promotion is verifiable under signed=required: rapid release signs the release tag with the owner's
# key; a release under the owner's email signed by another key (checked against .rapid/signers at main)
# or with no key at all is refused, so is a hand-made unsigned release tag at pre-push and by I5; and
# the agent guard denies rapid release run as a renamed copy, a link or a shell's script.
. "$(dirname "$0")/../lib.sh"
command -v ssh-keygen >/dev/null || fail "ssh-keygen is required for the signing scenario"
command -v python3 >/dev/null || fail "python3 is required by the agent guard"
mkrepo "$T/r" origin; cd "$T/r"
ssh-keygen -q -t ed25519 -N '' -C agent1@team.test -f "$T/owner"
ssh-keygen -q -t ed25519 -N '' -C bob@team.test -f "$T/bob"
printf 'agent1@team.test %s\n' "$(cat "$T/owner.pub")" > "$T/allowed"
git config gpg.format ssh; git config user.signingkey "$T/owner.pub"; git config gpg.ssh.allowedSignersFile "$T/allowed"
git config commit.gpgsign true
rapid branch refactor sign -r "Every commit, merge, version tag and release tag of this repository is signed." >/dev/null
printf 'signed=required\n' >> .rapid/conf; git add .rapid/conf; git commit -q -m "[MODE] Require signatures on every commit"
rapid land >/dev/null || fail "land signed=required"
rapid branch feature signers -r "The owner's release key is committed so releases verify against it." >/dev/null
cp "$T/allowed" .rapid/signers; git add .rapid/signers; git commit -q -m "[NEW] Commit the owner's release signing key"
rapid land >/dev/null || fail "land the signers file"
# the owner's release: a signed tag whose signer is the owner, pushed through pre-push
rapid release > "$T/rel" 2>&1 || fail "the owner's signed release: $(cat "$T/rel")"
v=$(git describe --exact-match --match 'v*' dev); t="release/$v"
[ "$(git cat-file -t "$t")" = tag ] || fail "no annotated release tag"
git verify-tag "$t" >/dev/null 2>&1 || fail "the release tag is not signed"
om=$(git ls-remote origin refs/heads/main | cut -f1); git fetch -q origin main 2>/dev/null || true
[ "$(git rev-parse "$om^2" 2>/dev/null)" = "$(git rev-parse dev)" ] || fail "origin's main did not take the release merge of dev"
history_clean
rapid branch feature more >/dev/null; commit m.txt; rapid land >/dev/null || fail "land after the release"
# Bob, under the owner's email, signs with his own key his git config trusts: .rapid/signers at main rules
git config user.signingkey "$T/bob.pub"
printf 'agent1@team.test %s\n' "$(cat "$T/bob.pub")" > "$T/bob-allowed"; git config gpg.ssh.allowedSignersFile "$T/bob-allowed"
m0=$(git rev-parse main)
refused rapid release
grep -q 'carries no signature git verifies against .rapid/signers at main' "$T/err" || fail "a foreign key released as the owner: $(cat "$T/err")"
[ "$(git rev-parse main)" = "$m0" ] && [ -z "$(git tag -l "release/$(git describe --exact-match --match 'v*' dev)")" ] || fail "the refused release left a trace"
# no signing key at all: refused before anything moves
git config --unset user.signingkey
refused rapid release
grep -q 'could not make the release tag' "$T/err" || fail "a release without a key went through: $(cat "$T/err")"
git config user.signingkey "$T/owner.pub"; git config gpg.ssh.allowedSignersFile "$T/allowed"
# a hand-made unsigned release tag: pre-push refuses it with main, and I5 names it
v2=$(git describe --exact-match --match 'v*' dev)
git -c tag.gpgsign=false tag -a "release/$v2" -m "hand release" dev
refused git push -q --atomic origin dev:refs/heads/main "refs/tags/release/$v2"
grep -q 'carries no signature' "$T/err" || fail "pre-push let an unsigned release tag through: $(cat "$T/err")"
rapid doctor --history-only > "$T/doc" 2>&1 && fail "doctor missed the unsigned release tag"
grep -q "^doctor: I5 .*release/$v2 carries no signature" "$T/doc" || fail "no I5 for the unsigned release tag: $(cat "$T/doc")"
git tag -d "release/$v2" >/dev/null
history_clean
# the agent guard: rapid release however the program is named
A="$TOOL/agent"
guard() { python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$T/r" | "$A/guard-destructive.sh"; }
mkdir -p "$T/x"; cp -R "$TOOL" "$T/x/fw"; mv "$T/x/fw/rapid" "$T/x/fw/n"; cp "$T/x/fw/n" "$T/x/solo"; ln -s "$TOOL/rapid" "$T/x/rel"
for c in "$T/x/fw/n release" "$T/x/solo release" "$T/x/rel release" "bash $T/x/fw/n release" "GIT_AUTHOR_EMAIL=agent1@team.test $T/x/rel release"; do
  out=$(guard "$c"); grep -q 'rapid release blocked' <<<"$out" || fail "the guard allowed: $c: $out"
done
out=$(guard "$T/x/rel release --dry-run"); [ -z "$out" ] || fail "the guard denied a dry run: $out"
