#!/usr/bin/env bash
# the requirements register (project-reqs model) is the output of a command: rapid check --reqs prints it on
# the spot from the requirement files under .rapid/requirements, --save writes it (.rapid/REQUIREMENTS.md, or
# the file named); nothing is generated at a commit.
# Rows take status, priority, tests, source and code from the file; an intent is a Unit of Intent until a
# later branch promotes it, a scrapped row moves to the graveyard with its reason, a row whose test the tree
# lacks is said by the command. Two branches that both state a requirement never conflict, through rapid sync
# or a plain git rebase; branch --rename moves the file; a landed requirement file is never edited; a fresh
# clone passes doctor --history.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r" origin; cd "$T/r"
reg() { rapid check --reqs > "$T/reg" 2> "$T/reg.err" || fail "check --reqs: $(cat "$T/reg.err")"; }
rapid branch refactor reqs-token -r "Register IDs carry the APP token." >/dev/null
printf 'reqs_id=APP\n' >> .rapid/conf
git add .rapid/conf; git commit -q -m "[MODE] Name the register token"
# the requirement lives under .rapid/requirements; a commit generates nothing
git cat-file -e HEAD:.rapid/requirements/reqs-token.md 2>/dev/null || fail "the requirement file is not at .rapid/requirements/reqs-token.md: $(git ls-tree -r --name-only HEAD | grep -i req)"
reg
[ "$(sed -n 1p "$T/reg")" = "# APP Requirements" ] || fail "the command does not print the register: $(head -3 "$T/reg")"
grep -qF '| APP-R-reqs-token | Register IDs carry the APP token. | P2 | ✅ done | ⚠️ needs units | internal | `refactor/reqs-token` |' "$T/reg" \
  || fail "the branch's own row: $(grep reqs-token "$T/reg")"
[ ! -e .rapid/REQUIREMENTS.md ] || fail "printing the register wrote a file"
[ -z "$(git status --porcelain)" ] || fail "printing the register changed the work tree: $(git status --porcelain)"
rapid land >/dev/null || fail "land the token branch"
# fields: priority, named tests, source from a ticket, code
rapid branch feature login -r "Users sign in with a passkey." >/dev/null
mkdir -p tests; printf 'true\n' > tests/login_test.sh
printf '\nPri: P0\nTests: tests/login_test.sh\nCode: src/login.sh\nTicket: APP-12\n' >> .rapid/requirements/login.md
git add .rapid/requirements/login.md tests/login_test.sh; git commit -q -m "[NEW] Add the login test to the project"
reg
grep -qF '| APP-R-login | Users sign in with a passkey. | P0 | ✅ done | ✅ `tests/login_test.sh` | jira-APP-12 | `feature/login` · `src/login.sh` |' "$T/reg" \
  || fail "the login row: $(grep R-login "$T/reg")"
rapid land >/dev/null || fail "land login"
# an intent, then its promotion; a scrap with its reason
rapid branch docs ideas -r "A dark theme for the sign-in page." >/dev/null
printf '\nStatus: intent\nSprint: backlog\nNotes: needs design\n' >> .rapid/requirements/ideas.md
git add .rapid/requirements/ideas.md; git commit -q -m "[DOCS] Record the dark theme intent"
reg
grep -qF '| APP-I-ideas | A dark theme for the sign-in page. | P2 | internal | backlog | needs design |' "$T/reg" || fail "intent row: $(grep ideas "$T/reg")"
rapid land >/dev/null || fail "land the intent"
rapid branch feature dark -r "The sign-in page has a dark theme." >/dev/null
printf '\nPromotes: ideas\nScraps: reqs-token: the token moved to the conf docs\n' >> .rapid/requirements/dark.md
git add .rapid/requirements/dark.md; git commit -q -m "[DOCS] Promote the dark theme intent"
reg
! grep -F '| APP-I-ideas |' "$T/reg" >/dev/null || fail "the promoted intent is still listed"
grep -qF '`feature/dark` · promoted from APP-I-ideas' "$T/reg" || fail "no promotion crumb: $(grep dark "$T/reg")"
grep -qF '| APP-R-reqs-token | Register IDs carry the APP token. | `feature/dark` | the token moved to the conf docs |' "$T/reg" \
  || fail "the scrapped row: $(grep reqs-token "$T/reg")"
# a row whose test the tree lacks: the command says so, prints no register
mv tests/login_test.sh "$T/kept"
refused rapid check --reqs
grep -qF "names test tests/login_test.sh, which the tree lacks" "$T/err" || fail "a row without its test was printed: $(cat "$T/err")"
mv "$T/kept" tests/login_test.sh
rapid land >/dev/null || fail "land the promotion"
# --save writes what the command prints: .rapid/REQUIREMENTS.md by default, the file named else
reg
rapid check --reqs --save > "$T/saved" || fail "check --reqs --save"
cmp -s .rapid/REQUIREMENTS.md "$T/reg" || fail "--save did not write the printed register to .rapid/REQUIREMENTS.md"
grep -qF '.rapid/REQUIREMENTS.md' "$T/saved" || fail "--save does not name the file it wrote: $(cat "$T/saved")"
rapid check --reqs --save "$T/named.md" >/dev/null || fail "check --reqs --save FILE"
cmp -s "$T/named.md" "$T/reg" || fail "--save FILE did not write the printed register"
mv .rapid/REQUIREMENTS.md "$T/dropped"
refused rapid check --reqs --write
# two clones each state a requirement; the second syncs, lands, with no conflict
git clone -q "$T/origin.git" "$T/b"; ( cd "$T/b" && rapid setup >/dev/null 2>&1 || true )
rapid branch feature alpha -r "The alpha branch works as stated." >/dev/null; git commit -q -m "[NEW] Start the alpha branch"
( cd "$T/b"; git switch -q dev; rapid branch feature beta -r "The beta branch works as stated." >/dev/null; git commit -q -m "[NEW] Start the beta branch"; rapid land >/dev/null ) || fail "land beta"
rapid sync >/dev/null || fail "sync alpha onto beta"
reg
grep -qF 'APP-R-beta' "$T/reg" && grep -qF 'APP-R-alpha' "$T/reg" || fail "the register after a sync lacks a row: $(grep -E 'alpha|beta' "$T/reg")"
# a rename moves the requirement file in the branch's commits
rapid branch --rename alpha-two >/dev/null || fail "rename"
git cat-file -e HEAD:.rapid/requirements/alpha-two.md 2>/dev/null || fail "the renamed branch's requirement file did not move"
! git cat-file -e HEAD:.rapid/requirements/alpha.md 2>/dev/null || fail "the renamed branch keeps the old requirement file"
reg; grep -qF 'APP-R-alpha-two' "$T/reg" || fail "the register keeps the old name after a rename"
rapid land >/dev/null || fail "land the renamed branch"
# a plain git rebase stops on nothing
git switch -q dev; rapid branch feature gamma -r "The gamma branch works as stated." >/dev/null; git commit -q -m "[NEW] Start the gamma branch"
( cd "$T/b"; git switch -q dev; git pull -q --ff-only origin dev; rapid branch feature delta -r "The delta branch works as stated." >/dev/null; git commit -q -m "[NEW] Start the delta branch"; rapid land >/dev/null ) || fail "land delta"
git fetch -q origin; git -C . update-ref refs/heads/dev origin/dev 2>/dev/null || true
git rebase -q dev || fail "a plain rebase stopped: $(git status --short | head -3)"
rapid land >/dev/null || fail "land gamma after a plain rebase"
history_clean
# a landed requirement is never edited
rapid branch refactor edit-reqs >/dev/null
printf '\nNotes: edited after it landed\n' >> .rapid/requirements/gamma.md
git add .rapid/requirements/gamma.md; git commit -q -m "[REFACTOR] Edit a landed requirement file"
refused rapid land
grep -qF 'landed requirements are never edited or deleted (I8)' "$T/err" || fail "an edited landed requirement was landed: $(cat "$T/err")"
git switch -q dev
# a fresh clone passes the history check
git clone -q "$T/origin.git" "$T/fresh"; cd "$T/fresh"; git switch -q dev; rapid setup >/dev/null 2>&1 || fail "setup of a fresh clone"
rapid doctor --history > "$T/doc" 2>&1 || fail "a fresh clone fails doctor --history: $(cat "$T/doc")"
