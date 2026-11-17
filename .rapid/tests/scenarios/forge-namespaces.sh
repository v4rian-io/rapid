#!/usr/bin/env bash
# the branch namespaces: anchors are branches safety/v<series>/<name> (an anchor commit on the
# fork point), landed tips branches vault/v<series>/<name>, so setup --remote's rapid-safety-lockdown,
# rapid-vault-readonly and rapid-branch-deletions rulesets (admins alone bypass) cover them, as the gh stub
# records; creating an anchor stays open to every lander, and pre-push refuses an anchor or a
# number key that names another branch. A forge that lets only admins delete branches keeps a landed or closed branch: the land and the
# close still succeed, status and doctor list it, and an admin's rapid branch --delete-landed removes it (never
# a branch not landed yet).
. "$(dirname "$0")/../lib.sh"
mkrepo "$T/r"; cd "$T/r"
# setup --remote: the three rulesets
B="$T/bin"; mkdir -p "$B" "$T/sets"
cat > "$B/gh" <<STUB
#!/bin/sh
case "\$*" in "api -X POST"*) cp "\$6" "$T/sets/" ;; esac
exit 0
STUB
chmod +x "$B/gh"
PATH="$B:$PATH" rapid setup --remote --repo acme/app >/dev/null || fail "setup --remote"
rs() { python3 - "$T/sets/$1.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print(d["name"], " ".join(d["conditions"]["ref_name"]["include"]), " ".join(r["type"] for r in d["rules"]),
      " ".join("%s:%s:%s" % (b["actor_type"], b["actor_id"], b["bypass_mode"]) for b in d["bypass_actors"]))
PY
}
[ "$(rs safety-lockdown)" = "rapid-safety-lockdown refs/heads/safety/* refs/heads/safety/*/* update deletion RepositoryRole:5:always" ] || fail "safety-lockdown: $(rs safety-lockdown)"
[ "$(rs vault-readonly)" = "rapid-vault-readonly refs/heads/vault/* refs/heads/vault/*/* update deletion RepositoryRole:5:always" ] || fail "vault-readonly: $(rs vault-readonly)"
[ "$(rs branch-deletions)" = "rapid-branch-deletions refs/heads/pool/* refs/heads/pool/*/* deletion RepositoryRole:5:always" ] || fail "branch-deletions: $(rs branch-deletions)"
rm -rf .github
# a forge where this developer is no admin: the server refuses deleting a branch, and creating,
# moving or deleting a safety or vault branch it already holds
O=$(mkremote origin); git remote add origin "$O"; rapid setup >/dev/null
cat > "$O/hooks/pre-receive" <<'HOOK'
#!/bin/sh
[ -f "$GIT_DIR/admin" ] && exit 0
z=0000000000000000000000000000000000000000
while read old new ref; do
  case "$ref" in
    refs/heads/pool/*) [ "$new" = "$z" ] && { echo "ruleset: only admins delete $ref"; exit 1; } ;;
    refs/heads/safety/*|refs/heads/vault/*) [ "$old" = "$z" ] || { echo "ruleset: $ref is frozen"; exit 1; } ;;
  esac
done
exit 0
HOOK
chmod +x "$O/hooks/pre-receive"
rapid branch feature kept >/dev/null; commit k.txt; L=$(lname kept); a="refs/heads/safety/${L#pool/}"
[ "$(git rev-parse "$a^1")" = "$(git rev-parse dev)" ] || fail "the anchor branch is not on the fork point"
git push -q origin "$L" || fail "branch push"
settle
# a non-admin's branch takes a plain number with origin in reach, and its push wrote its own anchor there
[[ "$L" =~ ^pool/v2026[.]0/n[0-9]+[.]feature[.]kept$ ]] || fail "the branch was not numbered online: $L"
# no anchor is forged under another branch's name
refused git push -q origin "$a:refs/heads/safety/v2026.0/n77.feature.other"
grep -q 'is the anchor of branch' "$T/err" || fail "an anchor under another branch's name passed: $(cat "$T/err")"
[ "$(git ls-remote origin "$a" | cut -f1)" = "$(git rev-parse "$a")" ] || fail "the branch push did not carry the anchor branch"
rapid land > "$T/out" 2>&1 || fail "land with a forge that keeps branches: $(cat "$T/out")"
grep -q "stays on origin" "$T/out" || fail "the land did not say the branch stays: $(cat "$T/out")"
[ -n "$(rbranch origin kept)" ] || fail "a non-admin's land deleted the branch"
[ "$(git ls-remote origin dev | cut -f1)" = "$(git rev-parse dev)" ] || fail "dev did not land on origin"
[ "$(git ls-remote origin "refs/heads/vault/${L#pool/}" | cut -f1)" = "$(git rev-parse dev^2)" ] || fail "no vault branch on the landed tip"
rapid status > "$T/out"; grep -q "landed, still on origin.*$L" "$T/out" || fail "status does not list the landed branch: $(cat "$T/out")"
rapid doctor > "$T/out" 2>&1 || true; grep -q "still on origin.*$L" "$T/out" || fail "doctor does not list the landed branch: $(cat "$T/out")"
# a branch never landed stays a branch: status and doctor list it as not landed yet
rapid branch feature idle >/dev/null; commit i.txt; I=$(lname idle); git push -q origin "$I"
settle
rapid status > "$T/out"; grep -q "branches not landed yet: .*$I" "$T/out" || fail "status does not list the branch not landed yet: $(cat "$T/out")"
rapid doctor > "$T/out" 2>&1 || true; grep -q "branches not landed yet: .*$I" "$T/out" || fail "doctor does not list the branch not landed yet: $(cat "$T/out")"
# an admin deletes the landed branch, never the one not landed yet
refused rapid branch --delete-landed "$L"
grep -q 'only a repository admin' "$T/err" || fail "a non-admin delete did not say why: $(cat "$T/err")"
touch "$O/admin"
rapid branch --delete-landed "$I" > "$T/out" 2>&1 && fail "a branch not landed yet was deleted"
[ -n "$(rbranch origin idle)" ] || fail "delete deleted a branch not landed yet"
rapid branch --delete-landed > "$T/out" 2>&1 || fail "delete: $(cat "$T/out")"
[ -z "$(rbranch origin kept)" ] || fail "the admin's delete left the landed branch"
history_clean
