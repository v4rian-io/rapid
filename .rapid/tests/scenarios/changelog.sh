#!/usr/bin/env bash
# rapid changelog generates the changelog from history: the landed merges up to a hash (default dev's
# tip), after --from a hash, grouped by the release that first shipped them and Unreleased above the
# last release, newest first, one line per merge with its version, kind/name and the first paragraph of
# its requirement; the output is byte-identical on a second run and no CHANGELOG.md is written.
. "$(dirname "$0")/../lib.sh"
actor "Owner One" owner@team.test
mkrepo "$T/r"; cd "$T/r"
rapid branch feature export -r "Reports export to CSV files." >/dev/null; commit export.txt; rapid land >/dev/null || fail "land export"
rapid branch fix crlf -r "Exports end lines with CRLF." >/dev/null; commit crlf.txt; rapid land >/dev/null || fail "land crlf"
rapid release >/dev/null 2>&1 || fail "release"
rapid branch feature import -r "Reports import from CSV files." >/dev/null; commit import.txt; rapid land >/dev/null || fail "land import"
d=$(git rev-parse --short=12 dev); m2=$(git rev-parse --short=12 v2026.0.2^{commit}); m1=$(git rev-parse --short=12 v2026.0.1^{commit})
rapid changelog > "$T/all" || fail "rapid changelog"
printf '%s\n' "# Changelog up to v2026.1.1 ($d)" "" "## Unreleased" "" \
  "- v2026.1.1 feature/import: Reports import from CSV files." "" "## release/v2026.0.2" "" \
  "- v2026.0.2 fix/crlf: Exports end lines with CRLF." "- v2026.0.1 feature/export: Reports export to CSV files." > "$T/want"
diff -u "$T/want" "$T/all" >&2 || fail "the changelog is not the expected text"
rapid changelog > "$T/again"; cmp -s "$T/all" "$T/again" || fail "a second run differs"
# up to a hash
rapid changelog "$m2" > "$T/upto"
printf '%s\n' "# Changelog up to v2026.0.2 ($m2)" "" "## release/v2026.0.2" "" \
  "- v2026.0.2 fix/crlf: Exports end lines with CRLF." "- v2026.0.1 feature/export: Reports export to CSV files." > "$T/want"
diff -u "$T/want" "$T/upto" >&2 || fail "the changelog up to a hash is wrong"
# after --from a hash
rapid changelog --from "$m1" > "$T/from"
printf '%s\n' "# Changelog up to v2026.1.1 ($d), after v2026.0.1 ($m1)" "" "## Unreleased" "" \
  "- v2026.1.1 feature/import: Reports import from CSV files." "" "## release/v2026.0.2" "" \
  "- v2026.0.2 fix/crlf: Exports end lines with CRLF." > "$T/want"
diff -u "$T/want" "$T/from" >&2 || fail "the changelog after --from is wrong"
refused rapid changelog --from "$d" "$m1"
grep -q 'is not an ancestor' "$T/err" || fail "a --from after the end was not refused: $(cat "$T/err")"
[ ! -e CHANGELOG.md ] && [ -z "$(git ls-files CHANGELOG.md)" ] || fail "a CHANGELOG.md was written"
[ -z "$(git status --porcelain)" ] || fail "rapid changelog changed the work tree"
history_clean
