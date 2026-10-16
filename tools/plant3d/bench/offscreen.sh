#!/bin/sh
# Runs a command on a private, invisible display: a headless mutter with Xwayland (DISPLAY set by mutter), never the
# desktop of whoever uses this machine. For the bench on this laptop (Godot under the headless Wayland session got
# only a few frames a second: no frame callbacks without a consumer; on Xwayland it renders unthrottled) and for the
# export (the shader baker needs a rendering device). The runtime folder stays under $TMPDIR.
#   XH_SIZE=1600x900@240 tools/plant3d/bench/offscreen.sh COMMAND...
set -eu
RT="$(mktemp -d "${TMPDIR:-/tmp}/kks-offscreen.XXXXXX")"
chmod 700 "$RT"
mkdir -p "$RT/home/data" "$RT/home/config" "$RT/home/cache" "$RT/home/state"
# its own data folder too (the private bus would start a keyring daemon on the user's keyrings otherwise)
# Godot's folder (export templates, keystores, the bench's user data and shader cache) is linked in; OFFSCREEN_GODOT_DATA
# names another (an empty one: a first start with no shader cache, as on a fresh install)
ln -s "${OFFSCREEN_GODOT_DATA:-${XDG_DATA_HOME:-$HOME/.local/share}/godot}" "$RT/home/data/godot"
export XDG_RUNTIME_DIR="$RT" XDG_DATA_HOME="$RT/home/data"
export XDG_CONFIG_HOME="$RT/home/config" XDG_CACHE_HOME="$RT/home/cache" XDG_STATE_HOME="$RT/home/state"
unset DISPLAY WAYLAND_DISPLAY
exec dbus-run-session -- mutter --headless --virtual-monitor "${XH_SIZE:-1600x900@240}" --wayland-display "xh-$$" -- "$@"
