# shellcheck shell=bash
# history.sh - the history invariants I1 to I9, checked by doctor --history
# and, per landed merge, by pre-push. Each check prints "<Id> <sha> <why>"
# for every violation; empty output means the history holds.
#
#   I1 every first-parent commit on dev after the root is a two-parent merge
#      whose second-parent range is linear
#   I2 every such merge carries exactly one version tag, the next version
#      after the previous one (version.sh)
#   I3 the merge subject is "[MERGE] pool/v<series>/<number>.<kind>.<name> into dev: <version>" and
#      its trailers Branch-Base, Gates, Tested-Tree and Requirement are present,
#      Tested-Tree equal to the merge's tree, Branch-Base equal to its first parent;
#      and Branch-Number, a branch number (core.sh)
#   I4 the branch holds 1 to max_commits commits, each with a ruled subject,
#      no commit-audit smell (lib/audit.sh) and at most one
#      Red: trailer, on a [TEST] commit that neither ends the branch nor follows
#      another Red: commit, and each change commit with a body line (commit_body)
#      another Red: commit; a commit changing .rapid/conf or .rapid/admins is a
#      [MODE] commit of those files only, by an admin of the first parent
#   I5 main holds nothing dev lacks: its first-parent line is release merges
#      "[MERGE] dev into main: <version>" (rapid release, --no-ff), each with a
#      released dev commit as second parent and that commit's tree, down to
#      the root or a release made before release merges (main then a dev
#      commit carrying release/<version>); every release/<version> made under
#      the owner rule is an annotated tag whose tagger is an admin
#      (.rapid/admins)
#   I6 every v* and release/* tag sits on dev's first-parent line
#   I7 branch names are unique across landed merges and branches not landed yet,
#      and so are branch numbers: one number never names two branches
#   I8 the requirement file (.rapid/requirements/<name>.md) exists at every merge of a branch that states a requirement
#      (every branch under requirement_test=required) and at dev's tip
#   I9 every replaced merge is re-landed on dev or kept as a branch not landed yet, and
#      no re-land is left half done

# rapid_check_merge M PREV_VERSION PREV_RELEASED: I1-I4 and I8 for one merge;
# prints violations, and on success prints "OK <version>" as its last line.
rapid_check_merge() {
  local m="$1" prev="$2" released="$3" n p1 p2 v vs subj slug want tt tree base req c reds f pb
  n=$(git rev-list --parents -n1 "$m" | wc -w | tr -d ' ')
  if [ "$n" != 3 ]; then echo "I1 $m is not a two-parent merge"; return 0; fi
  p1=$(git rev-parse "$m^1"); p2=$(git rev-parse "$m^2")
  if [ -n "$(git rev-list --merges "$p1..$p2")" ]; then echo "I1 $m branch range holds a merge commit"; fi
  # the merge adds nothing of its own: its tree is its branch's tree when the branch holds the first
  # parent (the shape rapid land writes after it rebases), else the tree merging the two parents gives
  if git merge-base --is-ancestor "$p1" "$p2" 2>/dev/null; then want=$(git rev-parse "$p2^{tree}")
  else want=$(git merge-tree --write-tree "$p1" "$p2" 2>/dev/null | sed -n 1p) || want=""; fi
  [ "$(git rev-parse "$m^{tree}")" = "$want" ] || echo "I1 $m tree is not the tree merging its branch gives: the merge commit changes files itself"
  vs=$(git tag --points-at "$m" -l 'v*' | grep -cE '^v[0-9]{4}\.[0-9]+\.[0-9]+$' || true)
  v=$(rapid_version_of "$m")
  if [ "$vs" != 1 ]; then echo "I2 $m carries $vs version tags (want 1)"; fi
  subj=$(git log -1 --format=%s "$m")
  f=$(mktemp "${TMPDIR:-/tmp}/rapid-msg.XXXXXX"); git log -1 --format=%B "$m" >"$f"
  while IFS= read -r line; do [ -n "$line" ] && echo "I3 $m $line"; done <<<"$(rapid_msg_violations "$f" merge)"
  rm -f "$f"
  if [ -n "$v" ]; then
    want=$(rapid_version_next "$prev" "$released" "${v:1:4}")
    [ "$v" = "$want" ] || echo "I2 $m is $v, expected $want after ${prev:-<none>}"
    case "$subj" in *": $v") ;; *) echo "I3 $m subject does not name its tag $v" ;; esac
  fi
  slug=$(sed -nE 's/^\[MERGE\] pool\/[^ ]*[.]([a-z0-9-]+) into dev: .*/\1/p' <<<"$subj")
  local trs; trs=$(git log -1 --format=%B "$m" | git interpret-trailers --parse)
  base=$(sed -nE 's/^Branch-Base: (.*)$/\1/p' <<<"$trs" | sed -n 1p); tt=$(sed -nE 's/^(Tested|Merge)-Tree: (.*)$/\2/p' <<<"$trs" | sed -n 1p)
  req=$(sed -nE 's/^Requirement: (.*)$/\1/p' <<<"$trs" | sed -n 1p)
  grep -q '^Gates: ' <<<"$trs" || echo "I3 $m has no Gates: trailer"
  tree=$(git rev-parse "$m^{tree}")
  [ "$tt" = "$tree" ] || echo "I3 $m Tested-Tree or Merge-Tree ${tt:-<missing>} is not its tree $tree"
  # a test record never claims a test of a tree no gate ran on: deferred gates go with Merge-Tree
  if grep -q '^Gates: deferred to the close of batch [0-9a-f]\{7,40\}$' <<<"$trs"; then
    grep -q '^Merge-Tree: ' <<<"$trs" || echo "I3 $m defers its gates to a batch close, so it names its tree as Merge-Tree, never Tested-Tree"
  elif grep -q '^Gates: deferred' <<<"$trs"; then
    echo "I3 $m Gates: test record is not 'deferred to the close of batch <id>'"
  else
    grep -q '^Tested-Tree: ' <<<"$trs" || echo "I3 $m names no Tested-Tree for the gates its test record lists"
  fi
  [ -n "$base" ] && [ "$(git rev-parse -q --verify "$base^{commit}" 2>/dev/null)" = "$p1" ] \
    || echo "I3 $m Branch-Base ${base:-<missing>} is not its first parent"
  # a branch that states no requirement lands without the trailer and without the file, unless
  # requirement_test=required governs the merge (the conf at its first parent)
  local rp; rp=$(rapid_req_path "$m" "$slug" || true)
  if [ -n "$req" ] || [ -z "$slug" ] || [ -n "$rp" ] \
     || [ "$(RAPID_CONF_REV="$p1" rapid_conf requirement_test optional)" = required ]; then
    # the trailer names the file as the merge holds it
    case "$req" in
      "$RAPID_REQ_DIR/$slug.md")
        git cat-file -e "$m:$req" 2>/dev/null || echo "I8 $m has no $req" ;;
      *) echo "I3 $m Requirement ${req:-<missing>} is not $RAPID_REQ_DIR/$slug.md"
         [ -n "$rp" ] || echo "I8 $m has no $RAPID_REQ_DIR/${slug:-?}.md" ;;
    esac
  fi
  n=$(git rev-list --count "$p1..$p2")
  local max; max=$(RAPID_CONF_REV="$p1" rapid_policy_max_commits)
  if [ "$n" -lt 1 ] || [ "$n" -gt "$max" ]; then echo "I4 $m branch holds $n commits (1 to $max)"; fi
  local prevred=0 red ln
  if rapid_rule_on branch-number; then
    ln=$(sed -nE 's/^Branch-Number: (.*)$/\1/p' <<<"$trs" | sed -n 1p)
    [[ "$ln" =~ ^$RAPID_NUM_RE$ ]] || echo "I3 $m Branch-Number ${ln:-<missing>} is not a branch number (n<N>)"
  fi
  f=$(mktemp "${TMPDIR:-/tmp}/rapid-msg.XXXXXX")
  for c in $(git rev-list --reverse "$p1..$p2"); do
    git log -1 --format=%B "$c" >"$f"
    while IFS= read -r line; do [ -n "$line" ] && echo "I4 $c $line"; done <<<"$(RAPID_CONF_REV="$p1" rapid_msg_violations "$f")"
    while IFS= read -r line; do [ -n "$line" ] && echo "I4 $c $line"; done <<<"$(RAPID_CONF_REV="$p1" rapid_commit_smells "$c")"
    # the admins are each working copy's own: a copy that names none (a fresh clone, CI) has no list to check flips against
    pb=$(RAPID_CONF_REV="$p1" RAPID_ADMINS_NONE_OK=1 rapid_policy_flip_commit "$c")
    while IFS= read -r line; do [ -n "$line" ] && echo "I4 $c $line"; done <<<"$pb"
    if rapid_rule_on red-test; then
      red=$(grep -cE '^Red: .+' "$f" || true)
      if [ "${red:-0}" -ge 1 ]; then
        [ "$prevred" = 0 ] || echo "I4 $c a Red: commit follows a Red: commit"
        [ "$c" != "$p2" ] || echo "I4 $c a Red: commit is the branch tip"
        prevred=1
      else
        prevred=0
      fi
    fi
  done
  rm -f "$f"
  # signed=required at the first parent: the branch commits and the merge verify
  if [ "$(RAPID_CONF_REV="$p1" rapid_conf signed optional)" = required ]; then
    for c in $(git rev-list "$p1..$p2") "$m"; do
      pb=$(RAPID_CONF_REV="$p1" rapid_signed_problem "$c"); [ -z "$pb" ] || echo "I4 $c $pb"
    done
  fi
  [ -n "$v" ] && echo "OK $v"
  return 0
}

# rapid_jobs: how many merge checks run at once: one per core
# (RAPID_HISTORY_JOBS, a positive number, overrides it).
rapid_jobs() {
  local j="${RAPID_HISTORY_JOBS:-}"
  [[ "$j" =~ ^[1-9][0-9]*$ ]] || j=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)
  printf '%s' "$j"
}

# rapid_check_merges_par DIR: stdin holds one "<merge> <previous version or -> <released 0|1>"
# line per merge; rapid_check_merge runs on each with rapid_jobs workers at once
# (worker w takes lines w, w+N, ...), and the output for line i (from 1) goes to
# DIR/i, so the caller prints the results in order whatever order they finish in.
rapid_check_merges_par() {
  local dir="$1" list n w total
  list=$(sed '/^$/d'); [ -n "$list" ] || return 0
  n=$(rapid_jobs); total=$(grep -c . <<<"$list")
  for ((w = 0; w < n; w++)); do
    (
      i=0
      while read -r m p r; do
        i=$((i + 1))
        [ $(( (i - 1) % n )) = "$w" ] || continue
        [ "$p" != - ] || p=""
        rapid_check_merge "$m" "$p" "$r" > "$dir/$i"
        # rapid doctor follows the walk live (rapid_live, set by the doctor alone: a push stays quiet)
        [ -z "${rapid_live:-}" ] || rapid_progress "$dir" "$total" "doctor: history: " "$(_hv=$(rapid_version_of "$m"); [ -n "$_hv" ] || _hv=$(git rev-parse --short "$m"); printf %s "$_hv")"
      done <<<"$list"
    ) &
  done
  wait
}

# rapid_release_point C DEVFP: the dev commit main's commit C released: C
# itself when it is on dev's first-parent line (DEVFP, one sha per line),
# else, for a release merge, its second parent.
rapid_release_point() {
  if grep -Fx -- "$1" <<<"$2" >/dev/null; then printf '%s' "$1"; else git rev-parse "$1^2" 2>/dev/null || printf '%s' "$1"; fi
}

# rapid_main_check MAIN DEV [FROM]: I5's shape of main. Walks MAIN's
# first-parent line down to FROM (a push: the main it moves from) or to its
# base on DEV's first-parent line: every commit walked is a release merge
# "[MERGE] dev into main: <v>" whose second parent is a dev commit carrying
# <v> and an annotated release/<v>, whose tree is that commit's tree, and
# whose first parent's release point is an ancestor of it (releases go
# forward). The base is the root or a release made before release merges
# (it carries release/<v>); a push never reaches it (FROM is met first).
# Prints "I5 <sha> <why>" per break.
rapid_main_check() {
  local main="$1" dev="$2" from="${3:-}" fp root c n p1 p2 v
  fp=$(git rev-list --first-parent "$dev"); root=$(rapid_dev_root "$dev")
  c=$(git rev-parse "$main")
  while :; do
    [ -n "$from" ] && [ "$c" = "$from" ] && return 0
    if grep -Fx -- "$c" <<<"$fp" >/dev/null; then
      if [ -n "$from" ]; then echo "I5 $c main moves to a dev commit; it takes only release merges made by rapid release"; return 0; fi
      # the root, or a commit from before the seed of a repository that held commits at its first setup
      [ "$c" = "$root" ] && return 0
      git merge-base --is-ancestor "$c" "$root" && return 0
      v=$(rapid_version_of "$c")
      [ -n "$v" ] && git rev-parse -q --verify "refs/tags/release/$v" >/dev/null \
        || echo "I5 $c $main holds a dev commit that carries no release/<version>"
      return 0
    fi
    n=$(git rev-list --parents -n1 "$c" | wc -w | tr -d ' ')
    if [ "$n" != 3 ]; then echo "I5 $c on $main is neither a release merge nor a released dev commit"; return 0; fi
    p1=$(git rev-parse "$c^1"); p2=$(git rev-parse "$c^2")
    grep -Fx -- "$p2" <<<"$fp" >/dev/null || { echo "I5 $c release merge's second parent is not on dev's first-parent line"; return 0; }
    v=$(rapid_version_of "$p2")
    [ "$(git log -1 --format=%s "$c")" = "[MERGE] dev into main: ${v:-<no version>}" ] \
      || echo "I5 $c subject is not '[MERGE] dev into main: ${v:-<version>}'"
    { [ -n "$v" ] && [ "$(git cat-file -t "refs/tags/release/$v" 2>/dev/null)" = tag ]; } \
      || echo "I5 $c releases ${v:-a commit with no version}, which carries no annotated release/<version>"
    [ "$(git rev-parse "$c^{tree}")" = "$(git rev-parse "$p2^{tree}")" ] || echo "I5 $c tree is not the released dev commit's tree"
    git merge-base --is-ancestor "$(rapid_release_point "$p1" "$fp")" "$p2" || echo "I5 $c releases a dev commit older than the release before it"
    c="$p1"
  done
}

# rapid_version_map: "<commit> <version>" for each commit a version tag names,
# the tag rapid_version_of picks (the first well-formed v* in name order), from
# one git call, so the whole-history walks run no git per merge.
rapid_version_map() {
  git tag -l 'v*' --format='%(refname:short) %(objecttype) %(objectname) %(*objecttype) %(*objectname)' \
    | awk '$1 ~ /^v[0-9][0-9][0-9][0-9][.][0-9]+[.][0-9]+$/ {
        c = ""; if ($2 == "commit") c = $3; else if ($2 == "tag" && $4 == "commit") c = $5
        if (c != "" && !(c in seen)) { seen[c] = 1; print c, $1 } }'
}
# rapid_first_parents DEV: "<commit> <version or ->" for each commit on DEV's
# first-parent line, oldest first.
rapid_first_parents() {
  git rev-list --first-parent --reverse "$1" | RAPID_VMAP="$(rapid_version_map)" awk 'BEGIN { n = split(ENVIRON["RAPID_VMAP"], L, "\n")
    for (i = 1; i <= n; i++) if (split(L[i], a, " ") == 2) ver[a[1]] = a[2] }
    { print $1, (($1 in ver) ? ver[$1] : "-") }'
}
# _hrel V: 0 when refs/tags/release/V exists (_HV_REL: the release tag refs, newline-framed).
_hrel() { case "$_HV_REL" in *$'\n'"refs/tags/release/$1"$'\n'*) return 0 ;; esac; return 1; }

# rapid_history_check [DEV] [MAIN]: every invariant over the whole history.
rapid_history_check() {
  local dev="${1:-dev}" main="${2:-main}" since="${RAPID_HISTORY_SINCE:-}" checking=1 root c out prev="" released=0 v t tc slugs dup s r
  git rev-parse -q --verify "$dev^{commit}" >/dev/null || { echo "I1 - no $dev branch"; return 0; }
  root=$(rapid_dev_root "$dev")
  local _HV_REL fpv cv pre=1
  fpv=$(rapid_first_parents "$dev")
  _HV_REL=$'\n'"$(git for-each-ref --format='%(refname)' refs/tags/release/)"$'\n'
  [ -z "$since" ] || { since=$(git rev-parse -q --verify "$since^{commit}") || { echo "I1 - unknown revision for --since"; return 0; }; checking=0; }
  [ "$since" != "$root" ] || checking=1
  # the version chain is read from the tags first (a merge's "OK <version>" is
  # its own version tag when it is a two-parent merge), so every merge's
  # check is independent: they run at once (rapid_check_merges_par), and
  # their findings print in history order
  local twop jobs="" pd i
  twop=$'\n'"$(git rev-list --first-parent --min-parents=2 --max-parents=2 "$dev")"$'\n'
  while read -r c cv <&3; do
    # the commits before the root, if any, are a history from before rapid
    [ "$pre" = 0 ] || { [ "$c" = "$root" ] && pre=0; continue; }
    if [ "$checking" = 0 ]; then
      # before SINCE: only the version chain, for the checks that follow
      v=${cv#-}; [ -z "$v" ] || { prev="$v"; if _hrel "$v"; then released=1; else released=0; fi; }
      [ "$c" = "$since" ] && checking=1
      continue
    fi
    jobs="$jobs$c ${prev:--} $released"$'\n'
    v=${cv#-}
    case "$twop" in *$'\n'"$c"$'\n'*) ;; *) v="" ;; esac
    if [ -n "$v" ]; then
      prev="$v"
      if _hrel "$v"; then released=1; else released=0; fi
    fi
  done 3<<<"$fpv"
  if [ -n "$jobs" ]; then
    pd=$(mktemp -d "${TMPDIR:-/tmp}/rapid-history.XXXXXX")
    rapid_check_merges_par "$pd" <<<"$jobs"
    i=1
    while [ -f "$pd/$i" ]; do grep -v '^OK ' "$pd/$i" | sed '/^$/d' || true; i=$((i + 1)); done
    rm -rf "$pd"
  fi
  # I5: main holds nothing dev lacks, release merge by release merge
  if git rev-parse -q --verify "$main^{commit}" >/dev/null; then
    rapid_main_check "$main" "$dev"
  fi
  # I5: main is production; each release was an admin's, by the admins at the release before it
  local gov="$root" rt rtag tagger why
  while read -r c cv <&3; do
    v=${cv#-}; [ -n "$v" ] || continue
    rt="refs/tags/release/$v"
    _hrel "$v" || continue
    # releases made before the framework knew the owner rule are not checked by it
    if git cat-file -e "$c:.rapid/version" 2>/dev/null || git show "$c:.rapid/lib/policy.sh" 2>/dev/null | grep -F 'release_who' >/dev/null; then
      rtag=$(git rev-parse "$rt")
      if [ "$(git cat-file -t "$rtag")" != tag ]; then
        echo "I5 $c release/$v is not an annotated tag"
      else
        tagger=$(git for-each-ref --format='%(taggeremail)' "$rt" | tr -d '<>')
        # a copy that names no admin (a CI checkout) leaves the owner to the forge, whose rulesets let only an admin release
      fi
    fi
    gov="$c"
  done 3<<<"$fpv"
  # I6
  local fp ty o pt po; fp=$'\n'"$(git rev-list --first-parent "$dev")"$'\n'
  while read -r t ty o pt po; do
    [ -n "$t" ] || continue
    # a tag of a commit, or an annotated tag of one, peels here; anything else asks git
    if [ "$ty" = commit ]; then tc="$o"; elif [ "$ty" = tag ] && [ "$pt" = commit ]; then tc="$po"; else tc=$(git rev-parse "$t^{commit}"); fi
    case "$fp" in *$'\n'"$tc"$'\n'*) ;; *) echo "I6 $tc tag $t is off dev's first-parent line" ;; esac
  done <<<"$(git tag -l 'v*' 'release/*' --format='%(refname:short) %(objecttype) %(objectname) %(*objecttype) %(*objectname)')"
  # I7 (a branch landed into the open batch keeps its branch until rapid land: not a repeat)
  local bbranches; bbranches=$(cat "$(git rev-parse --git-common-dir)/rapid/batch.branches" 2>/dev/null || true)
  slugs=$( { git log --first-parent --format=%s "$dev" | sed -nE 's/^\[MERGE\] pool\/[^ ]*[.]([a-z0-9-]+) into dev: .*/\1/p'
             git for-each-ref --format='%(refname:short)' $RAPID_POOL_NS | { if [ -n "$bbranches" ]; then grep -vxF -- "$bbranches" || true; else cat; fi; } | sed -nE 's#^pool/[^/]+/##p' | sed -E "s/^$RAPID_NUM_RE[.]//; s/^[a-z]+[.]//"; } )
  dup=$(sort <<<"$slugs" | uniq -d | sed '/^$/d' || true)
  for s in $dup; do
    # a branch still open after it landed is the one allowed repeat: land deletes it, a stale copy is reported
    echo "I7 - branch name '$s' is used more than once"
  done
  # I7 for numbers: each "number name" pair once; a number with two names is two branches
  local pairs
  pairs=$( { git log --first-parent --format='%(trailers:key=Branch-Number,valueonly,separator=%x2C)%x09%s' "$dev" \
               | awk -F '\t' '$1 ~ /^n/ && $2 ~ /^\[MERGE\] pool\/[^ ]+ into dev: / { split($2, w, " "); sub(/^.*[.]/, "", w[2]); print $1, w[2] }'
             git for-each-ref --format='%(refname:short)' $RAPID_POOL_NS \
               | sed -nE "s#^pool/[^/]+/($RAPID_NUM_RE)[.][a-z]+[.]([a-z0-9-]+)\$#\\1 \\2#p"; } | sort -u )
  for s in $(awk '{ print $1 }' <<<"$pairs" | sort | uniq -d); do
    echo "I7 - branch number '$s' names more than one branch"
  done
  # I8 at the tip
  # every merge that names a requirement (a branch may land without one under requirement_test=optional):
  # the file is still there
  local s rpath
  while read -r s rpath; do
    [ -n "$s" ] || continue
    rapid_req_path "$dev" "$s" >/dev/null || echo "I8 - $rpath was deleted after it landed"
  done <<<"$(git log --first-parent --format='%(trailers:key=Requirement,valueonly,separator=%x2C)%x09%s' "$dev" \
               | awk -F '\t' '$1 ~ /^[.]rapid\/requirements\// && $2 ~ /^\[MERGE\] pool\/[^ ]+ into dev: / { split($2, w, " "); sub(/^.*[.]/, "", w[2]); print w[2], $1 }')"
  # I3 over a batch: deferred gates are shown by the close record
  # I9
  rapid_reland_pending "$dev" | sed 's/^/I9 - re-land pending: /'
  [ ! -d "$(git rev-parse --git-path rapid-reland)" ] || echo "I9 - a rapid sync --dev re-land is half done; finish it with --continue or --abort"
  return 0
}

# rapid_slug_landed NAME [DEV]: 0 when DEV's first-parent line holds a merge of NAME.
rapid_slug_landed() {
  git log --first-parent --format=%s "${2:-dev}" 2>/dev/null | grep -E "^\[MERGE\] pool/[^ ]*[.]$1 into dev: " >/dev/null
}

# rapid_reland_pending [DEV]: the replaced merges whose branch is neither on DEV
# nor kept as a branch not landed yet, one "merge kind/name" per line (I9). A
# re-land keeps the dev it replaced in a snapshot branch safety/dev-<timestamp>;
# its first-parent merges that DEV lacks are the replaced ones.
rapid_reland_pending() {
  local dev="${1:-dev}" b m subj ks
  for b in $(git for-each-ref --format='%(refname)' 'refs/heads/safety/dev-*'); do
    for m in $(git rev-list --first-parent "$b" --not "$dev"); do
      subj=$(git log -1 --format=%s "$m")
      ks=$(rapid_subject_ks "$subj")
      [ -n "$ks" ] || continue
      set -- $ks
      rapid_slug_landed "$2" "$dev" && continue
      git for-each-ref --format='%(refname)' $RAPID_POOL_NS | sed -E "s#.*/##; s/^$RAPID_NUM_RE[.]//; s/^[a-z]+[.]//" | grep -Fx -- "$2" >/dev/null && continue
      printf '%s %s/%s\n' "$(git rev-parse --short "$m")" "$1" "$2"
    done
  done
}
