#!/usr/bin/env bash
# a first use works and no gate is silent: the readme's Install block is the installer's one line (never
# run here: no network); In your repository holds two blocks, cd then rapid setup, then branch, add, commit,
# land, each step under its comment; both run with a rapid installed from this source, the scenario
# bringing its own repository, which already holds a commit, branch name, files and commit message, ending in a
# landed, history-clean branch whose repository holds data only, setup having committed the seed on dev
# above that commit (and --require-test working there at the first setup); setup and doctor
# name a gate that runs a script the repository does not hold; land refuses a conf with no gates_full and lands an explicit gates_full=none with a
# warning; doctor --verify counts the merges that carry no gate instead of calling every gate passed.
. "$(dirname "$0")/../lib.sh"
actor "Human Dev" human@team.test
R="$RAPID_SRC/README.md"
# block HEADING N: the commands of the Nth sh block under HEADING, its comment and blank lines left out
block() { awk -v h="## $1" -v want="$2" '$0 == h { on = 1; next } on && /^## / { exit } on && /^```sh$/ { n++; inb = 1; next } inb && /^```$/ { inb = 0; next } inb && n == want && !/^#/ && !/^$/ { print }' "$R"; }
[ "$(block Install 1)" = 'curl -fsSL https://raw.githubusercontent.com/v4rian-io/rapid/main/.rapid/install.sh | bash' ] \
  || fail "Install is not the installer's one line: $(block Install 1)"
# In your repository: cd and rapid setup, then the steps of one change; the repository, the branch name, the files and the
# commit message are the user's own, here the scenario's
[ "$(block 'In your repository' 1)" = 'cd <your-repo>
rapid setup' ] || fail "the first block is not cd, then rapid setup: $(block 'In your repository' 1)"
[ "$(block 'In your repository' 2)" = 'rapid branch <kind> <name>
git add <your files>
git commit -m "..."
rapid land' ] || fail "the second block is not branch, add, commit, land: $(block 'In your repository' 2)"
[ -z "$(block 'In your repository' 3)" ] || fail "In your repository holds a third block: $(block 'In your repository' 3)"
{ block 'In your repository' 1; block 'In your repository' 2; } | sed -e "s|^cd <your-repo>\$|cd '$T/q'|" -e 's|^rapid branch <kind> <name>$|rapid branch feature passkey-login|' \
  -e "s|^git add <your files>\$|printf 'echo signed in\\\\n' > passkey.sh; printf 'test -f passkey.sh\\\\n' > passkey_test.sh; git add passkey.sh passkey_test.sh|" \
  -e 's|^git commit -m "[.][.][.]"$|git commit -m "[NEW] Add the passkey entry point" -m "Users sign in through passkey.sh; passkey_test.sh checks that it exists."|' > "$T/quick.sh"
! grep -q '<your-repo>\|<kind>\|<name>\|<your files>\|"[.][.][.]"' "$T/quick.sh" || fail "a placeholder of the block was not filled: $(cat "$T/quick.sh")"
# rapid installed once from this source: a clone of the framework, linked into a bin directory of PATH
mkdir -p "$T/tool" "$T/home/.local/bin"; cp -R "$RAPID_SRC" "$T/tool/.rapid"
( cd "$T/tool" && git init -q && git add -- .rapid && git -c core.hooksPath=/dev/null commit -q -m "[NEW] Carry the framework" && git tag -a v2026.0.1 -m v2026.0.1 && git tag -a release/v2026.0.1 -m "rapid release v2026.0.1" ) || fail "the tool repository"
tool() { HOME="$T/home" PATH="$T/home/.local/bin:$PATH" "$@"; }
tool bash "$T/tool/.rapid/rapid" setup --install > "$T/out" 2>&1 || fail "the install: $(cat "$T/out")"
# the real-world case: the repository already holds a commit when rapid setup first runs in it
mkdir -p "$T/q"; cd "$T/q"; git init -q
printf 'echo hello\n' > app.sh; git add app.sh; git commit -q -m "First version of the app"; first=$(git rev-parse HEAD)
tool bash -e "$T/quick.sh" > "$T/out" 2>&1 || fail "the readme's steps failed: $(tail -n 8 "$T/out")"
grep -q 'landed feature/passkey-login as v2026.0.1' "$T/out" || fail "the quick start did not land: $(cat "$T/out")"
[ "$(git ls-tree -r --name-only dev | grep -v '^[.]rapid/' | tr '\n' ' ')" = "app.sh passkey.sh passkey_test.sh " ] || fail "the landed tree is not the file beside its test: $(git ls-tree -r --name-only dev)"
seed=$(git rev-parse dev^1)
[ "$(git log -1 --format=%s "$seed")" = "[NEW] Seed the rapid workflow" ] && [ "$(git rev-parse "$seed^")" = "$first" ] || fail "the seed is not committed on dev above the first commit: $(git log --oneline dev)"
[ "$(git show "$seed:.rapid/conf" | grep -c '^gates_full=none$')" = 1 ] && ! git cat-file -e "$seed:.rapid/admins" 2>/dev/null && git cat-file -e "$seed:.rapid/version" \
  || fail "the seed does not hold the conf and the pin alone, without the admins: $(git ls-tree -r --name-only "$seed" .rapid)"
[ "$(grep -v '^#' .rapid/admins)" = "human@team.test # $(git var GIT_AUTHOR_IDENT | sed -E 's/^(.*) <.*/\1/')" ] || fail "setup names no admin in the working copy: $(cat .rapid/admins 2>&1)"
[ "$(git rev-parse main)" = "$first" ] || fail "setup moved main off the first commit"
[ ! -e .rapid/rapid ] && [ -s .rapid/version ] || fail "the repository holds more than data: $(ls .rapid)"
tool command rapid doctor --history > "$T/out" 2>&1 || fail "the quick start's history is not clean: $(cat "$T/out")"
grep -q 'doctor: ok' "$T/out" || fail "the quick start's doctor is not ok: $(cat "$T/out")"
# --require-test works at the first setup of a repository that already holds a commit
mkdir -p "$T/rt"; cd "$T/rt"; git init -q
printf 'echo hello\n' > app.sh; git add app.sh; git commit -q -m "First version of the app"
tool command rapid setup --require-test > "$T/out" 2>&1 || fail "setup --require-test in a repository with a commit: $(cat "$T/out")"
[ "$(git show dev:.rapid/conf | grep -c '^requirement_test=required$')" = 1 ] || fail "the seed does not hold requirement_test=required: $(git show dev:.rapid/conf 2>&1)"
# a conf whose gates run the framework's own tests, which a repository does not hold: setup names the gate
mkdir -p "$T/v/.rapid"; cd "$T/v"; git init -q
cp "$RAPID_SRC/conf" .rapid/conf
refused rapid setup
grep -q 'gates_fast runs .rapid/tests/run.sh, which this repository does not have' "$T/err" || fail "setup kept a gate that cannot run: $(cat "$T/err")"
rapid doctor > "$T/doc" 2>&1 && fail "doctor missed the gate that cannot run"
grep -q 'doctor: gates_full runs .rapid/tests/run.sh' "$T/doc" || fail "doctor did not name the gate: $(cat "$T/doc")"
# a branch that drops the full gate is refused; a dev with none lands only a branch that sets one
mkrepo "$T/r"; cd "$T/r"
rapid branch refactor no-gates -r "Drop every gate from the conf of this repository." >/dev/null
grep -vE '^gates_' .rapid/conf > c && mv c .rapid/conf; git add .rapid/conf; git commit -q -m "[MODE] Drop every gate from the conf"
refused rapid land
grep -q "this branch's .rapid/conf sets no gates_full" "$T/err" || fail "a branch dropping the full gate landed: $(cat "$T/err")"
mkdir -p "$T/g/.rapid"; cd "$T/g"; git init -q
printf 'max_commits=20\ntest_paths=*\ncommit_body=optional\nrequirement_test=optional\n' > .rapid/conf; rapid setup >/dev/null || fail "setup with no gates"
rapid branch feature silent >/dev/null; commit x.txt
refused rapid land
grep -q "this branch's .rapid/conf sets no gates_full" "$T/err" || fail "a land with no full gate was not refused: $(cat "$T/err")"
git switch -q dev; git branch -q -D "$(lname silent)"
rapid branch refactor say-none -r "Land without a full gate, said out loud." >/dev/null
printf 'gates_full=none\n' >> .rapid/conf; git add .rapid/conf; git commit -q -m "[MODE] Say that no full gate runs"
rapid land > "$T/out" 2>&1 || fail "a branch setting gates_full=none was refused: $(cat "$T/out")"
grep -q "dev's .rapid/conf sets no gates_full, so this land runs no full gate" "$T/out" || fail "the gateless land was silent: $(cat "$T/out")"
rapid branch feature loud >/dev/null; commit y.txt
rapid land > "$T/out" 2>&1 || fail "a land under gates_full=none: $(cat "$T/out")"
grep -q 'gates_full=none: this land runs no full gate' "$T/out" || fail "gates_full=none was silent: $(cat "$T/out")"
rapid doctor --verify > "$T/out" 2>&1 || fail "doctor --verify: $(cat "$T/out")"
grep -q '2 merge(s) carry no gate: v2026.0.1 v2026.0.2' "$T/out" || fail "doctor --verify hid the ungated merges: $(cat "$T/out")"
history_clean
