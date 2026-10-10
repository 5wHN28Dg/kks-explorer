#!/bin/sh
# Install the v2 (M6) server for one user under ~/kks-server, separate from the development checkout:
#   ~/kks-server/app/<version>-<commit>/   kks-server, kks-import, glyph library, web pages, vendor/, data/ (read-only)
#   ~/kks-server/app/current               -> the active one (this script switches it; the previous stays for rollback)
#   ~/kks-server/config.json               settings (written once, never overwritten)
#   ~/kks-server/state/                    server.db (sealed rows), plant-data/, backups/
#   ~/kks-server/storage-key.cred          the storage key, sealed to this user + TPM2 by systemd-creds (decision 0020)
#   ~/.config/systemd/user/kks-server.service
# Editing the repo never changes the running server: updating it means running this script again on purpose.
# Usage: deploy/install-server-user.sh            (build from this checkout and install; does not start anything)
#        KKS_SERVER_UNIT=system deploy/install-server-user.sh    (the same without the user unit and its key: for a
#                                                 machine without a TPM2, where deploy/install-server-system.sh
#                                                 runs this install as a system service instead)
set -eu
UNIT_KIND="${KKS_SERVER_UNIT:-user}"
case "$UNIT_KIND" in user|system) ;; *) echo "KKS_SERVER_UNIT must be user or system" >&2; exit 2;; esac
SYSTEM_UNIT="${KKS_SYSTEM_UNIT_FILE:-/etc/systemd/system/kks-server.service}"   # the variable is for the tests
if [ "$UNIT_KIND" = user ] && [ -e "$SYSTEM_UNIT" ]; then
  echo "$SYSTEM_UNIT exists: this machine runs the server as a system service." >&2
  echo "Run this with KKS_SERVER_UNIT=system (a user unit and a second key next to it must never exist)." >&2
  exit 1
fi
REPO=$(cd "$(dirname "$0")/.." && pwd)
HOME_DIR="${KKS_SERVER_HOME:-$HOME/kks-server}"
NIM="${NIM:-$HOME/.nimble/bin/nim}"
VER="$(cat "$REPO/VERSION")-$(git -C "$REPO" rev-parse --short HEAD)$(git -C "$REPO" diff --quiet HEAD -- . || echo -dirty)"
APP="$HOME_DIR/app/$VER"
echo "installing $VER into $APP"
mkdir -p "$HOME_DIR/state" && chmod 700 "$HOME_DIR"
rm -rf "$APP.tmp" && mkdir -p "$APP.tmp"
(cd "$REPO/platform/linux" && "$NIM" c -d:release --hints:off -o:"$APP.tmp/kks-server" kks_server.nim >/dev/null)
(cd "$REPO/importer" && "$NIM" c -d:release --hints:off -o:"$APP.tmp/kks-import" kks_import.nim >/dev/null)
cp "$REPO/importer/fontlib.kgl" "$APP.tmp/"
for f in index.html index.js admin.html admin.js common.js tiles.js dark.js systems.js course-bridge.js learning.html learning.js course.html course.js course-figure.js \
         course.css kks-wasm.js kks-wasm-worker.js sw.js manifest.webmanifest icon.svg icon-192.png icon-512.png apple-touch-icon.png; do
  cp "$REPO/$f" "$APP.tmp/"
done
cp -r "$REPO/vendor" "$APP.tmp/vendor"
mkdir -p "$APP.tmp/data" && cp "$REPO/data/kks.json" "$APP.tmp/data/" && cp -r "$REPO/data/courses" "$APP.tmp/data/courses"
chmod -R a-w "$APP.tmp"
rm -rf "$APP" && mv "$APP.tmp" "$APP"
[ -e "$HOME_DIR/app/current" ] && ln -sfn "$(readlink "$HOME_DIR/app/current")" "$HOME_DIR/app/previous"
ln -sfn "$VER" "$HOME_DIR/app/current"
if [ ! -f "$HOME_DIR/config.json" ]; then
  cat > "$HOME_DIR/config.json" <<CFG
{"address": "127.0.0.1", "port": 8420, "sync_port": 8421,
 "web_dir": "$HOME_DIR/app/current", "data_dir": "$HOME_DIR/app/current/data",
 "importer": "$HOME_DIR/app/current/kks-import", "glyphs": "$HOME_DIR/app/current/fontlib.kgl",
 "store": "$HOME_DIR/state/server.db", "plant_dir": "$HOME_DIR/state/plant-data", "backup_dir": "$HOME_DIR/state/backups"}
CFG
  echo "wrote $HOME_DIR/config.json"
fi
if [ "$UNIT_KIND" = system ]; then
  echo "installed. No user unit (KKS_SERVER_UNIT=system): as root, deploy/install-server-system.sh $(id -un)"
  echo "Rollback: ln -sfn \$(readlink $HOME_DIR/app/previous) $HOME_DIR/app/current"
  exit 0
fi
if [ ! -f "$HOME_DIR/storage-key.cred" ]; then
  head -c 32 /dev/urandom | systemd-creds --user encrypt --name=kks-storage-key - "$HOME_DIR/storage-key.cred"
  chmod 600 "$HOME_DIR/storage-key.cred"
  echo "sealed a new storage key into $HOME_DIR/storage-key.cred (this user + this machine only)"
fi
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/kks-server.service" <<UNIT
# Walkdown v2 server for this user (deploy/install-server-user.sh). Start: systemctl --user start kks-server
[Unit]
Description=Walkdown server (v2, user)
After=network-online.target

[Service]
Environment=KKS_CONFIG=$HOME_DIR/config.json
WorkingDirectory=$HOME_DIR/state
ExecStart=$HOME_DIR/app/current/kks-server serve
LoadCredentialEncrypted=kks-storage-key:$HOME_DIR/storage-key.cred
Restart=on-failure
RestartSec=5
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
# issue #34: the server and the drawing importer it starts (which also has its own address-space limit and timeout,
# import_memory_mb / import_timeout_s) together; a large sheet's import peaks near 1.8 GB, the server itself stays
# in the low hundreds of MB (2026-10-09). A server that runs away anyway is killed at the cap and restarted
# (Restart=on-failure) instead of crowding the desktop or a small VM: no swap for it, and never MemoryHigh (throttling
# took the desktop down here). The importer's own address-space limit (import_memory_mb, 2560 by default; the largest
# real sheet needs about 2 GB of address space) is below the cap, so an import that grows stops itself first, and the
# server's import log says which setting to raise (keep it below the cap, or raise both). OOMPolicy=continue: when
# the kernel picks the importer (usually: it is the biggest), only its import fails; when it picks the server, the
# server restarts.
# ProtectSystem/ProtectHome are not set: a user unit can't apply them without user namespaces, and here they were
# silently ignored.
MemoryMax=3G
MemorySwapMax=0
OOMPolicy=continue
LimitCORE=0

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
echo "installed. Not started. Rollback: ln -sfn \$(readlink $HOME_DIR/app/previous) $HOME_DIR/app/current"
