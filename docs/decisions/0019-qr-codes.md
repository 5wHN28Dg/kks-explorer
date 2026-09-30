# 0019 QR codes: reading and drawing

Date 2026-09-30 · Scope: R13 (join a device by QR) · Status: **accepted by the user 2026-09-30**

**What the platforms provide (docs/m6/CAPABILITIES.md §3):**

| | Read QR from the camera | Draw a QR |
|---|---|---|
| Windows | 🟡 built-in camera barcode scanner, Windows 10 1803+ (WinRT point-of-service API; needs a package capability, so probably MSIX; unverified) [D] | ❌ |
| GNOME | ❌ (zxing-cpp 2.3 is installed here only as a GStreamer plugin dependency [V], not a GNOME component) | ❌ |
| Android | ❌ framework; ML Kit through Play services is optional [D] | ❌ |
| Browsers | 🟡 `BarcodeDetector`: Chrome Android, macOS, ChromeOS only; Safari behind a preference; Firefox no [D] | ❌ |

So a library is needed almost everywhere, and for drawing everywhere.

**Candidate: zxing-cpp.** It reads and writes QR and other barcodes, in C++ with a C API.
- It has official wrappers for Android, C, WebAssembly, WinRT, Kotlin/Native, Rust, Python and more.
- Distributions package it (Debian/Ubuntu `libzxing3`).

| Criterion | Evidence (GitHub, 2026-09-30) | Result |
|---|---|---|
| Releases | v3.1.1 2026-07-29, v3.1.0 2026-07-07, v3.0.0 2026-02-10 | passes, and it survived a major version |
| Maintainers | last 12 months: 259 commits by one maintainer (axxel), 29 by 7 others | **concentrated in one person**: fails the strict "more than one active maintainer" |
| Security policy | none published | fails |
| License | Apache-2.0, compatible with AGPL-3.0 | passes |

The alternatives are worse:
- zxing (Java): maintenance mode, see 0007.
- jsQR: dead since 2021, see 0009.
- qrcodegen: draws only, one maintainer, see 0010.

**Proposed:**
- **zxing-cpp, pinned and SHA-256-checked like libjxl, for reading and drawing on every target:**
  - linked on Windows;
  - Android through the NDK, the same toolchain as libjxl;
  - on GNOME the distribution's package when it is new enough, else the pinned build;
  - WebAssembly for browsers.
- **Browsers use the platform first:** `BarcodeDetector` where it exists, and load the zxing-cpp WebAssembly only when
  it doesn't (web policy: platform first). Typing the invite code stays as the fallback path.
- **One library for reading and drawing** replaces three today: jsQR, qrcodegen and zxing-android-embedded.
- The camera itself is platform-provided everywhere: CameraCaptureUI/MediaCapture, the Camera portal + PipeWire,
  CameraX, `getUserMedia`. Only decoding the frames uses the library.

**Risk and mitigation:**
- The maintainer concentration is real. Mitigations:
  - pinned sources;
  - a small API surface: decode one QR from a frame, encode one QR;
  - replacing it later is contained, because the invite format is ours.
- It parses camera input, which is untrusted. Our own code checks the decoded invite (signature, expiry) before
  trusting anything.

**Revisit:**
- if zxing-cpp stops releasing;
- if Windows packaging (MSIX) is chosen: then the built-in camera scanner is worth testing, since the Windows
  capability shows up then;
- if `BarcodeDetector` reaches all engines.

Sources: https://github.com/zxing-cpp/zxing-cpp (releases, commits since 2025-09-30, `wrappers/`) ·
https://learn.microsoft.com/en-us/windows/apps/develop/devices-sensors/pos/camerabarcode-system-requirements · docs/decisions/0007, 0009, 0010
