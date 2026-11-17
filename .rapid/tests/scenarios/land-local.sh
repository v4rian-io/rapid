#!/usr/bin/env bash
# fast
# branch, three commits, land with no remote: I1-I4 and I8 hold, exit 0. requirement_test is
# optional by default: a branch opened with no -r, --test or --ticket stages no requirement file,
# commits with no placeholder in its way and lands with no Requirement: trailer; a test that is
# given is checked and recorded.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
rapid branch feature parser -r "Parse nested blocks and report the first malformed one." >/dev/null
commit a.txt a "[NEW] Add the block parser entry point"
commit b.txt b "[NEW] Add nested block recovery"
commit c.txt c "[TEST] Cover malformed block reporting"
rapid land > "$T/land" || { cat "$T/land"; fail "land refused"; }
grep -q 'no remote, landed locally' "$T/land" || fail "land output: $(cat "$T/land")"
m=$(git rev-parse dev)
[ "$(git rev-list --parents -n1 "$m" | wc -w | tr -d ' ')" = 3 ] || fail "dev tip is not a merge"
[ "$(git log -1 --format=%s "$m")" = "[MERGE] pool/v2026.0/n1.feature.parser into dev: v2026.0.1" ] || fail "subject: $(git log -1 --format=%s "$m")"
[ "$(git describe --exact-match "$m")" = v2026.0.1 ] || fail "no v2026.0.1 tag on the merge"
[ "$(git cat-file -t v2026.0.1)" = tag ] || fail "tag not annotated"
[ "$(git rev-list --count "$m^1..$m^2")" = 3 ] || fail "branch commits not all in the merge"
git cat-file -e "$m:.rapid/requirements/parser.md" || fail "requirement file missing"
[ -z "$(lref parser)" ] || fail "branch ref kept after land"
[ "$(git rev-parse HEAD)" = "$m" ] || fail "not on dev after land"
rapid status > "$T/status"
grep -q 'last version v2026.0.1' "$T/status" || fail "status: $(cat "$T/status")"
history_clean
# a git that cannot read HEAD once is not a detached HEAD: the land stops on git's own word,
# never on "no branch to land here", nothing lands, and the same land then goes through
rapid branch feature again >/dev/null; commit again.txt; d1=$(git rev-parse dev)
real=$(command -v git); mkdir -p "$T/bin"
cat > "$T/bin/git" <<SHIM
#!/bin/sh
if [ "\$*" = "symbolic-ref --short -q HEAD" ] && [ -e "$T/failref" ]; then rm -f "$T/failref"; echo "fatal: forced: cannot read HEAD" >&2; exit 128; fi
exec "$real" "\$@"
SHIM
chmod +x "$T/bin/git"; touch "$T/failref"
rc=0; PATH="$T/bin:$PATH" command rapid land > "$T/out" 2> "$T/err" || rc=$?
[ "$rc" != 0 ] || fail "a land went on although git could not read HEAD"
grep -qF 'fatal: forced: cannot read HEAD' "$T/err" || fail "git's own error was swallowed: $(cat "$T/err")"
grep -q "on 'detached'" "$T/err" && fail "a git that cannot answer was read as a detached HEAD: $(cat "$T/err")"
[ "$(git rev-parse dev)" = "$d1" ] || fail "the stopped land moved dev"
rapid land >/dev/null || fail "the same land after git answers again"
history_clean
# requirement_test left at its default (optional): no requirement file, no trailer, a clean history
rapid branch refactor default-test -r "Leave requirement_test at its default in this repository." >/dev/null
grep -v '^requirement_test=' .rapid/conf > c && mv c .rapid/conf; git add .rapid/conf
git commit -q -m "[MODE] Leave requirement_test at its default"
rapid land >/dev/null || fail "land the default requirement_test"
command rapid branch feature plain > "$T/out" || fail "rapid branch with no requirement: $(cat "$T/out")"
[ ! -e .rapid/requirements/plain.md ] && [ -z "$(git status --porcelain)" ] || fail "a branch opened with no requirement staged something: $(git status --porcelain)"
commit plain.txt p "[NEW] Add the plain file to the project"
rapid land > "$T/land" 2>&1 || fail "a branch with no requirement was refused: $(cat "$T/land")"
m=$(git rev-parse dev)
[ -z "$(git log -1 --format='%(trailers:key=Requirement,valueonly)' "$m" | sed '/^$/d')" ] || fail "a merge with no requirement carries a Requirement: trailer: $(git log -1 --format=%B "$m")"
git cat-file -e "$m:.rapid/requirements/plain.md" 2>/dev/null && fail "a requirement file appeared for a branch that stated none"
grep -Fx 'Lands the branch feature/plain.' <<<"$(git log -1 --format=%B "$m")" >/dev/null || fail "the merge body does not name the branch: $(git log -1 --format=%B "$m")"
# what is given is checked and recorded: a Test: the tip does not hold is refused, one it holds lands as a trailer
command rapid branch feature verified -r "The verified file exists in the project." --test verified.t >/dev/null
commit verified.txt
refused rapid land
grep -q 'Test: verified.t, which the branch tip does not hold' "$T/err" || fail "a Test: naming a missing file landed: $(cat "$T/err")"
commit verified.t t "[TEST] Cover the verified file"
rapid land >/dev/null || fail "land a requirement with its test"
[ "$(git log -1 --format='%(trailers:key=Test,valueonly)' dev | sed '/^$/d')" = verified.t ] || fail "the merge has no Test: trailer: $(git log -1 --format=%B dev)"
[ "$(git log -1 --format='%(trailers:key=Requirement,valueonly)' dev | sed '/^$/d')" = .rapid/requirements/verified.md ] || fail "the merge does not name its requirement"
history_clean
