#!/usr/bin/env bash
# fast
# the session fixture (tests/run.sh, pytest-xdist style): under RAPID_TEST_FIXTURE mkrepo sets a repo
# up once per run and per setup input (actors, RAPID_/GIT_ environment, global git config) and copies it,
# so the copy is the repo setup makes (hooks active, main and dev seeded, the actor the first admin);
# mkrepo DIR origin copies the repo with its seeded bare origin at $T/origin.git, the remote pointing
# there; another actor gets its own fixture, and a set commit date or a non-empty directory builds
# afresh; a lock left by a dead builder makes mkrepo build without the fixture.
. "$(dirname "$0")/../lib.sh"
export RAPID_TEST_FIXTURE="$T/fixture"; mkdir -p "$RAPID_TEST_FIXTURE"
fixtures() { find "$RAPID_TEST_FIXTURE" -maxdepth 1 -name 'repo.*' -type l | wc -l | tr -d ' '; }
set_up() { # set_up DIR EMAIL: DIR is a repo rapid setup made, with EMAIL its first admin
  [ "$(git -C "$1" config core.hooksPath)" = "$(cd "$1/.git" && pwd -P)/rapid/hooks" ] || fail "$1: hooks not active"
  [ "$(git -C "$1" rev-parse main)" = "$(git -C "$1" rev-parse dev)" ] || fail "$1: main and dev not seeded"
  grep -qx "$2" <<<"$(grep -v "^#" "$1/.rapid/admins" | awk "{ print \$1 }")" || fail "$1: $2 is not the admin"
  [ -z "$(git -C "$1" status --porcelain)" ] || fail "$1: the copy is not clean"
}

# 1. the first mkrepo builds the fixture, the second copies it: same root commit, same set-up repo
mkrepo "$T/a"; [ "$(fixtures)" = 1 ] || fail "mkrepo built no session fixture"
mkrepo "$T/b"; [ "$(fixtures)" = 1 ] || fail "the second mkrepo built another fixture"
[ "$(git -C "$T/a" rev-parse main)" = "$(git -C "$T/b" rev-parse main)" ] || fail "the copies differ"
set_up "$T/b" agent1@team.test
( cd "$T/b"; rapid branch feature one >/dev/null; commit one.txt; rapid land >/dev/null ) || fail "a copied repo cannot land"
[ "$(git -C "$T/a" rev-parse main)" = "$(git -C "$T/a" rev-parse dev)" ] || fail "a land in one copy moved another"

# 2. with origin: the copy's remote is this scenario's own $T/origin.git, seeded with main and dev
mkrepo "$T/o" origin; [ "$(git -C "$T/o" remote get-url origin)" = "$T/origin.git" ] || fail "the remote is not \$T/origin.git"
for b in main dev; do
  [ "$(git --git-dir="$T/origin.git" rev-parse "$b")" = "$(git -C "$T/o" rev-parse "$b")" ] || fail "origin's $b is not seeded"
done
set_up "$T/o" agent1@team.test; o0=$(git -C "$T/o" rev-parse dev)
( cd "$T/o"; rapid branch feature two >/dev/null; commit two.txt; rapid land >/dev/null; git push -q origin dev ) || fail "a copied repo cannot land and push"
[ "$(git --git-dir="$T/origin.git" rev-parse dev)" = "$(git -C "$T/o" rev-parse dev)" ] || fail "the push did not reach \$T/origin.git"
( T="$T/t2"; mkdir -p "$T"; mkrepo "$T/o" origin; [ "$(git -C "$T/o" remote get-url origin)" = "$T/origin.git" ] ) || fail "a second origin copy"
[ "$(find "$RAPID_TEST_FIXTURE" -maxdepth 1 -name 'repo-origin.*' -type l | wc -l | tr -d ' ')" = 1 ] || fail "the origin fixture was not shared"
[ "$(git --git-dir="$T/t2/origin.git" rev-parse dev)" = "$o0" ] || fail "a push to one origin reached another"

# 3. another actor is another setup input: its own fixture, its own owner
actor "Owner One" owner@team.test
mkrepo "$T/c"; [ "$(fixtures)" = 2 ] || fail "another actor reused the first fixture"
set_up "$T/c" owner@team.test

# 4. a set commit date or a non-empty directory builds afresh
GIT_COMMITTER_DATE="2026-01-02T03:04:05" mkrepo "$T/d"
[ "$(git -C "$T/d" log -1 --format=%cI main | cut -c1-19)" = 2026-01-02T03:04:05 ] \
  || fail "a set commit date was not honoured"
mkdir -p "$T/e"; printf 'kept\n' > "$T/e/keep.txt"; mkrepo "$T/e"
[ -f "$T/e/keep.txt" ] || fail "mkrepo dropped a file already in the directory"
[ "$(fixtures)" = 2 ] || fail "a fresh build made a fixture"

# 5. a lock left by a dead builder: mkrepo builds without the fixture
actor "Human Dev" human@team.test
k="$RAPID_TEST_FIXTURE/repo.$(_mkrepo_key)"; mkdir "$k.lock"
( sleep 2; rmdir "$k.lock" ) & mkrepo "$T/f"; wait
set_up "$T/f" human@team.test; [ "$(fixtures)" = 2 ] || fail "a waiter published a fixture"
cd "$T/b"; history_clean
