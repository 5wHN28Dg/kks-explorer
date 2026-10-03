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
set -eu
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
cp "$REPO/extractor/fontlib.kgl" "$APP.tmp/"
for f in index.html admin.html common.js tiles.js course-bridge.js learning.html course.html course.js course-figure.js \
         course.css kks-wasm.js kks-wasm-worker.js sw.js manifest.webmanifest icon.svg icon-192.png icon-512.png; do
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
{"address": "0.0.0.0", "port": 8420, "sync_port": 8421,
 "web_dir": "$HOME_DIR/app/current", "data_dir": "$HOME_DIR/app/current/data",
 "importer": "$HOME_DIR/app/current/kks-import", "glyphs": "$HOME_DIR/app/current/fontlib.kgl",
 "store": "$HOME_DIR/state/server.db", "plant_dir": "$HOME_DIR/state/plant-data", "backup_dir": "$HOME_DIR/state/backups"}
CFG
  echo "wrote $HOME_DIR/config.json"
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

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
echo "installed. Not started. Rollback: ln -sfn \$(readlink $HOME_DIR/app/previous) $HOME_DIR/app/current"
