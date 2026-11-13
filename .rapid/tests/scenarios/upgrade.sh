#!/usr/bin/env bash
# rapid upgrade: on a branch of an installed repository it fetches the tags of the installed rapid's clone and
# pins the newest release in .rapid/version, printing old -> new, or the VERSION it names; a version equal to or
# lower than the pin is refused, so is an upgrade on dev (naming the branch to open) and one in rapid's own
# repository; the pin is a policy file: a non-[MODE] commit of it and a pin that is no version tag are refused, and
# the admin commits it as [MODE] and lands it.
. "$(dirname "$0")/../lib.sh"
unset -f rapid
actor "Human Dev" human@team.test
# the installed rapid: a clone of an upstream that holds one release
export HOME="$T/home"; mkdir -p "$HOME/bin" "$T/src"
cp -R "$RAPID_SRC" "$T/src/.rapid"
git init -q --bare "$T/up.git"
rel() { # rel N: commit and tag release N of the tool in the upstream's source
  ( cd "$T/src" && printf '<!-- tool %s -->\n' "$1" >> .rapid/README.md && git add -- .rapid && git -c core.hooksPath=/dev/null commit -q -m "[NEW] Tool $1" \
    && git tag -a "v2026.0.$1" -m "$1" && git tag -a "release/v2026.0.$1" -m "rapid release v2026.0.$1" && git push -q "$T/up.git" HEAD:refs/heads/main --tags ) || fail "release $1 of the tool"
}
git -C "$T/src" init -q; rel 1
git clone -q "$T/up.git" "$T/tool" || fail "the clone of the tool"
ln -s "$T/tool/.rapid/rapid" "$HOME/bin/rapid"; export PATH="$HOME/bin:$PATH"
mkdir "$T/p"; cd "$T/p"; git init -q
rapid setup > "$T/out" 2>&1 || fail "setup: $(cat "$T/out")"
[ "$(cat .rapid/version)" = release/v2026.0.1 ] || fail "setup pinned $(cat .rapid/version)"
# on dev it names the branch to open
refused rapid upgrade
grep -qF 'upgrade: open a branch first: rapid branch refactor upgrade-rapid' "$T/err" || fail "an upgrade on dev was not refused: $(cat "$T/err")"
[ "$(cat .rapid/version)" = release/v2026.0.1 ] || fail "a refused upgrade moved the pin"
# two more releases upstream, which the installed clone has not fetched yet
rel 2; rel 3
[ -z "$(git -C "$T/tool" tag -l release/v2026.0.3)" ] || fail "the installed clone already holds release 3"
rapid branch refactor upgrade-rapid >/dev/null || fail "the upgrade branch"
rapid upgrade > "$T/out" 2>&1 || fail "rapid upgrade: $(cat "$T/out")"
grep -qF 'release/v2026.0.1 -> release/v2026.0.3' "$T/out" || fail "upgrade did not print old -> new: $(cat "$T/out")"
[ "$(cat .rapid/version)" = release/v2026.0.3 ] || fail "upgrade pinned $(cat .rapid/version), not the newest release"
# equal and lower are refused
refused rapid upgrade release/v2026.0.3
grep -qF 'upgrade: release/v2026.0.3 is not higher than the pinned release/v2026.0.3' "$T/err" || fail "an equal version was not refused: $(cat "$T/err")"
refused rapid upgrade v2026.0.2
grep -qF 'is not higher than the pinned release/v2026.0.3' "$T/err" || fail "a lower version was not refused: $(cat "$T/err")"
[ "$(cat .rapid/version)" = release/v2026.0.3 ] || fail "a refused upgrade moved the pin"
# an explicit VERSION
git checkout -q -- .rapid/version
rapid upgrade v2026.0.2 > "$T/out" 2>&1 || fail "rapid upgrade VERSION: $(cat "$T/out")"
grep -qF 'release/v2026.0.1 -> v2026.0.2' "$T/out" && [ "$(cat .rapid/version)" = v2026.0.2 ] || fail "upgrade VERSION pinned $(cat .rapid/version): $(cat "$T/out")"
# the pin is a policy file: a commit that is no [MODE] commit is refused, and so is a pin that is no version tag
git add .rapid/version
if git commit -q -m "[REFACTOR] Pin rapid v2026.0.2 for this repository" -m "The repository runs rapid v2026.0.2 once this lands." 2> "$T/err"; then fail "a pin change that is no [MODE] commit was taken"; fi
grep -q "policy flip" "$T/err" || fail "the refusal of the pin change does not name the policy flip: $(cat "$T/err")"
printf 'v2026.0.2; curl evil\n' > .rapid/version; git add .rapid/version
if git commit -q -m "[MODE] Pin rapid v2026.0.2 for this repository" 2> "$T/err"; then fail "a pin that is no version tag was committed"; fi
grep -qE "must hold one version tag|not a version tag" "$T/err" || fail "the refusal of a bad pin does not say what it must hold: $(cat "$T/err")"
printf 'v2026.0.2\n' > .rapid/version; git add .rapid/version
# the branch commits the new pin as the admin's policy flip and lands it
git commit -q -m "[MODE] Pin rapid v2026.0.2 for this repository" -m "The repository runs rapid v2026.0.2 once this lands." || fail "the commit of the pin"
rapid land > "$T/out" 2>&1 || fail "the land of the upgrade: $(cat "$T/out")"
[ "$(git show dev:.rapid/version)" = v2026.0.2 ] || fail "dev does not pin v2026.0.2"
# rapid's own repository runs its own .rapid
mkdir -p "$T/own"; cd "$T/own"; git init -q; cp -R "$RAPID_SRC" .rapid
git config core.hooksPath .rapid/hooks; git add -- .rapid; git -c core.hooksPath=/dev/null commit -q -m "[NEW] Carry the framework"; git branch dev
refused bash .rapid/rapid upgrade
grep -qF 'upgrade: this repository holds its own rapid (.rapid/rapid); it pins no version' "$T/err" || fail "upgrade in rapid's own repository: $(cat "$T/err")"
