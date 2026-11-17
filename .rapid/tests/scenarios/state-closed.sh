#!/usr/bin/env bash
# rapid's own state is closed to hand writes: the agent guard denies writes to rapid's state
# under the git common dir (the open batch, the rapid-close note ref) while reads stay allowed, and a
# green branch still lands with its gates run on the merge tree.
. "$(dirname "$0")/../lib.sh"
# the tools of rapid live in the installed clone, never in the repository
command -v python3 >/dev/null || fail "python3 is required by the agent guard"
mkrepo "$T/r" origin; cd "$T/r"
rapid branch feature good >/dev/null; commit good.txt; rapid land >/dev/null || fail "land good"
d=$(git rev-parse dev)

# 1. the agent guard denies hand writes to rapid's state under the git common dir; reads stay allowed
A="$TOOL/agent"
export GUARD_TMP_ROOTS="$T/throwaway"; mkdir -p "$T/throwaway"
guard() { python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$T/r" | "$A/guard-destructive.sh"; }
write() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$T/r" | "$A/guard-write.sh"; }
printf 'x\n' > "$T/msg"
for c in "mkdir -p .git/rapid && echo $d > .git/rapid/batch" "cp $T/msg .git/rapid/batch.branches" \
         "printf x >> .git/rapid/batch" "echo $d > .git/refs/notes/rapid-close" "/usr/bin/trash .git/rapid/batch"; do
  out=$(guard "$c"); grep -q '"deny"' <<<"$out" || fail "the guard allowed a write to rapid's state: $c"
done
out=$(write "$T/r/.git/rapid/batch"); grep -q "rapid's own state" <<<"$out" || fail "the Write tool may write the batch: $out"
out=$(write "$T/r/.git/refs/notes/rapid-close"); grep -q "rapid's own state" <<<"$out" || fail "the Write tool may forge a close note: $out"
out=$(guard "cat .git/rapid/batch"); [ -z "$out" ] || fail "reading the batch was denied: $out"
out=$(guard "echo x > $T/throwaway/y"); [ -z "$out" ] || fail "a temp write was denied: $out"

# 2. a green branch still lands, its fast gate run on the merge tree
git switch -q dev
rapid branch feature fine >/dev/null; commit fine.txt; rapid land >/dev/null || fail "a green branch did not land"
history_clean
