#!/bin/bash
# libjxl + zxing-cpp for the browser client (decision 0037), built with a pinned Emscripten from the same pinned,
# SHA-256-checked sources as the native apps (platform/windows/build-deps.sh). Two variants: WebAssembly SIMD and
# scalar (Chromium 80–90). Run with bash. Output: vendor/kks/{kks-simd,kks}{,-dec}.{js,wasm} + SHA256SUMS (-dec: JPEG XL decoding only).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
DEV="${KKS_DEV:-$HOME/.local/kksdev}"
SRC="$DEV/src"
EMSDK="$DEV/emsdk"
EMSDK_VERSION=6.0.10
EMSDK_COMMIT=a2b92777574c2feda07994cd4f1079a3dfc151f8   # the emsdk repository at tag 6.0.10
OUT="$REPO/vendor/kks"
mkdir -p "$SRC/dl" "$OUT"

fetch() { # name url sha256
  f="$SRC/dl/$1.tar.gz"
  if [ ! -f "$f" ] || [ "$(sha256sum "$f" | cut -d' ' -f1)" != "$3" ]; then
    echo "download $1"; curl -sL -o "$f" "$2"
  fi
  got=$(sha256sum "$f" | cut -d' ' -f1)
  [ "$got" = "$3" ] || { echo "$1: SHA-256 $got, expected $3" >&2; rm -f "$f"; exit 1; }
}
unpack() { rm -rf "$2"; mkdir -p "$2"; tar xzf "$SRC/dl/$1.tar.gz" -C "$2" --strip-components=1; }

# the toolchain, pinned (emsdk installs the matching LLVM, binaryen and node)
if [ ! -x "$EMSDK/upstream/emscripten/emcc" ]; then
  rm -rf "$EMSDK"
  git clone -q https://github.com/emscripten-core/emsdk.git "$EMSDK"
  git -C "$EMSDK" checkout -q "$EMSDK_COMMIT"
  "$EMSDK/emsdk" install "$EMSDK_VERSION" >/dev/null
  "$EMSDK/emsdk" activate "$EMSDK_VERSION" >/dev/null
fi
source "$EMSDK/emsdk_env.sh" >/dev/null 2>&1

fetch libjxl https://codeload.github.com/libjxl/libjxl/tar.gz/v0.12.0 03e9be69a30be4011f559da75328b6d7cea8ad921fabfbd551ce10bf45cdc992
fetch highway https://codeload.github.com/google/highway/tar.gz/457c891775a7397bdb0376bb1031e6e027af1c48 5124b0501c98d9930dbb065bfa1a5bbbd59ce0f12facb7e1e33aaef01a5f1f1a
fetch brotli https://codeload.github.com/google/brotli/tar.gz/028fb5a23661f123017c060daa546b55cf4bde29 0afe09a53c8bad9861c8dd1fc1284308d54f19d2979ba3541cfdcc9b05fe360f
fetch skcms https://codeload.github.com/google/skcms/tar.gz/96d9171c94b937a1b5f0293de7309ac16311b722 9bb4b5bba0b7c04f6c2bce9ff713d61e23c9a20c4945161ae16290498ad74627
fetch zxing-cpp https://codeload.github.com/zxing-cpp/zxing-cpp/tar.gz/v3.1.1 7286b1e6ade66fe82b7c8208b4595deeb55d6486b410834fdc65702f46650542

build() { # variant cflags
  V=$1; FLAGS=$2
  P="$DEV/wasm-$V"
  if [ ! -f "$P/lib/libjxl.a" ]; then
    J="$SRC/wasm-$V-libjxl"
    unpack libjxl "$J"; unpack highway "$J/third_party/highway"; unpack brotli "$J/third_party/brotli"; unpack skcms "$J/third_party/skcms"
    CFLAGS="$FLAGS" CXXFLAGS="$FLAGS" emcmake cmake -S "$J" -B "$J/build" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
      -DCMAKE_INSTALL_PREFIX="$P" -DBUILD_TESTING=OFF -DJPEGXL_ENABLE_TOOLS=OFF -DJPEGXL_ENABLE_DOXYGEN=OFF \
      -DJPEGXL_ENABLE_MANPAGES=OFF -DJPEGXL_ENABLE_BENCHMARK=OFF -DJPEGXL_ENABLE_EXAMPLES=OFF -DJPEGXL_ENABLE_JNI=OFF \
      -DJPEGXL_ENABLE_SJPEG=OFF -DJPEGXL_ENABLE_OPENEXR=OFF -DJPEGXL_ENABLE_JPEGLI=OFF -DJPEGXL_ENABLE_PLUGINS=OFF \
      -DJPEGXL_ENABLE_VIEWERS=OFF -DJPEGXL_ENABLE_DEVTOOLS=OFF -DJPEGXL_ENABLE_FUZZERS=OFF -DJPEGXL_BUNDLE_LIBPNG=OFF \
      -DJPEGXL_ENABLE_TRANSCODE_JPEG=OFF -DJPEGXL_ENABLE_SKCMS=ON -DJPEGXL_STATIC=ON -DJPEGXL_FORCE_SYSTEM_BROTLI=OFF \
      -DHWY_ENABLE_TESTS=OFF -DHWY_ENABLE_EXAMPLES=OFF -DHWY_ENABLE_CONTRIB=OFF -DBROTLI_DISABLE_TESTS=ON >/dev/null
    cmake --build "$J/build" -j"$(nproc)" >/dev/null
    cmake --install "$J/build" >/dev/null
  fi
  if [ ! -f "$P/lib/libZXing.a" ]; then
    Z="$SRC/wasm-$V-zxing"
    unpack zxing-cpp "$Z"
    CFLAGS="$FLAGS" CXXFLAGS="$FLAGS" emcmake cmake -S "$Z/core" -B "$Z/build" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
      -DCMAKE_INSTALL_PREFIX="$P" -DZXING_READERS=ON -DZXING_WRITERS=OLD -DZXING_C_API=ON -DCMAKE_CXX_STANDARD=20 >/dev/null
    cmake --build "$Z/build" -j"$(nproc)" >/dev/null
    cmake --install "$Z/build" >/dev/null
  fi
  name=$([ "$V" = simd ] && echo kks-simd || echo kks)
  COMMON="-s MODULARIZE=1 -s EXPORT_ES6=1 -s EXPORT_NAME=KksWasm -s ENVIRONMENT=web,worker -s ALLOW_MEMORY_GROWTH=1 \
    -s FILESYSTEM=0 -s INITIAL_MEMORY=33554432 -s EXPORTED_RUNTIME_METHODS=HEAPU8,HEAPU32"
  # decode only: what a browser without JPEG XL needs to show photos and drawings
  em++ -O3 $FLAGS -std=c++17 -DKKS_DECODE_ONLY -I"$P/include" "$HERE/kks_wasm.cpp" \
    "$P/lib/libjxl.a" "$P/lib/libjxl_cms.a" "$P/lib/libhwy.a" "$P/lib/libbrotlidec.a" "$P/lib/libbrotlicommon.a" \
    $COMMON -s EXPORTED_FUNCTIONS=_kks_malloc,_kks_free,_kks_jxl_decode -o "$OUT/${name}-dec.js"
  # everything: encoding photos, QR codes
  em++ -O3 $FLAGS -std=c++17 -I"$P/include" -I"$P/include/ZXing" "$HERE/kks_wasm.cpp" \
    "$P/lib/libjxl.a" "$P/lib/libjxl_cms.a" "$P/lib/libhwy.a" "$P/lib/libbrotlienc.a" "$P/lib/libbrotlidec.a" \
    "$P/lib/libbrotlicommon.a" "$P/lib/libZXing.a" \
    -s MODULARIZE=1 -s EXPORT_ES6=1 -s EXPORT_NAME=KksWasm -s ENVIRONMENT=web,worker -s ALLOW_MEMORY_GROWTH=1 \
    -s FILESYSTEM=0 -s INITIAL_MEMORY=33554432 \
    -s EXPORTED_FUNCTIONS=_kks_malloc,_kks_free,_kks_jxl_decode,_kks_jxl_encode,_kks_qr_read,_kks_qr_write \
    -s EXPORTED_RUNTIME_METHODS=HEAPU8,HEAPU32 -o "$OUT/$name.js"
}

build simd "-msimd128"
build scalar ""
(cd "$OUT" && sha256sum kks-simd.js kks-simd.wasm kks.js kks.wasm kks-simd-dec.js kks-simd-dec.wasm kks-dec.js kks-dec.wasm > SHA256SUMS)
ls -la "$OUT"
