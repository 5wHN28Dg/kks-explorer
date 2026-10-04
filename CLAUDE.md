# Walkdown (formerly KKS Explorer) — project context for Claude Code

**Name (the user's choice, 2026-10-03): Walkdown.** IDs: Android `io.github.walkdown` (Android segments must start
with a letter, so not Flathub's `_5wHN28Dg`; the code namespace stays `kks.explorer.v2`), Flatpak
`io.github._5wHN28Dg.walkdown` (Flathub's form for a GitHub account starting with a digit), MSIX `Walkdown` (alias `walkdown.exe`, exe `Walkdown.exe`),
release APK `walkdown.apk`. Unchanged on purpose: the v1 app (`kks.explorer`, "KKS Explorer", `kks-explorer.apk`: 0.8.0
phones look for them), every protocol string (`kks-…` signature domains, relay rooms, `_kks._tcp`, ALPN, vectors), the
deployed relay, the GitHub repo name (renaming it is the user's call; GitHub redirects the old URLs).

Tool built by an I&C maintenance engineer at a combined-cycle power plant. The repository is meant to become public
(M5b): no plant name, plant data or plant-specific notes in tracked files. Those live in `plant-data/` (the manager's
working copy, gitignored) and `CLAUDE.local.md` (gitignored: the plant, reader accuracy per sheet, findings on the
drawings). Goal: given only a KKS code (e.g. `11LAB70AA501`), find the equipment on the P&IDs and see everything known
about it: decoded meaning, physical location, photos, notes, and which operation-manual procedures use it.
Also: pick a procedure ("Preparations for Startup — Air Compressor System") → see its steps and highlighted equipment.

The user prefers direct, no-fluff communication and honest pushback. Be explicit about what is verified vs not.

**Where documentation goes (the user, 2026-10-03):**
- Guides, how-tos, operations, history and research go in the **wiki**
  (https://github.com/5wHN28Dg/kks-explorer/wiki; clone https://github.com/5wHN28Dg/kks-explorer.wiki.git, push to it
  directly).
- The repository keeps only what code, tests and the policy point at: the specs (PROTOCOL*, PATHSTORE, COURSES,
  GLYPHLIB), `docs/decisions/`, the policy documents, `docs/m6/`, and each component's build README.
- The wiki is public: no plant name, plant data or relay URL there either.

**Live since 2026-10-03 (the cutover, done by Claude at the user's request; record on the wiki's Cutover page):**
- **Server:** the v2 server runs as a user service from `~/kks-server` (0.9.2-c7c4848 since 2026-10-04; `systemctl --user`, linger on).
  CLI through `systemd-run` with the sealed credential (wiki: Server). v1's files are archived read-only in
  `~/kks-server/v1` and `~/kks-server/archive`.
- **Release:** v0.9.0 published: the bridge, Walkdown for Android, Windows and Linux. Teammates move by themselves;
  Manage → Devices lists who hasn't.
- **The old app's code was removed on 2026-10-03** (the user's request), before anyone had moved. It is in git
  history; its notes are on the wiki ("KKS Explorer v1 notes").
- **What stays until every phone has moved:**
  - the server's v1 support (`succession`/`migrate` answers, the v1 relay room, the v1 device table);
  - the archived bridge APK `~/kks-server/archive/kks-explorer-bridge-0.9.0.apk`, which `tools/release.py` attaches
    to every release, because 0.8.0 phones only install `kks-explorer.apk`;
  - the Ed25519 release signature.
  Check with `kks-server v1-status` (wiki: Server). When it says none are left, remove all three (decision 0042 "When
  to revisit") and `docs/PROTOCOL.md`.
- **The plant root key:** inside the server. An encrypted backup and its passphrase are in
  `~/.config/kks-explorer/signing/walkdown-root.{kksroot,passphrase}` (`kks-server export-root-key`).

## Development policy: evidence-first (in force from 2026-09-30)

Two documents:
- `docs/evidence-first-platform-engineering.md` governs native code: the Android app (`android/app2`), the desktop
  apps, any iOS work, and the server.
- `docs/evidence-first-web-engineering.md` governs what runs in a browser engine: index.html, admin.html, learning.html,
  common.js, sw.js, course-bridge.js, the courses, vendor/.
- The web pages are served by the server to browsers; they ship no engine. They must also work in Safari, since that
  is the iOS path (https://github.com/5wHN28Dg/kks-explorer/wiki/iOS-research).

Rules for this project (solo developer, 3+ targets, long lifespan):
- **Investigate before implementing or bundling.** For each feature touching the platform, or each new dependency,
  answer the policy's four questions per target (what the platform provides, optional components and how reliably
  they're present, what's missing, small custom code vs a well-maintained dependency). Base the answers on evidence:
  vendor docs with links, or a test on the target. Record the result in `docs/decisions/NNNN-title.md` (one page:
  question, per-platform findings with sources, choice, when to revisit) before writing the code.
- **Capability matrix before architecture.** Keep `docs/CAPABILITIES.md` per target platform. Rebuild it when adding
  a platform or a major feature, and before M6's design. The architecture is an output of the matrix, not an input.
- **Dependencies** must meet the policy's "well-maintained" test: recent releases, a findable security response
  history, more than one active maintainer, a compatible license, and survival of a major version change. Say which
  criteria a dependency fails and why it is still chosen.
- **Measure on the target** (clean device, no dev tools): installed size, startup time, steady memory, and on phones
  battery. Each metric gets a baseline and a regression rule, written before measuring.
- **Never weaken or bypass a platform security mechanism** to drop a dependency or simplify code.
- **Keep business logic platform-independent** (`core/`, the sans-I/O Nim core): platform code stays a thin adapter,
  tested on the platform.
- Every claim about a platform names its source or says it is unverified; "verified" means it ran on the target.
- Existing dependencies were audited on 2026-09-30: `docs/decisions/0001`–`0013`. The open actions are listed in
  `docs/decisions/README.md`.
- **Web specifics:**
  - Browser support is declared per engine (Blink, WebKit, Gecko); check features on caniuse/MDN, not memory.
  - Prefer, in order: the browser platform, then a small library, then a framework. Each step needs a written reason.
  - A polyfill counts as a dependency; graceful degradation is preferred.
  - The UI is vanilla JS with no framework, so we own HTML escaping: `textContent` by default, and every `innerHTML`
    with data in it must be escaped and audited.
  - Native elements for accessibility (`<button>`, `<dialog>`, labels).
  - UI changes are tested in Playwright on all three engines, plus keyboard-only and screen-reader checks.

## Build and test (the code that exists)

- **Nim:** `~/.nimble/bin/nim` (choosenim; put it on PATH).
  - Core: `cd core && nim test`.
  - Platform and server: `cd platform/linux && nim test`; the server is
    `nim c -d:release -o:/tmp/kkslinux/kks_server kks_server.nim`.
  - Importer: `cd importer && nim test` (MuPDF from `fetch_mupdf.sh`).
- **Apps:**
  - GNOME: apps/gnome/README;
  - Windows: apps/windows/README (cross-built with mingw; VMs `kks-win10` and `kks-win11` under virsh);
  - Android: android/app2/README.
- **Python** (tests and tools only, `.venv` from `requirements-dev.txt`):
  - `.venv/bin/python -m unittest discover -s tests` (protocol v2 vectors, strict JSON, path store, courses);
  - `ref/` is the independent reference;
  - `relay/twin.py PORT` is the relay twin.
- **End to end:** see the wiki's Development page. Emulator: AVD Pixel_9_Pro_XL, `JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64`.
- **Keys:** `~/.config/kks-explorer/signing/` (wiki: Releasing). The repo's history before the M5b rewrite (with plant data)
  is kept privately in `~/kks-explorer-history-before-M5b.bundle`.
- NEVER commit plant data, `plant.db`, `photos/`, `backups/`, `config.json` or `root.key`. The repo root still holds the
  old v1 server's files on this machine (gitignored; archived in `~/kks-server/v1`).

## How extraction works (and why)

(Python module names below are the old reader, removed with v1; the Nim ports are `importer/src/kksi/`: mupdf,
reader, fontlib, extract, textlines. The glyph library is `importer/fontlib.kgl`.)


P&IDs are AutoCAD plots: no text objects, no layers, every character is loose vector strokes (SHX fonts), many
glyphs split into several paths, box edges are zero-height paths. Pipeline:

1. Normalize orientation (`extractor/orient.py`): place page 1:1 via `show_pdf_page`, try 0/90/180/270, keep the one
   with most horizontal text lines. Score can't reliably tell upright from upside-down → check visually for new sheets.
2. Detect tag containers (`reader2.detect`): render 200 dpi, contour holes = box halves / instrument-bubble halves; pair
   stacked cells. Threshold <215 (thin line weights) and size window H 4–24pt, W 15–110pt (Block 1 sheets use bigger text).
2. Read each half (`reader3`): re-render at 600 dpi, trim border blobs with the contour mask, split characters by column
   projection (wide blobs split at ink minima), classify each glyph by kNN against `fontlib.pkl`, then family rules
   C/G (lower-right ink), B/8 (left edge straight), 0/D/Q (tail + straight left edge).
3. KKS grammar (`fontlib.interpret`): `DDLLLDD` over `LLDDD[L]` = equipment; ISA letters over `DDLLLDDLLDDD[suffix]` =
   instrument. I→1 / O→0 only in digit slots (KKS never uses letters I or O). Confidence = min char confidence.
4. Second pass for open-ended instrument bubbles: long vector text lines not inside a container, read with the same reader.

Lessons (don't repeat):

- Tesseract/general OCR on this condensed SHX font produced confident wrong KKS after grammar coercion. Removed entirely.
- Per-glyph geometric rules tuned on one font break another (a mid-height 0/8 rule turned Q→B, then B→D, 0→8).
  Prefer adding labeled samples to the library over new rules. Always re-check the LP sheet after any reader change:
  it has a verified reference, but that reference was itself wrong about suffixes (see Accuracy status).
- Test reader changes with a harness that pins the OLD behaviour in the script itself; importing the edited module as
  "old" silently compares new with new (happened once, 2026-09-25). Compare every tag cell old vs new on all sheets
  and look at every changed crop.

## M6: the product re-derived under the evidence-first policy (decided 2026-09-30, no code yet)

docs/m6/ (README, REQUIREMENTS, CAPABILITIES, COMPARISON) and docs/decisions/0014–0027 supersede the architecture
above for new work.
- **UI:** native UI per platform, no embedded web engine: Win32 + Direct2D on Windows, GTK 4 + libadwaita on GNOME,
  Compose on Android. A web UI remains for browser clients (iOS).
- **Language:** Nim for the core (sans I/O), desktop apps, server and importer. Android calls the Nim core through
  JNI.
- **Crypto and sync:** P-256 + AES-GCM + the platform's TLS, replacing Ed25519 and our Noise. Protocol v2 (entry ID
  without sig), with a one-time migration.
- **Drawings:** a grid-indexed path store, with CPU tiles composited by the GPU (measured on the laptop and a Note 9;
  tools/m6).
- **Photos, QR:** JPEG XL only, with libjxl everywhere (including our own WebAssembly build); zxing-cpp for QR.
- **Security:** encryption at rest with a per-device key in the platform key store; Argon2id on the server.
- **Courses:** re-authored in a JSON content model with declarative figures.
- **Distribution:** Windows: self-signed MSIX trusted once by IT (no Microsoft Store: the user's registration was
  blocked, 2026-10-03; 0022); Linux: Flatpak (Flathub).

**Phase 1 started 2026-09-30:**
- `docs/PROTOCOL-v2.md` (v2 spec; v1 PROTOCOL.md stays frozen).
- `ref/` = the test-only Python v2 reference (proto2, replay2, crypto2, make_v2_vectors).
- `ref/vectors/v2-*.json`: core, replay (incl. the v1 import), malformed, crypto. FROZEN once the Nim core uses them.

Spec details settled while writing:
- peer ID = the first 24 bytes of SHA-256 of the uncompressed P-256 key; the key sits in each device's seq-1 entry;
- entry ID excludes `sig`; copies sharing an ID are valid if any copy verifies;
- the v1 import uses sorted [key, value] pairs.

- `docs/PATHSTORE.md` + `ref/pathstore.py` + `ref/vectors/pathstore-v1.json`: the .kkp grid path store; measured on
  all 11 sheets with `tools/m6/pathstore_measure.py` (5.6 MB vs 8.0 MB of PDFs; hairline policy differs from MuPDF on
  purpose).
- `docs/COURSES.md` + `ref/courses.py` (validator + figure evaluator) + `ref/vectors/courses-v1.json` (valid, 54
  rejects with codes, frame scripts, unit cases). Figures = a value graph (tables, sum, product, select, follow,
  hold) bound to shapes, flows of particles on routes; no expressions. `tools/m6/course_figures.py` converts all 16
  animated figures (206 KB compact) and compares 22 states side by side with the original JS in headless Chromium
  (`~/.cache/ms-playwright/chromium_headless_shell-1243/…/chrome-headless-shell --no-sandbox`; the snap
  chromium-browser isn't installed): geometry, labels and texts match; simplifications listed in COURSES.md §12.
  Not frozen until a second implementation passes the vectors.

**Phase 2 started 2026-09-30:** the Nim core in `core/` (README there; `cd core && nim test`, 37 tests).
- Decision 0029 (accepted): crypto through a provider interface (`crypto.nim`; GnuTLS on GNOME/Linux in
  `provider_gnutls.nim`, CNG on Windows and Java through JNI on Android still to write); our own strict JSON reader;
  zlib linked; small hand-written `importc` bindings with the `header` pragma (the C compiler checks them); std/unittest.
- **Strict reading added to PROTOCOL-v2 §1:** reject duplicate keys, trailing commas, leading zeros, raw control
  characters, unpaired surrogates, BOM, trailing bytes, depth > 128. Nim's std/json accepts all of these. Vectors
  `ref/vectors/v2-json.json` (`ref/sjson.py` = Python's parser with hooks, an independent reader).
- **Passing:** every vector file (v2-json, v2-core, v2-crypto, v2-replay, v2-malformed, pathstore-v1, courses-v1),
  byte-identical state bytes and ECIES output. Local checks with plant data in /tmp only: all 11 sheets' .kkp
  re-encode to the Python reference's bytes, and the 16 real figures match the Python evaluator on 192 frames.
- **Lessons:**
  - Nim identifiers ignore case after the first letter, so `jbool` clashed with the enum `jBool`. JSON constructors
    are now `newBool`, `newObj`, and so on.
  - GnuTLS can't import a bare P-256 scalar, so `PrivateKey` = scalar + public point.
  - `gnutls_free` is a macro; call it as `(gnutls_free)(p)`.
  - Course-text rounding expands the double exactly (mantissa × 5^k), because C's printf rounds ties to even.
- **Measured:** replay of 2019 entries 282 ms, of which 222 ms is ECDSA verification (GnuTLS 0.11 ms per signature;
  Python/OpenSSL does the whole replay in 243 ms).
- **Not done yet:** the CNG and JNI providers, the sync state machine (§15), core CI, and the importer in Nim (0026).

Phase 2 also added: the §15 sync session as a sans-I/O state machine (`sync.nim`), the node (`node.nim`), the
local API (`api.nim`, a port of LocalApi), invites, progress, plant data, bundles. `core`: 61 tests. Still to
write: the CNG and JNI providers, core CI.

**Phase 3 (2026-09-30/10-01): Linux platform layer + server** (`platform/linux/`, decision 0030; `nim test`: 18, incl. 4 relay tests and the dual-stack listener since 2026-10-02).
- **Building blocks:** SQLite store with sealed rows (`dbstore`), TLS 1.3 over GnuTLS with peer-ID pinning
  (`tls`), sync over TCP (`net`), Argon2id via OpenSSL plus a scrypt check of v1 hashes (`argon2`), mDNS through
  Avahi's D-Bus (`mdns`).
- **`kks_server`:** v1's HTTP routes for the unchanged web pages, setup link, users, publish-data, import-v1,
  backup.
- **Deployment:** `deploy/kks-server.service` (systemd-creds storage key).
- **Tests:** `e2e/test_server_http.py`, 3 tests: the flow, login throttling, Drawings.
- **Migration dry run:** `tools/m6/migrate_v1.py` on a copy of the real plant.db came out identical (copies
  deleted).

**Phase 4 (2026-10-01): importer in Nim, the 0026 gate met** (`importer/`, README there; `nim test`: 11 synthetic
checks).
- **The gate:** `kks-import` reproduces the Python importer bit for bit on all 11 sheets:
  - orientation scores, 5,350 crops/masks, 27,847 glyphs (incl. every kNN similarity), 2,130 tags;
  - 3.5 min single-threaded against Python's 11 min on 11 processes;
  - LP: 203 of 207 stored tags read the same, the 4 others go to review.
- **MuPDF 1.28.2** built from pinned source (`fetch_mupdf.sh`). OpenCV ops ported from 5.0.0 source; numpy's
  OpenBLAS kernel order in `kks_dot.c`.
- **Writes:** `.kkp` (vectors byte-identical to ref/pathstore), overview pyramid `sheets/<id>.o<k>.jxl` (spec in
  PATHSTORE.md), the source PDF, sheets.json/tags.json.
- **Glyph library:** `importer/fontlib.kgl` (docs/GLYPHLIB.md; first exported from the Python pickle, see git history).
- **The Nim server's Drawings:** runs `kks-import` (config `importer`, `plant_dir`, `backup_dir`, `glyphs`), with
  backup/restore and publish.
- **Local gate:** `importer/tests/dump_*.py` + `diff_*.nim`, references outside the repo.
- **Lessons:**
  - The Python reference depends on OpenBLAS's thread count: chunk-boundary rows use another kernel, 1 ulp off.
    Gate against `OPENBLAS_NUM_THREADS=1`.
  - cv2's labels follow 2×2 blocks (Spaghetti), not pixels.
  - cv2's GaussianBlur on float32 uses FMA (AVX2 build), even in its scalar tail.
  - Nim builds an array literal in place: `a = [x, a[0]]` reads the overwritten a[0] (broke a SHA-256).
  - Embedded JPEGs: Pillow (libjpeg-turbo) and MuPDF decode differently, up to 84 levels; the importer follows
    MuPDF.

**Phase 5 (2026-10-01): GNOME app** (`apps/gnome/`, README there; decision 0031).
- **Build:** GTK 4.22 + libadwaita 1.9 through hand-written bindings; headers via `apt-get download` into
  ~/.local/kksdev/root.
- **What works:** the viewer (pyramid + Cairo vector tiles + hotspots), search, the equipment panel with editing,
  review and photos (annotate → JXL d1.9), missed-tag marking, procedures with link mode, the review queue, the floor
  filter, notes, Manage (approvals, proposals, history, people, devices with invite QR / nearby / request file /
  bundle, account with root key backup), all ways of joining, the sync service (listener, mDNS, auto rounds), the
  status line.
- **Tests:** `apps/gnome/e2e/test_gnome.py` drives the app through AT-SPI against the Nim server (~30 s, no plant
  data).
- **Measured** (docs/m6/MEASUREMENTS.md, rules written first): startup 315 ms, 248 MB RSS, 2.8 MB binary.
- **Not done:** the Flatpak build (manifest written and validated; no flatpak-builder/SDK here), webcam QR, courses
  (after phase 8's conversion).
- **Lessons:**
  - Nim closures in loops share variables: use `closureScope` over indexed copies.
  - Never let a Nim exception unwind through GLib: the trampolines catch and log. One escaped and silently killed
    every timer.
  - A dialog built during an AT-SPI action had no accessibility contents: handlers run from idle.
  - `pkill -f` patterns match your own shell: anchor them (`^/tmp/...`).

**Phase 6 (2026-10-01): Android v2** (`android/app2`, `android/nim`; README in app2; decision 0032 + addendum).
- **Build:** the Nim core as `libkks.so` (NDK 27, SQLite amalgamation compiled in) behind a small JNI surface. Crypto
  goes through the JCA, the device key lives in AndroidKeyStore, and TLS 1.3 in Kotlin pins the peer ID.
- **Screens (Compose):** setup with four ways to join, drawings (pyramid, vector tiles, hotspots, marking, floors,
  notes, search), the equipment panel (edit, review, photos with annotation → JPEG XL), procedures with link mode, the
  review queue, Manage (approvals, proposals, history, people, devices with the invite QR from zxing-cpp, account).
- **Sync service:** listener, NSD with TXT, rounds, and a WorkManager worker every 15 min.
- **New protocol piece:** PROTOCOL-v2 §16 `enroll` over TLS, so passwords never travel in clear text.
- **Removed devices wipe themselves (§15):** core `Hooks.wipe(by)`, used on Android and in GNOME (which re-executes).
- **Tests:** `android/app2/e2e/test_app2.py` (emulator + Nim server, synthetic sheet; ~80 s): join, search, edit
  synced, approval on the phone, removal and wipe.
- **Also verified on the emulator:**
  - procedure linking;
  - an Arabic proposal approved on the phone;
  - a photo round trip (1600×1200 JXL, arrow burned in);
  - marking a missed tag;
  - "Ask an admin" against the server (codes match);
  - the background worker with the app closed;
  - a GNOME laptop joining through the phone's invite;
  - the QR decodes (OpenCV).
- **Lessons:**
  - NimMain must run on the core thread.
  - Compose dialogs without the platform default width get no insets.
  - The old v1 app on the same emulator was the "8491" sync noise.
- **Not verified (needs the Note 9 and the Honor 600):** camera QR, TalkBack, real Wi-Fi discovery, Honor's
  background limits, all measurements (rules in docs/m6/MEASUREMENTS.md).

**Phase 7 (2026-10-01): Windows** (`apps/windows`, `platform/windows`; README in apps/windows; decision 0033).
- **Toolchain:** mingw-w64 13 / GCC 13 cross-compile on this machine (`~/.local/kksdev/mingw`). Libraries come from
  `platform/windows/build-deps.sh` (zlib, libjxl, zxing-cpp; pinned SHA-256). One static 14 MB exe.
- **Core and platform:**
  - `provider_cng.nim` (+ `kks_cng.c`): CNG crypto; device key in the NCrypt software key store; our own P-256 curve
    check, since CNG's import check isn't documented;
  - `kksw/tls` (Schannel through buffers, the same API as GnuTLS's `kksl/tls`): `net.nim` is shared;
  - `kksw/mdns` (DnsService API) and `kksw/keystore` (DPAPI);
  - `apps/common/appstate.nim` is now shared by GNOME and Windows.
- **App:** Win32 controls + a Direct2D view (tiles on worker threads, the drawing's tags as UIA buttons via
  `kks_uia.cpp`), the GNOME app's screens (setup, drawings, panel, procedures, review, Manage with the invite QR,
  photos from a file with the mark-up editor).
- **Test VMs:** Windows 10 22H2 (unactivated, the user's choice) and Windows 11 26H2 evaluation, under QEMU/KVM;
  `apps/windows/e2e/vm/make-vm.sh` (unattended, OpenSSH, auto-logon).
- **Tests:**
  - core + platform tests pass in both VMs;
  - TLS negotiates 1.2 on Windows 10 and 1.3 on Windows 11 [V];
  - `apps/windows/e2e/test_windows.py VM_IP` drives the app through native UIA (`uiadrive.exe`): join, a tag
    invoked via UIA, search + panel, an edit synced, a marked-up photo (its JPEG XL on the server checked for the box),
    an approval, removal + wipe. 9 of 10 runs passed (the one failure was not kept).
- **Measured (VMs, WARP):** startup to the first sheet 390 ms (10) / 268 ms (11), 45 MB private memory.
- **Lessons:** in decision 0033's findings (handlers after notifications, WideCString lifetimes, UIA COM threading,
  the numeric manifest resource type, the Windows 11 Terminal handoff).
- **Not done:** camera and webcam QR (no camera in the VMs), MSIX packaging, a real laptop, CI (needs the user's OK
  to push).

**Phase 8 (2026-10-01): web client + courses** (decisions 0034, 0035).
- **v2 viewer in index.html** (0034): path store tiles from `tiles.js` (module Worker), JXL pyramid; verified in all
  three engines (`platform/linux/e2e/test_web_v2.py`). `/?kks=CODE` opens that equipment (course links).
- **Escaping audit:** a stored XSS in admin.html (full name inside an inline handler, live since v1) fixed with
  `jsa()`; the v1 Android APK in the field still carries the old admin.html.
- **Courses converted:** `tools/m6/convert_courses.py dump RAW` (Playwright evaluates each HTML course) then
  `build RAW OUT` (HTML → runs/blocks, the 10 static SVG diagrams → static figures, the 16 animated ones from
  course_figures.py, WebP → JXL d1.9, shared photos deduplicated). Output in `data/courses/`: `ppt.json`, `fnd.json`,
  `hrsg.json` (305/208/214 KB) + 28 `.jxl` (4.5 MB). Question counts match v1 (88/96/83); drill rules are checked
  against the original JS judging functions; static diagrams compared pixel-wise with the original SVGs.
- **Format additions** (COURSES.md, not frozen): module `bridge` {title, intro, questions}; test items by reference
  `{module, ref}`. Vectors regenerated; Python, Nim core and course-figure.js all pass them.
- **Web renderer** (0035): `course.html` + `course.js` (pages, DOM + textContent only) + `course-figure.js`
  (evaluator port + Canvas 2D) + `course.css` (the original courses' stylesheet). Progress keys unchanged
  (`<id>.solved` …), course-bridge.js takes the id from `?c=`. Nim server `/api/courses` (core `courses.summary`);
  learning.html lists JSON courses there, else v1's. Tests: `tests/web/test_course_figure.py` (vectors in 3 engines),
  `platform/linux/e2e/test_course_web.py` (every page of every course, figures drawn, answers, order, test, drills,
  decoder, keyboard answer; 3 engines).
- **Lesson:** a sync() inside the frame loop scheduled a second rAF each frame: callbacks multiplied, 8 fps; fixed by
  marking the loop busy (60 fps).
- **Native course renderers** (decision 0036; results there): GNOME (GtkLabel markup + Cairo/Pango), Windows
  (RichEdit from escaped RTF + Direct2D/DirectWrite, WOFF2 faces unpacked by DirectWrite on 10 and 11), Android
  (Compose, figure ops recorded in the Nim library and replayed on the canvas). Shared: `apps/common/figdraw.nim`,
  `apps/common/coursestate.nim`, core `courses.pickCourses`/`summary`. Each app's e2e has a `test_courses`; all pass
  (GNOME, Windows 10 + 11, Android emulator), and the existing flows still pass.
- **Windows wipe flake:** `disk I/O error` after a removal: the restarted process opened the DB while the old one was
  still closing it. Now the old process closes the store before starting the new one and exits at once; opening
  retries briefly; the wipe overwrites deleted rows (secure_delete) and retries VACUUM. Before: 3 of 6 full
  Windows runs failed (2 of them a test race on the photo blob, also fixed); after: 6 of 6 passed (3 per VM).
- **Own WebAssembly build** (decision 0037): `platform/web/build-wasm.sh` (pinned emsdk 6.0.10, the same pinned
  libjxl/zxing-cpp sources as native; SIMD + scalar; full 3.6 MB / decode-only 0.74 MB; reproducible) →
  `vendor/kks/`, used through `kks-wasm.js` (+ `kks-wasm-worker.js` for encoding). Browsers now **encode photos to
  JXL themselves** (effort 7: ~1.2 s for 1.9 MP on this laptop); the Nim server/core refuse non-JXL photos when they
  have no encoder (they had stored JPEG before: a 0018 gap). QR read: BarcodeDetector first, else zxing-cpp; QR write
  (admin invite) through zxing-cpp. Removed `vendor/jxl` (@jsquash), `vendor/jsqr`, `qrcodegen.js`.
  Test: `platform/linux/e2e/test_web_wasm.py` (3 engines).
- **Accessibility:** course pages keyboard-tested in 3 engines (rail, answers, order question, slider; roles and
  names); index.html search is now a combobox/listbox and a pick moves focus to the panel heading; the Windows pages
  scroll a Tab-focused control into view. Not done: TalkBack, Narrator, Orca themselves.
- **Android figure faces:** TTF copies (`tools/build_courses.py --ttf`, vendor/fonts/ttf).

**v2 internet sync (2026-10-02, decision 0038):** the relay pipe on every native target, no hole punching yet (this
side sends `cand: []`; PROTOCOL-v2 §18: an empty list on either side = straight to the pipe).
- **Code:** `platform/linux/src/kksl/ws.nim` (WebSocket client, shared with Windows), `internet.nim` (presence, connect,
  `syncOver`/`serveOver` from `net.nim` over the pipe); the server answers through it, the GNOME/Windows rounds also
  sync relay-online devices that no LAN sync reached. Web trust: GnuTLS `newWebTlsConn` (system CAs, SNI, host name),
  Schannel `kks_tls_new_web` (auto validation). Android: `core/Relay.kt` (WsClient with HTTPS endpoint identification,
  `EngineTls` = SSLEngine over the pipe), `sync/Internet.kt`, core route `/native/relay` signs the hello. Manager field
  "Internet relay" in Manage → Account on all three apps. The Worker accepts v2 hellos (deployed 2026-10-02 with the
  user's OK; v1 tests still pass against it).
- **Verified:** `platform/linux/tests/test_internet.nim` against the Python twin, `wrangler dev` and the deployed Worker
  (Linux, Windows 10 TLS 1.2, Windows 11 TLS 1.3); the Honor 600 on mobile data only synced both ways with the server
  through the deployed Worker (phone edit on the server 7.2 s after Save). The relay URL is in memory, never in tracked
  files.
- **Lessons:** GnuTLS says "again" after a TLS 1.3 session ticket while records wait (keep reading while it consumes);
  send a TLS handshake step's output before waiting (TLS 1.2 hung on Windows 10); workerd lists a closing socket during
  `webSocketClose` (the Worker never said `left`); `pkill -f "wrangler dev"` in a command that contains that text kills
  the shell itself.
- **Not done then:** hole punching + reliable UDP (0028; done on Linux/Windows/server 2026-10-03, below); a phone on
  mobile data skips private LAN addresses, laptops don't.
- **Also 2026-10-02:**
  - The Nim server now fills `/api/devices.sync` in v1's shape (`discovery`, `syncs`, `found`, `internet`) and its own
    addresses for invites. Before, admin.html's Devices page said "Cannot reach the server" (a TypeError shown as a
    network error) and invites were refused.
  - Sync listeners are dual-stack (`listen` address "" = `::` with IPV6_V6ONLY off, else IPv4), and clients dial IPv4
    or IPv6 (`connectTcp`). mDNS hands out IPv6 addresses, which the IPv4-only listener refused. Tested on Linux and
    Windows 11.
  - On real phones: the camera QR join worked on the Honor. TalkBack reads the drawing's tags on the Honor ("…, read
    automatically, button, double tap to activate"), although uiautomator's dump on MagicOS lists none of them.
  - e2e scripts can leave `kks_server` processes behind after failures: check with `pgrep -af kks_server`.
  - Android course pages (the user's Note 9 report): pictures were decoded on the main thread on every scroll into
    view, and figure frames waited on the core thread from the main thread. Worst of all, drawing a figure's vector
    ops on the view canvas made the render thread re-rasterize every path each frame (13.6 ms per frame, against
    4.5 ms for a plain list). Now: pictures are decoded on IO into an LRU cache; frames are computed on
    Dispatchers.Default; a figure is drawn as vectors only while it plays and the page is still (smooth playback:
    60 fps, p99 18 ms), else as one bitmap of the last frame rasterized in the background (`LocalScrolling`; frames
    pause while the page moves). Rasterizing every animation frame on the CPU made playback stutter (the user's second
    report). LazyColumn items carry contentType. Module 3 of course 2 went from 73 % janky frames (p90 38 ms) to
    43–48 % (p90 20 ms), the level of a text-only page on that phone.
  - Picture boxes are computed in a `layout` modifier: `fillMaxWidth().heightIn(max).aspectRatio()` asked for a size
    outside the constraints, and Compose drew the picture over the items above and below.
    Measured with `dumpsys gfxinfo` (+ `setprop debug.hwui.profile true` for the per-stage split; set it back).
  - Also from that report: table columns sized to content (text columns share what is left and wrap); number
    columns centered (the user's choice) with tabular figures, headings wrap when a table is too wide; a one-line course title so "N of M solved" fits; Material vector
    icons in the bottom bar (`Glyphs`) with one shared label size that shrinks until "Procedures" fits; pictures
    open full screen with pinch/double-tap zoom (`ZoomImage`).

**Done 2026-10-03 (agreed with the user 2026-10-02):**
1. **Webcam QR scanning in the GNOME and Windows apps** (decision 0039). GNOME: `kks_camera.c` (camera portal →
   `OpenPipeWireRemote` fd → GStreamer `pipewiresrc` → GRAY8 appsink; `v4l2src` without a portal), dialog in
   `camera.nim`, button "Scan with the camera…" on Join with a code. GStreamer headers in ~/.local/kksdev/root (`.pc`
   prefixes rewritten like GTK's). Windows: `kks_camera.cpp` (Media Foundation Source Reader, RGB32 → grey on a worker
   thread; mfplat/mf/mfreadwrite loaded at run time so N editions still start; `initguid.h` for the GUIDs), scan
   window in `camera.nim`, zxing-cpp reader `kks_qr_decode` in kks_qr.cpp. `KKS_CAMERA_FILE` plays a video through the
   same pipeline (tests; `apps/gnome/e2e/make_qr_video.py` makes one with OpenCV + ffmpeg).
   Verified: GNOME test_scan_camera (video file) and the real webcam through the portal on this laptop (frames,
   no permission prompt for the unsandboxed app); Windows 10 + 11 test_scan_camera (video through MF), the VM
   without a camera says so, and this laptop's webcam passed into the Windows 11 VM (`virsh attach-device` USB
   13d3:5463, detached after) delivered frames. Verified 2026-10-03 with the user: GNOME scanned the Note 9's invite
   QR through the laptop webcam and joined the measurement plant ("testingqrcamera · vivobook-s14x"). NOT verified:
   the same on Windows with a real webcam and a real QR (waits for the borrowed laptop).
2. **Diagnostics reports to the manager** (decision 0040, PROTOCOL-v2 §13a): entry type `report` {sealed} (ECIES to
   the setting `diagnostics.key`, purpose `kks-report`); the report key's private half is a `private` entry
   (`report_key`) of the manager. `core/src/kks/diagnostics.nim` (record with repeat counts, maybeReport ≤ 1 per 6 h,
   ≤ 32 KB, enable/disable, readReports), `/api/diagnostics` GET/POST (server mode refuses the switch), config
   `diagnostics`. Hooks: appstate (unexpected sync failures, "no successful sync for 24 h", report after each round),
   GNOME/Windows `errorHook` in the callback guards, server HTTP 500s + hourly report, Android
   `sync/Diagnostics.kt` (uncaught-exception handler → crash.txt → recorded at the next start, sync failures, report
   after rounds). UI: Account → Diagnostics reports (state; the manager's switch) and Manage → Diagnostics (reports,
   Copy / Copy all) on all three apps. Vectors `ref/vectors/v2-reports.json` (new; older files unchanged); Python
   reference + Nim core agree. Tests: core test_diagnostics (6), Android e2e test_diagnostics (debug-only
   `DebugDiagReceiver`). Connection-level failures (refused, timed out) are not recorded: a device that is off is
   normal.
3. **Honor 600 background sync:** in the `rare` standby bucket the worker never ran in 1 h unplugged
   (MEASUREMENTS.md). A second hour forced to `active` didn't help: MagicOS forces the app back to `rare` (reason `f`)
   seconds after it leaves the screen. Third hour (2026-10-03 08:40): the app on the battery-optimization exemption
   list ("Unrestricted", `cmd deviceidle whitelist +kks.explorer.v2`): bucket `exempted` (5), still no run: only
   Honor's `HN_USER_EXPERIENCE` constraint unsatisfied. Fourth hour (MagicOS "App launch" set to manual by the user):
   bucket stayed `active`, but the job lost its JobScheduler registration after its run (WorkManager diagnostics:
   SyncWorker ENQUEUED with Job Id null; `adb shell am broadcast -a androidx.work.diagnostics.REQUEST_DIAGNOSTICS -p
   kks.explorer.v2`), and the system log shows "job is prohibit by iaware" for many apps' jobs (iAware = MagicOS's
   power manager). Conclusion: on Honor, background sync every 15 min is not reliable whatever the app does within
   Android's rules; foreground service / FCM push rejected (battery, notification, Google dependency). Built instead
   (2026-10-03): `Sync.backgroundLimit` (isBackgroundRestricted, standby bucket ≥ rare, or the worker hasn't run for
   3 h although scheduled that long: SyncWorker records `worker_last` / `bg_since`) → a notice in Manage → Account
   with a button to the app's system settings, and a diagnostics event. Verified on the Honor (forced `rare` bucket,
   restored).

**Cutover prep (2026-10-03, asked by the user; plan in https://github.com/5wHN28Dg/kks-explorer/wiki/Cutover-2026-10-03):**
- **Server install:** `deploy/install-server-user.sh` builds into `~/kks-server/app/<version>-<commit>` (`current` /
  `previous` links), writes `~/kks-server/config.json` once, seals the storage key with `systemd-creds --user`
  (`storage-key.cred`, TPM) and writes the user unit `~/.config/systemd/user/kks-server.service`
  (`LoadCredentialEncrypted`). Ran once (not started; unsealing checked).
- **v1 copy:** `~/kks-server/v1` holds a checked copy of the live plant.db, root.key, photos, backups and plant-data
  (102 files, SHA-256 equal). Nothing in the repo was touched.
- **Drawings:** `kks-import SOURCE.pdf "" ID --keep-tags --data-dir D` re-makes a sheet's .kkp and pyramid but keeps
  its v1 tags, notes, name and rotation. It checks the size before writing anything. Verified on a /tmp copy: all 11
  sheets the same size, all 1,379 tags identical.
- **Distribution:** no Microsoft Store (the user's registration was blocked); Windows = self-signed MSIX trusted by IT,
  or the zip (0022). Flatpak manifest `apps/gnome/flatpak/io.github._5wHN28Dg.kks_explorer.yml`:
  - GNOME 50 runtime;
  - zxing-cpp 3.1.1 built in (`-d:flatpak` links `-lZXing` from /app/lib);
  - Nim via `koch boot`;
  - built here with flatpak-builder `--disable-rofiles-fuse` in ~/.local/kksdev/flatpak;
  - bundle `kks-explorer.flatpak` 6.7 MB (10.6 MB installed). The GNOME e2e passes against the installed Flatpak and
    the bundle (`e2e/flatpak-app.sh`; apps/gnome/README).
- **MSIX (decision 0043):** `packaging/windows/make-msix.sh`:
  - MakeAppx from the pinned NuGet `Microsoft.Windows.SDK.BuildTools`, run in the Windows VM;
  - signed here with osslsigncode (Ubuntu's 2.13, unpacked into ~/.local/kksdev/root: no sudo).
  The Windows e2e passes against the installed package on 10 and 11 (`KKS_WIN_MSIX`, `KKS_WIN_MSIX_CER`). Installs
  need the desktop session (`e2e/msix.ps1`). Signed with the real certificate `CN=Walkdown` since the rename
  (`~/.config/kks-explorer/signing/windows-msix.*`; the user must back it up).
- **Sync timing fixes (found by the e2e tests):**
  - **Desktop:** the automatic round's timer fired while another round ran (Sync now). It skipped that round and set
    the next one 2 minutes away, so a change made just before waited minutes (`appstate`: no turn while `syncing`).
  - **Android:** a round after a change was skipped while another ran, and waited for the 2-minute timer. Now one
    more round runs right after (`again`).
- **Desktop sync logging:** each sync's result, with its photo counts, goes to stderr (flushed). The Windows test
  keeps it per script: `C:\kks\app-<script>.log`.
- **Test fixes:**
  - the GNOME e2e: the shots folder, a retry when the Devices page rebuilds under a click, the wipe check by name;
  - the Windows e2e: the photo's file name is read again until its blob arrives (`file` is "" before);
  - the Android e2e tests start without the old app installed;
  - the bridge says "nothing to move" after a completed move.

**Direct connections (2026-10-03, decision 0028):**
- **Core:** `core/src/kks/rudp.nim` is the reliable UDP, sans I/O and wire-compatible with v1's `peer/rudp.py` /
  `Rudp.kt`. "Never sent" is `at = -1`: a send at time 0 is real.
- **Platform:** `platform/linux/src/kksl/udp.nim` (shared with Windows) has one receive loop per socket, STUN
  (Cloudflare, Google), punching (PUNCH/PUNCH_ACK) and `rudpStream` as a `net.Stream`.
- **Relay client:** `internet.nim` tries direct first. Both sides offering candidates → punch with session = the
  first 8 bytes of the connect id, else (or on failure) the pipe. `lastHow` = direct/relay. Its `roomOf` and `askPeer`
  serve §21a.
- **Tests:**
  - core test_rudp: a simulated lossy link, v1's cases;
  - test_internet: direct, and the pipe when one side has `direct = false`;
  - test_rudp_interop against `tools/rudp_peer.py`.
- **Android (2026-10-03):** `sync/Direct.kt` (the socket, STUN, punching; the stream's logic is the core's
  `rudp.nim` through JNI `Core.rudpStep`: datagram in, timers, bytes out, finish, free → packed result). TLS over it
  via `Net.overRaw`, which `overPipe` now uses too. `Internet.kt` tries direct first; `lastHow` is shown in
  Manage → Account. Verified on the emulator: `android/app2/e2e/test_direct.py`. The phone joins, the server
  restarts with its LAN sync port closed, and the server's change arrives through the relay twin (adb reverse) over
  the direct path.
- **Field finding (2026-10-03, the first two phones that moved, both on mobile data):**
  - **What happened:** the direct path punched through, then stalled on every sync ("the other device stopped
    answering"). Nothing fell back to the pipe, so their handed-over changes never reached the server.
  - **The fix (0.9.1):** a failed direct sync runs again at once through the pipe, and that device gets the pipe for
    an hour. It is in `Internet.kt` (Android) and `internet.nim` (desktop), with test switches `Direct.testStall` /
    `Internet.testStall`.
  - **Tests:** test_internet.nim "stalls after punching" and android/app2/e2e/test_direct.py
    `test_stalled_direct_falls_back`.
- **Test lesson:** `adb install -r` of an older version fails quietly after test_update's 9.9.9. The Android e2e tests
  now uninstall first and assert the install, because earlier runs had silently tested a stale build.
- **Real NATs studied (2026-10-04, decision 0028 "Field test"):** a carrier NAT that maps per destination against a
  home router that filters by address and port: plain punching can't work, and no side has global IPv6, so the pipe
  is the expected path for phones on mobile data. Fixed: each sync's fallback from its own path (the shared `lastHow`
  raced); a punch that hears nothing = that device on the pipe for an hour (no 4 s per sync); the stream follows an
  address change (the first desktop version shadowed `host` after `flush` captured it: a test now covers it); stalls
  log the rudp state. Desktop status lines show "last sync direct / through the relay".
- **Android tests and the user's phone:** the Android e2e tests uninstall `io.github.walkdown` on whatever device adb
  sees, and debug builds share that ID. The user's Honor holds their real account: run them only with
  `ANDROID_SERIAL=emulator-…`, and never install/clear anything on the Honor.

**Phone move without help (2026-10-03, decision 0042, PROTOCOL-v2 §21a; the user's choice "Bridge update, new ID").**
- **Flow:** 0.8.0 → "Download and install" → the bridge (the v1 app built at the release's VERSION) → it installs
  `kks-explorer-2.apk` from the same signed release → the new app asks the bridge (`Bridge.Handover`, a provider
  behind a signature permission) for the plant's addresses and relay → it gets the succession statement from the server.
  The bridge checks the statement against the v1 root, signs the move proof with the v1 device key, and hands over its
  open changes after its archived seq, with photo files, request notes and course progress. The new app sends
  `migrate`, syncs, then writes the changes through core `submitBody` (client_id = v1 entry ID: written once).
- **Server:**
  - `import-v1` keeps the v1 device table (custodial keys flagged `server`);
  - `migrate_v1.py succession` + `kks-server import-succession`;
  - `succession`/`migrate` sync hooks with GnuTLS Ed25519 verify (`provider_gnutls.ed25519Verify`, server only);
  - presence in the v1 relay room (`internetV1`, `Internet.roomOf`);
  - mDNS TXT `prev`;
  - `/api/devices.sync.v1_waiting` (admin.html "Moving from the old app").
- **New package ID** `io.github.walkdown` lives in `android/app2` applicationId, `Bridge.NEW_APP` and both manifests'
  `<queries>`.
- **Tests:**
  - `platform/linux/tests/test_migrate.nim` (8: statement, proofs, tampering, refusals, the relay room; v1 plant from
    `tools/m6/v1_test_plant.py`);
  - `android/app2/e2e/test_move.py`, the full rehearsal on the emulator: v1 server, the old app joins as tom (debug
    `DebugApiReceiver`), the server stops, a photo + link offline, migration, the bridge installs the new app from a
    fake signed release, the move, both changes in the Nim server's Approvals with note + JXL file, the bridge shows
    "Remove the old app", no duplicates after a restart. Passed twice.
- **Lessons:**
  - `pm clear` leaves an app stopped: broadcasts need `-f 32` or a start first;
  - `logcat -s TAG:I TAG:W` hides info lines;
  - the Android 16 install dialog says "INSTALL".
- **NOT verified:** release-signed builds (only debug-key builds), a real phone, the relay path on a phone.

**Walkdown updates itself on Android (2026-10-03, decision 0044):**
- **Signing:** the same GitHub release and `release.json`, plus `release.json.p256`: an ECDSA P-256 signature over
  `"kks-release-v2\n"` + the manifest, by `~/.config/kks-explorer/signing/release-p256.pem`. Its public key is pinned
  in `sync/Updates.kt` and `tools/release.py`; `release.py --yes` signs both and publishes without asking.
- **In the app:** a daily check, a banner with Install, and Manage → Account → Updates. The download is checked
  against the manifest, then goes to PackageInstaller (the person confirms).
- **Tested:** `android/app2/e2e/test_update.py`, on a fake release. A wrong key offers nothing; the right one installs
  0.8.0 → 9.9.9. The newer APK is built with `-PkksVersion=9.9.9`. Debug builds allow clear text to 10.0.2.2 only
  (`src/debug/res/xml/debug_network.xml`).
- **Rehearsal builds:** build type `rehearsal` in both apps (`assembleRehearsal`): the release with R8 shrinking,
  debug-signed, plus the debug test receivers. test_move, test_update and test_app2 passed on them before 0.9.0.

**2026-10-04 (the user's field notes on 0.9.2, among others):**
- **Rotated sheets:** kks-import wrote the .kkp of every rotated sheet turned against its overview and tags (since the
  cutover; the Python reference had the same mix-up). Fixed with `kkp.sheetExtra` = −(rot + page /Rotate), a test of
  all 16 combinations, the 7 sheets re-made live (plant data v4).
- **Server CLI:** `publish-data` in a second process wrote to the store, but the running server never saw it (new
  sheets reached no device until a restart; the two copies of the manager's chain could have forked: none did). Now
  `publish-data` and `set-plant-name` go through the server's 0600 Unix socket (decision 0045). The plant's name is a
  manager setting (`/api/settings/plant`, admin page Devices → Plant name; "" = none). `reset-password` /
  `reset-manager` are in the CLI's help but were never written.
- **Android APK:** arm64-v8a only in releases (18 MB), x86_64 in debug/rehearsal for the emulator; libraries stay
  uncompressed; no 32-bit phones (decision 0046; a Galaxy A02s is 32-bit only).
- **Android photo editor:** full-screen dialogs clipped their bottom (window between the bars, content at full screen
  height): `FullScreenDialogWindow()` in Common.kt (also the photo viewer and course pictures). Undo/Retake/Cancel/Send
  in a row of their own; Retake; tag plate photos = caption starting "Tag plate" (a convention: 0.9.x rejects unknown
  photo fields; PROTOCOL-v2 §9), offered after an equipment photo. e2e `test_photos` (emulator camera).
- **Fit button** on Android (bottom right) and Windows (side panel); GNOME had one.
- **New drawings:** b1circ and cwp (plant data v6); the booster pump drawing has no KKS and was left out (the user).

**2026-10-04, second batch (the user's list):**
- **Photo coverage view** on all four UIs (Android ⋮ menu, GNOME header, Windows side panel, web 📷): tags coloured
  green both / amber equipment only / blue tag plate only / red none; core `model.photoCover`, `tagsView.photos`.
- **Photo editor** on all four: zoom (−/+/Fit, wheel, two-finger pinch and pan, right-drag), three line sizes (per
  mark; Windows `Mark.size` in kks_d2d.cpp), and a touch-only loupe (Android pointer type, GNOME the drag's device
  source, Windows WM_POINTER PT_TOUCH, web pointerType). Tested: web 3 engines (synthetic pointers), Android emulator
  (`input motionevent`, the loupe's ring in a screenshot), Windows 11 VM (uiadrive `touchdrag` = InjectTouchInput, the
  stroke in the server's JXL). NOT tested: two-finger pinch on Android/GNOME/Windows, the GNOME loupe.
- **Server CLI** (decision 0045): `reset-password`, `reset-manager` (root `manager` statement; the old manager becomes
  admin), `submit-file` (submissions as the manager through /api/submit's checks; client_ids dedupe).
- **Procedures from other documents:** `tools/procedure_import.py` (public) + a private spec in
  `~/kks-server/state/imports/<id>/` → procedures.json entry with `source` (shown instead of "manual page"), and
  link/photo/equipment-field submissions. EP-06.27 (draining before start-up) imported live.
- **ARM64** (decision 0047): Windows cross-built here with llvm-mingw (`KKS_WIN_ARCH=aarch64`), Walkdown-arm64.msix
  signed here; `.github/workflows/arm64.yml` builds walkdown-aarch64.flatpak and tests on GitHub's ARM64 runners.
- **GNOME tests headless:** `apps/gnome/e2e/headless.sh` (private mutter); never on the user's desktop.
  - **A private test session must isolate `XDG_RUNTIME_DIR` as well as D-Bus and the display.** A nested
    `dbus-run-session` that shares `/run/user/$UID` spawns its own portals, which take over and then tear down the
    desktop's mounts and sockets: the first version of headless.sh started a second `xdg-document-portal` that
    unmounted `/run/user/1000/doc` when it ended, and every Flatpak app on the user's desktop stopped starting
    (`bwrap: Can't find source path …/doc/by-app/…`). headless.sh now runs in a fresh 0700 runtime directory and
    unmounts what the private portals left there.
  - **After any change to a test harness that starts sessions, compositors or D-Bus**, check the user's session for
    side effects before and after: `findmnt /run/user/$UID/doc` (the same mount ID), `ls /run/user/$UID` (nothing
    added or gone), `journalctl -b | grep run-user-$UID-doc.mount` (nothing new), and a Flatpak app's sandbox
    starting (`flatpak run --command=true app.zen_browser.zen`). "Nothing shared with the desktop" has to hold for
    everything in `/run/user/$UID`, not just the bus and the display.
- **Diagnostics:** reports are sealed to the manager's report key: the server and its web pages can't read them
  (0040); read them on the manager's phone (Manage → Diagnostics, Copy all).

## Backlog (rough priority)

1. When users have marked missed tags (the log's `tag_add` entries), find why the reader missed them and fix the cause
   in the Nim importer.
2. Verify a random sample of auto tags per new sheet; build per-sheet verified references like LP.
3. Valve type from symbols (gate/globe/check/motorized/safety) — template-match the legend symbols near each tag.
4. Extract instrument descriptions from the FW/LP junction-box panels (English text next to each instrument).
5. Suggest procedure→equipment links (system code + description matching), user confirms.
6. Attach PDF markup annotations to nearby tags instead of sheet-level notes.
7. Calibration UI in the app for new fonts (label unknown glyph clusters instead of doing it by hand).
