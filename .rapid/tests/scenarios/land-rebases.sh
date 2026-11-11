#!/usr/bin/env bash
# fast
# land-rebases: four branches forked from the same dev land in one command (rapid land BRANCH...): land
# rebases each stale branch onto dev itself behind a preflight ref; the third conflicts with the first,
# so it is left exactly as it was, named with its conflicting file, land_on_conflict starts on it,
# and the exit is 4, while the second and the fourth still land.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
for s in one two three four; do
  git switch -q dev; rapid branch feature "$s" >/dev/null
  case "$s" in
    one|three) commit shared.txt "$s" "[NEW] Write the shared file from branch $s" ;;
    *) commit "$s.txt" ;;
  esac
done
three=$(lname three); t3=$(git rev-parse "$three")
d0=$(git rev-parse dev)
rc=0; RAPID_LAND_ON_CONFLICT="printf '%s\n' \"\$1\" > '$T/fired.tmp'; cat \"\$2\" >> '$T/fired.tmp'; mv '$T/fired.tmp' '$T/fired'" \
  rapid land one two three four >"$T/out" 2>"$T/err" || rc=$?
[ "$rc" = 4 ] || fail "a list with one conflict exits $rc, want 4: $(cat "$T/err")"
grep -qF "$three conflicts with dev" "$T/err" && grep -qF 'shared.txt' "$T/err" || fail "the conflicting branch or file is not named: $(cat "$T/err")"
grep -qF "left on a conflict: $three" "$T/out" || fail "the summary does not name the branch left on its conflict: $(cat "$T/out")"
[ "$(git rev-list --first-parent --count "$d0..dev")" = 3 ] || fail "dev took $(git rev-list --first-parent --count "$d0..dev") merges, want 3"
[ "$(git log --first-parent --format=%s dev | grep -cE '^\[MERGE\] pool/[^ ]*[.]feature[.](one|two|four) into dev')" = 3 ] || fail "one, two and four did not all land"
[ "$(git rev-parse "$three")" = "$t3" ] || fail "the conflicting branch was not left as it was"
[ -n "$(git for-each-ref --format=x refs/rapid/preflight/four)" ] || fail "no preflight ref before the rebase of four"
i=0; while [ ! -f "$T/fired" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
[ "$(sed -n 1p "$T/fired" 2>/dev/null)" = "$three" ] && grep -qx 'shared.txt' "$T/fired" || fail "land_on_conflict did not fire with the branch and its files: $(cat "$T/fired" 2>/dev/null)"
history_clean
