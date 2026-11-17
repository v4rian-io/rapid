#!/usr/bin/env bash
# fast
# no shell pipeline ends in a quiet grep: the lint catches every spelling (its self-check),
# names a planted pipe by file and line, and passes the here-string form.
. "$(dirname "$0")/../lib.sh"
lint="$RAPID_SRC/lint/quiet-grep.py"
python3 "$lint" --self-check || fail "the lint misses a spelling"
mkdir -p "$T/r"; cd "$T/r"; git init -q
g="gr""ep"; p="|"
printf '#!/bin/sh\nset -o pipefail\nprintf "%%s" "$x" %s %s -q needle && echo hit\n' "$p" "$g" > bad.sh
printf '#!/bin/sh\n%s -q needle <<<"$x" && echo hit\n' "$g" > good.sh
git add bad.sh good.sh
refused python3 "$lint"
grep -q 'bad.sh:3' "$T/out" || fail "the planted pipe is not named: $(cat "$T/out")"
! grep -q 'good.sh' "$T/out" || fail "the here-string form was flagged"
git rm -q --cached bad.sh
python3 "$lint" >/dev/null || fail "a clean tree failed the lint"
