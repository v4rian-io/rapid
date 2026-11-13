#!/usr/bin/env bash
# version-pin: the installed mode. One rapid installed once (a clone of the framework, on PATH through a symlink) serves a repository whose .rapid holds data only: rapid setup pins by default the newest release tag of the tool in .rapid/version (with no release it says so, naming --pin; rapid setup --pin pins any tag the install holds) and writes hook stubs that run rapid hook, copying no framework file; a commit is checked through the stub; a repository that pins another tag is served by that tag, kept under <clone>/.rapid-versions/<tag>; the upgrade is a branch that changes .rapid/version; a tag the install does not hold is refused, naming the fetch; a repository with its own rapid is never redirected.
. "$(dirname "$0")/../lib.sh"
unset -f rapid
# the install: a clone of the framework holding two version tags; tool two says so in rapid status
export HOME="$T/home"; mkdir -p "$HOME/bin" "$T/tool"
cp -R "$RAPID_SRC" "$T/tool/.rapid"
( cd "$T/tool" && git init -q && git add -- .rapid && git -c core.hooksPath=/dev/null commit -q -m "[NEW] Tool one" && git tag -a v2026.0.1 -m one \
  && sed 's/, last version \${v/, last version by tool two ${v/' .rapid/rapid > "$T/r2" && cat "$T/r2" > .rapid/rapid \
  && git -c core.hooksPath=/dev/null commit -q -a -m "[NEW] Tool two" && git tag -a v2026.0.2 -m two ) || fail "the tool repository was not made"
grep -q 'last version by tool two' "$T/tool/.rapid/rapid" || fail "tool two carries no marker"
ln -s "$T/tool/.rapid/rapid" "$HOME/bin/rapid"; export PATH="$HOME/bin:$PATH"
[ "$(command -v rapid)" = "$HOME/bin/rapid" ] || fail "rapid on PATH is $(command -v rapid)"
# rapid setup in a project: the version pin, hook stubs, no framework file
mkdir "$T/p"; cd "$T/p"; git init -q
# the default pin is the newest release: an install that holds none says so, naming --pin, and nothing is seeded
refused rapid setup
grep -qF "no release to pin by default; use --pin VERSION" "$T/err" || fail "an install with no release was pinned: $(cat "$T/err")"
! git rev-parse -q --verify HEAD >/dev/null && [ ! -e .rapid/version ] || fail "a refused setup seeded or pinned the repository"
git -C "$T/tool" tag -a release/v2026.0.2 -m "rapid release v2026.0.2" || fail "the release tag of the tool"
rapid setup > "$T/out" 2>&1 || fail "setup by the installed rapid: $(cat "$T/out")"
[ "$(cat .rapid/version)" = release/v2026.0.2 ] || fail ".rapid/version holds '$(cat .rapid/version 2>/dev/null)', not the tool's newest release release/v2026.0.2"
[ ! -e .rapid/rapid ] && [ ! -e .rapid/lib ] && [ ! -e .rapid/hooks ] && [ ! -e .rapid/tests ] || fail "setup copied framework files into the repository: $(ls .rapid)"
extra=$(git ls-tree -r --name-only dev | grep -vxE '[.]rapid/(conf|admins|version)' || true)
[ -z "$extra" ] || fail "the seed holds more than data: $extra"
hp=$(git config core.hooksPath)
[ "$hp" = "$(cd .git && pwd -P)/rapid/hooks" ] || fail "core.hooksPath is $hp, not the stubs in the git directory"
for h in commit-msg pre-commit pre-push prepare-commit-msg; do
  [ -x "$hp/$h" ] || fail "no stub for $h"
  grep -qxF "exec rapid hook $h \"\$@\"" "$hp/$h" || fail "the $h stub does not run rapid hook: $(cat "$hp/$h")"
done
# a commit is checked through the stub
rapid branch feature alpha >/dev/null || fail "rapid branch in an installed repository"
printf 'a\n' > a.txt; printf 'true\n' > a_test.sh; git add -- a.txt a_test.sh
if git commit -q -m "bad subject" 2> "$T/err"; then fail "the stub let a bad message pass"; fi
grep -q 'commit-msg: the commit breaks the rules' "$T/err" || fail "the refusal is not the commit-msg hook's: $(cat "$T/err")"
git commit -q -m "[NEW] Add the alpha file to the tree" -m "The alpha file exists in the tree beside its test file." || fail "a good commit was refused"
rapid land > "$T/out" 2>&1 || fail "land in an installed repository: $(cat "$T/out")"
rapid status > "$T/st" || fail "status"
grep -q 'last version by tool two' "$T/st" || fail "the tool at the pinned tag did not serve the repository: $(cat "$T/st")"
[ ! -e "$T/tool/.rapid-versions" ] || fail "a version was prepared though the pin is the tool's own tag"
rapid doctor > "$T/out" 2>&1 || fail "doctor in an installed repository: $(cat "$T/out")"
rapid doctor --history > "$T/out" 2>&1 || fail "doctor --history in an installed repository: $(cat "$T/out")"
# the upgrade is a branch that changes .rapid/version (here to the other tag): its own pin serves
# the branch, from <clone>/.rapid-versions/<tag>, and the clone stays clean
git switch -q dev 2>/dev/null || true
rapid branch refactor pin-one >/dev/null || fail "rapid branch for the pin"
printf 'v2026.0.1\n' > .rapid/version; git add -- .rapid/version
git commit -q -m "[MODE] Pin rapid at its first tag" -m "The repository runs the first tag of rapid from now on." || fail "the pin commit was refused"
rapid status > "$T/st" || fail "status under the other pin"
if grep 'by tool two' "$T/st" >/dev/null; then fail "tool two served a repository that pins v2026.0.1: $(cat "$T/st")"; fi
[ -f "$T/tool/.rapid-versions/v2026.0.1/.rapid/rapid" ] || fail "the pinned version is not kept under the clone"
[ -z "$(git -C "$T/tool" status --porcelain)" ] || fail "the kept version shows in the clone's status: $(git -C "$T/tool" status --porcelain)"
rapid land > "$T/out" 2>&1 || fail "land of the pin branch: $(cat "$T/out")"
[ "$(git show dev:.rapid/version)" = v2026.0.1 ] || fail "dev does not pin v2026.0.1 after the land"
rapid status > "$T/st" || fail "status after the upgrade landed"
if grep 'by tool two' "$T/st" >/dev/null; then fail "after the upgrade landed tool two still serves the repository: $(cat "$T/st")"; fi
rapid doctor --history > "$T/out" 2>&1 || fail "doctor --history after the pin landed: $(cat "$T/out")"
# a tag the install does not hold is refused, naming the fetch; a pin that is no tag is refused too
git switch -q dev 2>/dev/null || true
printf 'v2026.0.9\n' > .rapid/version
refused rapid status
grep -qF "git -C $T/tool fetch --tags" "$T/err" || fail "a missing tag does not name the fetch: $(cat "$T/err")"
printf 'latest\n' > .rapid/version
refused rapid status
grep -q 'not a version tag' "$T/err" || fail "a pin that is no tag passed: $(cat "$T/err")"
git checkout -q -- .rapid/version
# rapid setup --pin names the tag to pin: one the install holds, a version tag included
mkdir "$T/k"; cd "$T/k"; git init -q
refused rapid setup --pin v2026.0.9
grep -qF "v2026.0.9 is not in the installed rapid" "$T/err" || fail "setup --pin of a tag the install lacks is not refused by name: $(cat "$T/err")"
refused rapid setup --pin latest
grep -q 'not a version tag' "$T/err" || fail "setup --pin of a word that is no tag passed: $(cat "$T/err")"
refused rapid setup --pin
grep -q -- '--pin needs a version' "$T/err" || fail "setup --pin without a version passed: $(cat "$T/err")"
[ ! -e .rapid/version ] || fail "a refused setup --pin wrote .rapid/version"
rapid setup --pin v2026.0.1 > "$T/out" 2>&1 || fail "setup --pin v2026.0.1: $(cat "$T/out")"
[ "$(cat .rapid/version)" = v2026.0.1 ] && [ "$(git show dev:.rapid/version)" = v2026.0.1 ] || fail "setup --pin did not pin v2026.0.1: $(cat .rapid/version 2>/dev/null)"
rapid status > "$T/st" || fail "status in the repository setup --pin made"
if grep 'by tool two' "$T/st" >/dev/null; then fail "tool two served a repository pinned at v2026.0.1 by setup --pin: $(cat "$T/st")"; fi
cd "$T/p"
# under signed=required on dev a pin to a tag git cannot verify is refused
mkdir -p "$T/s/.rapid"; ( cd "$T/s" && git init -q && git symbolic-ref HEAD refs/heads/dev && printf 'signed=required\n' > .rapid/conf && printf 'v2026.0.1\n' > .rapid/version \
  && git add -- .rapid && git -c core.hooksPath=/dev/null commit -q -m "[NEW] Seed a signed repository" ) || fail "the signed repository was not made"
( cd "$T/s" && refused rapid status ) || exit 1
grep -qF "$T/tool at v2026.0.1" "$T/err" && grep -qF 'is not signed with a key git verifies (signed=required)' "$T/err" || fail "an unverified pin passed under signed=required: $(cat "$T/err")"
# rapid hook refuses a name that is no hook of rapid
rc=0; rapid hook nope > "$T/out" 2> "$T/err" || rc=$?
[ "$rc" = 2 ] || fail "rapid hook nope exits $rc, not 2"
grep -q 'unknown hook nope' "$T/err" || fail "rapid hook nope: $(cat "$T/err")"
# a repository that carries its own rapid is never redirected, whatever .rapid/version says
selfhosted "$T/v"; cd "$T/v"; printf 'v2026.0.9\n' > .rapid/version
rapid status > "$T/out" 2>&1 || fail "a repository with its own rapid was redirected: $(cat "$T/out")"
ok "an installed rapid serves a repository at the version it pins"
