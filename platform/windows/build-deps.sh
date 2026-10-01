#!/bin/sh
# The Windows app's C/C++ libraries, cross-built with mingw-w64 (decision 0033) from pinned, SHA-256-checked sources:
# zlib (0015), libjxl + highway/brotli/skcms (0018), zxing-cpp (0019); SQLite comes from android/nim/fetch_sqlite.sh.
# Same versions as the Android app (android/app2/build.gradle.kts). Output: $KKS_DEV/win64/{include,lib}.
set -eu
DEV="${KKS_DEV:-$HOME/.local/kksdev}"
MINGW="${KKS_MINGW_BIN:-$DEV/mingw/usr/bin}"
OUT="$DEV/win64"
SRC="$DEV/src"
mkdir -p "$OUT/include" "$OUT/lib" "$SRC/dl"
export PATH="$MINGW:$PATH"

fetch() { # name url sha256
  f="$SRC/dl/$1.tar.gz"
  if [ ! -f "$f" ] || [ "$(sha256sum "$f" | cut -d' ' -f1)" != "$3" ]; then
    echo "download $1"; curl -sL -o "$f" "$2"
  fi
  got=$(sha256sum "$f" | cut -d' ' -f1)
  [ "$got" = "$3" ] || { echo "$1: SHA-256 $got, expected $3" >&2; rm -f "$f"; exit 1; }
}
unpack() { # name into
  rm -rf "$2"; mkdir -p "$2"; tar xzf "$SRC/dl/$1.tar.gz" -C "$2" --strip-components=1
}

cat > "$SRC/mingw-toolchain.cmake" <<T
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_C_COMPILER $MINGW/x86_64-w64-mingw32-gcc-posix)
set(CMAKE_CXX_COMPILER $MINGW/x86_64-w64-mingw32-g++-posix)
set(CMAKE_RC_COMPILER $MINGW/x86_64-w64-mingw32-windres)
set(CMAKE_FIND_ROOT_PATH $OUT)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
T
TC="-DCMAKE_TOOLCHAIN_FILE=$SRC/mingw-toolchain.cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX=$OUT"

# zlib 1.3.2 (hash published on zlib.net)
if [ ! -f "$OUT/lib/libz.a" ]; then
  fetch zlib https://zlib.net/zlib-1.3.2.tar.gz bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16
  unpack zlib "$SRC/w-zlib"
  (cd "$SRC/w-zlib" && make -s -f win32/Makefile.gcc PREFIX=x86_64-w64-mingw32- CC=x86_64-w64-mingw32-gcc-posix libz.a >/dev/null &&
   cp libz.a "$OUT/lib/" && cp zlib.h zconf.h "$OUT/include/")
fi

# libjxl v0.12.0 and the submodule commits it names
if [ ! -f "$OUT/lib/libjxl.a" ]; then
  fetch libjxl https://codeload.github.com/libjxl/libjxl/tar.gz/v0.12.0 03e9be69a30be4011f559da75328b6d7cea8ad921fabfbd551ce10bf45cdc992
  fetch highway https://codeload.github.com/google/highway/tar.gz/457c891775a7397bdb0376bb1031e6e027af1c48 5124b0501c98d9930dbb065bfa1a5bbbd59ce0f12facb7e1e33aaef01a5f1f1a
  fetch brotli https://codeload.github.com/google/brotli/tar.gz/028fb5a23661f123017c060daa546b55cf4bde29 0afe09a53c8bad9861c8dd1fc1284308d54f19d2979ba3541cfdcc9b05fe360f
  fetch skcms https://codeload.github.com/google/skcms/tar.gz/96d9171c94b937a1b5f0293de7309ac16311b722 9bb4b5bba0b7c04f6c2bce9ff713d61e23c9a20c4945161ae16290498ad74627
  J="$SRC/w-libjxl"
  unpack libjxl "$J"; unpack highway "$J/third_party/highway"; unpack brotli "$J/third_party/brotli"; unpack skcms "$J/third_party/skcms"
  cmake -S "$J" -B "$J/build" $TC -DBUILD_TESTING=OFF -DJPEGXL_ENABLE_TOOLS=OFF -DJPEGXL_ENABLE_DOXYGEN=OFF \
    -DJPEGXL_ENABLE_MANPAGES=OFF -DJPEGXL_ENABLE_BENCHMARK=OFF -DJPEGXL_ENABLE_EXAMPLES=OFF -DJPEGXL_ENABLE_JNI=OFF \
    -DJPEGXL_ENABLE_SJPEG=OFF -DJPEGXL_ENABLE_OPENEXR=OFF -DJPEGXL_ENABLE_JPEGLI=OFF -DJPEGXL_ENABLE_PLUGINS=OFF \
    -DJPEGXL_ENABLE_VIEWERS=OFF -DJPEGXL_ENABLE_DEVTOOLS=OFF -DJPEGXL_ENABLE_FUZZERS=OFF -DJPEGXL_BUNDLE_LIBPNG=OFF \
    -DJPEGXL_ENABLE_TRANSCODE_JPEG=OFF -DJPEGXL_ENABLE_SKCMS=ON -DJPEGXL_STATIC=ON -DHWY_ENABLE_TESTS=OFF \
    -DHWY_ENABLE_EXAMPLES=OFF -DHWY_ENABLE_CONTRIB=OFF -DBROTLI_DISABLE_TESTS=ON >/dev/null
  cmake --build "$J/build" -j"$(nproc)" >/dev/null
  cmake --install "$J/build" >/dev/null
fi

# zxing-cpp v3.1.1, reader + the built-in writer (0032 addendum: the new writer needs a submodule)
if [ ! -f "$OUT/lib/libZXing.a" ]; then
  fetch zxing-cpp https://codeload.github.com/zxing-cpp/zxing-cpp/tar.gz/v3.1.1 7286b1e6ade66fe82b7c8208b4595deeb55d6486b410834fdc65702f46650542
  Z="$SRC/w-zxing"
  unpack zxing-cpp "$Z"
  cmake -S "$Z/core" -B "$Z/build" $TC -DZXING_READERS=ON -DZXING_WRITERS=OLD -DZXING_C_API=ON -DCMAKE_CXX_STANDARD=20 >/dev/null
  cmake --build "$Z/build" -j"$(nproc)" >/dev/null
  cmake --install "$Z/build" >/dev/null
fi

# SQLite (the amalgamation, compiled into the program)
[ -f "$SRC/sqlite-amalgamation-3530400/sqlite3.c" ] || sh "$(dirname "$0")/../../android/nim/fetch_sqlite.sh"
ls "$OUT/lib"
