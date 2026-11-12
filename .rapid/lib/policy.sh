# shellcheck shell=bash
# policy.sh - who may land, how big a branch may be, which gates run.
#
# conf keys (all optional):
#   land_who=anyone|list     who may land a branch (default anyone)
#   land_list=a@x,b@x        allowed lander emails when land_who=list
#   max_commits=N            most commits one branch may carry (default 20)
#   commit_body=required|optional  required: a NEW, FIX, REFACTOR, REVERT or HOTFIX commit carries a body
#                            line of five words or more (default required)
#   requirement_test=required|optional  required: every branch carries .rapid/requirements/<name>.md, a requirement of
#                            eight words or more and a Test: <path or scenario name> line naming what verifies it in
#                            the branch tip; optional: a branch may state none, what it states is checked (default optional)
#   docs_rules=c=d,c2=d2     pairs <code glob>=<doc glob>: a branch changing code matching c changes a doc matching
#                            d, or its requirement says Docs: none (<reason>); the merge records which (default unset)
#   signed=required|optional required: every branch commit, merge, version tag and release tag is signed and verifies (%G? is
#                            G or U); the only answer to one person committing under another's address (default optional)
#   land_pr=optional|required  required: a land goes through review (rapid land --pr)
#   land_approvals=N         approving reviews land --pr waits for (default 1)
#   agent_env=VAR,VAR2       environment variables that mark an AI agent session besides CLAUDECODE,
#                            CLAUDE_CODE_ENTRYPOINT (rapid_agent_session): such a session never
#                            releases (default unset)
#   smart_commit_cmd=<cmd>   rapid commit --smart: the command that reads the prompt on stdin and prints the
#                            message (default: the claude CLI in print mode, fresh context, no tools)
#   forge_repo=OWNER/REPO    the forge repository when origin's URL does not name it
#   tracker=none             the committed conf may only say none (lib/tracker.sh)
#   reqs_id=TOKEN            the project token of the register IDs, <TOKEN>-R-<name> (default REQ; lib/reqs.sh)
#   release_who=owner|list   who may promote dev to main (default owner: the admins listed in .rapid/admins)
#   release_list=a@x,b@x     allowed releaser emails when release_who=list
#   gates_commit=<command>   run by the pre-commit hook on the staged tree of every branch commit (default none)
#   max_commit_lines=N       most lines one branch commit may change, added plus deleted (default 800; lib/audit.sh)
#   test_paths=<patterns>    shell patterns of test paths, space separated (default lib/audit.sh's list); a
#                            [NEW], [FIX] or [HOTFIX] commit that changes behaviour touches one of them
#   gates_fast=<command>     run on every branch commit by check --each
#   gates_full=<command>     run by rapid land on the batch's final tree (and on a land --pr merge tree)
#   gates_each=<command>     run by rapid land on the own tree of every merge of the batch, all at once,
#                            before the one gate on the final tree: a cheap test that each merge starts
#                            (default none)
#   gates_release=<command>  run on dev before a release
#   test_on_fail=<command>   started in the background the moment a scenario fails during any gate run
#                            (args: scenario name, its output file): a fixer starts on that issue at once
#   land_on_conflict=<command> started in the background when rapid land meets a conflict rebasing a branch
#                            (args: branch, the file listing the conflicting paths); land exits 4
#   release_build=<command>  builds the release artifacts on the released tree into $RAPID_ARTIFACTS, each
#                            named with $RAPID_LABEL (<version>-<sha>); BUILD_TYPE=release (default none)
#   gates_artifact=<command> run on those artifacts ($RAPID_ARTIFACTS) after rapid's no-debug audit (default none)
#   release_publish=<command> ships the gated artifacts ($RAPID_ARTIFACTS, $RAPID_VERSION) after the release push
# A gate is one shell command run from the tree's root; exit 0 passes.
# An empty gate passes and is reported as "none"; so does the explicit value
# "none", which land requires for gates_full instead of an unset key.

# the defaults, named once: lint/docs.sh checks RULES' policy table against them
RAPID_MAX_COMMITS_DEFAULT=20

rapid_policy_may_land() {
  local who email list
  who=$(rapid_conf land_who anyone)
  email=$(git var GIT_AUTHOR_IDENT 2>/dev/null | sed -E 's/.*<([^>]*)>.*/\1/')
  case "$who" in
    anyone) return 0 ;;
    list)
      list=$(rapid_conf land_list "")
      if [ -n "$email" ] && tr ',' '\n' <<<"$list" | grep -Fx -- "$email" >/dev/null; then return 0; fi
      echo "'${email:-<no identity>}' is not in land_list (land_who=list)"; return 1 ;;
    *) echo "land_who='$who' is not anyone or list"; return 1 ;;
  esac
}

# rapid_agent_session: prints the variable that marks this process as an AI
# agent session and returns 0, or returns 1. Claude Code sets CLAUDECODE and
# CLAUDE_CODE_ENTRYPOINT; conf agent_env names more (variable
# names, comma or space separated). An agent session is an agent whether or
# not the agent guard is installed: it never releases.
rapid_agent_session() {
  local v
  for v in CLAUDECODE CLAUDE_CODE_ENTRYPOINT; do
    [ -z "${!v:-}" ] || { echo "$v"; return 0; }
  done
  for v in $(rapid_conf agent_env "" | tr ',' ' '); do
    [[ "$v" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    [ -z "${!v:-}" ] || { echo "$v"; return 0; }
  done
  return 1
}

rapid_policy_max_commits() {
  local m; m=$(rapid_conf max_commits "$RAPID_MAX_COMMITS_DEFAULT")
  [[ "$m" =~ ^[0-9]{1,4}$ ]] && [ "$m" -ge 1 ] || RAPID_RC=2 rapid_die "max_commits='$m' must be 1 to 9999"
  printf '%s' "$m"
}

# rapid_gate_missing [DIR]: one line per gate whose command names a .rapid/tests
# or .rapid/lint script DIR (default the work tree root) does not have.
rapid_gate_missing() {
  local dir="${1:-.}" g cmd p
  for g in fast full release; do
    cmd=$(rapid_conf "gates_$g" "")
    for p in $(grep -oE '\.rapid/(tests|lint)/[A-Za-z0-9._/-]+' <<<"$cmd" || true); do
      [ -e "$dir/$p" ] || echo "gates_$g runs $p, which this repository does not have"
    done
  done
}

# rapid_path_in GLOBS PATH: 0 when PATH matches one of the comma-separated GLOBS.
rapid_path_in() {
  local g gs
  # split on commas only: a glob is never expanded against the work tree
  IFS=, read -r -a gs <<<"$1"
  for g in ${gs[@]+"${gs[@]}"}; do
    g="${g#"${g%%[![:space:]]*}"}"; g="${g%"${g##*[![:space:]]}"}"
    [ -n "$g" ] || continue
    # shellcheck disable=SC2053
    [[ "$2" == $g ]] && return 0
  done
  return 1
}

# rapid_verified_signer tag|commit OBJECT REV: who signed OBJECT, as git verifies it: the
# principal (ssh) or the GOODSIG email (gpg); empty without a good signature. The keys come
# from .rapid/signers committed at REV when it exists, else from git's own config.
rapid_verified_signer() {
  local af="" raw c=()
  if git cat-file -e "$3:.rapid/signers" 2>/dev/null; then
    af=$(mktemp "${TMPDIR:-/tmp}/rapid-signers.XXXXXX"); git show "$3:.rapid/signers" > "$af"
    c=(-c "gpg.ssh.allowedSignersFile=$af")
  fi
  raw=$(git ${c[@]+"${c[@]}"} "verify-$1" --raw "$2" 2>&1) || raw=""
  [ -z "$af" ] || rm -f "$af"
  sed -nE 's/^Good "git" signature for ([^ ]+) with .*/\1/p; s/^\[GNUPG:\] GOODSIG [^ ]+ .*<([^>]+)>.*/\1/p' <<<"$raw" | sed -n 1p
}

# rapid_docs_named BASE TIP REQFILE: with docs_rules set, a branch that changes
# code matching a rule's code glob changes a doc matching its doc glob, or
# its requirement says "Docs: none (<reason>)". Prints the merge trailer
# ("Docs: <doc>, ..." or "Docs: none (<reason>)"), or on rc 1 the reason.
rapid_docs_named() {
  local rules files r code doc hit need="" got="" why p rs
  rules=$(rapid_conf docs_rules "")
  [ -n "$rules" ] || return 0
  files=$(git diff --name-only --no-renames "$1" "$2" || true)
  IFS=, read -r -a rs <<<"$rules"
  for r in ${rs[@]+"${rs[@]}"}; do
    code="${r%%=*}"; doc="${r#*=}"; [ -n "$code" ] && [ -n "$doc" ] && [ "$code" != "$r" ] || continue
    hit=""; while IFS= read -r p; do [ -n "$p" ] && rapid_path_in "$code" "$p" && hit=1; done <<<"$files"
    [ -n "$hit" ] || continue
    hit=""; while IFS= read -r p; do [ -n "$p" ] && rapid_path_in "$doc" "$p" && { hit="$p"; break; }; done <<<"$files"
    if [ -n "$hit" ]; then got="$got, $hit"; else need="$need $code=$doc"; fi
  done
  if [ -n "$need" ]; then
    why=$(sed -nE 's/^Docs: none \((.+)\)$/\1/p' "$3" | sed -n 1p)
    [ -n "$why" ] && { echo "Docs: none ($why)"; return 0; }
    echo "the branch changes code its docs describe and no doc:$need; change the doc, or say 'Docs: none (<reason>)' in the requirement"; return 1
  fi
  [ -z "$got" ] || echo "Docs: ${got#, }"
}

# rapid_log_tail LOG: the last 25 lines of a gate's log as a gate record keeps them. The
# record is pushed with dev and never rewritten, so every value (8 characters or more) of an
# environment variable whose name holds TOKEN, SECRET, KEY, PASSWORD or CREDENTIAL is
# replaced with <redacted> first.
rapid_log_tail() {
  { tail -n 25 "$1" 2>/dev/null || true; } | awk '
    BEGIN {
      for (k in ENVIRON) if (toupper(k) ~ /TOKEN|SECRET|KEY|PASSWORD|CREDENTIAL/) {
        c = split(ENVIRON[k], part, "\n")
        for (i = 1; i <= c; i++) if (length(part[i]) >= 8) v[++n] = part[i]
      }
    }
    {
      for (i = 1; i <= n; i++) {
        out = ""
        while ((j = index($0, v[i])) > 0) { out = out substr($0, 1, j - 1) "<redacted>"; $0 = substr($0, j + length(v[i])) }
        $0 = out $0
      }
      print
    }'
}

# rapid_gate NAME DIR: run gates_NAME in DIR; prints pass|fail|none, rc 0 unless fail.
# With RAPID_GATE_REC set (a file path), the run, green or red, is recorded
# there: its command, exit code, duration and log tail (rapid land's gate log).
rapid_gate() {
  local name="$1" dir="$2" live="${3:-}" cmd rc=0 log t0
  cmd=$(rapid_conf "gates_$name" "")
  if [ -z "$cmd" ] || [ "$cmd" = none ]; then echo none; return 0; fi
  log=$(mktemp "${TMPDIR:-/tmp}/rapid-gate-$name.XXXXXX"); t0=$(date +%s)
  # The gate is the project's own command: it runs without rapid's internal
  # state (RAPID_CONF_REV names a revision of this repository, which a test
  # suite driving other repositories must not inherit).
  local tof; tof=$(rapid_conf test_on_fail "" 2>/dev/null || true)
  if [ "$live" = live ]; then
    # a long gate (the release gate) is followed as it runs: its output goes to stderr live, to the log as well
    { ( cd "$dir" && unset RAPID_CONF_REV RAPID_OFFLINE RAPID_RELAND_STEP RAPID_GATE_REC RAPID_DEVEXEC GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && export RAPID_TEST_ON_FAIL="${RAPID_TEST_ON_FAIL:-$tof}" && sh -c "$cmd" ) 2>&1 || echo "$?" > "$log.rc"; } | tee "$log" >&2 || true
    if [ -f "$log.rc" ]; then rc=$(cat "$log.rc"); rm -f "$log.rc"; fi
  else
    ( cd "$dir" && unset RAPID_CONF_REV RAPID_OFFLINE RAPID_RELAND_STEP RAPID_GATE_REC RAPID_DEVEXEC GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && export RAPID_TEST_ON_FAIL="${RAPID_TEST_ON_FAIL:-$tof}" && sh -c "$cmd" ) >"$log" 2>&1 || rc=$?
  fi
  if [ -n "${RAPID_GATE_REC:-}" ]; then
    {
      printf 'gate=%s\ncommand=%s\nexit=%s\nduration=%ss\nat=%s\n' \
        "$name" "$cmd" "$rc" "$(( $(date +%s) - t0 ))" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      printf -- '--- log tail\n'
      rapid_log_tail "$log"
    } > "$RAPID_GATE_REC"
  fi
  if [ "$rc" = 0 ]; then rm -f "$log"; echo pass; return 0; fi
  # the end of the log: a test runner prints its failures and counts last
  [ "$live" = live ] || tail -n 25 "$log" | sed 's/^/    | /' >&2
  rm -f "$log"
  echo fail; return 1
}

# rapid_check_each BASE TIP: the fast gate on every commit of BASE..TIP, in order.
# A failing commit passes only with a Red: trailer and a later green commit:
# the commit right after it must pass and carry no Red: (no chain of reds),
# and a Red: commit whose gate passes is a stale marker, refused. Shared by
# rapid check --each and rapid land (a branch push runs no gate: transport).
rapid_check_each() {
  local base="$1" tip="$2" wt c r subj red last fails=0 prev_red=0
  last=$(git rev-parse "$tip")
  if [ -z "$(rapid_conf gates_fast "")" ]; then rapid_info "check --each: no fast gate configured"; return 0; fi
  wt=$(rapid_private_wt each "$base") || { rapid_info "  FAIL  cannot make a private work tree under ${TMPDIR:-/tmp}"; return 1; }
  for c in $(git rev-list --reverse "$base..$tip"); do
    git -C "$wt" checkout -q --detach "$c"
    subj=$(git log -1 --format=%s "$c"); red=$(rapid_trailer "$c" Red)
    if r=$(rapid_gate fast "$wt" 2>/dev/null); then
      if [ -n "$red" ]; then
        rapid_info "  FAIL  $(git rev-parse --short "$c") $subj: stale Red: marker, the fast gate passes (Red: $red)"; fails=1
      else
        rapid_info "  pass  $(git rev-parse --short "$c") $subj"
      fi
      prev_red=0
    elif [ -n "$red" ] && [ "$prev_red" = 1 ]; then
      rapid_info "  FAIL  $(git rev-parse --short "$c") $subj: a Red: commit follows a Red: commit; the commit after a red one turns it green"; fails=1
    elif [ -n "$red" ] && [ "$c" != "$last" ]; then
      rapid_info "  red   $(git rev-parse --short "$c") $subj (marked: Red: $red)"; prev_red=1
    elif [ -n "$red" ]; then
      rapid_info "  FAIL  $(git rev-parse --short "$c") $subj: a Red: commit cannot be the branch tip"; fails=1
    else
      rapid_info "  FAIL  $(git rev-parse --short "$c") $subj: fast gate fails and no Red: trailer marks it"; fails=1
    fi
  done
  git worktree remove --force "$wt" >/dev/null 2>&1 || true
  return "$fails"
}


# Policy flips. .rapid/conf (every key above) and .rapid/admins (the admins, one
# email per line, # comments allowed: the owner and whoever the owner adds) are
# the policy files. A commit that changes one is a policy flip: its own [MODE]
# commit, changing only policy files (and the requirement file of the branch,
# which the first commit of a branch carries), authored and committed by an admin. Admins are read from
# .rapid/admins: as committed at RAPID_CONF_REV when an admin shared the list, else the working copy's own
# file, so a branch never makes
# itself an admin. Under signed=required the flip is also signed by an admin
# (rapid_flip_signer_problem): the email alone is whatever its author types. rapid setup writes its human runner, or the one --owner
# names, as the first admin, in the working copy. With no admin
# (a working copy an agent set up without --owner), rapid setup --owner EMAIL names one.
RAPID_POLICY_FILES=".rapid/conf .rapid/admins .rapid/version"

# rapid_admins: the admin emails at RAPID_CONF_REV (or in the work tree), one per line.
rapid_admins() {
  local text=""
  if [ -n "${RAPID_CONF_REV:-}" ]; then
    text=$(git show "$RAPID_CONF_REV:.rapid/admins" 2>/dev/null || true)
  fi
  # .rapid/admins is excluded from history: the working copy's own file names the admins
  if [ -z "$text" ] && [ -f "$(rapid_ns)/admins" ]; then
    text=$(cat "$(rapid_ns)/admins")
  fi
  grep -vE '^[[:space:]]*(#|$)' <<<"$text" | awk '{ print $1 }' || true
}

# rapid_policy_flip_problem SUBJECT FILES AE AN CE: empty when a commit with
# SUBJECT changing FILES (whitespace separated), authored by AE (name AN) and
# committed by CE, keeps the policy-flip rule at RAPID_CONF_REV; else one
# reason per line.
rapid_policy_flip_problem() {
  local subj="$1" files="$2" ae="$3" an="$4" ce="$5" f pol=0 other=0 admins who names boot=0
  names=$(sed 's/ /, /g' <<<"$RAPID_POLICY_FILES")
  for f in $files; do
    case " $RAPID_POLICY_FILES " in
      *" $f "*) pol=1 ;;
      *) case "$f" in .rapid/requirements/*.md) ;; *) other=1 ;; esac ;;   # the requirement of the branch rides along
    esac
  done
  if [[ "$subj" == "[MODE] "* ]]; then
    [ "$pol" = 1 ] || { echo "a [MODE] commit is a policy flip: it changes a policy file ($names), and this one changes none"; return 0; }
    [ "$other" = 0 ] || echo "a [MODE] commit changes only policy files ($names) and the requirement of its branch; commit the other files apart"
  elif [ "$pol" = 1 ]; then
    echo "a change to a policy file ($names) is a policy flip: give it its own [MODE] commit"
  else
    return 0
  fi
  admins=$(rapid_admins)
  if [ -z "$admins" ]; then
    # no admin yet: the one flip allowed creates the admins file, and only that
    [ "$(grep -vxE '[.]rapid/requirements/.*\.md' <<<"$(tr ' ' '\n' <<<"$files")" | sed '/^$/d')" = .rapid/admins ] \
      && [ -z "$(git show "${RAPID_CONF_REV:-HEAD}:.rapid/admins" 2>/dev/null | grep -vE '^[[:space:]]*(#|$)' || true)" ] && boot=1
    if [ "$boot" = 0 ]; then
      [ -z "${RAPID_ADMINS_NONE_OK:-}" ] || return 0
      echo "no admin is listed in .rapid/admins; rapid setup --owner EMAIL names the owner"; return 0
    fi
  fi
  [ "$boot" = 0 ] || return 0
  for who in "$ae" "$ce"; do
    grep -Fx -- "$who" <<<"$admins" >/dev/null \
      || { echo "'${who:-<no identity>}' is not an admin (.rapid/admins: $(tr '\n' ' ' <<<"$admins" | sed 's/ $//')); an admin flips policy"; return 0; }
  done
  return 0
}

# rapid_policy_flip_commit C: rapid_policy_flip_problem for commit C (its subject,
# the files it changes against its parent, its author and committer).
rapid_policy_flip_commit() {
  local who ae an ce subj files f flip=0
  who=$(git log -1 --format='%ae%x09%an%x09%ce' "$1"); IFS=$'\t' read -r ae an ce <<<"$who"
  subj=$(git log -1 --format=%s "$1"); files=$(git diff-tree --no-commit-id --name-only -r "$1")
  rapid_policy_flip_problem "$subj" "$files" "$ae" "$an" "$ce"
  ! grep -Fx .rapid/version <<<"$files" >/dev/null || rapid_pin_problem "$(git show "$1:.rapid/version" 2>/dev/null || true)"
  [[ "$subj" != "[MODE] "* ]] || flip=1
  for f in $files; do case " $RAPID_POLICY_FILES " in *" $f "*) flip=1 ;; esac; done
  [ "$flip" = 0 ] || rapid_flip_signer_problem "$1"
}

# rapid_flip_signer_problem [COMMIT]: an email is whatever its author types, so under
# signed=required at RAPID_CONF_REV a policy flip is signed by an admin: empty when
# signed=required is off, no admin is listed yet, or the verified signer of COMMIT
# (rapid_verified_signer, keys from .rapid/signers at that revision) is an admin; else why.
# commit-msg passes a probe commit signed with the key the commit will carry (none: no key signs).
rapid_flip_signer_problem() {
  local rev="${RAPID_CONF_REV:-HEAD}" admins signer=""
  [ "$(rapid_conf signed optional)" = required ] || return 0
  admins=$(rapid_admins); [ -n "$admins" ] || return 0
  [ -z "${1:-}" ] || signer=$(rapid_verified_signer commit "$1" "$rev")
  if [ -z "$signer" ]; then
    echo "the policy flip carries no signature git verifies$(! git cat-file -e "$rev:.rapid/signers" 2>/dev/null || echo " against .rapid/signers on dev") (signed=required): an admin signs a policy flip"
  elif ! grep -Fx -- "$signer" <<<"$admins" >/dev/null; then
    echo "the policy flip is signed by '$signer': '$signer' is not an admin (.rapid/admins: $(tr '\n' ' ' <<<"$admins" | sed 's/ $//')); an admin flips policy"
  fi
}

# rapid_pin_problem TEXT: empty when TEXT (a .rapid/version as committed or staged) pins one
# version tag, or is gone; else the one line that says what it must hold.
rapid_pin_problem() {
  local p; p=$(sed -n 1p <<<"$1" | tr -d '[:space:]')
}
