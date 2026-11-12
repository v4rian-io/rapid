#!/usr/bin/env bash
# fast
# doctor --history reports a planted untagged merge, a stray tag and a
# deleted requirement file by invariant id; --since the root still checks every merge.
# The checkpoint: a clean run records dev's tip in a per-clone note (in the git dir, untracked,
# no ref) and the next run checks in full only the merges after it; a failing run, --since and
# --history-only write no note; --all walks every merge; a recorded merge no longer on dev's
# first-parent line, changed tags, a changed conf or rapid code, or a broken note walk every
# merge and say why; over a 200-merge fixture the default run stays under 60 s.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
rapid branch feature alpha >/dev/null; commit a.txt; rapid land >/dev/null
history_clean
# stray tag off the first-parent line
git switch -q -c side main; echo s > s.txt; git add s.txt; git -c core.hooksPath=/dev/null commit -q -m "[NEW] Add a side commit"
git tag -a v2026.9.9 -m stray side
rapid doctor --history > "$T/doc" 2>&1 && fail "stray tag missed"
grep -q '^doctor: I6 ' "$T/doc" || fail "no I6: $(cat "$T/doc")"
git tag -d v2026.9.9 >/dev/null
# untagged merge made by hand
git switch -q dev; git -c core.hooksPath=/dev/null merge -q --no-ff side -m "[MERGE] pool/v2026.0/feature.side into dev: v2026.0.2"
rapid doctor --history > "$T/doc" 2>&1 && fail "untagged merge missed"
grep -q '^doctor: I2 ' "$T/doc" || fail "no I2: $(cat "$T/doc")"
git reset -q --hard HEAD~1
# requirement deleted after landing
rapid branch refactor cleanup >/dev/null; git rm -q .rapid/requirements/alpha.md; git commit -q -m "[DOCS] Remove a landed requirement file"
refused rapid land
grep -q 'never edited or deleted' "$T/err" || fail "land took a requirement deletion: $(cat "$T/err")"
# planted past land by hand, doctor still finds it
git switch -q dev; git -c core.hooksPath=/dev/null merge -q --no-ff "$(lname cleanup)" -m "[MERGE] pool/v2026.0/refactor.cleanup into dev: v2026.0.9"
rapid doctor --history > "$T/doc" 2>&1 && fail "deleted requirement missed"
grep -q '^doctor: I8 ' "$T/doc" || fail "no I8: $(cat "$T/doc")"
rapid doctor --history-only --since "$(git rev-list --first-parent --max-parents=0 dev)" > "$T/doc" 2>&1 && fail "--since the root checked nothing"
grep -q '^doctor: I2 ' "$T/doc" || fail "the merges after the root went unchecked with --since the root: $(cat "$T/doc")"

# doc_has LINE: the last doctor output holds LINE exactly.
doc_has() { grep -Fx -- "$1" "$T/doc" >/dev/null || fail "no '$1': $(cat "$T/doc")"; }
full_why() { doc_has "doctor: history: every merge in full ($1)"; }

# the checkpoint is written by a clean run, read by the next one, and lives in the git dir only
mkrepo "$T/c"; cd "$T/c"
note="$(git rev-parse --git-common-dir)/rapid-history-verified"
rapid branch feature alpha >/dev/null; commit a.txt; rapid land >/dev/null
rapid doctor --history > "$T/doc" 2>&1 || fail "clean history: $(cat "$T/doc")"
full_why "no merge verified by this clone yet"
[ "$(sed -n 's/^merge=//p' "$note")" = "$(git rev-parse dev)" ] || fail "the clean run recorded no checkpoint at dev's tip"
st=$(git status --porcelain --ignored | grep -vx '!! .rapid/admins' || true); [ -z "$st" ] || fail "the checkpoint shows in the work tree: $st"
if git for-each-ref --format='%(refname)' | grep -i 'history' >/dev/null; then fail "the checkpoint is a ref"; fi
rapid branch feature beta >/dev/null; commit b.txt; rapid land >/dev/null
rapid doctor --history > "$T/doc" 2>&1 || fail "checkpointed run: $(cat "$T/doc")"
doc_has "doctor: history: merges after v2026.0.1 in full, the ones up to it verified by this clone (--all walks every merge)"
[ "$(sed -n 's/^merge=//p' "$note")" = "$(git rev-parse dev)" ] || fail "the checkpoint did not move to the new tip"
rapid doctor --history --all > "$T/doc" 2>&1 || fail "--all: $(cat "$T/doc")"
full_why "--all"
refused rapid doctor --all
grep -q 'goes with --history' "$T/err" || fail "--all alone: $(cat "$T/err")"
# a failing run keeps the last good checkpoint; the violation after it is still found
good=$(cat "$note")
git switch -q -c side2 dev; echo s > s2.txt; git add s2.txt; git -c core.hooksPath=/dev/null commit -q -m "[NEW] Add a second side commit"
git switch -q dev; git -c core.hooksPath=/dev/null merge -q --no-ff side2 -m "[MERGE] pool/v2026.0/feature.side2 into dev: v2026.0.3"
rapid doctor --history > "$T/doc" 2>&1 && fail "untagged merge after the checkpoint missed"
grep -q '^doctor: I2 ' "$T/doc" || fail "no I2 after the checkpoint: $(cat "$T/doc")"
[ "$(cat "$note")" = "$good" ] || fail "a failing run rewrote the checkpoint"
git reset -q --hard HEAD~1; git branch -q -D side2
# --since and --history-only neither read nor write the note
rm -f "$note"
rapid doctor --history --since "$(git rev-list --first-parent --max-parents=0 dev)" > "$T/doc" 2>&1 || fail "--since: $(cat "$T/doc")"
rapid doctor --history-only > "$T/doc" 2>&1 || fail "--history-only: $(cat "$T/doc")"
[ ! -e "$note" ] || fail "--since or --history-only wrote the checkpoint"
rapid doctor --history > "$T/doc" 2>&1 || fail "re-record: $(cat "$T/doc")"
full_why "no merge verified by this clone yet"
# the verifier's config or code changed: every merge again, then trusted under the new verifier
printf '# a comment the verifier reads\n' >> .rapid/conf
rapid doctor --history > "$T/doc" 2>&1 || fail "conf change: $(cat "$T/doc")"
full_why "the verifier's code or config changed since the recorded run"
rapid doctor --history > "$T/doc" 2>&1 || fail "after conf change: $(cat "$T/doc")"
doc_has "doctor: history: merges after v2026.0.2 in full, the ones up to it verified by this clone (--all walks every merge)"
git checkout -q -- .rapid/conf
rapid doctor --history >/dev/null 2>&1 || fail "back to the committed verifier"
# the verifier's code changed: in a repository that carries rapid itself (the framework's own) a changed
# checker walks every merge again
( selfhosted "$T/s"; cd "$T/s"
  rapid branch feature one >/dev/null; commit one.txt; rapid land >/dev/null || fail "land in the self-hosted repository"
  rapid doctor --history >/dev/null 2>&1 || fail "the first record in the self-hosted repository"
  rapid doctor --history > "$T/doc" 2>&1 || fail "the second walk in the self-hosted repository: $(cat "$T/doc")"
  doc_has "doctor: history: merges after v2026.0.1 in full, the ones up to it verified by this clone (--all walks every merge)"
  printf '\n# a changed checker\n' >> .rapid/lib/version.sh
  rapid doctor --history > "$T/doc" 2>&1 || fail "code change: $(cat "$T/doc")"
  full_why "the verifier's code or config changed since the recorded run" ) || exit 1
# a version tag up to the checkpoint was replaced
git tag -d v2026.0.1 >/dev/null; git tag -a v2026.0.1 -m "v2026.0.1 again" dev^1
rapid doctor --history > "$T/doc" 2>&1 || fail "replaced tag: $(cat "$T/doc")"
full_why "the version or release tags up to the recorded merge changed"
# dev no longer holds the recorded merge
gone=$(git rev-parse --short dev)
git tag -d v2026.0.2 >/dev/null; git reset -q --hard dev^1
rapid doctor --history > "$T/doc" 2>&1 || fail "moved dev: $(cat "$T/doc")"
full_why "the recorded merge $gone is no longer on dev's first-parent line"
# a broken note is never trusted
printf 'junk\n' > "$note"
rapid doctor --history > "$T/doc" 2>&1 || fail "broken note: $(cat "$T/doc")"
full_why "the checkpoint note names no commit"

# 200 merges: the default run after one new land stays under 60 s. The full walk over 200
# merges takes minutes, so the checkpoint a clean run would leave is written by the same
# function doctor calls after one (rapid_history_record).
mkrepo "$T/big"; cd "$T/big"
rapid branch feature alpha >/dev/null; commit a.txt; rapid land >/dev/null
fixture_merges 200
[ "$(git rev-list --first-parent --merges --count dev)" = 201 ] || fail "the fixture holds $(git rev-list --first-parent --merges --count dev) merges"
( RAPID_SELF="$RAPID_SRC"; . "$RAPID_SRC/lib/core.sh"; . "$RAPID_SRC/lib/history.sh"; rapid_history_record dev )
rapid branch feature omega >/dev/null; commit o.txt; rapid land >/dev/null || fail "land on the 201-merge history"
t0=$(date +%s)
rapid doctor --history > "$T/doc" 2>&1 || fail "default run over 202 merges: $(cat "$T/doc")"
t=$(( $(date +%s) - t0 ))
doc_has "doctor: history: merges after v2026.0.201 in full, the ones up to it verified by this clone (--all walks every merge)"
# the bound sits far below a full walk (minutes) and far above a loaded machine's resume
[ "$t" -le 60 ] || fail "the default run over 202 merges took ${t} s (bound 60 s)"
