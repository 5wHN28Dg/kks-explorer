# Walkdown for Android (v2) (M6 phase 6)

Native Compose screens on the Nim core (`core/`, through JNI: `android/nim/`), decisions 0014, 0027, 0032. Installed
as `io.github.walkdown` (Walkdown; the code namespace stays `kks.explorer.v2`), next to the v1 app until the cutover.

## Build

    sh android/nim/build.sh                      # libkks.so for arm64-v8a + x86_64 (NDK 27, SQLite compiled in); the release
                                                 # APK takes arm64-v8a only (decision 0046)
    cd android && JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64 ./gradlew :app2:assembleDebug

Gradle fetches and checks (SHA-256) libjxl v0.12.0 and zxing-cpp v3.1.1, and builds them with CMake
(`src/main/cpp`).

## What is where

- `core/Core.kt`: the JNI surface. All core calls run on one "kks-core" thread; the core is single-threaded, and Nim
  emulates TLS on Android.
- `core/Keys.kt`: the AndroidKeyStore device key and storage-key wrap.
- `core/NativeCrypto.kt`: the JCA provider the core calls back.
- `core/Net.kt`: TLS 1.3 with peer-ID pinning, sync sessions, `ask` (join, enroll).
- `sync/`:
  - `Sync.kt`: joining, the listener, rounds, the status the core shows;
  - `Discovery.kt`: NSD announce and browse, with one resolve at a time;
  - `SyncWorker.kt`: every 15 min while the app is closed.
  - `PhotoQueue.kt`: the photo queue (decision 0049): one WorkManager job per photo encodes it to JPEG XL and submits it,
    in order, whether or not the panel or the app stays open.
- `ui/`:
  - Setup: server, code or QR, nearby admin, file;
  - Drawings: `SheetView` (pyramid, vector tiles, hotspots, marking, accessibility), search, floor filter, notes;
  - `Panel` (equipment, review, photos);
  - Procedures (link mode);
  - Review;
  - Manage: approvals, proposals, history, people, devices with the invite QR, account;
  - `Photos` (the floor first when the code has none, camera or gallery → annotate → the photo queue);
  - `ScanQr` (Camera2 + zxing-cpp).
- `Qr.kt` + `src/main/cpp/qr_jni.cpp`: zxing-cpp.
- `Jxl.kt` + `jxl_jni.cpp`: libjxl.

## Test

    python3 android/app2/e2e/test_app2.py        # needs a running emulator, the Nim server and importer built

The test drives the app through the accessibility tree (`adbui.py`, uiautomator) against a fresh Nim server holding
the synthetic sample sheet. It covers:
- joining through the server (TLS enroll);
- search and the panel;
- an edit synced to the server;
- a member's proposal approved on the phone;
- removal and wipe.

Debug builds only: `adb shell am broadcast -a kks.explorer.DEBUG_SYNC -p io.github.walkdown` runs the sync worker once;
`kks.explorer.DEBUG_DARK` checks the dark drawings colours (`ui/DarkColor.kt`) against `tests/web/dark-vectors.json`
(test_app2's `test_dark` copies the file in first).

## Not verified yet

These need the Note 9 and the Honor 600:
- QR scanning with a real camera;
- TalkBack (the emulator has none);
- finding phones and laptops on a real Wi-Fi;
- the background worker on Honor's battery management;
- every measurement (docs/m6/MEASUREMENTS.md).
