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


# rapid_slug_landed NAME [DEV]: 0 when DEV's first-parent line holds a merge of NAME.
rapid_slug_landed() {
  git log --first-parent --format=%s "${2:-dev}" 2>/dev/null | grep -E "^\[MERGE\] pool/[^ ]*[.]$1 into dev: " >/dev/null
}
