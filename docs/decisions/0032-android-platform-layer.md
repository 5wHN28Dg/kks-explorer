# 0032 Android: the Nim core through JNI, storage, keys, TLS, crypto

Date 2026-10-01 · Scope: phase 6 (R1–R20 on Android, N1, N1a, N3, N6) · Status: **decided by Claude under the user's
standing instruction to continue**; the user can revisit.

**Question:** how the Nim core runs inside the Android app (0027 (a): Nim through JNI, Compose UI per 0014). What the
platform provides for storage, keys, TLS and crypto, and what we bundle.

## Findings

[V] = checked on this machine 2026-10-01 (NDK 27.2.12479018, API 29 sysroot). [D] = vendor documentation.

| Need | What Android provides | Gap / choice |
|---|---|---|
| Native toolchain | NDK clang for arm64-v8a and x86_64 at API 29 [V]. Nim cross-compiles with `--os:android --cpu:arm64 --cc:clang --clang.exe=<NDK clang>` [D: Nim docs, "Cross-compilation"]. | the core as `libkks.so`, with JNI entry points written in a small C shim |
| SQLite | Java `android.database.sqlite` only. **The NDK sysroot has no `sqlite3.h` and no libsqlite** [V]. | **bundle the SQLite amalgamation** (3.53.4, 2026-07-24, pinned by SHA3-256 from sqlite.org), so `platform/linux/dbstore.nim` runs unchanged. SQLite passes the maintenance test: monthly releases in 2026, a published CVE list, three core developers, public domain. |
| zlib | `libz.so` in the NDK [V] | linked, as on Linux |
| OpenSSL / BoringSSL | not in the NDK sysroot [V]; Conscrypt (BoringSSL) only behind Java | crypto through Java (JCA) by JNI, as 0029 decided |
| Device key (0020: platform key store) | AndroidKeyStore: EC P-256 keys, non-exportable, with a generated self-signed certificate; `SHA256withECDSA`; API 23+ [D] | the device key is an AndroidKeyStore key (`kks-device`). The core signs through `PrivateKey.handle` (crypto.nim already allows it). |
| Storage key (0020) | AndroidKeyStore AES-256-GCM keys, non-exportable [D] | a random 32-byte storage key, wrapped by a Keystore AES key (`kks-storage-wrap`), unwrapped at start and handed to the core for the sealed rows. Same model as v1's SqliteStore seed. Limit, as N1a states: the key is in the app's memory while it runs. |
| TLS 1.3 + ALPN (0017) | `SSLEngine`/`SSLSocket` (Conscrypt) with TLS 1.3 on API 29+; `SSLParameters.setApplicationProtocols` API 29 [D] | the Kotlin side owns sockets and TLS, with client auth from the AndroidKeyStore key and its certificate, and a TrustManager that pins the expected peer ID. The core's §15 session (sans I/O) gets the plaintext bytes. |
| Crypto primitives | JCA on API 29: `SHA-256`, `HmacSHA256`, `PBKDF2WithHmacSHA256`, `SHA256withECDSA`, `ECDH`, `AES/GCM/NoPadding`, `SecureRandom` [D] | the Java provider: JNI calls into a Kotlin object. Verification speed to be measured on the Note 9 (0029: GnuTLS 0.11 ms per signature on the laptop). |
| mDNS, background sync, camera, JPEG XL | NSD, WorkManager, CameraX/intent, our libjxl JNI build: the v1 app's platform pieces [V in M3] | kept and adapted (COMPARISON.md) |

## Choice

**Layout:**
- `android/nim/`: the JNI library (`kks_jni.nim` + `jni_shim.c`), built for both ABIs by `build.sh` into
  `android/app/src/main/jniLibs/`.
- The Kotlin side keeps the app's platform pieces and the Compose UI.

**The JNI surface is small and coarse:**
- `open`;
- `api(method, path, query, body)` → JSON, the same routes as the web pages and the GNOME app;
- `file(path)` → bytes;
- sync sessions (`start`, `feed` → bytes out, `done`);
- the change callback.

The crypto provider calls back into Kotlin.

**When to revisit:**
- if JNI crypto makes a replay too slow on the Note 9 (then: a bundled, audited C library such as BoringSSL's
  libcrypto, with its own decision);
- if Android adds SQLite to the NDK.

## Addendum 2026-10-01: decided while building phase 6

1. **Joining through a server: PROTOCOL-v2 §16 `enroll` over TLS on the sync port.** v1 posted the password to
   `/api/devices/enroll` over HTTP. Android blocks cleartext HTTP by default (network security config [D]), and
   allowing it would weaken a platform security mechanism. So the password goes over the same TLS 1.3 connection as
   sync. Trust in the server is established on first use (no certificate authority). [V] emulator ↔ Nim server.
2. **QR scanning: the platform's Camera2, not CameraX.**
   - 0007 said "CameraX + zxing core", but a preview plus grayscale frames (the Y plane of YUV_420_888 through an
     ImageReader) needs about 150 lines of Camera2 code. That is the platform's own API since API 21 [D], so there's
     no dependency to audit.
   - zxing-cpp (0019) decodes the frames, replacing zxing core (Java).
   - Not verified: decoding from a real camera (the emulator's camera can't be aimed at a QR). Check on the Note 9
     and the Honor 600.
3. **zxing-cpp v3.1.1 with `ZXING_WRITERS=OLD`.**
   - Pinned by SHA-256 7286b1e6… from codeload.github.com, the same way as libjxl.
   - The new writer needs libzint from a git submodule, which isn't in the release tarball. The old built-in writer
     sits behind the same C API (`ZXing_CreateBarcodeFromText`, `ZXing_WriteBarcodeToImage`).
   - Only `core/` is added to the build: the top level adds a C example that would download stb.
   - [V] the invite QR drawn on the emulator decodes with OpenCV to the exact invite text.
4. **The drawing's tags for screen readers: the platform's `AccessibilityNodeProvider`.**
   - `ExploreByTouchHelper` would need `androidx.customview` (a new dependency); the platform class does the same
     with about 100 lines of our own.
   - Tags on screen are virtual views in reading order (at most 200), and they can be clicked.
   - [V] they appear in the accessibility tree (uiautomator). Not verified with TalkBack: the emulator image has none.
     Check on both phones.
5. **A removed device (§15).** The core empties the store and reports `wiped:<note>`. Kotlin then:
   - deletes the Keystore keys (device key, storage wrap) and the database;
   - keeps the note in preferences for the setup screen;
   - restarts the app, so the next start has a new device key.

   [V] emulator, also in `android/app2/e2e/test_app2.py`.
6. **Dialogs with `usePlatformDefaultWidth = false` get no window insets in their own composition** (Compose
   1.7, targetSdk 36, edge-to-edge). The photo editor read the system bars in the parent composition and passed the
   padding in. Found on the emulator: Send sat under the navigation bar.
