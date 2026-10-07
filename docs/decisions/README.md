# Decision records

One page per dependency or platform decision, as required by the development policy (CLAUDE.md;
the platform engineering guideline (CLAUDE.md, "Engineering guidelines"), the web engineering guideline (CLAUDE.md, "Engineering guidelines")). Each record names its sources.
"Verified" means it ran on the target; everything else is from vendor documentation or registries.

"Well-maintained" test (native policy): recent releases, a security response history, more than one active
maintainer, a compatible license (the project is AGPL-3.0), and survival of a major version change.

## M6 decisions

| No. | Subject | Status |
|---|---|---|
| [0014](0014-native-ui-per-platform.md) | Native UI per platform, no embedded web engine; courses re-authored in a neutral format | decided; browser access kept (4 UIs) |
| [0015](0015-drawing-format.md) | Viewer draws a grid-indexed path store of our own, made at import; the PDF stays the source of record | decided, measured on the laptop and the Note 9 |
| [0016](0016-viewer-rendering-pipeline.md) | CPU-drawn cached tiles on background threads; the GPU only composites; overview pre-rendered at import | decided (measured: GPU not faster for this content) |
| [0017](0017-crypto-primitives-and-transport.md) | Crypto: P-256 (ECDSA/ECDH) + AES-256-GCM + the platform's TLS with pinned device keys, replacing 25519 + our Noise | decided (option B) |
| [0018](0018-jpeg-xl-per-platform.md) | JPEG XL only: libjxl on Windows/Android, glycin + libjxl on GNOME; browsers decode natively or with our own WebAssembly libjxl build, and encode with it; no JPEG anywhere | decided (with the user's change) |
| [0019](0019-qr-codes.md) | QR: zxing-cpp for reading and drawing on every target; browsers use BarcodeDetector first | decided |
| [0020](0020-encryption-at-rest.md) | Encryption at rest: a storage key per device wrapped by the platform key store; AES-GCM on bodies and files; platform SQLite | decided |
| [0021](0021-background-sync.md) | Background sync: Run key + notification icon on Windows, Background portal on GNOME, WorkManager on Android, browsers only while open | decided |
| [0022](0022-distribution-and-updates.md) | Windows: MSIX via the Microsoft Store (private audience); GNOME: Flatpak on Flathub; Android: APK + in-app updater; own desktop updater retired | decided (fallback: self-signed MSIX via IT if the Store is blocked) |
| [0023](0023-password-hashing.md) | Passwords: Argon2id on the server (OpenSSL ≥ 3.2); root key backup: PBKDF2-SHA256 ≥ 600k with an app-generated 6-word passphrase | decided |
| [0024](0024-protocol-v2.md) | Protocol v2: keep the signed-log model; P-256, ID without sig, TLS channel, AES-GCM private entries, path store + JXL pyramid in plant data; one-time migration | decided |
| [0025](0025-course-content-format.md) | Courses: one JSON content model (blocks, questions, pages), text-authored and compiled; declarative figures (no scripting); published as a content set | decided |
| [0026](0026-importer-and-server.md) | Importer and server in Nim (user decision). The importer keeps MuPDF via its C API and replaces OpenCV with our own code, gated by identical readings on all sheets. The server is the Nim core without UI on headless Linux | decided |
| [0027](0027-language.md) | Nim for the desktop apps (Win32 + Direct2D on Windows, GTK 4 + libadwaita on GNOME), server, importer and a sans-I/O core; Kotlin for Android UI; JS for web UI and relay | decided; Android uses the same Nim core via JNI (option a) |
| [0028](0028-internet-transport-rudp-or-quic.md) | Internet transport: keep our reliable UDP (in Nim, TLS on top), field-test on real NATs, switch to MsQuic if it fails | decided (A) |
| [0029](0029-nim-core-building-blocks.md) | Nim core: crypto through a provider interface (GnuTLS on GNOME, CNG on Windows, Java on Android), own strict JSON reader (+ strict-reading rule in PROTOCOL-v2 §1), zlib linked, hand-written small bindings, std/unittest | decided |
| [0030](0030-linux-platform-layer.md) | Linux layer: SQLite C API, GnuTLS driven through buffers (pinned self-signed device certs), asyncdispatch + asynchttpserver with one thread owning the node, Argon2id via OpenSSL on a worker, mDNS via Avahi's D-Bus API (GIO) | decided under the user's go-ahead (revisitable) |
| [0031](0031-gnome-app.md) | GNOME app: hand-written GTK/libadwaita/Cairo bindings (owlkettle fails the maintenance test), asyncdispatch driven from GLib, a C GtkWidget for the viewer (GSK textures), libsecret for the storage key, zxing-cpp for QR, Flatpak | decided under the user's go-ahead (revisitable) |
| [0032](0032-android-platform-layer.md) | Android: Nim core via JNI (libkks.so, SQLite bundled), JCA crypto, AndroidKeyStore device key, TLS in Kotlin with peer-ID pinning; addendum: TLS enroll, Camera2 + zxing-cpp, platform AccessibilityNodeProvider | decided under the user's go-ahead (revisitable) |
| [0033](0033-windows-platform-layer.md) | Windows: mingw-w64 cross-build from Linux, Windows 10/11 VMs (QEMU/KVM), CNG + NCrypt + DPAPI, bundled SQLite, Schannel (TLS 1.2 on 10), DNS-SD API, UIA tests from PowerShell | decided under the user's go-ahead (revisitable) |
| [0034](0034-web-viewer-v2.md) | Browser client draws v2 plant data: DecompressionStream, path store tiles in a module Worker (OffscreenCanvas), JXL pyramid via `<img>` or the vendored WebAssembly decoder; escaping audit | decided under the user's standing instruction (revisitable) |
| [0035](0035-web-course-renderer.md) | Browser client renders the JSON courses: vanilla `course.js`, DOM + `textContent`, Canvas 2D figures with a port of the reference evaluator, native controls | decided under the user's standing instruction (revisitable) |
| [0037](0037-wasm-libjxl-zxing.md) | Our own WebAssembly libjxl (encode + decode) and zxing-cpp: pinned emsdk 6.0.10, same pinned sources as native, SIMD + scalar variants, BarcodeDetector first where present; browsers encode photos to JXL before upload | decided under the user's standing instruction (revisitable) |
| [0036](0036-native-course-renderers.md) | Native course renderers: shared Nim evaluator and page logic; GtkLabel markup + Cairo/Pango (GNOME), RichEdit + Direct2D/DirectWrite (Windows), Compose (Android); WOFF2 faces via fontconfig / DirectWrite, system faces on Android | decided under the user's standing instruction (revisitable) |
| [0038](0038-v2-relay-pipe.md) | Internet sync on the native apps through the relay pipe first; hole punching later (done 2026-10-03, 0028) | decided |
| [0039](0039-webcam-qr.md) | Webcam QR: camera portal + PipeWire/GStreamer on GNOME, Media Foundation (loaded at run time) on Windows | decided, verified |
| [0040](0040-diagnostics-reports.md) | Diagnostics reports to the manager: sealed `report` entries through the plant's own log | accepted by the user |
| [0041](0041-plant3d-engine.md) | The 3D plant's engine: Godot 4 measured on the Note 9 and a laptop (on hold) | investigating |
| [0042](0042-v1-phone-migration.md) | Phones move from the v1 app by a bridge update; v1 proofs checked by the server, open changes handed over | accepted by the user; retired 2026-10-05 (0048) |
| [0043](0043-msix-packaging.md) | MSIX: Microsoft's MakeAppx (NuGet, in a Windows VM), signed on the host with osslsigncode | accepted |
| [0044](0044-walkdown-android-updates.md) | Walkdown updates itself on Android: the same signed release, a second P-256 signature, PackageInstaller | accepted |
| [0045](0045-server-control-socket.md) | The server's CLI commands that change the plant run inside the running server (a 0600 Unix socket) | done |
| [0046](0046-android-abis.md) | Android release APKs for arm64-v8a only; libraries stay uncompressed; no 32-bit phones | accepted by the user |
| [0048](0048-retire-v1.md) | The v1 move path retired: the server's v1 answers, the bridge, the Ed25519 release signature and PROTOCOL.md removed | decided by the user 2026-10-05 |
| [0047](0047-arm64-desktop-builds.md) | Native ARM64 desktop builds: Windows cross-built with llvm-mingw (signed here), the aarch64 Flatpak and ARM64 tests on GitHub's ARM64 runners | accepted by the user |

## Audit of existing dependencies (2026-09-30)

Evidence collected 2026-09-30 from PyPI, Maven Central, Google Maven, npm, GitHub (commit activity over the last 12 months), Android API
reference, Microsoft Learn, caniuse and MDN browser-compat-data.

| No. | Subject | Verdict | Action |
|---|---|---|---|
| [0001](0001-python-cryptography.md) | `cryptography` (Python) | keep | none |
| [0002](0002-zeroconf.md) | `zeroconf` (Python mDNS) | replace with the OS service (user decision 2026-09-30) | on hold for M6 |
| [0003](0003-photo-format-jpeg-xl.md) | JPEG XL stack (pillow-jxl-plugin, libjxl NDK, @jsquash/jxl) | keep (user decision 2026-09-30, from own tests) | done 2026-10-01: @jsquash/jxl replaced by our own libjxl WebAssembly build (0037) |
| [0004](0004-pyinstaller-bundled-python.md) | PyInstaller + bundled CPython + Tk | keep until M6 | M6 replaces it |
| [0005](0005-importer-pymupdf-opencv-numpy.md) | Importer: PyMuPDF, OpenCV, NumPy | keep | none |
| [0006](0006-bouncycastle.md) | BouncyCastle (Android) | keep for Ed25519/X25519 on API 29–32 | the update is deferred to the v2 rewrite (the user, 2026-09-30); the post-1.79 advisories don't touch what we use; v2 removes it |
| [0007](0007-zxing-android-embedded.md) | zxing core + zxing-android-embedded | **fails** maintenance test (embedded) | replace the embedded scanner UI with CameraX + zxing core → done in v2 with Camera2 + zxing-cpp (0032 addendum) |
| [0008](0008-androidx.md) | AndroidX: Compose, Activity, Core, WorkManager | keep (platform model) | update the 2024 versions |
| [0009](0009-jsqr.md) | jsQR (web QR scanning) | **fails** maintenance test; still needed | done 2026-10-01: removed; `BarcodeDetector` first, else our zxing-cpp WebAssembly build (0037) |
| [0010](0010-qrcodegen.md) | qrcodegen.js (web QR drawing) | keep | removed 2026-10-01: QR drawing through zxing-cpp, as on every other platform (0019, 0037) |
| [0011](0011-vendored-fonts.md) | Vendored course fonts | keep | none |
| [0012](0012-cloudflare-relay.md) | Cloudflare Workers relay | keep | none |
| [0013](0013-own-implementations.md) | Our own Noise, reliable UDP, WebSocket clients, Kotlin JSON | keep; rudp re-evaluated in M6 | none now |

**Status (2026-09-30):** the user approved the actions for 0006, 0007, 0008 and 0009, and decided two others:
- 0003: keep JPEG XL, based on the user's own tests, with no WebP/AVIF measurement;
- 0002: use the OS DNS-SD service (Avahi on Linux) instead of bundling zeroconf.

**All code changes are on hold.** M6 first re-derives the whole project from scratch under the policy (capability
matrix, then decisions, language last). Only then do we compare with the current code and apply the changes that
survive.

No license conflicts: every dependency's license is compatible with AGPL-3.0. That includes GPL-3.0
(pillow-jxl-plugin), LGPL-2.1 (zeroconf) and AGPL-3.0 (PyMuPDF).
