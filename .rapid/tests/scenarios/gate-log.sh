#!/usr/bin/env bash
# the durable gate log: rapid land stores its one gate's command, exit code, duration and
# log tail (the value of every TOKEN, SECRET, KEY, PASSWORD or CREDENTIAL variable redacted) as a note on the merge under refs/notes/gates, pushed atomically with dev and the tag; a
# second clone's land merges origin's notes first, so the ref only grows; rapid doctor --verify shows
# the stored log beside the rerun; pre-push refuses deleting or rewriting the notes ref, and the agent
# guard refuses writing, rewriting or deleting it by hand.
. "$(dirname "$0")/../lib.sh"
# the tools of rapid live in the installed clone, never in the repository
mkrepo "$T/r" origin; cd "$T/r"
rapid branch feature one >/dev/null
printf '#!/bin/sh\necho "gate ran on $(ls | wc -l | tr -d " ") files"\n! ls *.bad >/dev/null 2>&1\n' > check.sh
git add check.sh; commit one.txt
rapid land >/dev/null || fail "land one"
m1=$(git rev-parse dev)
note=$(git notes --ref=gates show "$m1") || fail "the merge carries no gate log note"
for want in "gate=full" "command=sh check.sh" "exit=0" "duration=" "gate ran on"; do
  grep -qF -- "$want" <<<"$note" || fail "the gate log lacks '$want': $note"
done
[ "$(git ls-remote origin refs/notes/gates | cut -f1)" = "$(git rev-parse refs/notes/gates)" ] || fail "the gate log was not pushed with dev"
# the log tail is published and kept: the value of a secret-named variable a gate printed is redacted
rapid branch feature leak >/dev/null
printf '#!/bin/sh\necho "debug token=$DEPLOY_TOKEN"\necho "plain $PLAIN_NAME"\n! ls *.bad >/dev/null 2>&1\n' > check.sh
git add check.sh; commit leak.txt
DEPLOY_TOKEN=sk-live-SECRET123 PLAIN_NAME=visible-value rapid land >/dev/null || fail "land leak"
ml=$(git rev-parse dev); note=$(git notes --ref=gates show "$ml")
grep -qF 'debug token=<redacted>' <<<"$note" || fail "the gate log does not redact the token: $note"
grep -qF 'plain visible-value' <<<"$note" || fail "the gate log redacts a variable that names no secret: $note"
git fetch -q origin "+refs/notes/gates:refs/notes/gates-seen"
! grep -F 'sk-live-SECRET123' <<<"$(git notes --ref=gates-seen show "$ml")" >/dev/null || fail "the secret reached origin in the gate log"
# a coworker lands from another clone: origin's notes are merged first, both merges keep their log
git clone -q "$T/origin.git" "$T/b"; ( cd "$T/b" && git switch -q dev && rapid setup >/dev/null )
( cd "$T/b"; rapid branch feature two >/dev/null; commit two.txt; rapid land >/dev/null ) || fail "land two from the second clone"
git -C "$T/b" notes --ref=gates show "$m1" >/dev/null || fail "the second clone's land dropped the first merge's log"
git fetch -q origin "+refs/notes/gates:refs/notes/gates"; git pull -q --ff-only origin dev 2>/dev/null || true
git notes --ref=gates show "$(git rev-parse origin/dev)" >/dev/null || fail "the second merge has no log on origin"
# doctor --verify shows the stored log beside the rerun
rapid doctor --verify > "$T/verify" 2>&1 || fail "verify: $(cat "$T/verify")"
grep -qE "stored gate log of [0-9a-f]+ \(v2026\.0\.1\): full=exit 0 in [0-9]+s" "$T/verify" || fail "verify does not show the stored log: $(cat "$T/verify")"
# pre-push: the notes ref is never deleted or rewritten
refused git push -q origin :refs/notes/gates
grep -qF "refs/notes/gates (the gate log archive) is never deleted" "$T/err" || fail "deletion: $(cat "$T/err")"
git update-ref refs/notes/gates "$(git rev-parse refs/notes/gates)^"
refused git push -q --force origin refs/notes/gates:refs/notes/gates
grep -qF "only moves forward" "$T/err" || fail "rewrite: $(cat "$T/err")"
git fetch -q origin "+refs/notes/gates:refs/notes/gates"
# the agent guard: no hand-written, rewritten or deleted gate log
command -v python3 >/dev/null || fail "python3 is required by the agent guard"
export GUARD_TMP_ROOTS="$T/throwaway" RAPID_BAKS_DIR="$T/baks"; mkdir -p "$T/throwaway"
guard() { python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$PWD" | "$TOOL/agent/guard-destructive.sh"; }
for c in "git notes --ref=gates add -f -m forged $m1" "git notes --ref gates remove $m1" "git update-ref -d refs/notes/gates" \
         "git push origin :refs/notes/gates" "git push origin +refs/notes/gates:refs/notes/gates"; do
  out=$(guard "$c"); grep -qF "gate log" <<<"$out" || fail "the guard allowed '$c': $out"
done
out=$(guard "git notes --ref=gates show $m1"); grep -q '"deny"' <<<"$out" && fail "reading the gate log was denied: $out"
history_clean
