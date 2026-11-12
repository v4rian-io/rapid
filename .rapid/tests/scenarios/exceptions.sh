#!/usr/bin/env bash
# one command shows every exception: doctor --history (and --history-only) lists, by kind, the
# versions of the merges carrying Untested: (land copies it from the requirement) or Docs: none, and
# of the merges that ran no gate, while history stays ok.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
rapid branch refactor rules -r "Tie the src files of this project to its docs." >/dev/null
printf 'docs_rules=src/*=docs/*\n' >> .rapid/conf; git add .rapid/conf; git commit -q -m "[MODE] Tie src to docs"
rapid land >/dev/null || fail "land the rules"
rapid branch feature spike -r "Try the renderer.

Untested: a throwaway spike removed next sprint" >/dev/null
commit spike.txt; rapid land >/dev/null || fail "land an untested branch"
rapid branch feature src -r "Touch src without its docs.

Docs: none (an internal rename)" >/dev/null
mkdir -p src; printf 's\n' > src/a.txt; git add src/a.txt; git commit -q -m "[NEW] Rename the internal source file"
rapid land >/dev/null || fail "land Docs: none"
rapid branch refactor silent -r "Land under gates_full=none." >/dev/null
sed -i.bak 's/^gates_full=.*/gates_full=none/; s/^gates_fast=.*/gates_fast=/' .rapid/conf && rm -f .rapid/conf.bak; git add .rapid/conf
git commit -q -m "[MODE] Run no full gate"
rapid land >/dev/null 2>&1 || fail "land gates_full=none"
rapid branch feature after >/dev/null; commit after.txt; rapid land >/dev/null 2>&1 || fail "land without gates"
rapid doctor --history > "$T/out" 2>&1 || fail "doctor --history: $(cat "$T/out")"
grep -q '^doctor: exceptions: untested: 1 merge(s): v2026.0.2$' "$T/out" || fail "no untested count: $(cat "$T/out")"
grep -q '^doctor: exceptions: docs-none: 1 merge(s): v2026.0.3$' "$T/out" || fail "no docs-none count: $(cat "$T/out")"
grep -q '^doctor: exceptions: no-gate: 2 merge(s): v2026.0.4 v2026.0.5$' "$T/out" || fail "no no-gate count: $(cat "$T/out")"
grep -q '^doctor: ok' "$T/out" || fail "doctor is not ok: $(cat "$T/out")"
out=$(rapid doctor --history-only 2>&1) || fail "doctor --history-only: $out"
grep -q "^doctor: exceptions: untested:" <<<"$out" || fail "--history-only hides the exceptions: $out"
