#!/bin/sh
# Run a command against a private, invisible GNOME compositor, so the GNOME app's tests never open a window on the
# desktop of whoever uses this machine:
#   apps/gnome/e2e/headless.sh python3 apps/gnome/e2e/test_gnome.py
# - its own D-Bus session (dbus-run-session): its own accessibility bus for AT-SPI;
# - its own XDG_RUNTIME_DIR (a fresh 0700 directory, removed after): whatever the private bus starts (portals,
#   at-spi, dconf, pipewire …) puts its sockets and mounts there. Sharing /run/user/$UID broke every Flatpak app on
#   the desktop (2026-10-04): the private bus started a second xdg-document-portal, which took over
#   /run/user/$UID/doc and unmounted it when the session ended;
# - mutter --headless with one virtual monitor (1280x900), Wayland only;
# - DISPLAY unset and GDK_BACKEND=wayland: the app can only reach that compositor; GTK_USE_PORTAL=0 as well.
# mutter: $KKS_MUTTER, else `mutter` on PATH, else ~/.local/kksdev/root/usr/bin/mutter (Ubuntu's `mutter` package
# unpacked there with `apt-get download mutter && dpkg-deb -x`: it is a thin launcher for the libmutter GNOME Shell uses).
set -eu
MUTTER="${KKS_MUTTER:-$(command -v mutter || echo "$HOME/.local/kksdev/root/usr/bin/mutter")}"
[ -x "$MUTTER" ] || { echo "no mutter: see the comment in $0" >&2; exit 2; }
export KKS_HEADLESS_MUTTER="$MUTTER"
# its default plugin, next to it when unpacked locally (else mutter finds its own)
plugin="$(dirname "$MUTTER")/../lib/x86_64-linux-gnu/mutter-18/plugins/libdefault.so"
export KKS_HEADLESS_PLUGIN=""
[ -f "$plugin" ] && KKS_HEADLESS_PLUGIN="--mutter-plugin=$plugin"
# the runtime directory is made before dbus-run-session, so the private bus and everything it starts live in it
RT="$(mktemp -d "${TMPDIR:-/tmp}/kks-headless-rt.XXXXXX")"
chmod 700 "$RT"
export XDG_RUNTIME_DIR="$RT" GTK_USE_PORTAL=0
cleanup() {
  # the private portals' FUSE mounts (doc, gvfs) go away as dbus-run-session ends them: wait a moment, unmount any
  # left (they are ours: under $RT), then remove the directory
  i=0
  while findmnt -rn -o TARGET | grep -q "^$RT/" && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  findmnt -rn -o TARGET | grep "^$RT/" | while read -r t; do fusermount3 -uz "$t" 2>/dev/null || fusermount -uz "$t" 2>/dev/null; done
  rm -rf "$RT"
}
trap cleanup EXIT
r=0
dbus-run-session -- sh -c '
  disp="kks-headless-$$"
  unset DISPLAY
  export WAYLAND_DISPLAY="$disp" GDK_BACKEND=wayland
  "$KKS_HEADLESS_MUTTER" $KKS_HEADLESS_PLUGIN --headless --virtual-monitor 1280x900 --no-x11 --wayland-display "$disp" >/tmp/kks-headless-mutter.log 2>&1 &
  m=$!
  i=0
  while [ ! -S "$XDG_RUNTIME_DIR/$disp" ]; do
    i=$((i + 1)); [ $i -gt 100 ] && { echo "mutter did not start (/tmp/kks-headless-mutter.log)" >&2; kill $m; exit 2; }
    sleep 0.1
  done
  r=0
  "$@" || r=$?
  kill $m 2>/dev/null
  wait $m 2>/dev/null
  exit $r
' sh "$@" || r=$?
exit $r
