#!/usr/bin/env bash
# PR path bound to the tested head: with land_pr=required a plain land is refused; land --pr
# publishes the branch head the gates ran on and opens the PR with the merge subject and body, counts
# only approvals given on that sha, waits for the rapid-check and commit-audit statuses on it, then
# merges through GitHub's merge API (merge-once: rapid's subject and body), verifies the merge (parents
# old dev and the tested head, Tested-Tree, subject) and tags it. A new branch commit makes a new head
# and earlier approvals stop counting. setup --remote then requires rapid-check on dev, and check
# --merge is the forge's verification of a merge candidate.
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r" origin; cd "$T/r"
# forge mock: PR 7; approvals "login sha" per line; check-runs count; rulesets captured
P="$T/forge"; mkdir -p "$P" "$T/bin"; : > "$P/approvals"; echo 0 > "$P/checks"
cat > "$T/bin/gh" <<STUB
#!/bin/sh
echo "\$*" >> "$P/log"
case "\$1 \$2" in
  "pr list") [ -f "$P/num" ] && cat "$P/num" ;;
  "pr create") echo 7 > "$P/num"; while [ \$# -gt 0 ]; do [ "\$1" = --body-file ] && cp "\$2" "$P/body"; [ "\$1" = --title ] && printf '%s\n' "\$2" > "$P/title"; shift; done ;;
  "pr edit") while [ \$# -gt 0 ]; do [ "\$1" = --body-file ] && cp "\$2" "$P/body"; shift; done ;;
  "pr comment") ;;
  "api repos/acme/app/rulesets") echo "" ;;
  "api -X")
    case "\$4" in
      */pulls/*/merge)
        # GitHub's merge API: one merge of the PR head into dev, rapid's subject and body
        o="$T/origin.git"; shift 4; sha=""; t=""; msg=""
        while [ \$# -gt 0 ]; do case "\$1" in
          -f) case "\$2" in sha=*) sha="\${2#sha=}" ;; commit_title=*) t="\${2#commit_title=}" ;; commit_message=*) msg="\${2#commit_message=}" ;; esac; shift 2 ;;
          *) shift ;; esac; done
        dev=\$(git -C "\$o" rev-parse refs/heads/dev); tree=\$(git -C "\$o" rev-parse "\$sha^{tree}")
        m=\$(printf '%s\n\n%s\n' "\$t" "\$msg" | git -C "\$o" commit-tree "\$tree" -p "\$dev" -p "\$sha")
        git -C "\$o" update-ref refs/heads/dev "\$m" "\$dev"; echo "\$m" ;;
      *)
        while [ \$# -gt 0 ]; do [ "\$1" = --input ] && cat "\$2" >> "$P/rulesets"; shift; done ;;
    esac ;;
  api*)
    case "\$2" in
      */reviews) sha=\$(printf '%s' "\$*" | grep -oE '[0-9a-f]{40}' | head -1); grep -c " \$sha\$" "$P/approvals" || true ;;
      */check-runs) cat "$P/checks" ;;
      */pulls) cat "$P/num" ;;
      *) exit 1 ;;
    esac ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$T/bin/gh"; export PATH="$T/bin:$PATH"
rapid branch refactor review-policy -r "Lands go through review." >/dev/null
printf 'land_pr=required\nland_approvals=2\nforge_repo=acme/app\n' >> .rapid/conf
git add .rapid/conf; git commit -q -m "[MODE] Require two approvals before a land"
rapid land >/dev/null || fail "land the policy (dev's conf still says optional)"
rapid branch feature widget >/dev/null; commit widget.txt w "[NEW] Add the widget to the project"
refused rapid land
grep -q 'land_pr=required' "$T/err" || fail "plain land not refused under land_pr=required: $(cat "$T/err")"
rc=0; rapid land --pr >"$T/out" 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "land --pr without approvals: exit $rc, want 3: $(cat "$T/out")"
[ "$(cat "$P/num")" = 7 ] || fail "no PR was opened"
grep -q '^\[MERGE\] pool/[^ ]*[.]feature[.]widget into dev: ' "$P/title" || fail "PR title is not the merge subject: $(cat "$P/title")"
m1=$(git ls-remote origin "$(rbranch origin widget)" | cut -f1); d0=$(git rev-parse dev)
[ "$m1" = "$(git rev-parse HEAD)" ] || fail "the branch's head on origin is not the tested branch head"
[ "$(git rev-parse dev)" = "$(git ls-remote origin refs/heads/dev | cut -f1)" ] || fail "dev moved while waiting"
printf 'alice %s\nbob %s\n' "$m1" "0000000000000000000000000000000000000000" > "$P/approvals"
rc=0; rapid land --pr >"$T/out" 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "one approval on the merge (one stale) landed: $(cat "$T/out")"
[ "$(git ls-remote origin "$(rbranch origin widget)" | cut -f1)" = "$m1" ] || fail "an unchanged branch changed its head"
printf 'alice %s\nbob %s\n' "$m1" "$m1" > "$P/approvals"
rc=0; rapid land --pr >"$T/out" 2>&1 || rc=$?
[ "$rc" = 3 ] && grep -q 'rapid-check' "$T/out" || fail "landed before the rapid-check status passed: $rc $(cat "$T/out")"
echo 1 > "$P/checks"
rapid land --pr >"$T/out" 2>&1 || fail "land --pr with two approvals and rapid-check: $(cat "$T/out")"
mg=$(git rev-parse dev)
[ "$(git rev-list --parents -n1 "$mg")" = "$mg $d0 $m1" ] || fail "dev is not the merge of the old dev and the approved head"
[ "$(git ls-remote origin refs/heads/dev | cut -f1)" = "$mg" ] || fail "origin dev does not carry the merge"
grep -q 'pulls/7/merge' "$P/log" || fail "the merge was not made through the PR merge API"
git describe --exact-match "$mg" >/dev/null || fail "the PR merge carries no version tag"
[ "$(git ls-remote origin "refs/tags/$(git describe --exact-match "$mg")" | cut -f1)" ] || fail "the version tag was not pushed"
m1="$mg"
[ -z "$(rbranch origin widget)" ] || fail "the landed branch was not deleted on origin"
mb=$(git log -1 --format=%B "$m1" | sed '1,2d'); pb=$(cat "$P/body")
[ "$mb" = "$pb" ] || fail "PR body differs from the merge body"
! grep -q '^pr merge' "$P/log" || fail "the forge merge button was used"
# a new commit makes a new merge: approvals of the old head stop counting
rm -f "$P/num"; echo 0 > "$P/checks"
rapid branch feature gadget >/dev/null; commit gadget.txt g "[NEW] Add the gadget to the project"
rc=0; rapid land --pr >/dev/null 2>&1 || rc=$?; [ "$rc" = 3 ] || fail "gadget: first land --pr"
ma=$(git ls-remote origin "$(rbranch origin gadget)" | cut -f1)
printf 'alice %s\nbob %s\n' "$ma" "$ma" > "$P/approvals"; echo 1 > "$P/checks"
commit gadget2.txt g2 "[NEW] Add a second gadget file to the project"
rc=0; rapid land --pr >"$T/out" 2>&1 || rc=$?
mb2=$(git ls-remote origin "$(rbranch origin gadget)" | cut -f1)
[ "$mb2" != "$ma" ] || fail "a new branch commit did not make a new head"
[ "$rc" = 3 ] || fail "approvals of the old merge counted for the new one: $(cat "$T/out")"
# the forge's verification of a merge candidate (the land --pr shape under land_pr=optional)
mb2=$(rapid land --pr --dry-run 2>/dev/null | sed -n 's/^  | //p' | git commit-tree "HEAD^{tree}" -p dev -p HEAD)
git push -q origin "$mb2:$(rbranch origin gadget)" 2>/dev/null || git push -q --no-verify -f origin "$mb2:$(rbranch origin gadget)"
GITHUB_REPOSITORY=acme/app rapid check --merge "$mb2" >"$T/out" 2>&1 && fail "check --merge passed without approvals on the candidate"
printf 'alice %s\nbob %s\n' "$mb2" "$mb2" > "$P/approvals"
GITHUB_REPOSITORY=acme/app rapid check --merge "$mb2" >"$T/out" 2>&1 || fail "check --merge with approvals: $(cat "$T/out")"
# setup --remote requires rapid-check on dev under land_pr=required
rapid setup --remote --repo acme/app >/dev/null 2>&1 || fail "setup --remote"
grep -q '"context": "rapid-check"' "$P/rulesets" || fail "the protected ruleset does not require rapid-check: $(cat "$P/rulesets")"
grep -q '"require_last_push_approval": true' "$P/rulesets" || fail "two approvals render without the last-push approval: $(cat "$P/rulesets")"
# with land_approvals=0 the review rule asks for no approval, so none for the last push either (live canary C7)
git switch -q dev; rapid branch refactor no-approvals -r "Lands go through a pull request with no approval required." >/dev/null
sed -i.bak 's/^land_approvals=2$/land_approvals=0/' .rapid/conf; rm -f .rapid/conf.bak; git add .rapid/conf
git commit -q -m "[MODE] Require no approval on a pull request"
rm -f "$P/num"; echo 1 > "$P/checks"; : > "$P/rulesets"
printf 'alice %s\nbob %s\n' "$(git rev-parse HEAD)" "$(git rev-parse HEAD)" > "$P/approvals"   # dev's conf still asks for two
rc=0; rapid land --pr >"$T/out" 2>&1 || rc=$?
[ "$rc" = 0 ] || { [ "$rc" = 3 ] && rapid land --pr >"$T/out" 2>&1; } || fail "land --pr with no approval required: $(cat "$T/out")"
rapid setup --remote --repo acme/app >/dev/null 2>&1 || fail "setup --remote with no approvals"
grep -q '"required_approving_review_count": 0, "dismiss_stale_reviews_on_push": true, "require_last_push_approval": false' "$P/rulesets" \
  || fail "no approvals still render the last-push approval: $(cat "$P/rulesets")"
history_clean
