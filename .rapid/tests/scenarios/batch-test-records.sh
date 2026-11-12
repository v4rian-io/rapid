#!/usr/bin/env bash
# honest test records: a branch landed into a batch says Gates: deferred to the close of batch <id> and names its tree
# as Merge-Tree, never Tested-Tree, since no gate ran on it; the close runs gates_each on the own tree of
# every merge of the batch, all at once, records each result in the gate log of that merge, then records
# the one gate of the final tree on the last merge. doctor --history accepts exactly that: a batch with no
# passing close record is flagged I3 (and doctor --verify and the push refuse a deferred test record whose batch shows
# no close, running the full gate on the merge a close record names), a deferred test record under Tested-Tree is flagged I3, and a merge
# whose own tree fails gates_each stops the close by name.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
R="$(type -P rapid)"
"$R" branch refactor each -r "Every merge of a batch verifies that its own tree holds the check script." >/dev/null
printf 'gates_each=test -f check.sh && ! ls *.broken >/dev/null 2>&1\n' >> .rapid/conf; git add .rapid/conf
git commit -q -m "[MODE] Verify every merge of a batch on its own tree"
"$R" land --batch >/dev/null && "$R" land >/dev/null || fail "land the gates_each flip"
d0=$(git rev-parse dev)
"$R" branch feature one >/dev/null -r "Scenario branch one: the first of two branches in one batch."; commit one.txt; "$R" land --batch >/dev/null || fail "land one"
m1=$(git rev-parse dev)
grep -qE '^Gates: deferred to the close of batch [0-9a-f]+$' <<<"$(git log -1 --format=%B "$m1")" || fail "no deferred test record: $(git log -1 --format=%B "$m1")"
grep -q "^Merge-Tree: $(git rev-parse "$m1^{tree}")$" <<<"$(git log -1 --format=%B "$m1")" || fail "a batch merge does not name its Merge-Tree"
grep -q '^Tested-Tree: ' <<<"$(git log -1 --format=%B "$m1")" && fail "a batch merge claims a Tested-Tree"
grep -q 'no gate ran on this merge tree at the land' <<<"$(git notes --ref=gates show "$m1")" || fail "the gate log of a batch land hides that nothing ran"
git notes --ref=rapid-close show "$m1" >/dev/null 2>&1 && fail "a batch land wrote a close note before any gate ran"
# the open batch is not a violation yet
history_clean
"$R" branch feature two >/dev/null -r "Scenario branch two: the second of two branches in one batch."; commit two.txt; "$R" land --batch >/dev/null || fail "land two"
m2=$(git rev-parse dev)
"$R" land > "$T/close" 2>&1 || fail "close: $(cat "$T/close")"
for m in "$m1" "$m2"; do
  grep -q "gate each on this merge tree $(git rev-parse "$m^{tree}")$" <<<"$(git notes --ref=gates show "$m")" || fail "no gates_each record on $(git rev-parse --short "$m")"
  git notes --ref=gates show "$m" | awk '/gate each on this merge tree/ { f = 1 } f && /^exit=0$/ { ok = 1 } END { exit !ok }' || fail "the gates_each record of $(git rev-parse --short "$m") is not a pass"
  grep -q '^close=' <<<"$(git notes --ref=rapid-close show "$m")" || fail "the close left no close note on $(git rev-parse --short "$m")"
done
grep -q "gates on the final tree $(git rev-parse "$m2^{tree}")$" <<<"$(git notes --ref=gates show "$m2")" || fail "the last merge carries no record of the close"
grep -q 'gates on the final tree' <<<"$(git notes --ref=gates show "$m1")" && fail "the first merge claims the final gate"
history_clean
rapid doctor --history-only --all > "$T/doc" 2>&1 || fail "doctor refuses a closed batch: $(cat "$T/doc")"
grep -q 'exceptions: batch-close: 3 merge' "$T/doc" || fail "doctor does not count the batch merges: $(cat "$T/doc")"
# a batch whose close record is gone: its deferred gates are shown by nothing
keep=$(git rev-parse refs/notes/gates)
git notes --ref=gates remove "$m2" >/dev/null
rapid doctor --history-only --all > "$T/doc" 2>&1 && fail "doctor accepted a batch with no close record"
grep -q "^doctor: I3 $m2 batch [0-9a-f]* has no passing close record" "$T/doc" || fail "no I3 for the missing close record: $(cat "$T/doc")"
git update-ref refs/notes/gates "$keep"
# a deferred test record nothing backs: a merge landed into a batch whose close never ran (the batch record
# removed by hand) carries a tree the full gate fails. The rerun verifies it by the conf of its first
# parent and wants the close record on the batch's last merge: doctor --verify and the push refuse it
git init -q --bare "$T/o.git"; git push -q "$T/o.git" dev 'refs/tags/v*:refs/tags/v*' refs/notes/gates || fail "seed the bare remote"
d1=$(git rev-parse dev)
"$R" branch feature hollow >/dev/null -r "Scenario branch hollow: a merge whose deferred gates never ran."; commit hollow.bad; "$R" land --batch >/dev/null || fail "land hollow"
mh=$(git rev-parse dev); vh=$(git describe --exact-match dev)
mkdir "$T/kept"; mv .git/rapid/batch* "$T/kept/"
rapid doctor --verify > "$T/verify" 2>&1 && fail "doctor --verify accepted a deferred test record with no close: $(cat "$T/verify")"
grep -q "^doctor: P1 $mh defers its gates to the close of batch $(git rev-parse --short "$d1"), .* carries no close record in the gate log" "$T/verify" || fail "no P1 for the test record nothing backs: $(cat "$T/verify")"
refused git push -q "$T/o.git" dev "refs/tags/$vh"
grep -q "P1 $mh defers its gates to the close of batch .* carries no close record in the gate log" "$T/err" || fail "the push took a deferred test record with no close: $(cat "$T/err")"
# a close record written by hand makes the claim checkable: the full gate then runs on that merge and fails
git notes --ref=gates append -m "close of batch $(git rev-parse --short "$d1"): gates on the final tree $(git rev-parse "$mh^{tree}")" -m "gate=full" -m "exit=0" "$mh" >/dev/null 2>&1
rapid doctor --verify > "$T/verify" 2>&1 && fail "doctor --verify accepted a forged close record: $(cat "$T/verify")"
grep -q "^doctor: P1 $mh gate full fails on the merge tree" "$T/verify" || fail "the full gate did not run on the merge a forged close record names: $(cat "$T/verify")"
refused git push -q "$T/o.git" dev "refs/tags/$vh" refs/notes/gates
grep -q "P1 $mh gate full fails on the merge tree" "$T/err" || fail "the push took a forged close record: $(cat "$T/err")"
[ "$(git ls-remote "$T/o.git" refs/heads/dev | cut -f1)" = "$d1" ] || fail "the unverified merge reached the remote"
git update-ref refs/notes/gates "$keep"; mv "$T/kept"/batch* .git/rapid/; "$R" land --prune >/dev/null || fail "prune the hollow batch"
[ "$(git rev-parse dev)" = "$d1" ] || fail "the prune did not put dev back"
# a merge whose own tree fails gates_each stops the close, by name, and nothing closes
"$R" branch feature three >/dev/null -r "Scenario branch three: a merge whose own tree is broken."; commit three.broken; "$R" land --batch >/dev/null || fail "land three"
v3=$(git describe --tags --abbrev=0 dev)
"$R" branch fix four >/dev/null -r "Scenario branch four: the repair that makes the final tree whole."
git rm -q three.broken; git commit -q -m "[FIX] Remove the broken file from the project" -m "Cause: the file broke the tree." -m "Fix: the file is removed."
"$R" land --batch >/dev/null || fail "land four"
refused "$R" land
grep -q "the batch gate each fails on the own tree of: $v3" "$T/err" || fail "the close did not name the merge that fails on its own tree: $(cat "$T/err")"
[ -s .git/rapid/batch ] || fail "a close stopped by gates_each dropped the batch"
