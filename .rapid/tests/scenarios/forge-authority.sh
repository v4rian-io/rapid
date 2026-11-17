#!/usr/bin/env bash
# the forge checks a candidate with dev's checker, never the candidate's: run from the workflow
# file itself, the rapid-check step fails a branch head that replaces .rapid/rapid with a stub over a failing
# tree and passes an honest land --pr candidate and the dev push that lands it. With land_pr=required
# setup --remote adds GitHub's review rule (land_approvals approvals, stale ones dismissed, the last
# push approved) next to the rapid-check status. The workflow's rapid-linux job
# runs the full gate on ubuntu with dev's checker, and the history checks start after the base.
# A repository that pins a tag in .rapid/version, holding no rapid of its own, gets rapid installed by the
# same steps (the documented installer, RAPID_HOME in the runner's temp directory), run at the pin of the base,
# never the pin of the candidate's tree; a pin the install lacks fails.
. "$(dirname "$0")/../lib.sh"
# the framework's own repository: it holds its rapid, so the copy dev holds checks its branches
selfhosted "$T/a" origin; cd "$T/a"
P="$T/forge"; mkdir -p "$P" "$T/bin"; : > "$P/approvals"; echo 0 > "$P/checks"
cat > "$T/bin/gh" <<STUB
#!/bin/sh
case "\$1 \$2" in
  "pr list") [ -f "$P/num" ] && cat "$P/num" ;;
  "pr create") echo 7 > "$P/num" ;;
  "pr edit"|"pr comment") ;;
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
        while [ \$# -gt 0 ]; do [ "\$1" = --input ] && { cat "\$2"; echo; } >> "$P/rulesets"; shift; done ;;
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
chmod +x "$T/bin/gh"; export PATH="$T/bin:$PATH" GITHUB_REPOSITORY=acme/app RUNNER_TEMP="$T"
WF="$RAPID_SRC/remote/check.yml"
# step FILE NAME: the run: script of the workflow step named NAME, as the runner would execute it
step() {
  awk -v n="$2" 'index($0, "- name: " n) == 0 && !f { next }
    !f { f = 1; next }
    f && !r && /^ *run: \|$/ { r = 1; match($0, /^ */); ind = RLENGTH; next }
    r { match($0, /^ */); if ($0 !~ /^ *$/ && RLENGTH <= ind) exit; print substr($0, ind + 3) }' "$1"
}
step "$WF" "history invariants, branch commits and gate tests" > "$T/check.sh"
step "$WF" "full gate on Linux" > "$T/linux.sh"
[ -s "$T/check.sh" ] && [ -s "$T/linux.sh" ] || fail "the workflow lacks the rapid-check or the rapid-linux step"
grep -q 'git archive' "$T/check.sh" || fail "the rapid-check step does not take the checker from dev"
awk '/^  rapid-linux:/ { f = 1 } f && /runs-on: ubuntu-latest/ { ok = 1 } END { exit !ok }' "$WF" || fail "no rapid-linux job on ubuntu"
grep -q 'doctor --history-only --since' "$T/check.sh" || fail "the history check walks every merge on every push"
# ci REF SHA STEP [BEFORE]: a fresh clone of origin at SHA, the step run there as the runner would
ci() {
  local d; d=$(mktemp -d "$T/ci.XXXXXX"); git clone -q "$T/origin.git" "$d/c"
  ( cd "$d/c" && git checkout -q --detach "$2" && PUSHED_REF="$1" BEFORE="${4:-}" bash "$3" )
}
# review policy on dev: two approvals
rapid branch refactor review-policy -r "Lands go through review on the forge." >/dev/null
# max_commit_lines lifted: the hostile candidate below replaces the whole checker, and this scenario
# verifies the forge reruns its gates (commit-audit verifies the size cap)
printf 'land_pr=required\nland_approvals=2\nforge_repo=acme/app\nmax_commit_lines=99999\n' >> .rapid/conf
git add .rapid/conf; git commit -q -m "[MODE] Require two approvals before a land"
rapid land >/dev/null || fail "land the review policy"
d=$(git rev-parse dev)
# a hostile candidate: its tree replaces the checker with a stub and breaks the gate
git clone -q "$T/origin.git" "$T/h"; cd "$T/h"; git switch -q dev
git switch -q -c pool/v2026.0/feature.hostile
printf '#!/bin/sh\necho "ok (stub checker from the candidate tree)"; exit 0\n' > .rapid/rapid
mkdir -p .rapid/requirements; printf '# feature/hostile\n\nReplace the checker and break the gate.\n' > .rapid/requirements/hostile.md
echo bad > y.bad; git add .rapid/rapid .rapid/requirements/hostile.md y.bad
git -c core.hooksPath=/dev/null commit -q -m "[NEW] Replace the checker to break the gate"
tree=$(git rev-parse HEAD^{tree})
printf '[MERGE] pool/v2026.0/feature.hostile into dev: v2026.0.2\n\nForges a green candidate.\n\n- The checker is a stub now.\n\nBranch-Base: %s\nRequirement: .rapid/requirements/hostile.md\nGates: fast=pass full=pass\nTested-Tree: %s\nBranch-Number: n9\n' "$d" "$tree" > "$T/msg"
mh=$(git commit-tree "$tree" -p "$d" -p HEAD -F "$T/msg")
git push -q --no-verify origin "$mh:refs/heads/pool/v2026.0/feature.hostile"
printf 'alice %s\nbob %s\n' "$mh" "$mh" > "$P/approvals"; echo 7 > "$P/num"
if ci refs/heads/pool/v2026.0/feature.hostile "$mh" "$T/check.sh" > "$T/out" 2>&1; then fail "the rapid-check step passed a candidate that replaced the checker: $(cat "$T/out")"; fi
grep -q 'stub checker' "$T/out" && fail "the candidate's own checker ran: $(cat "$T/out")"
grep -q 'gates do not pass' "$T/out" || fail "dev's checker did not check the candidate: $(cat "$T/out")"
if ci refs/heads/pool/v2026.0/feature.hostile "$mh" "$T/linux.sh" > "$T/out" 2>&1; then fail "the rapid-linux step passed a failing tree: $(cat "$T/out")"; fi
# an honest candidate passes the same step, then lands, and the dev push passes too
cd "$T/a"; rm -f "$P/num"
rapid branch feature widget >/dev/null; commit widget.txt w "[NEW] Add the widget to the project"
rc=0; rapid land --pr >/dev/null 2>&1 || rc=$?; [ "$rc" = 3 ] || fail "land --pr: exit $rc, want 3"
w=$(rbranch origin widget); m=$(git ls-remote origin "$w" | cut -f1)
printf 'alice %s\nbob %s\n' "$m" "$m" > "$P/approvals"
ci "$w" "$m" "$T/check.sh" > "$T/out" 2>&1 || fail "the rapid-check step failed an honest candidate: $(cat "$T/out")"
ci "$w" "$m" "$T/linux.sh" > "$T/out" 2>&1 || fail "the rapid-linux step failed an honest candidate: $(cat "$T/out")"
echo 1 > "$P/checks"
rapid land --pr >/dev/null 2>&1 || fail "land --pr once approved and checked"
m=$(git rev-parse dev)
ci refs/heads/dev "$m" "$T/check.sh" "$d" > "$T/out" 2>&1 || fail "the rapid-check step failed the dev push: $(cat "$T/out")"
ci refs/heads/dev "$m" "$T/check.sh" 0000000000000000000000000000000000000000 > "$T/out" 2>&1 || fail "the rapid-check step failed a first dev push: $(cat "$T/out")"
# the rulesets: GitHub's review rule and the status on dev
rapid setup --remote --repo acme/app >/dev/null 2>&1 || fail "setup --remote"
r=$(tr -d '\n' < "$P/rulesets")
grep -q '"type": "pull_request", "parameters": { "required_approving_review_count": 2, "dismiss_stale_reviews_on_push": true, "require_last_push_approval": true' <<<"$r" \
  || fail "dev's ruleset lacks GitHub's review rule: $r"
grep -q '"context": "rapid-check"' <<<"$r" || fail "dev's ruleset lacks the rapid-check status: $r"
history_clean
# the installed path: a repository whose dev holds .rapid/version, no .rapid/rapid. The step installs rapid
# with the documented line (a curl stub answers with an installer that makes the clone, its tag, the rapid
# on PATH), then runs the same check through that rapid
mkdir -p "$T/p" "$T/phome" "$T/pbin"; cd "$T/p"; git init -q; git symbolic-ref HEAD refs/heads/dev
mkdir .rapid; echo v2026.9.9 > .rapid/version; git add .rapid/version
git -c core.hooksPath=/dev/null commit -q -m "[NEW] Pin the release of rapid"
cat > "$T/pbin/curl" <<STUB
#!/bin/sh
echo "\$*" > "$T/curl.args"
cat <<'INSTALLER'
git init -q "\$RAPID_HOME"; git -C "\$RAPID_HOME" -c core.hooksPath=/dev/null commit -q --allow-empty -m "[NEW] Release the tool"
git -C "\$RAPID_HOME" tag v2026.9.9
printf '#!/bin/sh\necho "\$RAPID_CONF_REV \$*" >> "\$RAPID_HOME/ran"\n' > "\$HOME/.local/bin/rapid"; chmod +x "\$HOME/.local/bin/rapid"
INSTALLER
STUB
chmod +x "$T/pbin/curl"
# the candidate's tree pins another release: the checker still runs at the pin of the base
echo v2026.9.7 > .rapid/version
( HOME="$T/phome" RUNNER_TEMP="$T/ptmp" PATH="$T/pbin:$PATH" bash "$T/linux.sh" ) > "$T/out" 2>&1 || fail "the rapid-linux step on a pinned repository: $(cat "$T/out")"
[ "$(cat .rapid/version)" = v2026.9.9 ] || fail "the checker runs at the pin of the candidate's tree ($(cat .rapid/version)), not of the base"
grep -qF 'https://raw.githubusercontent.com/v4rian-io/rapid/refs/tags/v2026.9.9/.rapid/install.sh' "$T/curl.args" || fail "the step did not fetch the installer of the tag the base pins: $(cat "$T/curl.args")"
[ "$(cat "$T/ptmp/rapid/ran")" = "refs/heads/dev check --gate full" ] || fail "the installed rapid did not run the gate: $(cat "$T/ptmp/rapid/ran" 2>&1)"
# a pin the installed rapid holds no tag for is refused by name
echo v2026.9.8 > .rapid/version; git add .rapid/version; git -c core.hooksPath=/dev/null commit -q -m "[NEW] Pin a release nobody made"
if ( HOME="$T/phome" RUNNER_TEMP="$T/ptmp2" PATH="$T/pbin:$PATH" bash "$T/linux.sh" ) > "$T/out" 2>&1; then fail "a pin with no tag passed: $(cat "$T/out")"; fi
grep -qF 'the installed rapid holds no tag v2026.9.8' "$T/out" || fail "the missing tag is not named: $(cat "$T/out")"
