#!/usr/bin/env bash
# the shipped tracker adapters speak the one contract, whatever the provider: trackers/github (gh),
# trackers/jira (curl on the REST API) and trackers/mcp (any MCP server through Claude Code) each answer
# get, link and transition with one JSON object, verified offline against a fake gh, curl and claude put
# first on PATH. A missing credential is a named refusal before any call, never a silent pass; the JIRA
# token never reaches a command line; the MCP call runs in a scrubbed environment, an answer not bound
# to its nonce fails, and a get whose run called a tool that is not a read of the server is dropped. Through rapid, a branch takes its requirement from the ticket and the land moves it to done.
. "$(dirname "$0")/../lib.sh"
A="$RAPID_SRC/trackers"
unset GH_TOKEN GITHUB_TOKEN GH_HOST RAPID_GITHUB_REPO RAPID_JIRA_URL RAPID_JIRA_USER RAPID_JIRA_TOKEN \
  RAPID_JIRA_STATUS_DONE RAPID_MCP_SERVER RAPID_MCP_CMD RAPID_MCP_LOGIN CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY
mkdir -p "$T/bin" "$T/home"; export HOME="$T/home" PATH="$T/bin:$PATH"
has() { grep -F -- "$2" "$1" >/dev/null 2>&1; }
said() { has "$T/err" "$1" || fail "expected the refusal '$1', got: $(cat "$T/err")"; }

# ---- the fakes
cat > "$T/bin/gh" <<STUB
#!/bin/sh
case "\$1 \$2" in
  "auth token") [ -f "$T/gh-login" ]; exit ;;
esac
printf '%s\n' "\$*" >> "$T/gh.log"
case "\$1 \$2" in
  "issue view") printf '{"number": 7, "title": "Export reports as CSV", "body": "Rows out.", "state": "OPEN", "url": "https://github.example/acme/app/issues/7"}\n' ;;
  "issue comment"|"issue close") ;;
  *) exit 1 ;;
esac
STUB
cat > "$T/bin/curl" <<STUB
#!/bin/sh
cat > "$T/curl.stdin"
printf '%s\n' "\$*" >> "$T/curl.log"
case "\$*" in
  *"-X GET"*/transitions) printf '{"transitions": [{"id": "11", "name": "Start", "to": {"name": "In Progress"}}, {"id": "31", "name": "Close issue", "to": {"name": "Done"}}]}\n' ;;
  *"-X GET"*) printf '{"key": "KB-12", "fields": {"summary": "Import reports from CSV", "description": "Rows in.", "status": {"name": "To Do"}}}\n' ;;
  *) printf '{}\n' ;;
esac
STUB
cat > "$T/bin/claude" <<STUB
#!/bin/sh
p=\$(cat); printf '%s\n' "\$*" > "$T/mcp.argv"; printf '%s\n' "\$p" > "$T/mcp.prompt"; env > "$T/mcp.env"
n=\$(printf '%s\n' "\$p" | sed -n 's/^BEGIN DATA-//p')
# asked for its events (get), the stub reports the tools it called, then its answer, as Claude Code does
pre=\$(printf '%s' "\$*" | sed -nE 's/.*--allowedTools (mcp__[A-Za-z0-9_-]+__)[*].*/\\1/p'); tools="\${pre}get_card"
[ "\$(cat "$T/mcp.mode")" != wrote ] || tools="\$tools \${pre}move_card"
answer() {
  case "\$1" in
    *stream-json*) python3 -c 'import json, sys
for t in sys.argv[1:]: print(json.dumps({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": t}]}}))
print(json.dumps({"type": "result", "subtype": "success", "result": sys.stdin.read()}))' \$tools ;;
    *) cat ;;
  esac
}
case "\$(cat "$T/mcp.mode")" in
  good|wrote) case "\$p" in
      *'["get"'*) printf 'Reading the card.\nRESULT %s {"key": "CARD-9", "title": "Board card twelve", "body": "", "state": "todo", "url": ""}\n' "\$n" ;;
      *) printf 'RESULT %s {"ok": true}\n' "\$n" ;;
    esac ;;
  forged) printf 'RESULT 0000000000000000 {"ok": true}\n' ;;
  failed) printf 'FAILED %s the board has no such card\n' "\$n" ;;
  notjson) printf 'RESULT %s done\n' "\$n" ;;
esac | answer "\$*"
STUB
chmod +x "$T/bin/gh" "$T/bin/curl" "$T/bin/claude"
branch=pool/v2026.0/n1.feature.exports

# ---- every adapter refuses a call that is not the contract's, before any credential or provider
for a in github jira mcp; do
  refused "$A/$a" create --title x; said "usage: $a get <ID>"
  refused "$A/$a" get kb12; said "a ticket id looks like CODE-123"
  refused "$A/$a" get KB-12 --branch x; said "get does not take --branch"
  refused "$A/$a" link KB-12; said "link needs --branch"
  refused "$A/$a" link KB-12 --branch; said "--branch needs a value"
  refused "$A/$a" transition KB-12 --to closed; said "transition needs --to done"
done
[ ! -e "$T/gh.log" ] && [ ! -e "$T/curl.log" ] && [ ! -e "$T/mcp.argv" ] || fail "a refused call reached a provider"

# ---- github
cd "$T"
refused "$A/github" get GH-7; said "no GitHub credential: set GH_TOKEN"
[ ! -e "$T/gh.log" ] || fail "github called gh without a credential: $(cat "$T/gh.log")"
export GH_TOKEN=test-token
refused "$A/github" get KB-7; said "a GitHub ticket id is GH-<issue number>"
refused "$A/github" get GH-7; said "set RAPID_GITHUB_REPO=owner/repo"
export RAPID_GITHUB_REPO=acme/app
out=$("$A/github" get GH-7) || fail "github get"
case "$out" in '{"key": "GH-7", "title": "Export reports as CSV", '*'}') ;; *) fail "github get answered: $out" ;; esac
has "$T/gh.log" "issue view 7 --repo acme/app --json number,title,body,state,url" || fail "github get: $(cat "$T/gh.log")"
[ "$("$A/github" link GH-7 --branch "$branch")" = '{"ok": true}' ] || fail "github link"
has "$T/gh.log" "issue comment 7 --repo acme/app --body rapid branch $branch now carries GH-7." || fail "github link: $(cat "$T/gh.log")"
[ "$("$A/github" transition GH-7 --to done --ref v2026.0.1)" = '{"ok": true}' ] || fail "github transition"
has "$T/gh.log" "issue close 7 --repo acme/app --comment Landed as v2026.0.1." || fail "github transition: $(cat "$T/gh.log")"
"$A/github" transition GH-7 --to in-review >/dev/null || fail "github in-review"
has "$T/gh.log" "issue comment 7 --repo acme/app --body rapid: in-review." || fail "github in-review: $(cat "$T/gh.log")"
# owner/repo read from origin; the login gh itself keeps counts as the credential
unset RAPID_GITHUB_REPO GH_TOKEN; touch "$T/gh-login"
mkdir "$T/o"; git -C "$T/o" init -q; git -C "$T/o" remote add origin ssh://git@github.example:22/umbrella/tools.git
( cd "$T/o" && "$A/github" get GH-7 >/dev/null ) || fail "github with gh's own login and origin's repo"
has "$T/gh.log" "issue view 7 --repo umbrella/tools " || fail "owner/repo not read from origin: $(tail -n 1 "$T/gh.log")"
mv "$T/gh-login" "$T/gh-login.off"

# ---- jira
refused "$A/jira" get KB-12; said "no JIRA site: set RAPID_JIRA_URL"
export RAPID_JIRA_URL=http://jira.example.com
refused "$A/jira" get KB-12; said "RAPID_JIRA_URL must be an https URL"
export RAPID_JIRA_URL=https://jira.example.com/
refused "$A/jira" get KB-12; said "no JIRA credential: set RAPID_JIRA_TOKEN"
[ ! -e "$T/curl.log" ] || fail "jira called curl without a credential: $(cat "$T/curl.log")"
export RAPID_JIRA_USER=bot@example.com RAPID_JIRA_TOKEN='s3cret"tok'
out=$("$A/jira" get KB-12) || fail "jira get"
case "$out" in '{"key": "KB-12", "title": "Import reports from CSV", "body": "Rows in.", "state": "To Do", "url": "https://jira.example.com/browse/KB-12"}') ;; *) fail "jira get answered: $out" ;; esac
has "$T/curl.log" "-X GET -H Accept: application/json https://jira.example.com/rest/api/2/issue/KB-12?fields=summary,description,status" || fail "jira get: $(cat "$T/curl.log")"
! has "$T/curl.log" "s3cret" || fail "the JIRA token is on curl's command line"
want="header = \"Authorization: Basic $(printf '%s' 'bot@example.com:s3cret"tok' | base64 | tr -d '\n')\""
[ "$(cat "$T/curl.stdin")" = "$want" ] || fail "jira did not hand curl the Basic header on stdin: $(cat "$T/curl.stdin")"
[ "$("$A/jira" link KB-12 --branch "$branch")" = '{"ok": true}' ] || fail "jira link"
has "$T/curl.log" "--data-binary {\"body\": \"rapid branch $branch now carries KB-12.\"} https://jira.example.com/rest/api/2/issue/KB-12/comment" || fail "jira link: $(tail -n 1 "$T/curl.log")"
[ "$("$A/jira" transition KB-12 --to done --ref v2026.0.2)" = '{"ok": true}' ] || fail "jira transition"
has "$T/curl.log" '--data-binary {"transition": {"id": "31"}} https://jira.example.com/rest/api/2/issue/KB-12/transitions' || fail "jira transition: $(cat "$T/curl.log")"
has "$T/curl.log" '{"body": "Landed as v2026.0.2."}' || fail "jira transition left no comment: $(cat "$T/curl.log")"
RAPID_JIRA_STATUS_DONE=Shipped refused "$A/jira" transition KB-12 --to done; said "KB-12 has no transition to 'Shipped'"
# a token with no user goes as a Bearer token; one that cannot be a bearer token is refused
unset RAPID_JIRA_USER
refused "$A/jira" get KB-12; said "RAPID_JIRA_TOKEN is not a bearer token"
RAPID_JIRA_TOKEN=pat-123 "$A/jira" get KB-12 >/dev/null || fail "jira with a bearer token"
[ "$(cat "$T/curl.stdin")" = 'header = "Authorization: Bearer pat-123"' ] || fail "jira bearer header: $(cat "$T/curl.stdin")"

# ---- mcp
echo good > "$T/mcp.mode"
refused "$A/mcp" get KB-12; said "no MCP server named: set RAPID_MCP_SERVER"
RAPID_MCP_SERVER='board;x' refused "$A/mcp" get KB-12; said "must be letters, digits, _ and - only"
export RAPID_MCP_SERVER=board
refused "$A/mcp" get KB-12; said "no Claude credential: set CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY"
[ ! -e "$T/mcp.argv" ] || fail "mcp called claude without a credential"
export CLAUDE_CODE_OAUTH_TOKEN=claude-test-token GH_TOKEN=forge-secret
out=$("$A/mcp" get KB-12) || fail "mcp get"
case "$out" in '{"key": "KB-12", "title": "Board card twelve", '*'}') ;; *) fail "mcp get answered: $out" ;; esac
[ "$(cat "$T/mcp.argv")" = "-p --permission-mode default --setting-sources user --allowedTools mcp__board__* --output-format stream-json --verbose" ] || fail "mcp get argv: $(cat "$T/mcp.argv")"
has "$T/mcp.prompt" 'get only reads' || fail "the prompt does not say that get only reads: $(cat "$T/mcp.prompt")"
# a ticket anyone can file holds instructions: a get whose run called a tool that is not a read is dropped
echo wrote > "$T/mcp.mode"; refused "$A/mcp" get KB-12; said "get only reads, and this run called a tool that is not a read of board (mcp__board__move_card)"
[ ! -s "$T/out" ] || fail "a get that wrote still answered: $(cat "$T/out")"
echo good > "$T/mcp.mode"
has "$T/mcp.prompt" '["get", "KB-12"]' || fail "mcp did not pass the operation as data: $(cat "$T/mcp.prompt")"
has "$T/mcp.env" "CLAUDE_CODE_OAUTH_TOKEN=claude-test-token" || fail "mcp did not pass the claude credential"
! has "$T/mcp.env" "forge-secret" || fail "mcp leaked a forge token into the model's environment"
[ "$("$A/mcp" link KB-12 --branch "$branch")" = '{"ok": true}' ] || fail "mcp link"
[ "$(cat "$T/mcp.argv")" = "-p --permission-mode default --setting-sources user --allowedTools mcp__board__*" ] || fail "mcp link argv: $(cat "$T/mcp.argv")"
has "$T/mcp.prompt" "[\"link\", \"KB-12\", \"--branch\", \"$branch\"]" || fail "mcp link data: $(cat "$T/mcp.prompt")"
[ "$("$A/mcp" transition KB-12 --to done --ref v2026.0.3)" = '{"ok": true}' ] || fail "mcp transition"
# the server named by the tracker value; an API key is a credential too
unset RAPID_MCP_SERVER CLAUDE_CODE_OAUTH_TOKEN
RAPID_TRACKER=mcp:kanban ANTHROPIC_API_KEY=key-test "$A/mcp" get KB-12 >/dev/null || fail "mcp with the server from the tracker value"
has "$T/mcp.argv" "--allowedTools mcp__kanban__*" || fail "mcp server from RAPID_TRACKER: $(cat "$T/mcp.argv")"
export RAPID_MCP_SERVER=board CLAUDE_CODE_OAUTH_TOKEN=claude-test-token
echo forged > "$T/mcp.mode"; refused "$A/mcp" link KB-12 --branch "$branch"; said "no result bound to this call"
echo failed > "$T/mcp.mode"; refused "$A/mcp" get KB-12; said "the board has no such card"
echo notjson > "$T/mcp.mode"; refused "$A/mcp" get KB-12; said "not the contract's JSON object"
echo good > "$T/mcp.mode"

# ---- through rapid: the operator names an adapter kept outside the repository
mkrepo "$T/r"; cd "$T/r"
: > "$T/gh.log"
export RAPID_TRACKER="command:$A/github" RAPID_GITHUB_REPO=acme/app GH_TOKEN=test-token
rapid branch feature exports --ticket GH-7 >/dev/null || fail "branch with the github adapter"
has .rapid/requirements/exports.md "Export reports as CSV" || fail "the issue title did not become the requirement"
has "$T/gh.log" "issue comment 7 --repo acme/app --body rapid branch $(lname exports) now carries GH-7." || fail "the branch was not linked: $(cat "$T/gh.log")"
commit export.txt e "[NEW] Export reports as CSV"
rapid land >/dev/null || fail "land with the github adapter"
has "$T/gh.log" "issue close 7 --repo acme/app --comment Landed as $(git describe --exact-match --tags dev)." || fail "the issue was not closed: $(cat "$T/gh.log")"
export RAPID_TRACKER="command:$A/mcp"
rapid branch feature cards --ticket KB-12 >/dev/null || fail "branch with the mcp adapter"
has .rapid/requirements/cards.md "Board card twelve" || fail "the card title did not become the requirement"
commit cards.txt c "[NEW] Show the board cards"
rapid land >/dev/null || fail "land with the mcp adapter"
has "$T/mcp.prompt" '["transition", "KB-12", "--to", "done", "--ref", "v' || fail "the card was not moved to done: $(cat "$T/mcp.prompt")"
# a missing credential is named to the operator; the branch stands and nothing reached the provider
unset GH_TOKEN; export RAPID_TRACKER="command:$A/github"; : > "$T/gh.log"
rapid branch feature notes --ticket GH-8 -r "Notes are kept per report." >/dev/null 2>"$T/err" || fail "a tracker refusal undid the branch"
said "no GitHub credential: set GH_TOKEN"; said "tracker get failed (exit 2)"
[ ! -s "$T/gh.log" ] || fail "gh was called without a credential: $(cat "$T/gh.log")"
unset RAPID_TRACKER
history_clean
