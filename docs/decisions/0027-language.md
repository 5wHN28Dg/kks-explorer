# 0027 Language: Nim for desktop, server, importer and the shared core

Date 2026-09-30 · Scope: N6, all targets · Status: **decided by the user 2026-09-30 (Nim; Android core: option (a), one Nim core via JNI)**

**The user's choice:** Nim for the Windows and GNOME apps, the server and the importer (0026). The user's reason:
fluency and preference for a systems language. For a solo developer that is a legitimate maintainability argument
(N6). Fixed by other decisions:
- Kotlin for the Android UI (0014, Compose);
- JavaScript for the web UI (0014, the web policy);
- a Cloudflare Worker (JavaScript) for the relay (0012).

**Evidence** (GitHub, 2026-09-30; commit authors counted in the last 12 months from the first 100 commits):

| Need | Nim route | State | Result |
|---|---|---|---|
| Compiler | Nim 2.2.12 (2.2.8 installed here via choosenim [V]) | 30+ authors | ✅ |
| C libraries (MuPDF, libjxl, zxing-cpp's C API, SQLite, OpenSSL/Nettle, Avahi, GLib/GIO) | FFI; bindings generated from the headers with **futhark** (v0.16.0, 6 authors) | active | ✅ generated bindings are ours to keep up to date |
| SQLite | `db_connector` (official) | 3 authors | ✅ |
| **Windows UI** | Win32 C API and COM (Direct2D, DirectWrite, WIC, Media Foundation), through futhark-generated bindings or **winim** | winim: 1 commit, 1 author | 🟡 winim fails the maintainer test. Win32 is a frozen C ABI, so generated bindings from the SDK headers are the safer path. **WinUI 3 is not practical from Nim** (C++/WinRT or C#), so the Windows UI is **Win32 common controls + Direct2D** (the policy lists Win32 as a legitimate, very stable platform facility). |
| WinRT-only APIs | CameraCaptureUI, camera barcode scanner, MSIX StartupTask | COM projection by hand | 🟡 avoided: camera via Media Foundation, QR via zxing-cpp (0019), startup via the Run key (0021) |
| **GNOME UI** | GTK 4 + libadwaita: **owlkettle** (v3.1.0, 2026-09-14, 4 authors, 5 commits), or our own futhark bindings to the GTK C API | owlkettle small but alive; gintro dead since 2023 | 🟡 small ecosystem. The GTK C API is stable and introspectable, so own bindings are a fallback. |
| Accessibility | Win32 controls come with UI Automation support; GTK 4 widgets with AT-SPI | | 🟡 **custom-drawn views** (the drawing viewer, course figures) need our own UIA provider on Windows (COM) and GtkAccessible on GNOME |
| TLS (0017) | Schannel via SSPI (Win32 C) on Windows; GIO `GTlsConnection`/GnuTLS or OpenSSL on Linux | stdlib TLS is OpenSSL-only | 🟡 Schannel bindings are ours |
| Web client | JavaScript by hand; Nim's JS backend is an option for shared pieces (canonical encoding) | | ✅ |
| **Android** | Nim compiles for the NDK as a shared library; Kotlin calls it through JNI (**jnim**: quiet since 2025-08; plain JNI via `jni.h` works without it) | | 🟡 see the open question |

**Consequences:**
- **Languages to maintain:** Nim (core, desktop, server, importer), Kotlin (Android UI and platform glue),
  JavaScript (web UI, relay). Plus build files, and C shims where a C library needs one (MuPDF's error handling).
- **The core is written "sans I/O":** encoding, verification, replay, merge and the sync message state machine are
  pure Nim. Crypto, TLS, sockets, storage and key stores come in through a small platform interface. That is the
  policy's own advice (business logic in pure modules), and it is what lets one core run on four platforms.
- **Bindings are ours:** futhark generates them from the platform headers; we pin and regenerate them. That is the
  price of a small ecosystem, and it is accepted.
- **Windows can't be tested here.** CI on GitHub's Windows runners builds and runs the tests. UI checks need a
  Windows machine at some point.

**The Android core: decided 2026-09-30, option (a).**
- **(a) One Nim core everywhere:** the same Nim core compiled for Android and called from Kotlin through JNI. Kotlin
  supplies the platform side (Keystore signing, `SSLEngine`, NSD, WorkManager) through the platform interface.
  - One implementation of the protocol, instead of two kept equal by vectors.
  - Costs: a JNI layer; a second NDK library besides libjxl and zxing-cpp; debugging across two languages.
- **(b) Two cores:** Kotlin keeps its own core (today's M3 code, ported to v2), Nim is the core everywhere else, and
  the v2 vectors keep them identical, as today.
  - Simpler Android build and debugging.
  - Costs: every protocol change is written twice.

**Revisit:** if owlkettle or the Windows bindings stall in a way generated bindings can't cover.

Sources: https://github.com/nim-lang/Nim, https://github.com/PMunch/futhark, https://github.com/khchen/winim,
https://github.com/can-lehmann/owlkettle, https://github.com/StefanSalewski/gintro, https://github.com/nim-lang/db_connector,
https://github.com/yglukhov/jnim, https://github.com/ArtifexSoftware/mupdf, https://github.com/opencv/opencv (all queried 2026-09-30);
docs/evidence-first-platform-engineering.md (Windows: Win32; "A cost this policy imposes")
