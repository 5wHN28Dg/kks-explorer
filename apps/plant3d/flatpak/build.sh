#!/bin/sh
# Builds Walkdown Plant's Flatpak from the release export's .pck (apps/plant3d/build.sh release linux), without
# installing it:
#   apps/plant3d/flatpak/build.sh BUILD_DIR [flatpak-builder options]
# Needs org.flatpak.Builder; Godot's base app (org.godotengine.godot.BaseApp//4.7) and the freedesktop 26.08
# runtime are fetched from Flathub into the user's installation if missing (--install-deps-from).
set -eu
HERE=$(cd -- "$(dirname -- "$0")" >/dev/null && pwd)
DIR="${1:?build dir}"; shift
[ -s "$HERE/../export/linux/walkdown-plant.pck" ] || { echo "no export/linux/walkdown-plant.pck: run build.sh release linux" >&2; exit 2; }
flatpak run org.flatpak.Builder --user --install-deps-from=flathub --force-clean "$@" "$DIR" "$HERE/io.github._5wHN28Dg.WalkdownPlant.yml"
