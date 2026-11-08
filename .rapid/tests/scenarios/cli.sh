#!/usr/bin/env bash
# the CLI helps and reports: each verb answers -h with its own usage, status --json reports
# branch, version and branches, and doctor --fix repairs the hooks setting.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
rapid land -h > "$T/out" 2>&1 || fail "land -h"
grep -q '^  rapid land ' "$T/out" || fail "land -h is not land's usage: $(cat "$T/out")"
! grep -q 'rapid setup' "$T/out" || fail "land -h prints other verbs"
rapid branch feature probe >/dev/null; commit probe.txt
rapid status --json > "$T/out"
p=$(lname probe); grep -q "\"branch\": \"$p\"" "$T/out" && grep -q "\"name\": \"$p\", \"ahead\": 1" "$T/out" || fail "status --json: $(cat "$T/out")"
git config core.hooksPath /nowhere
refused rapid doctor
rapid doctor --fix > "$T/out" 2>&1 || fail "doctor --fix: $(cat "$T/out")"
[ "$(git config core.hooksPath)" = "$(cd "$(git rev-parse --git-common-dir)" && pwd -P)/rapid/hooks" ] || fail "doctor --fix did not set hooksPath"
rapid land >/dev/null || fail "land"
history_clean
