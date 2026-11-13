#!/usr/bin/env bash
# release identity: with release_build, rapid release builds the artifacts on the released tree,
# labeled <version>-<sha>, audits them for debug output (also inside a tarball) and runs
# gates_artifact; a failing build, no artifact, an unlabeled name, a debug artifact, a build that
# edits a tracked file or a failing artifact gate refuses the release with main and tags unchanged.
# The release tag lists each artifact's sha256; release_publish and the forge's release object (gh
# stub) ship exactly those bytes, and rapid release --publish reships them after a failed channel,
# refusing a file that no longer matches the manifest; with no version named and none on dev it is a usage error.
. "$(dirname "$0")/../lib.sh"
actor "Owner One" owner@team.test
mkrepo "$T/r" origin; cd "$T/r"
P="$T/forge"; mkdir -p "$P/shipped" "$T/bin"
cat > "$T/bin/gh" <<STUB
#!/bin/sh
echo "\$*" >> "$P/gh.log"
[ -f "$P/fail" ] && exit 1
case "\$1 \$2" in
  "release view") exit 1 ;;
  "release create"|"release upload") for a in "\$@"; do [ -f "\$a" ] && case "\$a" in *notes*) cp "\$a" "$P/notes" ;; *) cp "\$a" "$P/shipped/" ;; esac; done; exit 0 ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$T/bin/gh"; export PATH="$T/bin:$PATH"
rapid branch refactor build-script -r "The project's release build and its own artifact check." >/dev/null
cat > build.sh <<'B'
#!/bin/sh
# the release build: one tarball, labeled; BAD_BUILD selects a broken variant
set -e
w=$(mktemp -d "${TMPDIR:-/tmp}/build.XXXXXX"); trap 'rm -rf "$w"' EXIT
echo "app $RAPID_VERSION $BUILD_TYPE" > "$w/app.js"
case "$(cat build.mode 2>/dev/null)" in
  fail) exit 3 ;;
  none) exit 0 ;;
  unlabeled) cp "$w/app.js" "$RAPID_ARTIFACTS/app.js" ;;
  map) echo '{}' > "$w/app.js.map" ;;
  debugger) echo 'debugger;' >> "$w/app.js" ;;
  dirty) echo touched >> check.sh ;;
esac
tar -czf "$RAPID_ARTIFACTS/app-$RAPID_LABEL.tar.gz" -C "$w" .
B
printf '#!/bin/sh\n# the artifact gate: every artifact is a non-empty tarball\nfor f in "$RAPID_ARTIFACTS"/*; do tar -tzf "$f" >/dev/null || exit 1; done\n[ ! -f artifact.block ]\n' > artifact-check.sh
git add build.sh artifact-check.sh; git commit -q -m "[NEW] Add the release build scripts"
rapid land >/dev/null || fail "land the build"
rapid branch refactor release-conf -r "Releases build, gate and ship their artifacts." >/dev/null
printf 'release_build=sh build.sh\ngates_artifact=sh artifact-check.sh\nrelease_publish=cp "$RAPID_ARTIFACTS"/* %s/channel/\nforge_repo=acme/app\n' "$T" >> .rapid/conf
mkdir -p "$T/channel"
git add .rapid/conf; git commit -q -m "[MODE] Ship the release artifacts"
rapid land >/dev/null || fail "land the release conf"
# each broken build refuses the release; main and the tags stay
main0=$(git rev-parse main)
for mode in fail none unlabeled map debugger dirty block; do
  rapid branch refactor "mode-$mode" -r "Release build mode $mode." >/dev/null
  if [ "$mode" = block ]; then commit artifact.block x "[NEW] Block the artifact gate"; else commit build.mode "$mode" "[NEW] Set the release build mode to $mode"; fi
  rapid land >/dev/null || fail "land mode $mode"
  refused rapid release
  case "$mode" in
    fail) want='release_build fails' ;; none) want='wrote no artifact' ;; unlabeled) want='is not labeled' ;;
    map) want='source map' ;; debugger) want='debugger; statement' ;; dirty) want='changed tracked files' ;; block) want='gates_artifact fails' ;;
  esac
  grep -q "$want" "$T/err" || fail "mode $mode was not refused with '$want': $(cat "$T/err")"
  [ "$(git rev-parse main)" = "$main0" ] && [ -z "$(git tag -l 'release/*')" ] || fail "a refused release ($mode) moved main or tagged"
  rapid branch refactor "unmode-$mode" -r "Back to the clean build after $mode." >/dev/null
  if [ "$mode" = block ]; then git rm -q artifact.block; else git rm -q build.mode; fi
  git commit -q -m "[NEW] Restore the clean release build after $mode"
  rapid land >/dev/null || fail "land unmode $mode"
done
# a clean release: built on the tag, listed in it, shipped as the same bytes
rapid release > "$T/out" 2>&1 || fail "release: $(cat "$T/out")"
v=$(git describe --exact-match --match 'v*' dev); short=$(git rev-parse --short dev); name="app-$v-$short.tar.gz"
msg=$(git cat-file -p "release/$v")
sum=$(sed -nE "s/^Artifact: ([0-9a-f]{64}) $name$/\1/p" <<<"$msg")
[ -n "$sum" ] || fail "the release tag lists no $name: $msg"
grep -q '^Gates: release=pass artifact=pass$' <<<"$msg" || fail "no artifact gate test record: $msg"
tar -xzOf "$(git rev-parse --git-common-dir)/rapid-artifacts/$v/$name" ./app.js | grep -Fx "app $v release" >/dev/null || fail "the artifact was not built on the tag in release mode"
for f in "$T/channel/$name" "$P/shipped/$name"; do
  [ "$(shasum -a 256 "$f" | cut -d' ' -f1)" = "$sum" ] || fail "$f is not the gated artifact"
done
grep -q "^release create release/$v .* --repo acme/app --verify-tag --title $v --notes-file" "$P/gh.log" || fail "no release object: $(cat "$P/gh.log")"
grep -q "^Artifact: $sum $name$" "$P/notes" || fail "the release object's notes lack the manifest"
# a failed channel is reshipped by --publish with the same bytes; a tampered file is refused
: > "$P/gh.log"; rm -rf "$P/shipped"; mkdir -p "$P/shipped"
rapid release --publish "$v" > "$T/out" 2>&1 || fail "release --publish: $(cat "$T/out")"
[ "$(shasum -a 256 "$P/shipped/$name" | cut -d' ' -f1)" = "$sum" ] || fail "--publish shipped other bytes"
echo tampered >> "$(git rev-parse --git-common-dir)/rapid-artifacts/$v/$name"
refused rapid release --publish "$v"
grep -q "does not match release/$v's manifest" "$T/err" || fail "a tampered artifact was shipped: $(cat "$T/err")"
history_clean
# --publish with no version named and none on dev yet: a usage error, never a release called "-"
mkrepo "$T/nv"; cd "$T/nv"
rc=0; command rapid release --publish > "$T/out" 2> "$T/err" || rc=$?
[ "$rc" = 2 ] || fail "release --publish with no version exits $rc, not 2: $(cat "$T/err")"
grep -q '^X rapid: usage: rapid release --publish \[VERSION\]' "$T/err" || fail "release --publish with no version gave no usage: $(cat "$T/err")"
! grep -F 'release/-' "$T/err" >/dev/null || fail "release --publish named a release called -: $(cat "$T/err")"
