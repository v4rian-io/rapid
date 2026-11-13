#!/usr/bin/env bash
# install: rapid installs once per machine with no copy. install.sh clones rapid with its tags into
# RAPID_HOME (default ~/.rapid) and runs rapid setup --install, which links rapid into a bin directory
# of PATH (~/.local/bin) from wherever the clone stands, baks/ and .rapid-versions/ kept out of the clone's tree by its
# local exclude; a second run changes nothing; rapid runs through
# the link from any directory; with no bin directory on PATH the install is refused by name; a file that
# is no link to a rapid is never replaced; nothing is written outside the clone and the link.
. "$(dirname "$0")/../lib.sh"
# the framework as a repository to install from: a local bare copy, never the network
mkdir -p "$T/src"; cp -R "$RAPID_SRC" "$T/src/.rapid"
( cd "$T/src" && git init -q && git add -- .rapid && git -c gc.auto=0 commit -q --no-verify -m "[NEW] Carry the framework" && git tag -a v2026.0.1 -m v2026.0.1 ) || fail "the source repository"
# a pack transfer, not a copy of loose object files that a background gc may move mid copy
git clone -q --bare --no-local "$T/src" "$T/rapid.git"
# the installer clones the published address: git itself serves it from the local repository here
git config --file "$GIT_CONFIG_GLOBAL" "url.$T/rapid.git.insteadOf" https://github.com/v4rian-io/rapid.git
H="$T/home"; mkdir -p "$H"
inst() { HOME="$H" PATH="$H/.local/bin:$PATH" bash "$RAPID_SRC/install.sh"; }
inst > "$T/out" 2>&1 || fail "the installer: $(cat "$T/out")"
[ -d "$H/.rapid/.git" ] || fail "no clone at the default place: $(cat "$T/out")"
grep -qF "rapid cloned into $H/.rapid" "$T/out" || fail "the installer does not say where it cloned: $(cat "$T/out")"
[ -n "$(git -C "$H/.rapid" tag -l v2026.0.1)" ] || fail "the clone carries no tag"
want="$(cd "$H/.rapid/.rapid" && pwd -P)/rapid"
[ -L "$H/.local/bin/rapid" ] && [ "$(readlink "$H/.local/bin/rapid")" = "$want" ] || fail "rapid is not linked to the clone: $(ls -l "$H/.local/bin" 2>&1)"
grep -qF "$H/.local/bin/rapid" "$T/out" || fail "the install does not say where it linked: $(cat "$T/out")"
grep -Fx baks/ "$H/.rapid/.git/info/exclude" >/dev/null && grep -Fx .rapid-versions/ "$H/.rapid/.git/info/exclude" >/dev/null \
  || fail "the install did not exclude baks/ and .rapid-versions/: $(cat "$H/.rapid/.git/info/exclude" 2>&1)"
# nothing but the clone and the link
[ "$(cd "$H" && find . -path ./.rapid -prune -o -print | LC_ALL=C sort | tr '\n' ' ')" = ". ./.local ./.local/bin ./.local/bin/rapid " ] \
  || fail "the install wrote outside the clone and the link: $(cd "$H" && find . -path ./.rapid -prune -o -print)"
# a second run changes nothing
h0=$(git -C "$H/.rapid" rev-parse HEAD); l0=$(ls -l "$H/.local/bin/rapid")
inst > "$T/out" 2>&1 || fail "the second install: $(cat "$T/out")"
grep -qF "rapid is at $H/.rapid (tags fetched)" "$T/out" || fail "a second install does not say it kept the clone: $(cat "$T/out")"
[ "$(git -C "$H/.rapid" rev-parse HEAD)" = "$h0" ] && [ "$(ls -l "$H/.local/bin/rapid")" = "$l0" ] || fail "a second install changed the clone or the link"
# rapid runs through the link, from any directory
mkdir -p "$T/away"; ( cd "$T/away" && HOME="$H" PATH="$H/.local/bin:$PATH" command rapid --help ) > "$T/help" 2>&1 || fail "rapid through the link: $(cat "$T/help")"
grep -q '^  rapid setup --install' "$T/help" || fail "the linked rapid does not print its usage: $(cat "$T/help")"
# another place, chosen by the user: the link follows
HOME="$H" RAPID_HOME="$T/else where/tool" PATH="$H/.local/bin:$PATH" bash "$RAPID_SRC/install.sh" > "$T/out" 2>&1 || fail "the install to RAPID_HOME: $(cat "$T/out")"
[ "$(readlink "$H/.local/bin/rapid")" = "$(cd "$T/else where/tool/.rapid" && pwd -P)/rapid" ] || fail "the link did not follow RAPID_HOME: $(readlink "$H/.local/bin/rapid")"
# a place that holds something else is refused, untouched
mkdir -p "$T/other"; echo mine > "$T/other/file"
refused env HOME="$H" RAPID_HOME="$T/other" PATH="$H/.local/bin:$PATH" bash "$RAPID_SRC/install.sh"
grep -q 'is not a rapid clone' "$T/err" || fail "a foreign directory was not refused by name: $(cat "$T/err")"
[ "$(cat "$T/other/file")" = mine ] && [ ! -e "$T/other/.git" ] || fail "a foreign directory was written"
# no bin directory on PATH: refused, the PATH line named, nothing written
H2="$T/home2"; mkdir -p "$H2"
refused env HOME="$H2" bash "$RAPID_SRC/rapid" setup --install
grep -q 'is not on PATH' "$T/err" && grep -qF 'export PATH="$HOME/.local/bin:$PATH"' "$T/err" || fail "no clear refusal without a bin directory on PATH: $(cat "$T/err")"
[ -z "$(ls -A "$H2")" ] || fail "a refused install wrote into the home"
# a file that is no link to a rapid stays as it is
H3="$T/home3"; mkdir -p "$H3/.local/bin"; echo mine > "$H3/.local/bin/rapid"
refused env HOME="$H3" PATH="$H3/.local/bin:$PATH" bash "$RAPID_SRC/rapid" setup --install
[ "$(cat "$H3/.local/bin/rapid")" = mine ] || fail "a file of the user was replaced"
rm -f "$H3/.local/bin/rapid"; ln -s /bin/ls "$H3/.local/bin/rapid"
refused env HOME="$H3" PATH="$H3/.local/bin:$PATH" bash "$RAPID_SRC/rapid" setup --install
[ "$(readlink "$H3/.local/bin/rapid")" = /bin/ls ] || fail "a link to another program was replaced"
ok "rapid installs by one clone and one link"
