#!/bin/sh
# Build the Flatpak with this checkout's commit in it, as About and the debugging information show it
# (platform/linux/src/kksl/buildinfo.nim). Flatpak builds a copy of the source tree without .git, where the program
# can't ask git itself: the commit, and whether the checkout has changed or new files the commit doesn't hold, go to
# the manifest's build in buildinfo.flags (the rule of deploy/install-server-user.sh), removed again after.
#   apps/gnome/flatpak/build.sh [flatpak-builder options] BUILD_DIR      (the manifest is added at the end)
# Without the file (flatpak-builder run directly) the app says "commit unknown". CI writes it from $GITHUB_SHA
# (.github/workflows/arm64.yml).
set -eu
HERE=$(cd -- "$(dirname -- "$0")" >/dev/null && pwd)     # (>/dev/null: cd prints the folder it found through CDPATH)
REPO=$(cd -- "$HERE/../../.." >/dev/null && pwd)
FLAGS="$HERE/buildinfo.flags"
# only this repository's own checkout: not a repository the source tree happens to sit in, not one without commits
COMMIT=$( [ -z "$(git -C "$REPO" rev-parse --show-prefix 2>/dev/null || echo no)" ] && git -C "$REPO" rev-parse --verify -q HEAD || true)
# (a git status that fails counts as changed: it can't say the checkout is clean)
DIRTY=false
if [ -n "$COMMIT" ]; then
  CHANGES=$(git -C "$REPO" status --porcelain -- .) || CHANGES=failed
  [ -z "$CHANGES" ] || DIRTY=true
fi
# removed after, also when the build is interrupted (dash runs no EXIT trap for a signal; a file left behind would
# name this commit in a later build of another one)
trap 'rm -f "$FLAGS"' EXIT
trap 'rm -f "$FLAGS"; trap - EXIT; exit 130' INT
trap 'rm -f "$FLAGS"; trap - EXIT; exit 143' TERM
trap 'rm -f "$FLAGS"; trap - EXIT; exit 129' HUP
rm -f "$FLAGS"
[ -z "$COMMIT" ] || echo "-d:kksCommit=$COMMIT -d:kksDirty=$DIRTY" > "$FLAGS"
flatpak run org.flatpak.Builder "$@" "$HERE/io.github._5wHN28Dg.walkdown.yml"
