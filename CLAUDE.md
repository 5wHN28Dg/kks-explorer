# Walkdown (formerly KKS Explorer): project context for Claude Code

Built by an I&C maintenance engineer at a combined-cycle power plant. Goal: given only a KKS code (e.g. `11LAB70AA501`),
find the equipment on the P&IDs and see everything known about it: decoded meaning, location, photos, notes, and the
operation-manual procedures that use it. Also: pick a procedure and see its steps with the equipment highlighted.

The user prefers direct, no-fluff communication and honest pushback. Be explicit about what is verified and what isn't.

**Public repository.** No plant name, plant data or plant-specific notes in tracked files. Those live in the manager's
plant-data working copy (gitignored) and `CLAUDE.local.md` (gitignored: the plant, reader accuracy per sheet, findings on
the drawings). The deployed relay's URL never goes in tracked files or the wiki. NEVER commit plant data, `plant.db`,
`photos/`, `backups/`, `config.json` or `root.key`.

**Names and IDs.**
- **Platform IDs:**
  - Android `io.github.walkdown` (the code namespace stays `kks.explorer.v2`);
  - Flatpak `io.github._5wHN28Dg.walkdown`;
  - MSIX `Walkdown` (exe `Walkdown.exe`, alias `walkdown.exe`);
  - release APK `walkdown.apk`.
- **Unchanged on purpose:** every protocol string (`kks-…` signature domains, relay rooms, `_kks._tcp`, ALPN,
  vectors), the deployed relay, and the GitHub repository name.

**Where documentation goes (the user, 2026-10-03).**
- Guides, how-tos, operations, history and research go in the **wiki**
  (https://github.com/5wHN28Dg/kks-explorer/wiki; clone https://github.com/5wHN28Dg/kks-explorer.wiki.git).
- The repository keeps only what code and tests point at: the specs (`docs/PROTOCOL-v2.md`, `PATHSTORE.md`,
  `COURSES.md`, `GLYPHLIB.md`), `docs/decisions/`, `docs/m6/` (requirements, capability matrix, measurements) and each
  component's build README.
- The wiki is public too.

## Engineering guidelines

`~/Documents/GitHub/Personal-LLM-prompts/skills/evidence-first-engineering/SKILL.md` governs architectural, stack and
dependency decisions, for native code and for what runs in a browser engine alike. The full reasoning is in its
`reference/` folder; open it only when a rule's reasoning is genuinely in question. In this project:
- Native: the Android app (`android/app2`), the desktop apps, any iOS work, and the server.
- Web: index.html, admin.html, learning.html, common.js, sw.js, course-bridge.js, the courses, vendor/. The pages are
  served by the server to browsers and ship no engine. They must also work in Safari, since that is the iOS path
  (https://github.com/5wHN28Dg/kks-explorer/wiki/iOS-research).
- The capability matrix is a file here: `docs/m6/CAPABILITIES.md`. Keep it current (this line is the request SKILL.md
  waits for before writing one).

## How to work
- Work on a branch and open a PR. Never push to main. Wait for CI to pass, then merge.
- Before saying a task is done: build, lint and test locally, then make sure CI is green.
- Every bug fix gets a test that fails without the fix. Every new feature gets a test of its main path.
- When finished, have a fresh subagent review the diff for bugs and security problems. Give it the task and the diff,
  not your reasoning. Fix what you can confirm in the code.
- Never weaken a safeguard to get something working: no skipping or deleting tests, disabling CI jobs, loosening lint
  rules, adding suppressions, or relaxing security settings.
- If a check fails for a reason outside your change (new vulnerability advisory, scanner update, flaky test, download
  error): upgrade to a fixed version if a non-major one exists. Otherwise stop and report what's failing. Stopping
  beats working around a safeguard.
- Report in plain language, five lines max: what changed, how you tested it, anything I need to decide.

**CI** (`.github/workflows/`):
- `policy.yml`: the secrets scan (gitleaks), dependency vulnerabilities and licenses (osv-scanner,
  `license-allowlist.txt`, `osv-scanner.toml`) and static analysis (Semgrep with HTML/URL-sink rules), pinned to a commit
  of github.com/5wHN28Dg/policy (keep that repository public). They read the README's `Tier:`/`Type:` lines. A PR that
  changes `.gitleaks.toml` needs a `Secrets config change: <reason>` line in its description. main requires these three
  checks.
- `android.yml` and `arm64.yml` build the apps (actions pinned by SHA).

## The system

- **Core** (`core/`, Nim, sans I/O): protocol v2 (`docs/PROTOCOL-v2.md`), the log and replay, the §15 sync session
  (`sync.nim`), the node, the local API (`api.nim`), invites, plant data, courses, diagnostics, reliable UDP
  (`rudp.nim`).
  - Crypto goes through a provider interface: GnuTLS on Linux, CNG on Windows, the JCA through JNI on Android.
  - The strict JSON reader rejects duplicate keys, trailing commas, leading zeros, control characters, unpaired
    surrogates, BOM and trailing bytes.
- **Linux platform and server** (`platform/linux/src/kksl/`):
  - the SQLite store with sealed rows (`dbstore`), TLS with peer-ID pinning (`tls`), sync over TCP (`net`), the relay
    client and direct UDP (`internet`, `ws`, `udp`), Argon2id (`argon2`), mDNS through Avahi (`mdns`);
  - the HTTP server (`httpserver.nim`, a modified copy of Nim's asynchttpserver with limits);
  - `kks_server` itself, which serves the web pages and API on 127.0.0.1 only. Remote browsers come through an HTTPS
    proxy or tunnel, with `public_url` (https) and optionally `trusted_proxy`.
- **Windows platform** (`platform/windows/src/kksw/`): Schannel TLS, CNG keys, DPAPI, DnsService; `net.nim` is shared
  with Linux.
- **Importer** (`importer/`, Nim + MuPDF 1.28.2 from pinned source): `kks-import` reads the tags from vector P&IDs
  and writes the `.kkp` path store, the JPEG XL overview pyramid and sheets.json/tags.json.
  - `--keep-tags` re-makes a sheet's drawing files without touching its tags.
  - The glyph library is `importer/fontlib.kgl`.
- **Apps:**
  - GNOME: GTK 4 + libadwaita through hand-written bindings (`apps/gnome`);
  - Windows: Win32 + Direct2D (`apps/windows`);
  - Android: Compose over `libkks.so` built from the Nim core (`android/app2`, `android/nim`);
  - shared desktop code: `apps/common`;
  - web client: index.html, admin.html, learning.html, course.html, common.js, sw.js, tiles.js. Views are built as
    elements (`K.h`), never markup.
- **Relay:** a Cloudflare Worker (`relay/`); `relay/twin.py` is the test twin.
- **Courses:** a JSON content model with declarative figures (`docs/COURSES.md`, `data/courses/`), rendered natively
  on each platform and on the web.
- **Photos and QR:** JPEG XL everywhere (libjxl, and our own WebAssembly build in `vendor/kks/`); zxing-cpp for QR.

## Live deployment (on this laptop)

- **Server:** runs as a user service from `~/kks-server` (`systemctl --user`, linger on; build in `app/current`, the
  previous one in `app/previous`; installed by `deploy/install-server-user.sh`). The store's key is sealed with
  systemd-creds.
- **CLI:** `KKS_CONFIG=~/kks-server/config.json ~/kks-server/app/current/kks-server <cmd>`. The commands
  `publish-data`, `set-plant-name`, `reset-password`, `reset-manager` and `submit-file` reach the running server through
  its 0600 control socket. Other commands need the sealed credential (wiki: Server).
- **Plant data working copy:** `~/kks-server/state/plant-data`.
  - **New drawing:** back it up first, then `kks-import PDF "Name" id --data-dir … --glyphs
    ~/kks-server/app/current/fontlib.kgl`, check orientation and tags by eye, then `publish-data`.
  - Backups are in `~/kks-server/state/backups/`.
- **The plant root key** is inside the server. An encrypted backup and its passphrase are in
  `~/.config/kks-explorer/signing/walkdown-root.{kksroot,passphrase}`.
- **Keys and releases:** keys are in `~/.config/kks-explorer/signing/` (wiki: Releasing).
  - `tools/release.py` publishes a GitHub release with `release.json` + `release.json.p256` (ECDSA P-256 over
    `"kks-release-v2\n"` + manifest); the app pins that key (`sync/Updates.kt`).
  - Android releases are arm64-v8a only. Windows: a self-signed MSIX (`CN=Walkdown`), no Microsoft Store.
    Linux: Flatpak.
- **Diagnostics reports** are sealed to the manager's report key: read them on the manager's phone (Manage →
  Diagnostics, Copy all); the server can't.
- **Left for the user to decide:**
  - the v1 leftovers on this machine: `~/kks-server/v1`, `~/kks-server/archive`, the store's `v1*` rows, the old
    Ed25519 release key, and the v1 server files in this repository's root (gitignored);
  - the deployed relay still accepts v1 hellos until it is redeployed.
- The repository's history before the M5b rewrite (with plant data) is kept privately in
  `~/kks-explorer-history-before-M5b.bundle`.

## Build and test

- **Where to work:** `/tmp` is wiped when the laptop restarts. Put worktrees under `~/kks-work/` and build outputs
  under `~/kks-work/build/`. Commit and push as soon as a change passes its tests.
- **Nim:** `~/.nimble/bin/nim` (choosenim; put it on PATH).
  - Core: `cd core && nim test`.
  - Platform and server: `cd platform/linux && nim test`; the server is `nim c -d:release -o:OUT/kks_server
    kks_server.nim`. `test_internet` uses the relay twin (needs `.venv`).
  - Windows tests: `nim wintests` cross-builds them (`KKS_WIN_OUT`).
  - Importer: `cd importer && nim test` (MuPDF from `fetch_mupdf.sh`). Tests that need an importer can use
    `~/kks-server/app/current/kks-import`.
- **Python** (tests and tools only, `.venv` from `requirements-dev.txt`): `.venv/bin/python -m unittest discover -s
  tests`; `ref/` is the independent reference used to make the vectors.
- **Server and web end to end:** `platform/linux/e2e/test_server_http.py SERVER` (`KKS_IMPORT` for the drawings
  test). Web e2e: `test_web_v2`, `test_web_wasm`, `test_course_web`, `test_web_stale`, `test_web_local_login`,
  `test_admin_web`, plus `tests/web/`. All run in Chromium, WebKit and Firefox (Playwright; `KKS_SERVER`).
- **GNOME:**
  - build: apps/gnome/README;
  - e2e: run headless only, never on the user's desktop: `apps/gnome/e2e/headless.sh /usr/bin/python3
    apps/gnome/e2e/test_gnome.py APP SERVER IMPORTER` (system Python, for AT-SPI). APP must be a file named
    `kks_explorer` (or the Flatpak): the wipe check finds the restarted app by that name, and a build copied to
    another name fails test_flow with "the removed device did not wipe itself";
  - pinch regression: `e2e/viewer_pinch.nim`, also under headless.sh;
  - after changing anything that starts sessions, compositors or D-Bus, check the desktop is untouched before and
    after:
    - `findmnt /run/user/$UID/doc` (same mount ID);
    - `ls /run/user/$UID`;
    - `~/.local/share/keyrings`, `~/.local/share/flatpak/db`, `~/.config/dconf/user`;
    - a Flatpak app's sandbox starting.
- **Windows:** apps/windows/README.
  - Cross-built with mingw-w64 (and llvm-mingw for ARM64).
  - VMs `kks-win10` and `kks-win11` under virsh, reached with `ssh -i ~/.ssh/kks_vm kks@IP` (PowerShell); find the
    address with `virsh domifaddr`.
  - e2e: `apps/windows/e2e/test_windows.py VM_IP APP UIADRIVE SERVER IMPORTER`.
  - Relay tests in the VM: ws:// is refused except to loopback (#56), so run the twin here and tunnel it: `ssh -i ~/.ssh/kks_vm -R PORT:127.0.0.1:PORT kks@VM` and set `KKS_RELAY_URL=ws://127.0.0.1:PORT` in the VM.
- **Android:** android/app2/README.
  - The Gradle wrapper is in `android/`: `./gradlew :app2:assembleDebug`. Check the APK's timestamp after building;
    a failure hidden by `-q | grep` once left the tests running a stale APK.
  - Rebuild `libkks.so` (`sh android/nim/build.sh`) after any core change, and commit it.
  - Emulator: AVD Pixel_9_Pro_XL, `JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64`. Start it in its own capped scope
    with guest rendering:

    ```
    systemd-run --user --scope -p MemoryMax=8G -p MemoryHigh=7G ~/Android/Sdk/emulator/emulator \
      -avd Pixel_9_Pro_XL -no-window -no-audio -no-snapshot-save -no-boot-anim -gpu guest
    ```

    The default host GPU path crashed every few minutes on this Iris Xe; swiftshader was too slow (System UI ANR).
  - The e2e tests (`test_app2`, `test_direct`, `test_update`) uninstall and reinstall `io.github.walkdown`. Run them
    only with `ANDROID_SERIAL=emulator-…`: the user's Honor holds their real account; never install or clear anything
    on it.
  - `test_update` needs a second APK built with `-PkksVersion=9.9.9`.
  - Some helpers ignore the arguments and use `/tmp/kkslinux/kks_server` and `/tmp/walkdown-9.9.9.apk`. /tmp is
    emptied at every reboot: link both again first, or the tests fail with FileNotFoundError.
  - After the emulator has hung and been restarted, the first runs can fail (test_update did 3 times in a row on a
    build that then passed 5 of 5). Re-run before blaming the change.
- **Memory:** this laptop has 37 GB. Never run the emulator and a Windows VM together, and keep at most two
  heavy background jobs (builds, browsers, emulator) at once. An OOM once took the user's GNOME session down.
- **Leftover processes:** `pkill -f` patterns match your own shell's command line. Kill by PID, or anchor the pattern
  (`^/home/...`). e2e scripts can leave `kks_server` or relay twins behind after a failure: check with `pgrep -af`.

## How extraction works (and why)

P&IDs are AutoCAD plots: no text objects, no layers, every character is loose vector strokes (SHX fonts), many glyphs
split into several paths, box edges are zero-height paths. The importer (`importer/src/kksi/`: mupdf, reader, fontlib,
extract, textlines):
1. Normalize orientation: try 0/90/180/270, keep the one with the most horizontal text lines. The score can't reliably
   tell upright from upside-down, so check new sheets visually.
2. Detect tag containers: render at 200 dpi; contour holes are box or bubble halves; pair stacked cells. Size window
   H 4–24 pt, W 15–110 pt.
3. Read each half at 600 dpi: trim border blobs with the contour mask, split characters by column projection, classify
   each glyph by kNN against the glyph library, then family rules (C/G, B/8, 0/D/Q).
4. KKS grammar:
   - `DDLLLDD` over `LLDDD[L]` = equipment;
   - ISA letters over `DDLLLDDLLDDD[suffix]` = instrument;
   - I→1 / O→0 only in digit slots;
   - confidence = the lowest character confidence.
5. A second pass reads open-ended instrument bubbles from long vector text lines.

Lessons (don't repeat):
- General OCR (Tesseract) on this condensed SHX font produced confident wrong KKS after grammar coercion. Removed.
- Per-glyph geometric rules tuned on one font break another. Prefer adding labeled samples to the library over new
  rules. Re-check the LP sheet after any reader change.
- Test reader changes with a harness that pins the OLD behaviour in the script itself. Importing the edited module as
  "old" silently compares new with new. Compare every tag cell old vs new on all sheets and look at every changed crop.
- Checking a new sheet by eye works well with contact sheets of exact tag crops labelled with the reading; zoom into
  the PDF for small vertical bubbles and for characters that touch a box edge.

## Lessons by area

- **Nim:**
  - identifiers ignore case after the first letter (`jbool` clashed with `jBool`);
  - closures in loops share variables (use `closureScope`);
  - an array literal is built in place (`a = [x, a[0]]` reads the overwritten `a[0]`);
  - `gnutls_free` is a macro: call it as `(gnutls_free)(p)`;
  - GnuTLS can't import a bare P-256 scalar (PrivateKey = scalar + point).
- **Async I/O:**
  - `withTimeout` leaves its timer in the dispatcher until it expires: never one per read. Use one deadline per
    connection (`httpserver.nim` Alarm).
  - asyncnet's `send(string)` has no closed check: a write after close goes to whatever socket now has that descriptor
    number.
  - On Windows an async `connect` binds the socket itself, so binding a source address first fails.
- **GTK (GNOME app):**
  - A signal's trampoline must match its signature: `on` takes none, `onPtr` one object, and a gboolean return needs a
    returning trampoline (`onCloseRequest`). A gesture's `begin` passes the event sequence, NULL for a touchpad pinch;
    the wrong trampoline crashed on pinch.
  - Never let a Nim exception unwind through GLib (the trampolines catch and log).
  - Dialogs built during an AT-SPI action have no accessibility contents: build from idle.
  - The viewer draws vector tiles at every zoom (the overview is a placeholder); zoomed out, the thinnest line is half a
    device pixel.
- **TLS and sync:**
  - GnuTLS says "again" after a TLS 1.3 session ticket while records wait (keep reading).
  - Send a TLS handshake step's output before waiting (TLS 1.2 hung on Windows 10).
  - A responder accepts only small frames until the other side is trusted, and ends a stranger after 60 s.
  - Listeners are dual-stack (mDNS hands out IPv6).
- **Direct connections and the relay:**
  - A carrier NAT that maps per destination can't be punched, so phones on mobile data use the pipe.
  - A direct sync that stalls falls back to the pipe at once, and that device keeps the pipe for an hour.
- **Android:**
  - NimMain runs on the core thread.
  - The canvas refuses bitmaps over 100 MB, so overview levels are drawn in pieces of at most 2048 px.
  - Decode pictures on IO and keep figure frames off the main thread.
  - On MagicOS (Honor) background sync every 15 min is not reliable within Android's rules. The app shows a notice
    with a button to the system settings instead (no foreground service, no FCM).
  - `adb install -r` of an older version fails quietly: the tests uninstall first and assert the install.
  - `pm clear` leaves an app stopped: broadcasts need `-f 32`.
  - `logcat -s TAG:I TAG:W` hides info lines.
- **Web:** a `sync()` inside the frame loop scheduled a second rAF each frame (8 fps). The service worker reads only
  its own caches and deletes any other.
- **Importer:**
  - The Python reference depends on OpenBLAS's thread count (gate against `OPENBLAS_NUM_THREADS=1`).
  - cv2 labels follow 2×2 blocks, and its float32 GaussianBlur uses FMA.
  - Embedded JPEGs decode differently in Pillow and MuPDF: the importer follows MuPDF.
  - A rotated sheet's `.kkp` must follow `kkp.sheetExtra` = −(rot + page /Rotate).
  - The overview is rendered with the annotations baked in; tags are read without them.

## Backlog (rough priority)

1. When users have marked missed tags (the log's `tag_add` entries), find why the reader missed them and fix the cause
   in the importer.
2. Verify a random sample of auto tags per new sheet; build per-sheet verified references like LP.
3. Valve type from symbols (gate/globe/check/motorized/safety): template-match the legend symbols near each tag.
4. Extract instrument descriptions from the FW/LP junction-box panels (English text next to each instrument).
5. Suggest procedure→equipment links (system code + description matching), the user confirms.
6. Attach PDF markup annotations to nearby tags instead of sheet-level notes.
7. Calibration UI in the app for new fonts (label unknown glyph clusters instead of doing it by hand).
