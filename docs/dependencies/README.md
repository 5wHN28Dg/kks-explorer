# Dependency records

One record per direct dependency, as `DEP-2` of the engineering policy v2.2 requires
(`standards/dependencies.md`, template `templates/dependency-record.md`). Written 2026-10-05 for the baseline audit
(#13). Facts that change (releases, maintainers, advisories) were checked that day against the projects' own pages,
PyPI, npm and the GitHub API, and each record names its sources. "Verified" or a measured number means it was run or
measured here; the rest is from the cited source.

The earlier dependency decisions stay where they are: `docs/decisions/0001`–`0013` (the 2026-09-30 audit) and the
later ones that chose a dependency (0018, 0019, 0026, 0029, 0033, 0037, 0043, 0047). The records reuse their evidence
and add what the template asks for (transitive counts, size, replacement cost).

Keep a record current when its dependency changes major version or license (`DEP-5`). A new direct dependency gets its
record in the pull request that adds it.

## Index

| Dependency | Kind | Used on | Where it is pinned | Record |
| --- | --- | --- | --- | --- |
| libjxl 0.12.0 (+ highway, brotli, skcms) | runtime | Android, Windows, web (WebAssembly) | `platform/windows/build-deps.sh`, `platform/web/build-wasm.sh`, `android/app2/build.gradle.kts` (`fetchLibjxl`): URL + SHA-256 per source | [libjxl.md](libjxl.md) |
| zxing-cpp 3.1.1 | runtime | Android, Windows, GNOME (Flatpak), web | the same three scripts (`fetchZxing`) and `apps/gnome/flatpak/io.github._5wHN28Dg.walkdown.yml`: URL + SHA-256 | [zxing-cpp.md](zxing-cpp.md) |
| MuPDF 1.28.2 (+ 12 bundled libraries) | runtime (server's importer) | server host | `importer/fetch_mupdf.sh`: URL + SHA-256 | [mupdf.md](mupdf.md) |
| SQLite 3.53.4 amalgamation | runtime | Android, Windows | `android/nim/fetch_sqlite.sh`: URL + SHA3-256 | [sqlite.md](sqlite.md) |
| zlib 1.3.2 | runtime | Windows | `platform/windows/build-deps.sh`: URL + SHA-256 | [zlib.md](zlib.md) |
| Nim 2.2.12 | build-time + runtime (stdlib in every native binary) | every native target | Flatpak manifest and `.github/workflows/arm64.yml`: tarball + SHA-256; locally choosenim (not hash-checked) | [nim.md](nim.md) |
| mingw-w64 13.0.0 / GCC 13.2 | build-time + static runtime | Windows x86_64 | Ubuntu 26.04 packages unpacked by hand (not pinned in a script) | [mingw-w64.md](mingw-w64.md) |
| llvm-mingw 20260922 | build-time + static runtime | Windows ARM64 | `platform/windows/fetch-llvm-mingw.sh`: URL + SHA-256 | [llvm-mingw.md](llvm-mingw.md) |
| Emscripten 6.0.10 (emsdk) | build-time + runtime parts in `vendor/kks/` | web | `platform/web/build-wasm.sh`: emsdk at a full commit | [emscripten.md](emscripten.md) |
| Kotlin 2.0.21 (stdlib, compiler, Compose compiler plugin) | runtime + build-time | Android | `android/build.gradle.kts`: exact plugin versions (no lockfile: EX-4, #3) | [kotlin.md](kotlin.md) |
| kotlinx.coroutines 1.7.3 | runtime | Android | not declared: resolved through AndroidX | [kotlinx-coroutines.md](kotlinx-coroutines.md) |
| Gradle 8.13 (and the vendored wrapper jars) | build-time | Android | `android/gradle/wrapper/gradle-wrapper.properties` (version only) | [gradle.md](gradle.md) |
| Eclipse Temurin JDK 21 | build-time | Android build | `actions/setup-java` (`21`) in CI; local install | [temurin-jdk.md](temurin-jdk.md) |
| Atkinson Hyperlegible (font) | runtime | courses on every client | committed in `vendor/fonts/` with `SHA256SUMS` | [atkinson-hyperlegible.md](atkinson-hyperlegible.md) |
| Barlow Semi Condensed (font) | runtime | courses on every client | committed in `vendor/fonts/` with `SHA256SUMS` | [barlow-semi-condensed.md](barlow-semi-condensed.md) |
| JetBrains Mono (font) | runtime | courses on every client | committed in `vendor/fonts/` with `SHA256SUMS` | [jetbrains-mono.md](jetbrains-mono.md) |
| Python packages for tests and tools (7, one family record) | dev-only | test and maintainer machines | `requirements-dev.txt` (`==`; completed by #19) | [python-dev-tools.md](python-dev-tools.md) |
| wrangler | dev-only (deploy, local relay tests) | the maintainer's machine | not pinned (`npx wrangler`) | [wrangler.md](wrangler.md) |
| osslsigncode 2.13 | build-time (release signing) | the maintainer's machine | Ubuntu package unpacked by hand (not pinned in a script) | [osslsigncode.md](osslsigncode.md) |

**Counted inside a record, not separately:** highway, brotli and skcms are the source trees libjxl 0.12.0 expects as
submodules; our scripts fetch them only because the release tarball leaves them out, at the commits libjxl names, and
they would go with libjxl. MuPDF's 12 libraries come inside its source release. The transitive Python, Gradle and npm
packages are listed in their records. AndroidX's own transitive modules are platform-provided (below).

## Platform-provided (no record)

These pass the policy's test for platform-provided code, so they are not dependencies under `DEP-0`. They are still
covered by the automated scans. Per-engine support evidence for the web features, and the rows for the native
facilities, belong in the capability matrix (`WEB-1`/`NAT-3`, #9); until it exists, the evidence is in
`docs/m6/CAPABILITIES.md` and the decisions named.

### Android: `NAT-1` (vendor SDK or library, available on API 29+, no duplicate runtime)

- Framework APIs used directly: JCA and AndroidKeyStore (keys, ECDSA, AES-GCM), `SSLEngine`/`SSLSocket` (TLS),
  Camera2, `NsdManager`, `PackageInstaller`, `org.json`, `Typeface`, the accessibility node provider (0032).
- NDK stable APIs: JNI, `libz`, `liblog`, the NDK's `libc++` (static), CMake from the SDK (0029, 0032).
- The Android Gradle Plugin 8.13.2, SDK build tools, R8 (Google's build toolchain).
- AndroidX/Jetpack, published by Google as how Android apps are built ([AndroidX](https://developer.android.com/jetpack/androidx)):
  the Compose BOM 2024.12.01 (`material3`, `ui`), `activity-compose` 1.9.3, `core-ktx` 1.13.1, `work-runtime-ktx`
  2.9.1, and the 90 AndroidX and Google modules they resolve to (`./gradlew :app2:dependencies --configuration
  releaseRuntimeClasspath`, including `com.google.guava:listenablefuture`). Decision 0008 treats them the same way and
  asks for their update. Established (test 4): Compose 1.0 in 2021, WorkManager 1.0 in 2019, both Google's documented path since.
- Not platform-provided, so recorded: Kotlin and `org.jetbrains:annotations` ([kotlin.md](kotlin.md)) and
  kotlinx.coroutines ([kotlinx-coroutines.md](kotlinx-coroutines.md)), published by JetBrains rather than Google.

### Windows: `NAT-1`

Win32 and common controls v6, Direct2D, DirectWrite, WIC, RichEdit, UI Automation, CNG and NCrypt, DPAPI, Schannel,
the DNS-SD API (`DnsService*`), Media Foundation (loaded at run time), on Windows 10 22H2 and 11 (decisions 0033,
0036, 0039). For packaging: MakeAppx from Microsoft's NuGet package `Microsoft.Windows.SDK.BuildTools` 10.0.28000.2705,
pinned by SHA-256 in `packaging/windows/make-msix.sh` (0043).

### GNOME / Linux desktop: `NAT-1`, Linux clause (the named desktop stack counts as the platform)

The stack is GTK 4 + libadwaita with portals and D-Bus, shipped as a Flatpak on the GNOME 50 runtime (decisions 0022,
0031). From the runtime (`org.gnome.Platform//50`): GTK, libadwaita, GLib/GIO, Cairo, Pango, fontconfig, libsecret
(through the Secret portal), GStreamer with the PipeWire plugin, GnuTLS, SQLite, zlib, and libjxl 0.11 (the runtime's
copy; the copy we build elsewhere has its record). Portals: FileChooser, Camera, Secret. Avahi over D-Bus for mDNS.
Build and packaging: the GNOME 50 SDK and `org.flatpak.Builder`. **Gap:** `NAT-1` asks for the stack to be named in
the README; the README doesn't name it yet (nor the OS versions, `NAT-2`). Until it does, this classification rests on
decision 0031.

### Server: `OTH-0`, service (the OS at the declared version and its service manager)

The server runs on an Ubuntu 26.04 LTS host as a systemd user service (`deploy/`). The OS libraries it links, all from
Ubuntu's main archive and covered by Ubuntu's security updates: GnuTLS, OpenSSL's `libcrypto` (Argon2id), SQLite,
zlib, GLib/GIO, plus the Avahi daemon over D-Bus and `systemd-creds` for the storage key (0026, 0030). The importer
links Ubuntu's `libjxl0.11` (with highway, brotli and lcms2 from the same archive). **Judgement call for the owner:**
`OTH-0` counts "the OS ... at the declared version"; the server's OS version is not declared in the README yet, and
`OTH-0`'s image rule ("anything a project's own image adds on top of the official base is a dependency") has no
counterpart for a host install. These libraries are treated as the OS because Ubuntu's main archive maintains them;
if the owner reads `OTH-0` more strictly, `libjxl0.11` and Avahi (not in a minimal Ubuntu install) need records.

### Web client: `WEB-3`

Standard Web Platform features: Canvas 2D, module Workers, `OffscreenCanvas`, `createImageBitmap`,
`DecompressionStream`, WebAssembly, `ResizeObserver`, `IntersectionObserver`, service workers, `localStorage`,
IndexedDB, `getUserMedia` (decisions 0034, 0035, 0037). Not in every declared engine, so used only after
feature detection with a fallback (`WEB-4`): `BarcodeDetector` (fallback: our zxing-cpp WebAssembly), JPEG XL in
`<img>` (fallback: our libjxl WebAssembly), WebAssembly SIMD (fallback: the scalar build). The browser list itself is
EX-5 / #12.

### Relay: `OTH-0`, service (the documented API of the external service)

Cloudflare Workers with Durable Objects (SQLite storage), the WebSocket Hibernation API and Web Crypto
(`relay/src/index.js`, decisions 0012, 0038); the public STUN servers the devices ask for their address. The deploy
tool is a dependency ([wrangler.md](wrangler.md)).

### CI: `DEP-7` only

Third-party actions (`actions/checkout`, `actions/setup-java`, `actions/cache`, `actions/upload-artifact`,
`actions/download-artifact`, `gradle/actions/setup-gradle`, `flatpak/flatpak-github-actions/flatpak-builder`, the
policy's own actions) are pinned to full commit SHAs and need no record. The tools inside the policy's actions
(gitleaks, osv-scanner, Semgrep, Syft, the Claude review) are pinned by those actions. The Flathub container image
`ghcr.io/flathub-infra/flatpak-github-actions:gnome-50` is pinned by digest; it is the Flatpak distribution's own
image carrying the GNOME 50 SDK, so it counts as an official distribution image under `OTH-0`. GitHub's hosted runner
images (`ubuntu-24.04`, `ubuntu-24.04-arm`, `windows-11-arm`) are the CI platform.

### Build and test host tools: the host OS

The maintainer's machine runs Ubuntu 26.04 LTS. General-purpose tools from its archive, whose output doesn't ship and
which do no security work for a release, are treated as part of that OS: `sh`, `make`, `cmake`, `curl`, `tar`,
`unzip`, `git`, the `openssl` CLI (the test certificate, reading the publisher name), `python3` and its standard
library, GCC for the Linux builds, `ffmpeg` (the QR test video), `pdftotext` from poppler-utils
(`tools/parse_locations.py`), `cjxl`/`djxl` from libjxl-tools (tools and tests), PyGObject, pycairo and the AT-SPI
bindings (the GNOME e2e driver, `tools/m6` benchmarks), libvirt/QEMU/OVMF/swtpm (the Windows test VMs), OpenSSH,
`adb` and the emulator from the Android SDK, and `gh`, GitHub's own CLI for its service (`tools/release.py`). Tools
whose output ships or that sign a release have records (mingw-w64, llvm-mingw, Emscripten, osslsigncode). This line is
a judgement for the owner to confirm: the policy defines platform-provided code for apps and services, not for build
hosts.

### Test targets

The Windows 10 and 11 VM images and the Android emulator system images are the vendors' own operating systems.

## Not dependencies today

Not built, run or shipped by any build, test or release script; a record is due if that changes:
- `tools/plant3d/bench`: a Godot 4 benchmark project with CC0 textures from ambientCG (`fetch_textures.sh`, pinned by
  SHA-256); decision 0041, on hold. If the 3D plant goes ahead, Godot needs a record (it fails `NAT-1` test 3, "no
  duplicate runtime").
- `tools/m6/android-bench`: a throwaway benchmark app (0015); its wrapper jar is covered by [gradle.md](gradle.md).
- `deploy/cloudflared-config.example.yml`: Cloudflare Tunnel is not deployed (it waits for IT approval); `cloudflared`
  needs a record before it is.

## Open points found while writing these records

Each is in the findings register; none is changed here (this change touches only `docs/dependencies/`):
1. **Gradle 8.13 is affected by CVE-2026-22865 and CVE-2026-22816** (high, fixed in 8.14.4): [gradle.md](gradle.md). #3 (fix in #55).
   Also: `gradle-wrapper.properties` has no `distributionSha256Sum`.
2. **Kotlin 2.0.21 is affected by CVE-2026-53914** (build-cache deserialization, fixed in 2.4.20): [kotlin.md](kotlin.md).
   Update it together with the Compose BOM (decision 0008's open action). #3 (fix in #55).
3. **MuPDF 1.28.2 lags 1.28.5**, whose notes list several memory-safety fixes; the update needs the importer's gate:
   [mupdf.md](mupdf.md). #51.
4. **wrangler runs unpinned** through `npx`, with an unlocked, unscanned 39-package tree: [wrangler.md](wrangler.md). #52.
5. **kotlinx.coroutines is used directly but not declared** in `android/app2/build.gradle.kts`:
   [kotlinx-coroutines.md](kotlinx-coroutines.md). #71.
6. Fetched by hand, not pinned in a script: the mingw-w64 packages and osslsigncode (Ubuntu's archive verifies them at
   download), and the local Nim from choosenim (CI and the Flatpak check the tarball's SHA-256). The course fonts'
   download is unpinned too, which is #4 (DEP-8). #53.
7. libjxl's pinned submodules are old: highway is two years behind its releases, and skcms predates its 2026 ICC
   parsing hardening. They move when libjxl names newer commits: [libjxl.md](libjxl.md). #72.
8. The maintainer's local JDK (Temurin 21.0.7) is five quarterly security updates behind: [temurin-jdk.md](temurin-jdk.md). #73.
9. The README doesn't yet name the Linux desktop stack or the server's OS version (`NAT-1`, `NAT-2`, `OTH-0`), which
   the platform-provided classification above relies on. #9 (the capability matrix declares them).
