#!/bin/sh
# Builds wdp_voice, Walkdown Plant's voice codec GDExtension (decision 0069), from pinned, SHA-256-checked sources:
# godot-cpp 10.0.0 (Godot 4.7's API), libopus 1.5.2 and SpeexDSP 1.2.1's resampler.
#   apps/plant3d/voice/build.sh [TARGET…]
# TARGETs (default: all four, the platforms the plant ships on):
#   linux-x86_64     in the Flatpak's own SDK (org.freedesktop.Sdk//26.08, the runtime of
#                    org.godotengine.godot.BaseApp//4.7), so its glibc is the one it runs on; WDP_LINUX_HOST=1 uses
#                    the host's gcc instead (a quick local check, never a release)
#   android-arm64    the NDK (WDP_NDK, default $ANDROID_HOME/ndk/27.2.12479018), API 24, libc++ linked in
#   windows-x86_64   llvm-mingw (platform/windows/fetch-llvm-mingw.sh, decisions 0047, 0053)
#   windows-arm64    the same, aarch64
# Output (none of it committed): apps/plant3d/voice/bin/libwdp_voice.<platform>.<arch>.{so,dll}, bin/wdp_voice.gdextension
# naming the libraries that are there (so an export for a platform without one carries no voice and warns, instead
# of failing on a missing file), and bin/BUILD-INFO.txt (each library's SHA-256 and the toolchain that made it). Two builds of the same
# commit with the same toolchains give the same bytes (no paths, dates or build IDs in them): WDP_CHECK_REPRO=1
# builds each target twice in fresh folders and compares.
# Sources are cached in $KKS_DEV/src/dl (default ~/.local/kksdev), checked on every run; work folders under
# $WDP_WORK (default $KKS_DEV/wdp-voice). WDP_JOBS: parallel compile jobs (default 2).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
DEV="${KKS_DEV:-$HOME/.local/kksdev}"
WORK="${WDP_WORK:-$DEV/wdp-voice}"
JOBS="${WDP_JOBS:-2}"
OUT="$HERE/bin"
TARGETS="${*:-linux-x86_64 android-arm64 windows-x86_64 windows-arm64}"
mkdir -p "$DEV/src/dl" "$WORK" "$OUT"

fetch() { # file url sha256
  f="$DEV/src/dl/$1"
  if [ ! -f "$f" ] || [ "$(sha256sum "$f" | cut -d' ' -f1)" != "$3" ]; then
    echo "download $1"; curl -sSfL -o "$f.part" "$2" && mv "$f.part" "$f"
  fi
  got=$(sha256sum "$f" | cut -d' ' -f1)
  [ "$got" = "$3" ] || { echo "$1: SHA-256 $got, expected $3" >&2; rm -f "$f"; exit 1; }
}
# godot-cpp 10.0.0-stable: the first release independent of Godot's own versions; built against its bundled
# extension_api-4-7.json (CMakeLists.txt GODOTCPP_API_VERSION). Opus and SpeexDSP: Xiph's release tarballs, the
# SHA-256 Xiph publishes (downloads.xiph.org/releases/{opus,speex}/SHA256SUMS.txt).
fetch godot-cpp-10.0.0-stable.tar.gz https://codeload.github.com/godotengine/godot-cpp/tar.gz/10.0.0-stable ebbf64f0f8f8b8b66bc4bc4d3797db97f95b19cf0dfb5b3f8cf56683d9df7db4
fetch opus-1.5.2.tar.gz https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz 65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1
fetch speexdsp-1.2.1.tar.gz https://downloads.xiph.org/releases/speex/speexdsp-1.2.1.tar.gz 8c777343e4a6399569c72abc38a95b24db56882c83dbdb6c6424a5f4aeb54d3d

# the sources, unpacked fresh into the work folder every run (the tarballs were just checked)
SRC="$WORK/src"
rm -rf "$SRC"; mkdir -p "$SRC/godot-cpp" "$SRC/opus" "$SRC/speexdsp"
tar xzf "$DEV/src/dl/godot-cpp-10.0.0-stable.tar.gz" -C "$SRC/godot-cpp" --strip-components=1
tar xzf "$DEV/src/dl/opus-1.5.2.tar.gz" -C "$SRC/opus" --strip-components=1
tar xzf "$DEV/src/dl/speexdsp-1.2.1.tar.gz" -C "$SRC/speexdsp" --strip-components=1

NDK="${WDP_NDK:-${ANDROID_HOME:-$HOME/Android/Sdk}/ndk/27.2.12479018}"
SDK_REF=org.freedesktop.Sdk//26.08
# fixed for reproducible archives and any tool that reads it
export SOURCE_DATE_EPOCH=1767225600

configure_build() { # target build_dir out_dir [cmake args…]
  t=$1; b=$2; o=$3; shift 3
  rm -rf "$b"; mkdir -p "$b" "$o"
  cmake -S "$HERE" -B "$b" -G Ninja -DCMAKE_BUILD_TYPE=Release -DWDP_SRC="$SRC" -DWDP_OUT="$o" "$@" >"$b.log" 2>&1 ||
    { tail -30 "$b.log"; echo "wdp_voice $t: configure failed ($b.log)" >&2; exit 1; }
  cmake --build "$b" --target wdp_voice -j "$JOBS" >>"$b.log" 2>&1 ||
    { grep -E "error|Error" "$b.log" | head -30; echo "wdp_voice $t: build failed ($b.log)" >&2; exit 1; }
}

build_one() { # target dir_for_the_library
  t=$1; o=$2; b="$WORK/build-$t"
  case "$t" in
    linux-x86_64)
      if [ -n "${WDP_LINUX_HOST:-}" ]; then
        configure_build "$t" "$b" "$o" -DWDP_SUFFIX=linux.x86_64
      else
        flatpak info --user "$SDK_REF" >/dev/null 2>&1 || flatpak info --system "$SDK_REF" >/dev/null 2>&1 ||
          { echo "the Linux build needs $SDK_REF (flatpak install flathub $SDK_REF), or WDP_LINUX_HOST=1 for a local check" >&2; exit 2; }
        rm -rf "$b"; mkdir -p "$b" "$o"
        # the SDK sees only the sources, this folder and the output (nothing else of the home folder), no network
        flatpak run --die-with-parent --unshare=network --filesystem="$WORK" --filesystem="$HERE" --filesystem="$o" \
          --env=SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" --command=sh "$SDK_REF" -c '
            set -e
            cmake -S "$1" -B "$2" -G Ninja -DCMAKE_BUILD_TYPE=Release -DWDP_SRC="$3" -DWDP_OUT="$4" -DWDP_SUFFIX=linux.x86_64
            cmake --build "$2" --target wdp_voice -j "$5"' sh "$HERE" "$b" "$SRC" "$o" "$JOBS" >"$b.log" 2>&1 ||
          { grep -E "error|Error" "$b.log" | head -30; tail -5 "$b.log"; echo "wdp_voice $t: build failed ($b.log)" >&2; exit 1; }
      fi ;;
    android-arm64)
      [ -f "$NDK/build/cmake/android.toolchain.cmake" ] || { echo "no NDK at $NDK (WDP_NDK)" >&2; exit 2; }
      configure_build "$t" "$b" "$o" -DWDP_SUFFIX=android.arm64 -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24 -DANDROID_STL=c++_static ;;
    windows-x86_64|windows-arm64)
      sh "$ROOT/platform/windows/fetch-llvm-mingw.sh"
      M="$DEV/llvm-mingw/bin"
      if [ "$t" = windows-arm64 ]; then A=aarch64; P=ARM64; S=windows.arm64; else A=x86_64; P=AMD64; S=windows.x86_64; fi
      TC="$WORK/mingw-$A.cmake"
      cat > "$TC" <<T
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR $P)
set(CMAKE_C_COMPILER $M/$A-w64-mingw32-clang)
set(CMAKE_CXX_COMPILER $M/$A-w64-mingw32-clang++)
set(CMAKE_RC_COMPILER $M/$A-w64-mingw32-windres)
set(CMAKE_AR $M/llvm-ar)
set(CMAKE_RANLIB $M/llvm-ranlib)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
T
      configure_build "$t" "$b" "$o" -DWDP_SUFFIX="$S" -DCMAKE_TOOLCHAIN_FILE="$TC" ;;
    *) echo "unknown target $t (linux-x86_64 android-arm64 windows-x86_64 windows-arm64)" >&2; exit 2 ;;
  esac
}

lib_of() { # target -> the library's file name
  case "$1" in
    linux-x86_64) echo libwdp_voice.linux.x86_64.so ;;
    android-arm64) echo libwdp_voice.android.arm64.so ;;
    windows-x86_64) echo libwdp_voice.windows.x86_64.dll ;;
    windows-arm64) echo libwdp_voice.windows.arm64.dll ;;
  esac
}

toolchain_of() { # target -> one line naming the toolchain
  case "$1" in
    linux-x86_64)
      if [ -n "${WDP_LINUX_HOST:-}" ]; then echo "host $(gcc --version | head -1) (not for release)"
      else echo "$SDK_REF $(flatpak info "$SDK_REF" 2>/dev/null | sed -n 's/^ *Version: //p' | head -1) commit $(flatpak info "$SDK_REF" 2>/dev/null | sed -n 's/^ *Commit: //p' | head -1)"; fi ;;
    android-arm64) echo "NDK $(sed -n 's/^Pkg.Revision *= *//p' "$NDK/source.properties")" ;;
    windows-*) echo "llvm-mingw $(cat "$DEV/llvm-mingw/VERSION.kks")" ;;
  esac
}

INFO="$OUT/BUILD-INFO.txt"
touch "$INFO"
for t in $TARGETS; do
  L=$(lib_of "$t")
  [ -n "$L" ] || { echo "unknown target $t" >&2; exit 2; }
  rm -f "$OUT/$L"
  build_one "$t" "$WORK/out-$t"
  [ -s "$WORK/out-$t/$L" ] || { echo "wdp_voice $t: no $L made" >&2; exit 1; }
  if [ -n "${WDP_CHECK_REPRO:-}" ]; then
    mv "$WORK/out-$t/$L" "$WORK/$L.first"
    build_one "$t" "$WORK/out-$t"
    cmp -s "$WORK/$L.first" "$WORK/out-$t/$L" || { echo "wdp_voice $t: two builds differ (not reproducible)" >&2; exit 1; }
    rm -f "$WORK/$L.first"
    echo "wdp_voice $t: two builds, identical"
  fi
  cp "$WORK/out-$t/$L" "$OUT/$L"
  H=$(sha256sum "$OUT/$L" | cut -d' ' -f1)
  grep -v " $L " "$INFO" > "$INFO.new" || true
  printf '%s %s %s bytes, %s\n' "$H" "$L" "$(wc -c < "$OUT/$L" | tr -d ' ')" "$(toolchain_of "$t")" >> "$INFO.new"
  sort -k2 "$INFO.new" > "$INFO"; rm -f "$INFO.new"
  echo "wdp_voice $t: $OUT/$L ($(wc -c < "$OUT/$L" | tr -d ' ') bytes)"
done

# the extension's file, naming the libraries there are (Godot finds it in the project, `--import` registers it)
{
  echo "; wdp_voice: Walkdown Plant's voice codec (decision 0069; apps/plant3d/voice/README.md). Made by voice/build.sh"
  echo "; with the libraries that were built here: an export for a platform missing from [libraries] has no voice."
  echo "[configuration]"
  echo 'entry_symbol = "wdp_voice_library_init"'
  echo 'compatibility_minimum = "4.7"'
  echo "reloadable = false"
  echo
  echo "[libraries]"
  for t in linux-x86_64 android-arm64 windows-x86_64 windows-arm64; do
    L=$(lib_of "$t")
    [ -s "$OUT/$L" ] || continue
    K=$(echo "$L" | sed 's/^libwdp_voice\.//; s/\.[a-z]*$//')
    echo "$K = \"$L\""
  done
} > "$OUT/wdp_voice.gdextension"
