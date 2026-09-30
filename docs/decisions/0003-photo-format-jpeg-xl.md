# 0003 Photo format: the JPEG XL stack

Date 2026-09-30 · Scope: photos everywhere · Status: keep (the user chose JXL on 2026-09-27 and confirmed it on 2026-09-30 from their own tests; no WebP/AVIF measurement)

**Current stack:**
- Python encoding: Pillow + `pillow-jxl-plugin`.
- Android: libjxl v0.12.0 built from pinned sources with the NDK, JNI encode + decode to BMP for the WebView.
- Browsers without JXL: `@jsquash/jxl` 1.3.0 WebAssembly decoder (850 KB, loaded only when needed).

Why JXL: at equal quality (SSIMULACRA2 ≈ 79) it was 680 KB against 1212 KB for JPEG q85, over 8 photos (CLAUDE.md,
M3). WebP and AVIF were not measured.

**What each platform provides for JPEG XL:**
- **Android:** no JPEG XL at any version.
  - WebP: decode since 4.0, lossy encode through `Bitmap.compress`.
  - AVIF: encoder and decoder mandatory only from Android 14 (our minimum is Android 10).
- **Browsers (caniuse, 2026-09-30):**
  - JXL: Chrome 155+, Firefox 158+, Safari 17+ partial. **Edge: no** (the Windows default browser). **Chrome
    Android / Android WebView: no.**
  - WebP and AVIF: all three engines.
- **Python:** Pillow encodes WebP and AVIF with no plugin (checked: Pillow 12.3.0 in `.venv`, `PIL.features`
  reports both).

So the JXL choice costs three pieces we build or ship, all of which a platform format wouldn't need:
- the NDK build (and its CMake/NDK toolchain in CI);
- a WebAssembly decoder;
- a GPL-3.0 plugin.

**Dependency check:**

| Piece | Evidence | Result |
|---|---|---|
| libjxl | v0.12.0 on 2026-07-01, 38 active contributors, SECURITY.md, BSD-3-Clause | passes |
| pillow-jxl-plugin | 1.3.8 on 2026-07-17, 8 active contributors, GPL-3.0 (AGPL-compatible), no security policy, only since 2023 | weak |
| @jsquash/jxl | 1.3.0 on 2025-07-12, **1 maintainer** | fails the maintainer criterion |

**Decision:** keep until measured. The next step is evidence, not a switch:
1. Encode the same 8 photos as WebP and AVIF at settings giving SSIMULACRA2 ≈ 79.
2. Compare size and encode time, on a phone too.

If WebP/AVIF land close to JXL, the platform formats remove all three pieces above. The user decides.

**Revisit:** after the measurement; or when Edge and Android WebView ship JXL (then the decoder goes, but the
Android encoder stays).

Sources: https://developer.android.com/media/platform/supported-formats · https://caniuse.com/jpegxl · https://caniuse.com/webp · https://caniuse.com/avif · https://github.com/libjxl/libjxl · https://github.com/Isotr0py/pillow-jpegxl-plugin · https://www.npmjs.com/package/@jsquash/jxl
