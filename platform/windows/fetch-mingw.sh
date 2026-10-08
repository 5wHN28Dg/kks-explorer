#!/bin/sh
# mingw-w64 13 / GCC 13 with POSIX threads (decision 0033), the Windows x86_64 cross toolchain, unpacked without root
# from Ubuntu 26.04's packages into ~/.local/kksdev/mingw (build-deps.sh and apps/windows/build.sh look there).
# Each .deb is pinned by SHA-256 (the same files apt verified against the archive's signed index, SHA-512 there;
# checked 2026-10-08) and fetched from Launchpad's librarian, which keeps every published file at a fixed URL.
# CI installs the same versions with apt instead (.github/workflows/tests.yml).
set -eu
DEV="${KKS_DEV:-$HOME/.local/kksdev}"
VER=13.2.0-6ubuntu1+26.1
[ -x "$DEV/mingw/usr/bin/x86_64-w64-mingw32-gcc-posix" ] && grep -qx "$VER" "$DEV/mingw/VERSION.kks" 2>/dev/null && exit 0
DL="$DEV/mingw-debs"
mkdir -p "$DL"
LP=https://launchpad.net/ubuntu/+archive/primary/+files
while read -r sha deb; do
  f="$DL/$deb"
  if [ ! -f "$f" ] || [ "$(sha256sum "$f" | cut -d' ' -f1)" != "$sha" ]; then
    echo "download $deb"; curl -sSfL -o "$f" "$LP/$(printf %s "$deb" | sed 's/+/%2B/g')"
  fi
  echo "$sha  $f" | sha256sum -c --quiet || { rm -f "$f"; exit 1; }
done <<'DEBS'
f835050ed5b7fedf8f3242610fda1eb55b5472b72624f9a88de90c610b465552 binutils-mingw-w64-x86-64_2.45.90.20260125-1ubuntu1+13.3_amd64.deb
a30c07e807e9874ea93909448c5d6d37f9569ebe60ad32de8e490aad198538a3 gcc-mingw-w64-base_13.2.0-6ubuntu1+26.1_amd64.deb
0855fa1d4a618550faac3a3e4352aa3226833b28184ad3c3b496a68a22c4eda2 gcc-mingw-w64-x86-64-posix_13.2.0-6ubuntu1+26.1_amd64.deb
aca6b438e0b55b11cedcf1170a1ee26e7979e34192e34f6e6389e560908a5bfc gcc-mingw-w64-x86-64-posix-runtime_13.2.0-6ubuntu1+26.1_amd64.deb
52c3613f386e462ae71105d1a0b2a48d866ccb048ad253acff629c5a2291252d g++-mingw-w64-x86-64-posix_13.2.0-6ubuntu1+26.1_amd64.deb
da9b2cb14134ca0ef3a31302df50295a2dd6fee7aa4fd888b11c6f72f8ab939e mingw-w64-common_13.0.0-2ubuntu1_all.deb
da40b9e2ae89d98d44b547a9e4fd01862858edb176bade9f12ad143e7ae7efe4 mingw-w64-x86-64-dev_13.0.0-2ubuntu1_all.deb
DEBS
rm -rf "$DEV/mingw.tmp"; mkdir -p "$DEV/mingw.tmp"
for f in "$DL"/*.deb; do dpkg-deb -x "$f" "$DEV/mingw.tmp"; done
echo "$VER" > "$DEV/mingw.tmp/VERSION.kks"
rm -rf "$DEV/mingw"; mv "$DEV/mingw.tmp" "$DEV/mingw"
echo "mingw-w64 $VER in $DEV/mingw"
