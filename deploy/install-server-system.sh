#!/bin/sh
# Run the server installed by deploy/install-server-user.sh as a SYSTEM service under an unprivileged user. For a
# machine without a TPM2 (most rented virtual servers): there a user service cannot load the sealed storage key
# ("Failed to determine local credential key: Permission denied", exit status 243/CREDENTIALS), because only the
# system manager can read the machine's credential key (/var/lib/systemd/credential.secret).
#   /etc/systemd/system/kks-server.service       the unit (User=USER; it can only write ~USER/kks-server/state)
#   /etc/credstore.encrypted/kks-storage-key     the storage key, sealed to this machine (decision 0020); made once
# Steps on a new machine:
#   1. as USER:  KKS_SERVER_UNIT=system deploy/install-server-user.sh    (builds and installs; no user unit, no key)
#   2. as root:  deploy/install-server-system.sh USER                    (this script; does not start anything)
#   3. set public_url, secure_cookies and trusted_proxy in ~USER/kks-server/config.json, put an HTTPS proxy in front
#      (deploy/Caddyfile.example), then: systemctl enable --now kks-server
# Updating: step 1 again, then systemctl restart kks-server.
# Commands that need the storage key (wiki: Server), as root:
#   systemd-run --pipe --wait -q -p User=USER -E KKS_CONFIG=HOME/kks-server/config.json \
#     -p LoadCredentialEncrypted=kks-storage-key:/etc/credstore.encrypted/kks-storage-key \
#     -p WorkingDirectory=HOME/kks-server/state HOME/kks-server/app/current/kks-server COMMAND
# The service has its own /tmp (PrivateTmp): a file handed to the running server (publish-data DIR, submit-file FILE)
# must be somewhere it can read, e.g. under HOME/kks-server/state, not /tmp.
# Usage: deploy/install-server-system.sh USER
#        deploy/install-server-system.sh --print-unit USER HOME     (prints the unit, changes nothing; for the tests)
set -eu
CRED=/etc/credstore.encrypted/kks-storage-key
P="${KKS_SYSTEM_PREFIX:-}"   # the tests write under a scratch folder instead of /

unit() {  # $1 user, $2 the server's folder
  cat <<UNIT
# Walkdown v2 server as a system service running as the unprivileged user $1 (deploy/install-server-system.sh).
[Unit]
Description=Walkdown server (v2)
After=network-online.target
Wants=network-online.target

[Service]
User=$1
Environment=KKS_CONFIG=$2/config.json
WorkingDirectory=$2/state
ExecStart=$2/app/current/kks-server serve
LoadCredentialEncrypted=kks-storage-key:$CRED
Restart=on-failure
RestartSec=5
UMask=0077
# hardening: the process can only write its state folder. ProtectHome is not set: the server lives in the user's home.
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ReadWritePaths=$2/state
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
RestrictSUIDSGID=true
RestrictRealtime=true
LockPersonality=true
RestrictNamespaces=true
SystemCallArchitectures=native
CapabilityBoundingSet=
# AF_NETLINK: the server lists the machine's addresses (getifaddrs)
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX AF_NETLINK
# the server and the importer it starts: the reasoning is in deploy/install-server-user.sh (never MemoryHigh)
MemoryMax=3G
MemorySwapMax=0
OOMPolicy=continue
LimitCORE=0

[Install]
WantedBy=multi-user.target
UNIT
}

if [ "${1:-}" = "--print-unit" ]; then
  [ $# -eq 3 ] || { echo "usage: $0 --print-unit USER HOME" >&2; exit 2; }
  unit "$2" "$3/kks-server"
  exit 0
fi
[ $# -eq 1 ] || { echo "usage: $0 USER" >&2; exit 2; }
[ "$(id -u)" -eq 0 ] || { echo "run this as root (it writes a system unit and the machine's credential)" >&2; exit 1; }
USER_NAME=$1
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
[ -n "$USER_HOME" ] || { echo "no such user: $USER_NAME" >&2; exit 1; }
[ "$(id -u "$USER_NAME")" -ne 0 ] || { echo "the server must not run as root" >&2; exit 1; }
HOME_DIR="$USER_HOME/kks-server"
[ -x "$HOME_DIR/app/current/kks-server" ] || {
  echo "$HOME_DIR/app/current/kks-server is missing: run deploy/install-server-user.sh as $USER_NAME first" >&2; exit 1; }
case "$USER_NAME$HOME_DIR" in *[!A-Za-z0-9._/-]*)
  echo "a user name or home folder with characters outside A-Z a-z 0-9 . _ / - can't go into the unit" >&2; exit 1;;
esac
if [ -e "$USER_HOME/.config/systemd/user/kks-server.service" ] || [ -e "$HOME_DIR/storage-key.cred" ]; then
  echo "$USER_NAME also has a user unit or a user-sealed key (from install-server-user.sh without" >&2
  echo "KKS_SERVER_UNIT=system). Two services on one database must never exist." >&2
  echo "If $HOME_DIR/state/server.db exists, $HOME_DIR/storage-key.cred is the ONLY key that opens it:" >&2
  echo "do not delete it. Stop the user service and move the key first (wiki: Server, moving a server)." >&2
  echo "Otherwise remove both, then run this again." >&2
  exit 1
fi
if [ ! -f "$P$CRED" ]; then
  if [ -e "$HOME_DIR/state/server.db" ]; then
    echo "$HOME_DIR/state/server.db exists but $CRED does not: a new key could not open that database." >&2
    echo "Bring the database's own storage key over first (wiki: Server, moving a server)." >&2
    exit 1
  fi
  mkdir -p "$(dirname "$P$CRED")"
  chmod 700 "$(dirname "$P$CRED")"
  KEY=$(head -c 32 /dev/urandom | base64 -w0)
  [ "${#KEY}" -eq 44 ] || { echo "could not read 32 random bytes" >&2; exit 1; }
  rm -f "$P$CRED.tmp"   # sealed into a temporary name: a failure never leaves a half-written credential in place
  (umask 077 && printf %s "$KEY" | base64 -d | systemd-creds encrypt --name=kks-storage-key - "$P$CRED.tmp")
  KEY=
  [ -s "$P$CRED.tmp" ] || { echo "systemd-creds wrote no credential" >&2; exit 1; }
  mv "$P$CRED.tmp" "$P$CRED"
  echo "sealed a new storage key into $CRED (this machine only)"
fi
mkdir -p "$P/etc/systemd/system"
unit "$USER_NAME" "$HOME_DIR" > "$P/etc/systemd/system/kks-server.service"
systemctl daemon-reload
echo "installed. Not started. Start: systemctl enable --now kks-server"
