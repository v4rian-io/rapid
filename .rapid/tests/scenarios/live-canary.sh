#!/usr/bin/env bash
# fast
# the live canary (tests/canary/live.sh) is safe before it is live, verified against a gh stub: it
# writes nothing unless gh has the repo and workflow scopes (and names the refresh the owner runs),
# never asks for delete_repo and never deletes a repository; --dry-run names the persistent canary
# repository and the run; --cleanup RUN removes only that run's branches not landed yet (pool/*/*-RUN), never
# another run's branch, a landed branch, dev, main, a tag or a safety anchor.
. "$(dirname "$0")/../lib.sh"
C="$RAPID_SRC/tests/canary/live.sh"
[ -x "$C" ] || fail "no live canary"
grep -q 'delete_repo' "$C" && grep -qE 'repos/\$repo"? *>|DELETE "repos/\$repo"' "$C" && fail "the canary can delete a repository"
F="$T/forge"; mkdir -p "$F" "$T/bin"
cat > "$T/bin/gh" <<STUB
#!/bin/sh
echo "\$*" >> "$F/log"
case "\$1 \$2" in
  "api -i") printf 'HTTP/2 200\r\nX-OAuth-Scopes: %s\r\n\r\n{}\n' "\$(cat "$F/scopes")" ;;
  "api user") echo acme ;;
  "api -X") ref=\$(echo "\$4" | sed 's#^repos/acme/rapid-canary/git/##'); git -C "$T/origin.git" update-ref -d "\$ref" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$T/bin/gh"; export PATH="$T/bin:$PATH"
# a forge with the run's branches, another run's branch, dev, main, a tag and a safety anchor
git init -q --bare "$T/origin.git"; export RAPID_CANARY_URL="$T/origin.git"
git init -q "$T/w"; ( cd "$T/w" && git commit -q --allow-empty -m "[NEW] Seed the forge for the canary" && \
  for r in refs/heads/dev refs/heads/main refs/tags/v2026.0.1 refs/heads/safety/v2026.0/feature.widget-261112100000 \
           refs/heads/pool/v2026.0/feature.widget-261112100000 refs/heads/pool/v2026.0/refactor.review-261112100000 \
           refs/heads/pool/v2026.0/feature.widget-261112090000 refs/heads/pool/v2026.0/feature.widget-2611121000001; do git push -q "$T/origin.git" "HEAD:$r"; done )
# missing workflow scope: nothing is written
printf 'gist, repo' > "$F/scopes"
rc=0; bash "$C" > "$T/out" 2>"$T/err" || rc=$?
[ "$rc" = 2 ] || fail "a missing scope did not stop the canary (exit $rc)"
grep -qF "gh auth refresh -h github.com -s workflow" "$T/err" || fail "the refresh is not named: $(cat "$T/err")"
grep -qE 'repo create|-X' "$F/log" && fail "the canary wrote to the forge without the scope"
# never asks for delete_repo: repo and workflow suffice for a dry run
printf 'repo, workflow' > "$F/scopes"
bash "$C" --dry-run > "$T/out" 2>&1 || fail "dry run: $(cat "$T/out")"
grep -qE 'dry run: run [0-9]{12} on public acme/rapid-canary \(created when missing, never deleted\)' "$T/out" || fail "dry run plan: $(cat "$T/out")"
grep -qE 'repo create|-X' "$F/log" && fail "--dry-run wrote to the forge"
# cleanup of one run: only its branches not landed yet
bash "$C" --cleanup 261112100000 > "$T/out" 2>&1 || fail "cleanup: $(cat "$T/out")"
left=$(git -C "$T/origin.git" for-each-ref --format='%(refname)' | sort)
for gone in refs/heads/pool/v2026.0/feature.widget-261112100000 refs/heads/pool/v2026.0/refactor.review-261112100000; do
  grep -Fx "$gone" <<<"$left" >/dev/null && fail "$gone was not removed"
done
for kept in refs/heads/dev refs/heads/main refs/tags/v2026.0.1 refs/heads/safety/v2026.0/feature.widget-261112100000 \
            refs/heads/pool/v2026.0/feature.widget-261112090000 refs/heads/pool/v2026.0/feature.widget-2611121000001; do
  grep -Fx "$kept" <<<"$left" >/dev/null || fail "$kept was removed"
done
grep -qF "repos/acme/rapid-canary\"" "$F/log" && fail "a repository-level call was made"
refused bash "$C" --cleanup "../../dev"
grep -qF "is not a canary run id" "$T/err" || fail "a bad run id was not refused: $(cat "$T/err")"
