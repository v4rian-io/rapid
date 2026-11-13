#!/usr/bin/env bash
# when main's ruleset on the forge requires a pull request (gh stub), rapid release opens the dev to
# main PR and merges it through the forge's API (merge_method=merge, sha=dev's tip, the release subject
# and body), then checks origin main is the release merge (parents old main and dev, dev's tree) before
# it pushes release/<v>; a release whose tag push failed is finished by the next rapid release; a merge
# the forge declines exits 3 with main and tags unchanged; a forge merge that is not the release merge
# (a squash) is refused and nothing is tagged.
. "$(dirname "$0")/../lib.sh"
actor "Owner One" owner@team.test
mkrepo "$T/r"; cd "$T/r"
O=$(mkremote origin); git remote add origin "$O"; rapid setup >/dev/null
P="$T/forge"; mkdir -p "$P" "$T/bin"; echo merge > "$P/mode"
cat > "$T/bin/gh" <<STUB
#!/bin/sh
echo "\$*" >> "$P/log"
case "\$1 \$2" in
  "pr list") [ -f "$P/num" ] && cat "$P/num"; exit 0 ;;
  "pr create") echo 5 > "$P/num"; exit 0 ;;
  "pr edit") exit 0 ;;
esac
case "\$*" in
  "api repos/acme/app/rules/branches/main"*) echo pull_request; exit 0 ;;
  "api -X PUT repos/acme/app/pulls/5/merge"*)
    mode=\$(cat "$P/mode"); [ "\$mode" = decline ] && exit 1
    sha=""; title=""; body=""
    while [ \$# -gt 0 ]; do
      case "\$2" in sha=*) sha=\${2#sha=} ;; commit_title=*) title=\${2#commit_title=} ;; commit_message=*) body=\${2#commit_message=} ;; esac
      shift
    done
    main=\$(git --git-dir="$O" rev-parse main); tree=\$(git --git-dir="$O" rev-parse "\$sha^{tree}")
    if [ "\$mode" = squash ]; then m=\$(git --git-dir="$O" commit-tree "\$tree" -p "\$main" -m "\$title")
    else m=\$(git --git-dir="$O" commit-tree "\$tree" -p "\$main" -p "\$sha" -m "\$title" -m "\$body"); fi
    git --git-dir="$O" update-ref refs/heads/main "\$m"; rm -f "$P/num"; exit 0 ;;
esac
exit 1
STUB
chmod +x "$T/bin/gh"; export PATH="$T/bin:$PATH"
rapid branch refactor forge -r "The forge repository the release PR goes to." >/dev/null
printf 'forge_repo=acme/app\n' >> .rapid/conf; git add .rapid/conf; git commit -q -m "[MODE] Name the forge repository"
rapid land >/dev/null || fail "land the forge conf"
rapid branch feature export >/dev/null; commit export.txt; rapid land >/dev/null || fail "land export"
main0=$(git rev-parse main); d=$(git rev-parse dev); v=$(git describe --exact-match --match 'v*' dev)
rapid release > "$T/out" 2>&1 || fail "release through the PR: $(cat "$T/out")"
grep -q '^pr create --repo acme/app --base main --head dev --title \[MERGE\] dev into main: '"$v" "$P/log" || fail "no dev to main PR: $(cat "$P/log")"
grep -q "^api -X PUT repos/acme/app/pulls/5/merge -f merge_method=merge -f sha=$d -f commit_title=\[MERGE\] dev into main: $v" "$P/log" || fail "the PR was not merged by the API: $(cat "$P/log")"
om=$(git ls-remote origin refs/heads/main | cut -f1)
[ "$(git rev-list --parents -n1 "$om")" = "$om $main0 $d" ] || fail "origin main is not the release merge of dev"
[ "$(git rev-parse "$om^{tree}")" = "$(git rev-parse "$d^{tree}")" ] || fail "the release merge's tree is not dev's"
[ -n "$(git ls-remote origin "refs/tags/release/$v")" ] || fail "the release tag is not on origin"
[ "$(git rev-parse main)" = "$om" ] || fail "local main is not the forge's merge"
history_clean
# the tag push failed after the merge: the next rapid release pushes it
git --git-dir="$O" update-ref -d "refs/tags/release/$v"
rapid release > "$T/out" 2>&1 || fail "resume the tag push: $(cat "$T/out")"
grep -q 'pushed the release tag of the merge' "$T/out" || fail "the resume did not say so: $(cat "$T/out")"
[ -n "$(git ls-remote origin "refs/tags/release/$v")" ] || fail "the resumed tag is not on origin"
# the forge declines (reviews pending): exit 3, nothing changes
rapid branch feature import >/dev/null; commit import.txt; rapid land >/dev/null || fail "land import"
v2=$(git describe --exact-match --match 'v*' dev); m1=$(git rev-parse main)
echo decline > "$P/mode"
rc=0; rapid release > "$T/out" 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "a declined merge did not exit 3 ($rc): $(cat "$T/out")"
[ -z "$(git tag -l "release/$v2")" ] && [ -z "$(git ls-remote origin "refs/tags/release/$v2")" ] || fail "a declined release was tagged"
[ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$m1" ] || fail "origin main moved on a declined merge"
# a forge merge that is not the release merge (a squash) is refused and never tagged
echo squash > "$P/mode"
refused rapid release
grep -q 'is not the release merge' "$T/err" || fail "a squash merge was accepted: $(cat "$T/err")"
[ -z "$(git tag -l "release/$v2")" ] && [ -z "$(git ls-remote origin "refs/tags/release/$v2")" ] || fail "a squash release was tagged"
