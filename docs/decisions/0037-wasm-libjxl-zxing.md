# 0037 Our own WebAssembly build of libjxl and zxing-cpp

Date 2026-10-01 · Scope: phase 8 (browser client: R9 photos, R13 QR; decisions 0018, 0019, 0034) · Status: **decided by
Claude under the user's standing instruction to continue**; the user can revisit.

**Question:** 0018 and 0019 decided that browsers use libjxl and zxing-cpp compiled to WebAssembly **by us**, from the
same pinned sources as the native apps, replacing `@jsquash/jxl` (single maintainer), jsQR and qrcodegen. They left
the toolchain and the shape of the build open. Also found 2026-10-01: the Nim server has no photo encoder, so today a
browser's photo would be stored as JPEG, against 0018's "no JPEG anywhere". The browser must encode JXL itself.

## Findings

- **Toolchain: Emscripten (emsdk)**, the only maintained C/C++ → WebAssembly toolchain with a browser runtime.
  - Releases: emsdk 6.0.10, 2026-09-18 (tags 6.0.6–6.0.10 within weeks) [GitHub tags, fetched 2026-10-01].
  - Maintainers: many (kripken, sbc100, juj, aheejin, dschuff, tlively, brendandahl, …); part of the WebAssembly
    tooling at Google [GitHub contributors].
  - Security: SECURITY.md routes reports to the Chromium security tracker.
  - License: MIT or University of Illinois/NCSA (the repository's LICENSE).
  - Survived major versions (1.x → 2.x → 3.x → 4.x → 6.x) with a stable `emcmake`/`emcc` interface.
  - It is a **build tool on the developer machine only**: nothing of it ships except the generated loader JS and
    the `.wasm`.
- **WebAssembly SIMD** (highway's WASM target makes libjxl several times faster): Chrome/Edge 91+, Safari 16.4+,
  Firefox 89+ [caniuse wasm-simd]. 0034's floor is Chrome 80, so a scalar build is kept for Chromium 80–90, picked
  at runtime by `WebAssembly.validate` on a tiny SIMD module. No threads (they need cross-origin isolation headers).
- **BarcodeDetector** (0019's "where present"): Chrome on Android 83+; Chrome desktop only on macOS and ChromeOS
  (partial); Safari behind a flag; Firefox none [MDN browser-compat-data api/BarcodeDetector]. zxing-cpp is the main
  path; BarcodeDetector is used first where it exists.

## Choice

- `platform/web/build-wasm.sh`: installs a **pinned** emsdk (6.0.10) into `~/.local/kksdev/emsdk`; fetches libjxl
  v0.12.0 (+ highway, brotli, skcms) and zxing-cpp v3.1.1 by the same URLs and SHA-256 as `platform/windows/
  build-deps.sh` and the Android build; builds one module per variant (SIMD, scalar) with a small C API
  (`platform/web/kks_wasm.cpp`): JXL decode → RGBA, RGBA → JXL (distance, effort), QR read from luminance, QR write
  → module matrix.
- Output in `vendor/kks/` (our build, so `vendor/` keeps its rule: README + SHA256SUMS of what is served).
- The pages: `K.jxl` decodes with it where the browser can't; photos are encoded to JXL in the browser before upload
  (distance 1.9; effort set by measurement on a phone); QR read and write through it. `@jsquash/jxl`, jsQR and
  qrcodegen leave `vendor/` once the pages no longer use them.

**When to revisit:** when every supported engine decodes JPEG XL and has BarcodeDetector (then only encoding and QR
writing remain), or if a WebAssembly build of libjxl appears that the libjxl project maintains itself.

Sources: https://github.com/emscripten-core/emsdk/tags · https://github.com/emscripten-core/emscripten (LICENSE,
SECURITY.md, contributors) · https://github.com/Fyrd/caniuse/blob/main/features-json/wasm-simd.json ·
https://github.com/mdn/browser-compat-data/blob/main/api/BarcodeDetector.json · decisions 0011, 0018, 0019, 0034

## Results 2026-10-01

- **Built** (`platform/web/build-wasm.sh`), reproducibly (a second build gave the same SHA-256):
  - everything: 3.58 MB (SIMD) / 3.57 MB (scalar), 1.48 MB gzipped; code 2.8 MB, data 0.8 MB;
  - decoding only: 741 KB (SIMD) / 774 KB (scalar), smaller than the `@jsquash/jxl` decoder it replaces (849 KB).
- **Verified in Chromium, Firefox and WebKit** (`platform/linux/e2e/test_web_wasm.py`, against the Nim server): a
  course picture decoded by both variants alike; a photo encoded in the browser and stored as JPEG XL (the server
  refuses anything else: `photos must be sent as JPEG XL`); a QR code with non-ASCII text written and read back. All
  three engines took the SIMD variant.
- **Encoding cost** (Chromium, one thread, i7-12700H, a 1600×1200 course photo at distance 1.9): effort 7 about
  1.2 s (146 KB), effort 9 about 4.8 s (135 KB, 7.5 % smaller). Phones are several times slower and not measured, so
  browsers use **effort 7**; the native apps keep effort 9 with threads.
- **Removed:** `vendor/jxl` (@jsquash/jxl), `vendor/jsqr`, `qrcodegen.js`. The v1 packagers (Android v1 WebView copy,
  PyInstaller spec) now carry the new files.
- **Not verified:** BarcodeDetector (no engine here has it), a real camera, Edge itself, phones.
