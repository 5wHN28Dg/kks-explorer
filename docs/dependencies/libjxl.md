# Dependency record: libjxl 0.12.0

Added: 2026-09-27 (Android, M3; decision 0003), 2026-10-01 (Windows 0033, WebAssembly 0037)   Pull request: https://github.com/5wHN28Dg/kks-explorer/pull/23 (record written for an existing dependency)   Recorded by: Claude for Hashim, 2026-10-05
Kind: runtime
Packages covered: libjxl, with the three libraries its source tree expects as submodules, which our build scripts fetch
and pin separately (highway, brotli, skcms; counted below as its transitive dependencies)

## Purpose
Encodes and decodes JPEG XL, the only photo and drawing-pyramid format of the project (decisions 0003, 0018): photos
on every client, the drawings' overview pyramid, the course pictures.

## Platform alternative checked
Decision 0018 and `docs/m6/CAPABILITIES.md` §2, rechecked 2026-10-05:
- **Android:** no JPEG XL decoder or encoder at any API level
  ([supported media formats](https://developer.android.com/media/platform/supported-formats)).
- **Windows:** a WIC codec only on Windows 11 24H2+, as an optional Store install; none on Windows 10, which is a
  target (0018, 0033).
- **Browsers:** no engine encodes JPEG XL; decoding in Safari 17+, Chrome 155+, Firefox 158+, not in Edge
  ([caniuse](https://caniuse.com/jpegxl)). Browsers that decode natively use `<img>`; the others load our WebAssembly
  build (`vendor/kks/`, decision 0037).
- **GNOME, the server and the importer:** the platform's libjxl 0.11 (the GNOME 50 runtime's copy in the Flatpak,
  Ubuntu's `libjxl0.11` from the main archive on the server host). Those copies are platform-provided (see the index);
  this record covers the copy we build.

So the platform falls short on Android, on Windows 10 and for encoding in every browser.

## Custom implementation considered
None realistic: JPEG XL is a large codec (modular and VarDCT modes, entropy coding, ICC handling). Writing it means
owning a parser of untrusted image data, the most security-sensitive kind of code there is, plus an encoder whose
quality we could not match. The alternative to libjxl is another format (WebP or AVIF, which the platforms provide),
not our own codec; decision 0003 kept JPEG XL on the user's own tests (680 KB vs 1212 KB for JPEG at equal
SSIMULACRA2 over 8 photos) and records what a switch would remove.

## Transitive dependencies
Count: 3 (highway, brotli, skcms)   How counted: the libraries each build actually compiles. The build scripts
(`platform/windows/build-deps.sh`, `platform/web/build-wasm.sh`, the Gradle task `fetchLibjxl` in
`android/app2/build.gradle.kts`) unpack exactly these three into `third_party/`, at the commits libjxl 0.12.0 names,
each pinned by SHA-256. Everything else libjxl can use is switched off (tools, JPEG transcoding, jpegli, plugins,
OpenEXR, libpng; `JPEGXL_ENABLE_SKCMS=ON` instead of lcms2).

| Library | Pinned at | License | Signals (GitHub, 2026-10-05) |
| --- | --- | --- | --- |
| [highway](https://github.com/google/highway) (SIMD) | commit `457c891` (2024-05-31, 512 commits behind 1.3.0) | Apache-2.0 OR BSD-3-Clause | 1.4.0 on 2026-04-23; 46 authors in 12 months (jan-wassenberg leads); no SECURITY.md, no published advisories |
| [brotli](https://github.com/google/brotli) (box compression) | commit `028fb5a` = the v1.2.0 release (2025-10-27) | MIT | v1.2.0 is the latest; it carries the decompression-bomb mitigation of [CVE-2025-6176](https://access.redhat.com/security/cve/cve-2025-6176); SECURITY.md present; 19 authors in 12 months (eustas leads) |
| [skcms](https://skia.googlesource.com/skcms/+log) (ICC color profiles) | commit `96d9171` (2025-09-16) | BSD-3-Clause | part of Skia, about 10 Google authors in the last 18 months; later commits (2026) harden ICC table parsing (CLUT bounds, profiles that "walk off the end"), which our pin predates |

## License
BSD-3-Clause, with a separate royalty-free patent grant (`PATENTS` in the source). Transitive: Apache-2.0 OR
BSD-3-Clause (highway), MIT (brotli), BSD-3-Clause (skcms). All permissive and compatible with the project's
AGPL-3.0; none would need review under a copyleft-only rule. The project has no written license allowlist yet (#10).

## Maintenance signals
- Recent releases: v0.12.0 on 2026-07-01; v0.11.2, v0.10.5, v0.9.5, v0.8.5 and v0.7.3 on 2026-02-10 (security
  backports to five release lines at once) ([releases](https://github.com/libjxl/libjxl/releases)).
- Security response: [SECURITY.md](https://github.com/libjxl/libjxl/blob/main/SECURITY.md) (reports through Google's
  vulnerability program); GitHub advisories for CVE-2021-22563/22564; CVE-2024-11403, CVE-2024-11498, CVE-2025-12474,
  CVE-2026-1837 and CVE-2025-70103 were fixed in point releases of every supported line (the 2026-02-10 releases)
  ([OpenCVE list](https://app.opencve.io/cve/?vendor=libjxl_project)). 0.12.0 contains those fixes.
- Active maintainers: 37 commit authors in the last 12 months, led by eustas (166 commits), jonsneyers and others
  at Google and Cloudinary (GitHub contributor statistics, 2026-10-05).
- Age across major versions: first release 2021; still 0.x, but it has carried the frozen ISO/IEC 18181 bitstream
  through 0.7 → 0.12 with a stable C API (`JxlDecoder*`/`JxlEncoder*`). Our wrappers build against both lines today:
  `importer/src/kksi/kks_jxl.c` (GNOME app and importer) against the platform's 0.11, and `jxl_jni.cpp`,
  `kks_wasm.cpp`, `kks_img.cpp`/`kks_d2d.cpp` (Windows) against 0.12.

## Size impact
Measured on the release builds of 2026-10-05:
- Android: `libkksjxl.so` (libjxl + highway + brotli + skcms + our JNI wrapper, arm64-v8a, stored uncompressed) is
  6.39 MB of the 18.6 MB `app2-release.apk`.
- Windows: about 3.9 MB of the 14.0 MB code of `Walkdown.exe` (x86_64), estimated from the symbol table by name
  (`jxl::`, `Brotli*`, `skcms*`; `x86_64-w64-mingw32-nm --size-sort -S`).
- Web: `vendor/kks/kks-simd.wasm` (libjxl encode + decode and zxing-cpp) 3.58 MB, 1.48 MB gzipped; the decode-only
  module `kks-simd-dec.wasm` 0.74 MB. Loaded only when needed (decision 0037).
- GNOME, server, importer: none (the platform's copy).

## Replacement cost
High. JPEG XL is in the data formats: photos in the log, the drawing pyramids (`docs/PATHSTORE.md`), the course
pictures (`data/courses/*.jxl`), and the server refuses non-JXL photos. Replacing libjxl with another JPEG XL library
would touch four small wrappers (about 200 lines each); replacing the format would mean converting every stored photo
and pyramid and a protocol change.

## Decision
Keep. No platform covers Android, Windows 10 or browser encoding, a custom codec is out of the question, and libjxl
is the reference implementation with a real security process and many maintainers. The weak spots are the pinned
submodules: highway is two years behind its releases and skcms predates its 2026 ICC hardening. Both are fixed by
libjxl's choice of commits; when libjxl releases a version that names newer ones, update all four build scripts
together (they share the hashes). Revisit with 0018's triggers (Windows ships JXL by default; Edge decodes it).
