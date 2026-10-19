#!/bin/sh
# Walkdown Plant's MSIX (decision 0054 §8), made as packaging/windows/make-msix.sh makes Walkdown's: the release
# export's WalkdownPlant.exe (the .pck embedded) laid out with AppxManifest.xml and the logos, packed by Microsoft's
# MakeAppx in a Windows VM, signed here with osslsigncode (the key never leaves this machine).
#
#   apps/plant3d/msix/make-msix.sh VM_IP CERT.pfx OUT.msix                          x64 (export/windows/)
#   KKS_WIN_ARCH=aarch64 apps/plant3d/msix/make-msix.sh VM_IP CERT.pfx OUT.msix     ARM64 (export/windows-arm64/)
#   apps/plant3d/msix/make-msix.sh --layout DIR CERT.pfx                            only the package's folder
#   apps/plant3d/msix/make-msix.sh --test-cert DIR                                  a self-signed test certificate
#
# The exe: tools/plant3d/bench/offscreen.sh apps/plant3d/build.sh release windows (or windows-arm64); PLANT_EXE names
# another (a check export, for tests). CERT.pfx: its subject is the package's publisher; its password in
# $KKS_MSIX_PASS (or empty). A release is signed with Walkdown's own certificate (CN=Walkdown,
# ~/.config/kks-explorer/signing/windows-msix.pfx, 0043); tests only ever with --test-cert's. The package's version is
# the app's (project.godot application/config/version) with .0. The VM: OpenSSH with ~/.ssh/kks_vm, user kks
# (apps/windows/e2e/vm). MakeAppx and osslsigncode are the ones Walkdown's script pins.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
APP=$(cd "$HERE/.." && pwd)
REPO=$(cd "$APP/../.." && pwd)
WIN="$REPO/packaging/windows"
DEV="${KKS_DEV:-$HOME/.local/kksdev}"
OSSL="${KKS_OSSLSIGNCODE:-$DEV/osslsigncode/bin/osslsigncode}"

if [ "${1:-}" = "--test-cert" ]; then
  exec sh "$WIN/make-msix.sh" --test-cert "$2"
fi

case "${KKS_WIN_ARCH:-x86_64}" in x86_64) ARCH=x64 ;; aarch64) ARCH=arm64 ;; *) echo "KKS_WIN_ARCH is x86_64 or aarch64, not $KKS_WIN_ARCH" >&2; exit 2 ;; esac
EXPORT_DIR=$([ "$ARCH" = arm64 ] && echo windows-arm64 || echo windows)
EXE="${PLANT_EXE:-$APP/export/$EXPORT_DIR/WalkdownPlant.exe}"
VERSION=$(sed -n 's/^config\/version="\([0-9]*\.[0-9]*\.[0-9]*\)"$/\1/p' "$APP/project.godot").0
[ "$VERSION" != ".0" ] || { echo "project.godot has no application/config/version" >&2; exit 2; }

# the package's folder: the exe, the manifest (publisher = the certificate's subject, exactly as Windows writes it),
# the logos drawn from icon.svg
layout() {  # DIR PFX
  [ -s "$EXE" ] || { echo "no $EXE: build.sh release $EXPORT_DIR first (or PLANT_EXE)" >&2; exit 2; }
  SUBJECT=$(openssl pkcs12 -in "$2" -nokeys -passin "pass:${KKS_MSIX_PASS:-}" 2>/dev/null | openssl x509 -noout -subject -nameopt RFC2253 | sed 's/^subject=//')
  [ -n "$SUBJECT" ] || { echo "cannot read the certificate's subject from $2" >&2; exit 2; }
  case "$SUBJECT" in *'|'*|*'&'*|*'<'*|*'>'*|*'"'*) echo "the certificate's subject has characters the manifest can't take: $SUBJECT" >&2; exit 2 ;; esac
  rm -rf "$1"; mkdir -p "$1/Assets"
  cp "$EXE" "$1/WalkdownPlant.exe"
  GODOT="${GODOT:-$("$REPO/tools/plant3d/bench/fetch_godot.sh")}"
  timeout 120 "$GODOT" --headless --path "$APP" --script res://msix/logos.gd -- "$1/Assets" >/dev/null 2>&1 ||
    { echo "the logos were not made (msix/logos.gd)" >&2; exit 1; }
  sed -e "s|@PUBLISHER@|$SUBJECT|" -e "s|@VERSION@|$VERSION|" -e "s|@ARCH@|$ARCH|" \
    "$HERE/AppxManifest.xml.in" > "$1/AppxManifest.xml"
  ! grep -q '@[A-Z]*@' "$1/AppxManifest.xml" || { echo "AppxManifest.xml still has a placeholder" >&2; exit 1; }
  echo "package WalkdownPlant $VERSION ($ARCH), publisher $SUBJECT"
}

if [ "${1:-}" = "--layout" ]; then
  layout "$2" "$3"
  exit 0
fi

VM="$1"; PFX="$2"; OUT="$3"
[ -n "${KKS_OSSLSIGNCODE:-}" ] || sh "$WIN/build-osslsigncode.sh" >/dev/null   # the pinned build (exits at once when present)
W="${TMPDIR:-/tmp}/plant-msix-$ARCH"
rm -rf "$W"; mkdir -p "$W"
layout "$W/layout" "$PFX"

# MakeAppx from the NuGet package Walkdown's script pins (version and SHA-256 read from it: one pin), in the VM
SDKBT_VERSION=$(sed -n 's/^SDKBT_VERSION=\([0-9.]*\)$/\1/p' "$WIN/make-msix.sh")
SDKBT_SHA256=$(sed -n 's/^SDKBT_SHA256=\([0-9a-f]*\)$/\1/p' "$WIN/make-msix.sh")
[ -n "$SDKBT_VERSION" ] && [ ${#SDKBT_SHA256} -eq 64 ] || { echo "cannot read the MakeAppx pin from $WIN/make-msix.sh" >&2; exit 2; }
SDKBIN="10.0.$(echo "$SDKBT_VERSION" | cut -d. -f3).0"
NUPKG="$DEV/microsoft.windows.sdk.buildtools.$SDKBT_VERSION.nupkg"
if [ ! -f "$NUPKG" ]; then
  curl -sSLf -o "$NUPKG.part" "https://api.nuget.org/v3-flatcontainer/microsoft.windows.sdk.buildtools/$SDKBT_VERSION/microsoft.windows.sdk.buildtools.$SDKBT_VERSION.nupkg"
  mv "$NUPKG.part" "$NUPKG"
fi
echo "$SDKBT_SHA256  $NUPKG" | sha256sum -c --quiet
mkdir -p "$W/sdk"
(cd "$W/sdk" && unzip -q "$NUPKG" "bin/$SDKBIN/x64/*")
SSH="-i $HOME/.ssh/kks_vm -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes"
vm() { ssh $SSH "kks@$VM" "powershell -NoProfile -Command \"$1\""; }
vm "Remove-Item -Recurse -Force C:\\plant-msix -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force C:\\plant-msix | Out-Null"
scp -q -r $SSH "$W/sdk/bin/$SDKBIN/x64" "kks@$VM:C:/plant-msix/sdk"
scp -q -r $SSH "$W/layout" "kks@$VM:C:/plant-msix/layout"
vm "& C:\\plant-msix\\sdk\\makeappx.exe pack /d C:\\plant-msix\\layout /p C:\\plant-msix\\unsigned.msix /o /h SHA256 | Select-Object -Last 2"
scp -q $SSH "kks@$VM:C:/plant-msix/unsigned.msix" "$W/unsigned.msix"
vm "Remove-Item -Recurse -Force C:\\plant-msix -ErrorAction SilentlyContinue"

# sign here
rm -f "$OUT"
"$OSSL" sign -pkcs12 "$PFX" -pass "${KKS_MSIX_PASS:-}" -h sha256 -in "$W/unsigned.msix" -out "$OUT" >/dev/null
"$OSSL" verify -in "$OUT" -CAfile "$(dirname "$PFX")/$(basename "$PFX" .pfx).crt" 2>/dev/null | grep -E "Signature verification|Number of verified" || true
ls -la "$OUT"
