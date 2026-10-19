#!/bin/sh
# Builds Walkdown Plant's Flatpak from the release export's .pck (apps/plant3d/build.sh release linux), without
# installing it:
#   apps/plant3d/flatpak/build.sh BUILD_DIR [flatpak-builder options]
#   apps/plant3d/flatpak/build.sh --bundle OUT.flatpak BUILD_DIR [flatpak-builder options]
#                                   and the single-file bundle a release ships (walkdown-plant.flatpak), from a
#                                   repository of its own under export/flatpak/
#   apps/plant3d/flatpak/build.sh --metainfo OUT.xml
#                                   only the AppStream file with this version's release entry
# The AppStream file's release entry is made from the app's version (project.godot application/config/version) and
# the date of the commit built, with a link to the release plant-vVERSION: never written by hand.
# Needs org.flatpak.Builder; Godot's base app (org.godotengine.godot.BaseApp//4.7) and the freedesktop 26.08
# runtime are fetched from Flathub into the user's installation if missing (--install-deps-from).
set -eu
HERE=$(cd -- "$(dirname -- "$0")" >/dev/null && pwd)
APP=$(cd -- "$HERE/.." && pwd)
ID=io.github._5wHN28Dg.WalkdownPlant
GEN="$APP/export/flatpak"

metainfo() {  # OUT
  V=$(sed -n 's/^config\/version="\([0-9]*\.[0-9]*\.[0-9]*\)"$/\1/p' "$APP/project.godot")
  [ -n "$V" ] || { echo "project.godot has no application/config/version" >&2; exit 2; }
  D=$(git -C "$APP" log -1 --format=%cs 2>/dev/null || true)
  [ -n "$D" ] || D=$(date -u +%Y-%m-%d)
  if grep -q '<releases' "$HERE/$ID.metainfo.xml"; then
    echo "$ID.metainfo.xml must have no <releases>: they are made here" >&2; exit 2
  fi
  mkdir -p "$(dirname "$1")"
  awk -v v="$V" -v d="$D" '/^<\/component>/ {
      print "  <releases>"
      print "    <release version=\"" v "\" date=\"" d "\">"
      print "      <url type=\"details\">https://github.com/5wHN28Dg/kks-explorer/releases/tag/plant-v" v "</url>"
      print "    </release>"
      print "  </releases>"
    } { print }' "$HERE/$ID.metainfo.xml" > "$1"
  grep -q "<release version=\"$V\" date=\"$D\">" "$1" || { echo "no release entry in $1" >&2; exit 1; }
}

case "${1:-}" in
  --metainfo) metainfo "$2"; exit 0 ;;
  --bundle) BUNDLE="$2"; shift 2 ;;
  *) BUNDLE="" ;;
esac
DIR="${1:?build dir}"; shift
[ -s "$APP/export/linux/walkdown-plant.pck" ] || { echo "no export/linux/walkdown-plant.pck: run build.sh release linux" >&2; exit 2; }
metainfo "$GEN/$ID.metainfo.xml"
if [ -n "$BUNDLE" ]; then
  rm -rf "$GEN/repo"
  flatpak run org.flatpak.Builder --user --install-deps-from=flathub --force-clean --state-dir="$GEN/state" \
    --repo="$GEN/repo" "$@" "$DIR" "$HERE/$ID.yml"
  rm -f "$BUNDLE"
  flatpak build-bundle --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo "$GEN/repo" "$BUNDLE" "$ID" master
  ls -l "$BUNDLE"
else
  flatpak run org.flatpak.Builder --user --install-deps-from=flathub --force-clean --state-dir="$GEN/state" "$@" "$DIR" "$HERE/$ID.yml"
fi
