#!/bin/sh
# Build the Windows MSIX (decision 0043): cross-build the app, lay it out, pack it with Microsoft's MakeAppx in a
# Windows VM, sign it here with osslsigncode (the key never leaves this machine).
#
#   packaging/windows/make-msix.sh VM_IP CERT.pfx OUT.msix
#   KKS_WIN_ARCH=aarch64 packaging/windows/make-msix.sh VM_IP CERT.pfx Walkdown-arm64.msix   (Windows on ARM64, 0047)
#
# CERT.pfx: the signing certificate with its key; its password in $KKS_MSIX_PASS (or empty). Its subject is the
# package's publisher. The real one lives in ~/.config/kks-explorer/signing (never in the repo); a test one:
#   packaging/windows/make-msix.sh --test-cert DIR
# The VM: OpenSSH with ~/.ssh/kks_vm, user kks (apps/windows/e2e/vm). Needs python3 with Pillow (the logos);
# osslsigncode is built from pinned source by build-osslsigncode.sh (run here when missing; KKS_OSSLSIGNCODE overrides).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
DEV="${KKS_DEV:-$HOME/.local/kksdev}"
SDKBT_VERSION=10.0.28000.2705
SDKBT_SHA256=8bfdfb6ca2633f531cf80b5fa22512ba61a394d7988f0970db83baadc67929ed
NAME="${KKS_MSIX_NAME:-Walkdown}"           # the package identity: changing it makes another app
DISPLAY_NAME="${KKS_MSIX_DISPLAY:-Walkdown}"     # Start menu and Settings → Apps (0.9.0 and 0.9.1 shipped "KKS Explorer")
OSSL="${KKS_OSSLSIGNCODE:-$DEV/osslsigncode/bin/osslsigncode}"
PY="${KKS_PY:-$REPO/.venv/bin/python}"

if [ "${1:-}" = "--test-cert" ]; then
  # a self-signed code-signing certificate for checking the pipeline (not for release)
  d="$2"; mkdir -p "$d"
  openssl req -x509 -newkey rsa:3072 -sha256 -days 365 -nodes -subj "/CN=KKS Explorer Test" \
    -addext "basicConstraints=critical,CA:FALSE" -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=codeSigning" -keyout "$d/test.key" -out "$d/test.crt" 2>/dev/null
  openssl pkcs12 -export -inkey "$d/test.key" -in "$d/test.crt" -out "$d/test.pfx" -passout pass: 2>/dev/null
  openssl x509 -in "$d/test.crt" -outform DER -out "$d/test.cer"
  echo "test certificate: $d/test.pfx (no password), $d/test.cer for TrustedPeople"
  exit 0
fi

VM="$1"; PFX="$2"; OUT="$3"
[ -n "${KKS_OSSLSIGNCODE:-}" ] || sh "$HERE/build-osslsigncode.sh" >/dev/null   # the pinned build (exits at once when present)
SSH="-i $HOME/.ssh/kks_vm -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes"
vm() { ssh $SSH "kks@$VM" "powershell -NoProfile -Command \"$1\""; }

# the publisher = the certificate's subject, as Windows writes it ("CN=…")
SUBJECT=$(openssl pkcs12 -in "$PFX" -nokeys -passin "pass:${KKS_MSIX_PASS:-}" 2>/dev/null | openssl x509 -noout -subject -nameopt RFC2253 | sed 's/^subject=//')
VERSION=$(tr -d ' \n' < "$REPO/VERSION").0
ARCH=$([ "${KKS_WIN_ARCH:-x86_64}" = aarch64 ] && echo arm64 || echo x64)
echo "package $NAME $VERSION ($ARCH), publisher $SUBJECT"

# 1. the app
W=/tmp/kks-msix-$ARCH
rm -rf "$W"; mkdir -p "$W/layout/Assets" "$W/layout/data/courses" "$W/layout/vendor/fonts"
sh "$REPO/apps/windows/build.sh" "$W/Walkdown.exe" >/dev/null
cp "$W/Walkdown.exe" "$W/layout/"
cp "$REPO"/data/courses/*.json "$REPO"/data/courses/*.jxl "$W/layout/data/courses/"
cp "$REPO"/vendor/fonts/*.woff2 "$W/layout/vendor/fonts/"
"$PY" - "$REPO/icon-512.png" "$W/layout/Assets" <<'EOF'
import sys
from PIL import Image
src, out = Image.open(sys.argv[1]).convert('RGBA'), sys.argv[2]
for name, px in (('Square44x44Logo', 44), ('Square150x150Logo', 150), ('StoreLogo', 50)):
    src.resize((px, px), Image.LANCZOS).save(f'{out}/{name}.png')
EOF
sed -e "s|@NAME@|$NAME|" -e "s|@PUBLISHER@|$SUBJECT|" -e "s|@VERSION@|$VERSION|" -e "s|@DISPLAY@|$DISPLAY_NAME|g" -e "s|@ARCH@|$ARCH|" \
  "$HERE/AppxManifest.xml.in" > "$W/layout/AppxManifest.xml"

# 2. MakeAppx from the pinned NuGet package, in the VM
NUPKG="$DEV/microsoft.windows.sdk.buildtools.$SDKBT_VERSION.nupkg"
if [ ! -f "$NUPKG" ]; then
  curl -sSL -o "$NUPKG.part" "https://api.nuget.org/v3-flatcontainer/microsoft.windows.sdk.buildtools/$SDKBT_VERSION/microsoft.windows.sdk.buildtools.$SDKBT_VERSION.nupkg"
  mv "$NUPKG.part" "$NUPKG"
fi
echo "$SDKBT_SHA256  $NUPKG" | sha256sum -c --quiet
rm -rf "$W/sdk"; mkdir -p "$W/sdk"
(cd "$W/sdk" && unzip -q "$NUPKG" 'bin/10.0.28000.0/x64/*')
vm "Remove-Item -Recurse -Force C:\\kks-msix -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force C:\\kks-msix | Out-Null"
scp -q -r $SSH "$W/sdk/bin/10.0.28000.0/x64" "kks@$VM:C:/kks-msix/sdk"
scp -q -r $SSH "$W/layout" "kks@$VM:C:/kks-msix/layout"
vm "& C:\\kks-msix\\sdk\\makeappx.exe pack /d C:\\kks-msix\\layout /p C:\\kks-msix\\unsigned.msix /o /h SHA256 | Select-Object -Last 2"
scp -q $SSH "kks@$VM:C:/kks-msix/unsigned.msix" "$W/unsigned.msix"

# 3. sign here
rm -f "$OUT"
"$OSSL" sign -pkcs12 "$PFX" -pass "${KKS_MSIX_PASS:-}" -h sha256 -in "$W/unsigned.msix" -out "$OUT" >/dev/null
"$OSSL" verify -in "$OUT" -CAfile "$(dirname "$PFX")/$(basename "$PFX" .pfx).crt" 2>/dev/null | grep -E "Signature verification|Number of verified" || true
ls -la "$OUT"
