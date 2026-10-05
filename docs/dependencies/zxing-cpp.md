# Dependency record: zxing-cpp 3.1.1

Added: 2026-10-01 (decision 0019; Android 0032 addendum, Windows 0033, WebAssembly 0037, Flatpak 0031)   Pull request: @@PR@@   Recorded by: Claude for Hashim, 2026-10-05
Kind: runtime
Packages covered: zxing-cpp (the `core` library only: reader, the built-in "OLD" writer, the C API)

## Purpose
Reads the invite QR code from a camera frame or an image, and draws the invite QR code, on every client (joining a
device, decision 0019).

## Platform alternative checked
Decision 0019 and `docs/m6/CAPABILITIES.md` §3, rechecked 2026-10-05:
- **Android:** no barcode API in the framework; ML Kit needs Google Play services, which is optional on our targets.
- **Windows:** a camera barcode scanner exists only as a WinRT point-of-service API needing a package capability
  ([requirements](https://learn.microsoft.com/en-us/windows/apps/develop/devices-sensors/pos/camerabarcode-system-requirements));
  nothing draws a QR code.
- **GNOME:** no QR API in GTK or the GNOME runtime.
- **Browsers:** `BarcodeDetector` only in Chrome on Android, macOS and ChromeOS; Safari behind a flag; Firefox none
  ([MDN browser-compat-data](https://github.com/mdn/browser-compat-data/blob/main/api/BarcodeDetector.json)). The web
  client uses it first where it exists (decision 0037), zxing-cpp otherwise. No browser draws QR codes.

So drawing has no platform anywhere, and reading has none on three of four targets. (Ubuntu packages zxing-cpp as
`libzxing3`, 2.3.0, a GStreamer plugin dependency; the plain GNOME development build links it, but the shipped
Flatpak builds the pinned 3.1.1, since the GNOME runtime doesn't have it.)

## Custom implementation considered
Writing a QR encoder is feasible (the old `qrcodegen.js`, decision 0010, was about 1,000 lines), but a reader means
binarization, finder-pattern detection, perspective correction and Reed-Solomon decoding of camera frames: a parser of
untrusted input from the camera, which we would own and test against real-world images. One maintained library for
both directions replaced three (jsQR, qrcodegen, zxing-android-embedded: decisions 0007, 0009, 0010).

## Transitive dependencies
Count: 0   How counted: the libraries each build compiles. Our builds compile only `core/` with
`ZXING_DEPENDENCIES=LOCAL`, `ZXING_WRITERS=OLD` (the built-in writer, so no zint submodule), and examples, tests and
blackbox tests off (so no stb_image, which only the examples use): `android/app2/src/main/cpp/CMakeLists.txt`,
`platform/windows/build-deps.sh`, `platform/web/build-wasm.sh`, the Flatpak manifest.

## License
Apache-2.0. Compatible with the project's AGPL-3.0.

## Maintenance signals
- Recent releases: v3.1.1 on 2026-07-29, v3.1.0 on 2026-07-07, v3.0.0 on 2026-02-10; roughly monthly in 2026
  ([releases](https://github.com/zxing-cpp/zxing-cpp/releases)).
- Security response: no SECURITY.md and no GitHub advisories. The CVEs ever filed against zxing-cpp packages
  (CVE-2021-28021, CVE-2021-42715, CVE-2021-42716) were in the bundled stb_image, used only by the examples
  ([openSUSE-SU-2022:0157-1](https://osv.dev/vulnerability/openSUSE-SU-2022:0157-1)); we don't build them. Weak.
- Active maintainers: 33 commit authors in the last 12 months, but axxel wrote 460 of the commits and the next
  wrote 21 (GitHub contributor statistics, 2026-10-05). In practice one maintainer. Weak.
- Age across major versions: first release 2016; survived 1.x → 2.x → 3.0 (2026-02), with its C API used here
  unchanged since 3.0.

## Size impact
Measured 2026-10-05: Android `libkksqr.so` (zxing-cpp + JNI wrapper, arm64-v8a) 1.56 MB of the 18.6 MB release APK;
Windows about 1.0 MB of `Walkdown.exe` (symbol-table estimate by name, `ZXing::`); Flatpak `libZXing.so.3.1.1`
1.70 MB; WebAssembly: part of the 3.58 MB full module (the decode-only module has none of it).

## Replacement cost
Low to medium. The surface is two calls (decode one QR from a grey frame, encode one QR to a module matrix) behind one
small wrapper per target (`qr_jni.cpp`, `kks_qr.cpp`, `kks_wasm.cpp`, the GNOME `kks_zxing.cpp`). No data format depends on
it: the invite format is ours (PROTOCOL-v2), and typing the invite code stays as a fallback.

## Decision
Keep. No platform draws QR codes and three of four don't read them; owning a camera-frame decoder costs more. The weak
signals (no security policy, one main maintainer) are answered by the small, replaceable surface, pinned sources
checked by SHA-256, and the fact that the decoded text is untrusted anyway: the invite's signature and expiry are
checked by our own code before anything is trusted (0019). Revisit if zxing-cpp stops releasing, or when
`BarcodeDetector` reaches every engine.
