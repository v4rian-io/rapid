#!/usr/bin/env bash
# fast
# setup on a fresh clone: hooks active, main and dev seeded, the human runner the first admin. A
# repository with no .rapid/conf gets one that says gates_full=none; rapid setup --require-test
# writes requirement_test=required at the first setup, under which a branch with no requirement
# file is refused at land; in a seeded repository the flag is refused.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
[ "$(git config core.hooksPath)" = "$(cd "$(git rev-parse --git-common-dir)" && pwd -P)/rapid/hooks" ] || fail "hooksPath not set"
git rev-parse -q --verify refs/heads/main >/dev/null && git rev-parse -q --verify refs/heads/dev >/dev/null || fail "main/dev not seeded"
[ "$(git rev-parse main)" = "$(git rev-parse dev)" ] || fail "dev not at main"
rapid doctor >/dev/null || fail "doctor not clean after setup"
# a commit straight on dev is refused by the hook
git switch -q dev; echo x > x.txt; git add x.txt
refused git commit -q -m "[NEW] Add a file directly on dev"
grep -q 'no commit on dev' "$T/err" || fail "dev commit refusal text: $(cat "$T/err")"
git reset -q --hard
! git cat-file -e main:.rapid/admins 2>/dev/null || fail "the root commit holds .rapid/admins"
[ "$(grep -v '^#' .rapid/admins)" = "agent1@team.test # $(git var GIT_AUTHOR_IDENT | sed -E 's/^(.*) <.*/\1/')" ] || fail "setup does not name the runner as the first admin: $(cat .rapid/admins 2>&1)"
rapid setup >/dev/null || fail "a second setup"
history_clean
# the first setup of a repository with no conf: gates_full=none is written, and --require-test adds the key
mkdir -p "$T/n"; git -C "$T/n" init -q
cd "$T/n"; command rapid setup --require-test > "$T/out" 2>&1 || fail "setup --require-test: $(cat "$T/out")"
grep -Fx 'gates_full=none' .rapid/conf >/dev/null || fail "setup wrote no starting conf: $(cat .rapid/conf 2>&1)"
grep -Fx 'requirement_test=required' .rapid/conf >/dev/null || fail "setup --require-test did not write the key: $(cat .rapid/conf)"
[ "$(git show main:.rapid/conf | grep -c '^requirement_test=required$')" = 1 ] || fail "the root commit does not hold the key"
# under requirement_test=required rapid branch writes the requirement file, and a branch without one is refused at land
command rapid branch feature bare >/dev/null; [ -f .rapid/requirements/bare.md ] || fail "requirement_test=required: rapid branch wrote no requirement file"
git rm -q --cached .rapid/requirements/bare.md; rm -f .rapid/requirements/bare.md; git switch -q dev; git branch -q -D "$(lname bare)"
git switch -q -c pool/v2026.0/docs.hand dev
commit note.md n "[DOCS] Add a note to the project"
refused command rapid land
grep -q '.rapid/requirements/hand.md is not committed on the branch (I8)' "$T/err" || fail "a branch with no requirement landed under requirement_test=required: $(cat "$T/err")"
# a seeded repository changes its conf by a [MODE] commit, never by setup
refused command rapid setup --require-test
grep -q 'at the first setup only' "$T/err" || fail "setup --require-test in a seeded repository: $(cat "$T/err")"
