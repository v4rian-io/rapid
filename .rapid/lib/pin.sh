# shellcheck shell=bash
# pin.sh - the installed mode: one rapid installed once (a clone of the framework, on PATH
# through a symlink) serves every repository, and each repository pins the version it runs.
# Sourced first by .rapid/rapid, before devexec.sh. Bash 3.2 compatible; functions only.
#
# A repository is in installed mode when its .rapid holds `version` (one version tag) and
# no rapid of its own: .rapid there is data (conf, admins, the requirement files, version).
# Its hooks are stubs in the git directory that run `rapid hook <name>`.
#   - The running tool is at a tag when its checkout is that tag (the tag's commit, or its
#     tree: a release tag sits on the tip of dev that main's release merge carries), or, for
#     a version kept under <clone>/.rapid-versions/<tag>, when it is that tag.
#   - rapid setup pins the newest release tag (release/v<series>.<n>) the clone holds in HEAD;
#     a repository may pin any tag the clone holds, a version tag included.
#   - When the repository pins another tag, that version runs instead: it is kept inside the
#     clone, at .rapid-versions/<tag>, written there from the tag on first use (an archive of
#     the tag's .rapid: no work tree to register, nothing git prunes, removed by removing the
#     directory), and the command is handed to it with the same arguments.
#   - A land and a hook are checked by the version dev pins, never by the branch's own pin:
#     a branch that changes .rapid/version is the upgrade, and it lands under the old one.
#   - A tag the clone does not hold is refused, naming the fetch that brings it.
# A repository that carries its own .rapid/rapid (the framework's repository) is never
# redirected.

# rapid_exclude GITDIR PATTERN...: the one place rapid keeps a working copy's own files out of
# its history: each PATTERN goes once into GITDIR/info/exclude (local to that copy, never
# committed, never pushed).
rapid_exclude() {
  local g="$1" p; shift
  [ -d "$g" ] || return 0
  mkdir -p "$g/info"
  for p in "$@"; do
    grep -Fx -- "$p" "$g/info/exclude" >/dev/null 2>&1 || printf '%s\n' "$p" >> "$g/info/exclude"
  done
}

# _pin_tool_git CLONE ARGS...: git in the tool's clone. A hook or a linked work tree runs with
# git's own variables naming the project's repository: they never reach a query of the clone.
_pin_tool_git() {
  local c="$1"; shift
  ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE
    git -C "$c" "$@" )
}

# rapid_tool_clone SELF: the clone the running tool belongs to; SELF is its .rapid directory.
rapid_tool_clone() {
  case "$1" in
    */.rapid-versions/*/.rapid) printf '%s' "${1%%/.rapid-versions/*}" ;;
    *) printf '%s' "${1%/.rapid}" ;;
  esac
}

# rapid_tool_tag SELF: the tag rapid setup pins: the newest release tag the clone of the running
# tool holds in HEAD (for a kept version, its own tag); empty when the clone holds none.
rapid_tool_tag() {
  local d
  case "$1" in
    */.rapid-versions/*/.rapid) d="${1%/.rapid}"; printf '%s' "${d#*/.rapid-versions/}"; return 0 ;;
  esac
  _pin_tool_git "${1%/.rapid}" tag --merged HEAD -l 'release/v[0-9]*' --sort=-v:refname 2>/dev/null | sed -n 1p
}

# rapid_pin_ok PIN: 0 when PIN reads as a tag rapid pins: a version, or the release of one.
rapid_pin_ok() { [[ "$1" =~ ^(release/)?v[0-9]+([.][0-9]+)*$ ]]; }

# rapid_tool_at SELF PIN: 0 when the running tool is the tag PIN.
rapid_tool_at() {
  local d c
  case "$1" in
    */.rapid-versions/*/.rapid) d="${1%/.rapid}"; [ "${d#*/.rapid-versions/}" = "$2" ]; return ;;
  esac
  c=$(_pin_tool_git "${1%/.rapid}" rev-parse -q --verify "refs/tags/$2^{commit}" 2>/dev/null) || return 1
  [ "$c" = "$(_pin_tool_git "${1%/.rapid}" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null)" ] \
    || [ "$(_pin_tool_git "${1%/.rapid}" rev-parse -q --verify "$c^{tree}" 2>/dev/null)" = "$(_pin_tool_git "${1%/.rapid}" rev-parse -q --verify 'HEAD^{tree}' 2>/dev/null)" ]
}

# rapid_installed_root: the root of the repository of the current directory when it is in
# installed mode; fails otherwise.
rapid_installed_root() {
  local top
  top=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  [ -f "$top/.rapid/version" ] && [ ! -e "$top/.rapid/rapid" ] || return 1
  printf '%s' "$top"
}

# rapid_stub_dir: where the hook stubs of an installed repository live (in the git directory
# its work trees share).
rapid_stub_dir() { printf '%s/rapid/hooks' "$(cd "$(git rev-parse --git-common-dir)" && pwd -P)"; }

# rapid_pin_exec SELF DEVEXEC ARGS...: in an installed repository that pins another version than
# the running one, hand the command to that version; returns when the running tool is the one.
# DEVEXEC=1 (a land, a hook) reads the pin dev holds.
rapid_pin_exec() {
  local self="$1" devexec="$2" top pin="" clone vd tmp
  shift 2
  top=$(rapid_installed_root) || return 0
  if [ "$devexec" = 1 ]; then pin=$(git -C "$top" show refs/heads/dev:.rapid/version 2>/dev/null | sed -n 1p) || pin=""; fi
  [ -n "$pin" ] || pin=$(sed -n 1p "$top/.rapid/version")
  pin=$(printf '%s' "$pin" | tr -d '[:space:]')
  rapid_pin_ok "$pin" \
    || { echo "X rapid: .rapid/version holds '$pin', not a version tag (v<series>.<n>)" >&2; exit 2; }
  ! rapid_tool_at "$self" "$pin" || return 0
  clone=$(rapid_tool_clone "$self")
  # signed=required on dev: the rapid that checks every land is not taken from a tag
  # git cannot verify (the clone reads this repository's allowed signers)
  local conf sha asf sc=()
  conf=$(git -C "$top" show refs/heads/dev:.rapid/conf 2>/dev/null) || conf=$(cat "$top/.rapid/conf" 2>/dev/null || true)
  if [ "$(sed -n 's/^signed=//p' <<<"$conf" | sed -n 1p)" = required ] \
     && sha=$(_pin_tool_git "$clone" rev-parse -q --verify "refs/tags/$pin^{commit}" 2>/dev/null); then
    asf=$(git -C "$top" config --type=path --get gpg.ssh.allowedSignersFile 2>/dev/null || true)
    [ -z "$asf" ] || sc=(-c "gpg.ssh.allowedSignersFile=$asf")
    case "$(_pin_tool_git "$clone" ${sc[@]+"${sc[@]}"} log -1 --format=%G? "$sha" 2>/dev/null)" in
      G|U) ;;
      *) echo "X rapid: $clone at $pin ($(printf '%s' "$sha" | cut -c1-7)) is not signed with a key git verifies (signed=required)" >&2; exit 1 ;;
    esac
  fi
  vd="$clone/.rapid-versions/$pin"
  if [ ! -f "$vd/.rapid/rapid" ]; then
    _pin_tool_git "$clone" rev-parse -q --verify "refs/tags/$pin^{commit}" >/dev/null 2>&1 \
      || { echo "X rapid: this repository pins rapid $pin (.rapid/version), which the install at $clone does not hold; run: git -C $clone fetch --tags" >&2; exit 1; }
    mkdir -p "$clone/.rapid-versions" "${vd%/*}"
    # the kept versions are no part of the clone's own tree
    rapid_exclude "$clone/.git" .rapid-versions/
    tmp=$(mktemp -d "$clone/.rapid-versions/.x.XXXXXX")
    # through a file, never a pipe (tar may stop reading before git ends writing)
    _pin_tool_git "$clone" archive --format=tar -o "$tmp.tar" "refs/tags/$pin" -- .rapid && tar -x -f "$tmp.tar" -C "$tmp"
    rm -f "$tmp.tar"
    if [ -e "$vd" ]; then rm -rf "$tmp"; else mv "$tmp" "$vd" 2>/dev/null || rm -rf "$tmp"; fi
  fi
  [ -f "$vd/.rapid/rapid" ] || { echo "X rapid: could not prepare rapid $pin under $clone/.rapid-versions" >&2; exit 1; }
  [ -f "$vd/.rapid/lib/pin.sh" ] \
    || { echo "X rapid: rapid $pin cannot run from an install (it came before the installed mode); pin a later tag in .rapid/version" >&2; exit 1; }
  exec bash "$vd/.rapid/rapid" "$@"
}
