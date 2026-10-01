# M6 step 4: the decisions against today's code (2026-09-30)

What survives, what changes, what is rewritten, and in which order. Decisions: docs/decisions/0014–0027. Sizes are
today's source (lines; web files by bytes, since their lines are long).

## Today's code, part by part

| Part (size) | v2 outcome | Decision |
|---|---|---|
| **Protocol logic**: `peer/proto.py`, `replay.py`, `sync.py` (Python) and `android/core` Proto/Replay/Sync/MemoryNode/LocalNode (Kotlin) | **Semantics survive, code is rewritten** as one sans-I/O Nim core: encoding, entries, chains, clock, authority, replay, merge, sync messages. Python and Kotlin serve as the reference when generating v2 vectors and in the migration tool. | 0024, 0027 |
| Noise (`peer/noise.py`, `Noise.kt`) | **Removed**, replaced by the platform TLS with pinned device keys | 0017 |
| Crypto (`cryptography` package, BouncyCastle) | **Removed**, replaced by platform crypto (CNG, OpenSSL/Nettle, Android + Keystore, WebCrypto), P-256 + AES-GCM | 0017 |
| Reliable UDP, relay client, WebSocket (`rudp.py`, `internet.py`, `ws.py`, Kotlin twins) | **Algorithm survives**, ported to Nim; TLS runs over it | 0013, 0024 |
| Relay: Cloudflare Worker (131 lines JS) + Python twin | **Worker survives unchanged** (it only moves bytes); the test twin is ported to Nim | 0012 |
| Server: `app.py` + `server/*.py` (4,687 lines) | **Rewritten in Nim**: the core without UI, plus the HTTP server for the web UI, Argon2id sign-in, backups, `systemd-creds` | 0020, 0023, 0026 |
| Desktop package: `desktop.py`, PyInstaller spec, own updater | **Replaced** by native Nim apps: Win32 + Direct2D on Windows (MSIX via the Store), GTK 4 + libadwaita on GNOME (Flatpak on Flathub). The own updater is retired. | 0014, 0022, 0027 |
| Discovery: `zeroconf` | **Removed**; `dnsapi` on Windows, Avahi on GNOME, NSD on Android | 0002 |
| **Web UI**: index/admin/learning.html, common.js, sw.js (158 KB) | **Survives as the browser client** (Safari/iOS, borrowed computers). Changes: the web-policy audit (escaping, native elements, three engines); JXL from our own WebAssembly build; QR through `BarcodeDetector` or zxing-cpp WebAssembly; a renderer for the new course format; the viewer draws the path store (0015) on a canvas | 0014, 0015, 0018, 0019, 0025 |
| Android app: WebView shell (`WebHost`, `MainActivity`, `Shell`) | **Rewritten** as native Compose screens: viewer, equipment panel, procedures, courses, admin | 0014 |
| Android platform pieces: `PhoneSync` (NSD), `SyncWorker` (WorkManager), `SqliteStore`, `AppUpdates`, camera/FileProvider, Jxl JNI | **Survive, adapted**: they become the Kotlin side of the Nim core's platform interface. Keystore keys become P-256; libjxl stays. | 0020, 0021, 0027 |
| Kotlin core (3,784 lines) | **Replaced** by the Nim core through JNI | 0027 (a) |
| QR: jsQR, qrcodegen, zxing-android-embedded | **Replaced** by zxing-cpp (browsers: `BarcodeDetector` first) | 0019 |
| JXL in browsers: `@jsquash/jxl` | **Replaced** by our own libjxl WebAssembly build | 0018 |
| Photos pipeline (JXL d1.9, effort 9, annotation, lightbox) | **Behaviour survives**; libjxl on every target; the annotation and zoom viewer are rebuilt natively per UI | 0018 |
| Importer: `extractor/` + `import_sheet.py` (789 lines) + `fontlib.pkl` | **Ported to Nim**: MuPDF C API, own code for 12 OpenCV operations, glyph library in a documented format. Gated by identical readings on all sheets; the Python importer is used until then. It also gains the path store and the JXL pyramid. | 0015, 0016, 0026 |
| Viewer data: merged SVG + PNG per sheet | **Replaced** by the grid-indexed path store + overview pyramid; the original PDF stays in the set | 0015, 0016 |
| Plant data files (tags, locations, procedures JSON) | **Survive** (JSON) | 0024 §19 |
| `data/kks.json` (decode tables) | **Survives** as program data | — |
| Courses: 3 HTML files + `course-bridge.js` + build tool | **Re-authored** into the new content model (text source → JSON; declarative figures); published as a content set. Progress entries survive. | 0025 |
| Vendored fonts | **Survive**, bundled in the native apps and the web UI | 0011 |
| Tests: `tests/*.py` (1,998 lines), Kotlin tests, frozen vectors v1–v4 | The v1 vectors **stay frozen** as the record. New **v2 vectors**, and a Nim test suite. The Python tests stay while the Python server runs. | 0024 |
| Docs: PROTOCOL.md, ARCHITECTURE.md | **Revised to v2**; new specifications for the path store and the course format | 0015, 0024, 0025 |

**Superseded audit actions:**
- 0006 BouncyCastle update: BouncyCastle is removed in v2.
- 0007 zxing-android-embedded: replaced.
- 0008 AndroidX update: comes with the Compose rewrite.
- 0009 BarcodeDetector-first: part of the new web client.

**One exception worth doing now:** until v2 ships, the current Android app is in the field with BouncyCastle 1.79,
seven releases behind in a crypto library. A one-line version bump plus the existing test run is cheap. It is the
user's call, since code changes are on hold.

## Order of work (proposed)

Each phase ends with something testable. Nothing replaces the running system until phase 9.

1. **Specifications and vectors:** PROTOCOL.md v2, path store spec, course content spec. v2 vectors are generated and
   cross-checked against an independent verifier (Python `cryptography` for the crypto and encoding pieces), since
   there is now one core.
2. **Nim core (sans I/O):** encoding, entries, chains, replay, merge, sync state machine. Must pass the v2 vectors.
3. **Linux platform layer + server + migration tool:**
   - TLS, SQLite, `systemd-creds`, Avahi, HTTP;
   - the migration tool run as a **dry run on a copy** of the real plant.db: the replayed state must equal today's.
4. **Importer port:** gated by identical readings; then it writes v2 plant data (path store, pyramid).
5. **GNOME app** (GTK 4): viewer with tiles (0016), panels, admin, courses renderer, photos, QR.
6. **Android:** Nim core through JNI plus the native Compose UI, on the Note 9.
7. **Windows app** (Win32 + Direct2D): built and unit-tested in CI; UI checks when a Windows machine is available.
8. **Web client** changes, and **course conversion** (script for text and questions; figures by hand).
**Status 2026-10-01:** phases 1–8 done (CLAUDE.md lists each one's results and what is still unverified). Waiting for
the user: the two phones (6), MSIX/Store or certificate, CI push and a real laptop (7), and phase 9.

9. **Cutover:**
   1. back up everything;
   2. migrate the live plant;
   3. every device re-joins;
   4. retire the Python server, the desktop package and the WebView Android app.

## Open points outside the decisions

- No Windows machine: Windows UI, performance and accessibility stay unverified until one is available (0016, 0022,
  0027). Since 2026-10-01 they are verified in Windows 10 and 11 VMs (0033); a real laptop is still to come.
- Store availability at the company is unknown; the fallback is agreed (0022).
- The server's Linux distribution must have OpenSSL ≥ 3.2 (0023).
- Measure a login, and startup decryption, on the real server and phone when built (0020, 0023).
