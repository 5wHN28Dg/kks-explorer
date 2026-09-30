# 0018 JPEG XL on each platform

Date 2026-09-30 · Scope: R9 (photos) · Status: **accepted by the user 2026-09-30, with a change: no JPEG anywhere**

The format is decided: JPEG XL (0003, the user's own tests). This record decides how each target encodes and decodes
it.

**What each platform provides:**

| | Decode | Encode |
|---|---|---|
| **GNOME** | ✅ glycin JXL loader, the default image loader since GTK 4.20 [V: glycin-jxl on Ubuntu 26.04] | 🟡 libjxl 0.11 from the distribution [V]. A distribution library, not a GNOME-runtime guarantee. |
| **Windows** | 🟡 WIC codec only on Windows 11 24H2+, as an optional Store install; none on Windows 10 [D] | same, 🟡 |
| **Android** | ❌ at every version [D] | ❌ |
| **Safari 17+** | ✅ still images (no animation, no progressive decoding; caniuse notes 4, 5) [D] | ❌ |
| **Other browsers** | Chrome 155+, Firefox 158+ ✅; **Edge ❌** [D] | ❌ |

**Proposed:**
- **Library:** libjxl, the reference implementation. It passes the maintenance test (0003: v0.12.0 on 2026-07-01, 38
  active contributors, SECURITY.md, BSD-3-Clause). Pinned sources, SHA-256 checked, as the Android build does today.
- **Windows:** libjxl linked into the app for encoding and decoding. The WIC codec is not used: it is missing on
  Windows 10 and optional on 11, and one code path with fixed settings (distance 1.9, effort 9) is simpler.
- **GNOME:** decode through the platform (glycin, via GdkTexture/GdkPixbuf); encode with libjxl. Use the distribution's
  libjxl when present, and bundle the pinned one only if a package format lacks it (e.g. a Flatpak runtime without
  libjxl).
- **Android:** libjxl through the NDK for encoding and decoding (as today).
- **Browser clients (R19): fully JPEG XL, no JPEG anywhere (the user, 2026-09-30).**
  - Safari, Chrome and Firefox decode natively.
  - Browsers that can't (Edge) load **libjxl compiled to WebAssembly by us**, from the same pinned, SHA-256-checked
    sources as the other platforms, and only when the browser lacks JXL. This replaces `@jsquash/jxl` (0003,
    single maintainer): we own the build instead.
  - Photos taken in a browser are encoded to JXL **in the browser** with the same WebAssembly libjxl, before upload.
    The server never receives JPEG.
  - The user accepts the maintenance cost: one more libjxl build target (Emscripten), and the WebAssembly download
    (about 1 MB, only for browsers that need it).

**Costs:**
- libjxl is a C++ library built for four toolchains: MSVC or clang on Windows, the NDK, the Linux fallback, and
  Emscripten (WebAssembly).
- Encoding in the browser is slow at effort 9 on phones. The browser path may use a lower effort; measure it when
  building.

**Revisit:**
- when Windows ships JXL by default on all supported versions (then use WIC);
- when Edge decodes JXL (then the WebAssembly decoder is only needed for encoding in browsers).

Sources: docs/decisions/0003-photo-format-jpeg-xl.md · docs/m6/CAPABILITIES.md §2 · https://caniuse.com/jpegxl (notes 4, 5) ·
https://www.ghacks.net/2025/03/03/windows-11-how-to-add-jpeg-xl-support-officially/ · https://blogs.gnome.org/sophieh/2025/06/13/making-gnomes-gdkpixbuf-image-loading-safer/
