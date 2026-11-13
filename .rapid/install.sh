#!/usr/bin/env bash
# install.sh - install rapid once on this machine: clone rapid with its tags into RAPID_HOME
# (default ~/.rapid), then run its rapid setup --install, which links rapid into a bin
# directory of PATH. Run again it fetches the tags of the clone it finds, never clones twice,
# never resets it. It writes the clone and that one link, nothing else, never as root.
#   curl -fsSL https://raw.githubusercontent.com/v4rian-io/rapid/main/.rapid/install.sh | bash
set -euo pipefail
url="https://github.com/v4rian-io/rapid.git"
home="${RAPID_HOME:-$HOME/.rapid}"
die() { echo "X install: $*" >&2; exit 1; }
command -v git >/dev/null 2>&1 || die "git is not installed"
if [ -e "$home" ] && [ -n "$(ls -A "$home" 2>/dev/null)" ]; then
  [ -d "$home/.git" ] && [ -f "$home/.rapid/rapid" ] \
    || die "$home is not a rapid clone; choose another place (RAPID_HOME=<directory>) or remove it yourself"
  git -C "$home" fetch -q --tags origin || die "could not fetch the tags of $home"
  echo "rapid is at $home (tags fetched)"
else
  mkdir -p "$(dirname "$home")"
  git clone -q "$url" "$home" || die "could not clone $url into $home"
  echo "rapid cloned into $home"
fi
exec bash "$home/.rapid/rapid" setup --install
