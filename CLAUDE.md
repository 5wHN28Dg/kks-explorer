# KKS Explorer — project context for Claude Code

Tool built by an I&C maintenance engineer at a combined-cycle power plant. The repository is meant to become public
(M5b): no plant name, plant data or plant-specific notes in tracked files. Those live in `plant-data/` (the manager's
working copy, gitignored) and `CLAUDE.local.md` (gitignored: the plant, reader accuracy per sheet, findings on the
drawings). Goal: given only a KKS code (e.g. `11LAB70AA501`), find the equipment on the P&IDs and see everything known
about it: decoded meaning, physical location, photos, notes, and which operation-manual procedures use it.
Also: pick a procedure ("Preparations for Startup — Air Compressor System") → see its steps and highlighted equipment.

The user prefers direct, no-fluff communication and honest pushback. Be explicit about what is verified vs not.

## Development policy: evidence-first (in force from 2026-09-30)

Two documents:
- `docs/evidence-first-platform-engineering.md` governs native code: the Android shell (`android/app`), the desktop
  package and M6, any iOS work, and the server/peer processes.
- `docs/evidence-first-web-engineering.md` governs what runs in a browser engine: index.html, admin.html, learning.html,
  common.js, sw.js, course-bridge.js, the courses, vendor/.
- The Android app's WebView and the desktop's system browser count as the web platform: the pages ship no engine. The
  same pages must also work in Safari, since that is the iOS path (docs/IOS_RESEARCH.md).

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
- **Keep business logic platform-independent** (`peer/`, `android/core`): platform code stays a thin adapter, tested
  on the platform.
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

## Run

- `python3 app.py` → http://localhost:8420 (phone: printed LAN URL, same Wi-Fi). Stdlib + `cryptography` (since M1,
  2026-09-26; system python here has it, else `.venv/bin/python app.py`). Photos as JPEG XL need Pillow +
  pillow-jxl-plugin (optional; without them photos stay as uploaded, `app.py check` warns). `vendor/` = third-party
  browser code served publicly (jxl decoder, jsQR), each with README + SHA256SUMS. First run prints a one-time setup link to
  create the manager (also creates `root.key`). CLI: `users`, `reset-manager --user X`, `reset-password --user X`,
  `backup`, `restore [--seq N] [--out F]`, `export-root-key --out F`, `import-root-key --file F`, `added-tags`,
  `publish-data [--from DIR]`.
  Settings: `config.json` (see `config.example.json`, `server/config.py`).
- Tests: `.venv/bin/python -m unittest discover -s tests` (116, incl. 16 for protocol v2 in tests/test_protocol_v2.py, 3 strict JSON, 6 path store, 6 course format; server end-to-end over HTTP, protocol vectors,
  migration, sync, peer mode, join by invite, reliable UDP, internet sync, plant data, self-updates). Base.tearDown asserts the server never wrote an entry the replay ignores and a fresh replay matches.
  `peer/vectors/v1.json` is FROZEN (the Kotlin port must match it byte for byte); `test_file_is_frozen` fails if
  `peer/make_vectors.py` would change it. Add new vectors in a new file rather than editing v1. The UI was verified with Playwright
  in a throwaway venv (not committed): setup, invite, user proposal, offline queue + offline reload via the service
  worker, sync, approve/pick/force, revert, lease expiry, deactivation wipe.
- Adding sheets: `python3 app.py setup-importer` once (creates `.venv` from `requirements-import.txt`; the server stays
  stdlib and runs the importer as a subprocess with `.venv`'s python, or `import_python` in config). Then Manage →
  Drawings (upload, live log, preview, re-import with rotation, remove) or
  `.venv/bin/python import_sheet.py drawing.pdf "Name" [id] [--rotate …] [--replace] [--data-dir D]`.
  `server/sheets.py`: one job at a time; backs up sheets.json/tags.json (+ the sheet image) to
  `backups/sheets-<time>-<why>-<id>/` and restores them on failure; uploaded PDFs kept in `backups/sheet-sources/`.
  Sheet changes are logged in revisions as entity `sheet` (log only, not revertible). Sheet image URLs carry `?v=`
  so re-imports bypass the service worker's cache-first image cache.
  Auto rotation: text-line score picks among 0/90/180/270; if <25% of found tags auto-read, retry +180° and keep the
  better (upside-down text reads as garbage: Reheat forced to 270° read 0/101, at 90° 73/141). Verified: fresh LP
  import reproduces all 188 unique auto KKS of the existing LP sheet exactly.

## Layout

- `app.py` — HTTP handler + CLI. `server/`: `config.py` (settings), `store.py` (SQLite, journaled writes, snapshots,
  restore), `auth.py` (scrypt passwords, hashed session/one-time tokens, login throttling), `engine.py` (the signed
  log: `entries` table, custodial device keys per account in `custodial`, root key file, in-memory replay via
  `peer/replay.replay_run`, advanced per entry; `revoke`/`root` entries or entries from another process (CLI; seen by
  `refresh()` = entry count) → full replay, trusted=own DB so no re-verification: 20k entries 0.18 s),
  `changes.py` (submissions, conflicts, approve/pick/reject/withdraw/vote, History, revert, restore-to, all as log
  entries), `migrate_v1.py` (one-time move of a pre-log DB, see below).
- Plant data = the log (M1, 2026-09-26). Tables: `entries` (journaled), `custodial`, `subs` (submission number ↔
  entry, `client_id` idempotency; *held* admin changes that conflict or wait live only here, not in the log),
  `blobs` (photo sha → file; photos stored as `photos/<sha256>.<ext>`), `entry_notes` (History notes), `users` (+
  `person`, `device` columns; `role` mirrors the log), sessions, tokens, meta (`root_pub`, `log_version`), `revisions`
  (now only local `user`/`sheet` notes). The old live tables (equipment, photos, reviews, links, added_tags,
  submissions, votes) stay in the schema only for migration/old snapshots. Write via `with E.tx() as c:` +
  `E.append(c, device, type, body)`; journaled tables still via `store.put/delete`. API shapes unchanged (payloads ↔
  bodies in `engine.py`: tag bbox tenths ↔ px, photo_id/id ↔ photo/tag). History = replay's `run.history` + local
  notes, numbered 1..N in time order (numbers shift only if entries with older clocks arrive: M2).
- Rules on top of the protocol: a value set/approved by the manager can't be overwritten by an admin (403, not a
  silent no-op); forced approvals of held admin changes are rebased on the live value (no conflict record);
  deactivating revokes the account's custodial device at its last seq, reactivating certifies a new device;
  manager handover = root `manager` statement (needs `root.key`, checked when offering); `reset-manager` also uses it.
- Migration (`migrate_v1.py`): first start on a DB with users but no `log_version`. Copies the DB to
  `backups/plant-v1-<time>.db`, rebuilds history from the revision log with original times/people (user proposal +
  admin approve, admin entries, rejects/withdraws, votes, revoke for inactive accounts), keeps submission ids and
  client_ids, replays before committing and aborts on any difference (root.key only written after commit).
  Fixture `tests/fixtures/v1` was written by the OLD code (`tools/make_v1_fixture.py` runs commit 2d5fbdc).
  Real plant.db dry run (copy, 2026-09-26): 8 entries, 7 marked tags identical. The live plant.db is migrated on the
  next server start (not done yet).
- Accounts carry `full_name` (required for new accounts, setup and Users → Add) and `position` (optional), 2026-09-26.
  Existing DBs get the columns on startup (`store.migrate`, also run on restored snapshots before journal replay).
  Self-service: Account → Your details (`POST /api/profile`); admins edit users' details (`POST /api/users/<id>`,
  same who-manages-whom rule). Submissions carry `by_name`; History shows full names; `app.py users` lists them.
- One manager, enforced by a partial unique index. Only created by the console setup token, an accepted transfer, or the
  `reset-manager` CLI. Admins manage users only; the manager manages admins.
- Public: `index.html`, `admin.html`, `common.js`, `sw.js`, manifest, icons, `/api/config`, login/setup/password-link
  endpoints. Everything under `/data`, `/photos`, other `/api` needs the session cookie (HttpOnly, SameSite=Strict).
  POSTs must be JSON with a same-origin (or `public_url`) Origin.
- `common.js` — login gate, IndexedDB (cached `me` + offline lease, outbox), submit/flush, status. `sw.js` caches the
  shell and plant data (`kks-data` cache, wiped on logout/401). Service workers need HTTPS or localhost.
- Remote access (decided 2026-09-24): Cloudflare Tunnel + Access, not Tailscale (Tailscale's free plan is
  non-commercial; per-user app install; HQ laptops). Guide: `docs/REMOTE_ACCESS.md`; templates in `deploy/`
  (cloudflared config with `originRequest.access.required`, hardened systemd unit, remote config). App side: listen on
  127.0.0.1, `public_url` https, `secure_cookies`; HSTS sent when public_url is https; `app.py check` audits it
  (`server/check.py`). An expired Access session makes fetches fail like a network error: `K.accessExpired()` probes
  `/api/config` with `redirect:'manual'` (opaqueredirect = Access), and sw.js marks cached fallbacks with
  `X-KKS-From-Cache: offline|reauth` so the client shows "Sign in again" vs "Offline". Verified with Playwright against
  a fake Access proxy (redirect to another origin), not against real Cloudflare.
- Missing-tag marking (2026-09-25): ✎ button → drag a box on the sheet → submission kind `tag_add` {sheet, bbox (sheet
  px), kks+suffix (optional), isa, note}; `tag_remove` {id}. Approved → table `added_tags` (entity `added_tag`, logged,
  revertible); `/api/state.added_tags`; index.html `mergeTags()` appends them to TAGS as ids `u:<id>` (status
  verified, or review when no code), so they survive re-imports and work with photos/notes/links/review like any tag.
  Pending marks draw dashed (`.pendmark`). Admin approve accepts `edit:{kks,isa}` for tag_add (Approvals shows a crop).
  `python3 app.py added-tags` dumps them as JSON: feed these back into extractor fixes. Verified with Playwright.
- `admin.html` — Approvals (grouped by target, photo pick), My submissions (+ voting), Users, History, Account.
- `index.html` — whole front end, vanilla JS, no build step. Pan/zoom viewer, hotspots, panel (floating on desktop,
  bottom sheet ≤720px), search, floor filter, procedures drawer + step↔equipment linking, review queue, sheet notes.
- Plant data (published by the manager, PROTOCOL.md §19; working copy `plant-data/`, served as `/data/…`):
  `sheets.json` — `{id,name,file,vector,rot,w,h,notes[]}`; images in `sheets/*.png` (grayscale, ≤6400px),
  vectors in `sheets/<id>.svg.gz` (served as `<id>.svg` with Content-Encoding gzip). `rot` = rotation applied to
  the source PDF. Sharp zoom (2026-09-25): `extractor/svgopt.py` bakes per-path transforms and merges all black paths
  per style (PyMuPDF SVG: 40k–140k paths → 13–134; pixel-identical in Chromium 1×–125×). index.html draws it on
  `#sharp` canvas (between `#stage` PNG and `#stage2` hotspots) ~150 ms after the view settles, only when
  view.s·dpr ≥ 0.7; CSS-transforms the old drawing while panning. Max zoom 16× with a vector, 4× without.
  `tools/make_vectors.py ID source.pdf` makes one for an existing sheet: picks the rotation matching the PNG and
  checks alignment by phase correlation (all 11 sheets within 0.9 px). Firefox redraw ~250 ms on desktop.
- `tags.json` — one entry per tag occurrence:
  `{id:"sheet:n", sheet, kks, suffix, isa, kind:equipment|instrument, status, conf, bbox:[x0,y0,x1,y1] (image px),
    orient:h|v, read:[top,bottom] (raw reader output), note, flag, suggestion}`.
  status: `auto` (reader, conf ≥0.3) · `verified` (checked by eye) · `review` (needs a human). User decisions live
  in plant.db `reviews` and override tags.json at runtime (`eff()` in index.html). Equipment data is keyed by full KKS
  (kks+suffix), so the same item on several sheets shares data.
- `procedures.json` — 77 procedures parsed from the HRSG Operation Manual (English steps, parent path, page).
- `locations.json` — 360 rows from `source/KKS LOCATION HRSG.pdf` (level/elevation, cabinet, description, direction),
  built by `tools/parse_locations.py`. The list has no unit prefix → matched on KKS without the 2-digit unit, and on the
  base KKS for suffixed tags (R/K/D). Used as a fallback under the user's own equipment data; never written to plant.db.
  Known issues of the plant's list: CLAUDE.local.md.
- `data/kks.json` (ships with the program, public) — decode tables: system codes (from the legend printed on the P&IDs), component codes, ISA letters, unit prefixes.
- `extractor/` — the tag reader (see below). `fontlib.pkl` = labeled glyph library (~13.8k glyphs).
- `tools/` — manual parser and the calibration scripts used to build the glyph library (written for a scratch
  workspace; paths like `norm/`, `calib/`, `ext/` need adapting).
- NEVER commit or overwrite `plant.db` / `photos/` / `backups/` / `config.json` / `root.key`: field data, server
  state and the plant root key.
  (`plant.db` was committed once in 7c840ac, empty; it has been untracked since.)

## How extraction works (and why)

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

## Multi-user: open items

- Remote access is prepared but NOT live: needs written IT/security approval, a domain, a Cloudflare account and an
  always-on server on the IT (not OT) network. Nothing in the repo can be tested against real Cloudflare until then.
- Offline copies can't be revoked from a device that never reconnects (lease only locks the UI; data isn't encrypted,
  since the key would sit on the same device).
- Rejected/withdrawn photo files stay in `photos/` (no cleanup command yet).
- Sheets imported before 2026-09-25 have image URLs without `?v=`; re-importing one gives it a version.

## v2: server mode + P2P (decided 2026-09-26)

`docs/ARCHITECTURE.md` is the plan of record (supersedes `docs/PLAN_B_P2P.md`). Key decisions: every device runs a
local peer; signed per-device append-only logs + deterministic replay/merge (no host, no election; the server is an
always-on peer); same-Wi-Fi + file/QR sync first, internet P2P later (M5); Android = Material 3 native shell + the
existing web P&ID viewer in a WebView; Windows/Linux = this Python app packaged (double-click, opens browser; the
stdlib-only rule ends for the package: cryptography + zeroconf); one person may have several devices (device keys +
certificates). Build order M0 protocol spec + Python reference + test vectors → M1 server on the log → M2 desktop
package + LAN/file sync → M3 Android → M4 Learning (3 HTML courses, not yet in the repo) → M5 internet → M5b plant data out of the app, public
repo, self-updates (2026-09-28) → M6 fully native desktop in Nim, no browser (added 2026-09-27; details decided when
we get there) → M7 research iOS via Pythonista 3 / Pyto / iSH / a-Shell (2026-09-28; done 2026-09-30, before M6:
docs/IOS_RESEARCH.md: no as a peer (no background, no mDNS, crypto only in Pyto), yes as a browser client of the server
over HTTPS; nothing tried on a real iPhone).
Answered 2026-09-26: plant Wi-Fi allows device-to-device traffic; courses in `source/courses/` (3 single-file HTML,
localStorage progress, Google Fonts to vendor); quiz progress private (encrypted to the person's devices); photos
on-demand or all, per device, stored as JPEG XL (no JPEG fallback since 2026-09-27: viewers without JXL decode it with libjxl); manager key: no second
holder (self-held backup recommended). M0 done: `docs/PROTOCOL.md` §1–7 `peer/proto.py` + `peer/vectors/v1.json` (M0a); §8–14 `peer/replay.py` +
`peer/vectors/v2-replay.json` (M0b: identity, authority, revocation by priority, approvals, merge, private entries;
generator `peer/make_replay_vectors.py`, 3 scenarios). Both vector files frozen; tests in `tests/test_protocol.py`.
Root key: laptop + backup, not the phone (PROTOCOL.md §10: only a root-signed revoke settles a stolen same-person device).
M1 done 2026-09-26 (server on the log, see Layout). M2a done 2026-09-26: sync (PROTOCOL.md §15): `peer/noise.py`
(Noise_XX_25519_ChaChaPoly_SHA256, own implementation, matches the cacophony vector `peer/vectors/noise-xx.json`),
`peer/sync.py` (handshake with Ed25519-signed static key, hello with vv {device: [seq, head id]}, entries, want/blobs,
bye), Engine node methods (identity, vv, entries_for, may_read, ingest with trial replay: only entries of devices
certified after the batch are stored; fork evidence table `evidence`; `_after_ingest` adds `subs` rows for proposals
that came by sync + mirrors roles into `users`), blob_put only for referenced hashes. Server listens on `sync_port`
(8421, 0 = off); `app.py sync HOST[:PORT]`. Vectors `peer/vectors/v3-sync.json`. Verified: tests/test_sync.py (real
TCP between separate DBs: join, relay, stranger, other plant, photo, revoke, cloned key) + two app.py processes
(propose on one, approve over HTTP on the other, sync back). History rows carry a stable `hid` (entry-based);
revert/restore use it, numbers are display-only.
M2b done 2026-09-26 (decided: no password on your own laptop; both join ways; auto sync; admin-only unencrypted
bundles, encryption later). `mode: 'peer'` in config: HTTP bound to 127.0.0.1 + Host check (DNS rebinding) + loopback
client; `user()` = `E.owner()` (users row made from the log for the node's own device, meta `node_device`, key in
`custodial`). First screen (common.js `K.joinScreen`): join via server (`server/node.py` → server
`/api/devices/enroll` = password check + device_cert by the person's custodial key, then sync), join request
(`.kksjoin`, signed by the device key; admin imports in Manage → Devices → `/api/devices/import-request`, 409
`existing` needs existing_ok) + bundle (`/api/bundle` admin GET, `/api/bundle/import` raw gzip; a node without a
plant adopts the bundle's root), or a new plant (genesis with `device=` node key). `server/syncsvc.py`: listener,
zeroconf `_kks._tcp` (TXT peer, root[:16]; re-announced when identity/plant changes, serialized), auto sync every
`sync_interval` and 5 s after local changes, status for `/api/devices`. Deactivating an account revokes ALL its
devices; `/api/persons/<pid>` manages people with no account here. Bug found by a restart test and fixed:
migrate_v1 ran on a joined laptop (no log_version) and made a second genesis → now only on DBs with no entries,
log_version set on genesis/adopt, genesis refuses a node that has a plant. Verified: tests/test_peer.py, 2-3 real
processes with mDNS on one machine (two-way auto sync ~6 s, restart), Playwright (join screen, Devices, request →
bundle, Users). Not verified: two different machines on the plant Wi-Fi.
M2c done 2026-09-26: `desktop.py` (entry point: config in the user folder, `data_dir` = the program's bundled data,
free port fallback, second start only opens the browser, Tk window Open/Quit → `app.ON_READY` hands over httpd,
shutdown + snapshot; log file when windowed; `--self-test` in a temp folder, deleted after). `packaging/kks-explorer.spec`
(PyInstaller 6.22 one-folder, console=False, no UPX, importer libs excluded; 71 MB with 18 MB data),
`packaging/install-linux.sh` (~/.local/opt + .desktop), `packaging/README-desktop.txt`, `requirements-desktop.txt`,
`.github/workflows/desktop.yml` (windows-latest + ubuntu-22.04, Python 3.12, tests on Linux, frozen self-test, artifacts).
Verified here (Linux, Python 3.14): frozen self-test, normal start with mDNS on, second start exits in 0.3 s, window
close → clean stop + snapshot, installer + desktop-file-validate. NOT verified: the Windows build and the workflow
itself (needs a run on GitHub), Python 3.12 (CI's version), unsigned-exe/firewall prompts on real Windows. `withdraw`, `vote`, review `data:null` were added to the protocol
for it (v2-replay.json regenerated before anything depended on it; freeze it once the Kotlin port starts). Next: M2.

## M3 Android (Kotlin core; min Android 10 / API 29; decided 2026-09-26)

`android/`: Gradle 8.13 + Kotlin 2.0.21 (cached versions; AGP 8.13.2 for the app module later), run with
`JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64 ./gradlew :core:test` (Gradle 8.13 does not run on JDK 25). Android SDK
at ~/Android/Sdk (platform 36, emulator + KVM; AVDs Pixel_9_Pro_XL). `core` = plain Kotlin/JVM library (so JUnit
runs without an emulator): Json.kt (own parser: numbers the protocol can't carry → JNumber → bad_encoding;
`pyEquals` = Python equality incl. True == 1; `cmpCodePoints`), Canonical.kt, Crypto.kt (BouncyCastle 1.79
lightweight API: Android 10 lacks Ed25519/X25519 in platform crypto), Proto.kt, Replay.kt (check-for-check port of
peer/replay.py incl. history/decisions side output), Noise.kt, Sync.kt (Node interface), MemoryNode.kt (the node
rules of server/engine.py: vv with head ids, entriesFor, ingest with trial replay + fork evidence, blobs).
M3a done 2026-09-26: 16 JUnit tests: all vector files + Kotlin↔Kotlin + Kotlin↔Python (`tools/interop_node.py`,
needs `.venv`) both directions, states byte-identical. Found while porting and fixed in Python: `re.match` + `$`
accepted a trailing newline (now fullmatch), and three bodies (revoke/device_cert with a list, root with a list
`kind`) crashed the Python replay (unhashable dict key) → type checks first + a `bad_body` safety net; new frozen
`peer/vectors/v4-malformed.json` (1947 entries) checks both implementations never diverge on garbage.
M3b done 2026-09-26. core: `LocalNode.kt` (NodeStore interface + MemStore; persistence hooks in MemoryNode; owner,
statusOf, plan, restoreBody, bundles, afterIngest subs rows), `Payloads.kt` (normalize/tagPayload/body↔payload, same
messages as changes.py), `LocalApi.kt` (peer-mode routes of app.py/changes.py: config (app:true, can_create:false: no
new plants on phones = no root key on phones), me, state, submissions + vote/withdraw/approve/pick/reject with held
admin conflicts, revisions by hid, revert/restore, users/persons, devices/revoke/import-request, bundle GET/import,
sync/now, node join-request/join-server via HTTP enroll). Two Kotlin-vs-Python differences found by tests: Java
`putIfAbsent` treats a null value as absent (restore-to lost "didn't exist" befores), JSON numbers round-trip as
Double. MemoryNode methods are @Synchronized (sync threads vs API). app (`android/app`, AGP 8.13.2, minSdk 29,
targetSdk 36, no AndroidX yet): `SqliteStore` (seed AES-GCM under Keystore alias kks-device-seed; photos as files),
`PhoneSync` (listener 8421, sync by address, remembers addresses; no NSD yet), `MainActivity` (WebView on
https://kks.app, shouldInterceptRequest serves assets/data/photos and GET /api (bundle download), `KKSNative` bridge:
request/requestBytes/saveFile/saveApi/platform; file chooser; CREATE_DOCUMENT saves; window insets padded on a frame,
since a WebView ignores its own padding). Assets copied from the repo by the `copyWeb` Gradle task. common.js: K.api /
K.importBundle / K.download use the bridge when `window.KKSNative` exists; no service worker in the app. Build:
`cd android && echo sdk.dir=$HOME/Android/Sdk > local.properties && JAVA_HOME=…temurin-21… ./gradlew :app:assembleDebug`
(APK 29.5 MB). Verified on the Pixel_9_Pro_XL AVD (Android 16, headless, `-gpu swiftshader_indirect`), driven over
the WebView's DevTools socket with raw CDP (Playwright's connect_over_cdp can't attach to Android WebViews): join via
the Python server at 10.0.2.2, data incl. non-ASCII, proposal → server Approvals → approval back, viewer with 11
sheets / 207 hotspots, restart keeps everything.
M3c done 2026-09-27: Compose (BOM 2024.12.01, material3 1.3.1 + adaptive-navigation-suite, activity-compose 1.9.3,
core-ktx 1.13.1; `android.useAndroidX=true`; debug APK 50 MB, unshrunk). `App.kt` (node/api/sync singleton),
`WebHost.kt` (WebView factory: origin serving + KKSNative bridge; `onNavigate` hook), `MainActivity.kt`
(ComponentActivity, edge-to-edge; `pidWeb` kept across tabs, `manageWeb` for admin.html#section; `ShellState`
refreshed from LocalApi on node changes/bridge POSTs; camera-or-gallery chooser via FileProvider `kks.explorer.files`
(cache/camera), no CAMERA permission needed; CREATE_DOCUMENT saves), `Shell.kt` (dark brand scheme; icons as Material
path strings, not the extended icon lib; not joined → full-screen setup WebView; tabs P&ID / Learning (placeholder,
M4) / Account (name, Sync now + by address, Manage rows → admin.html sections full screen with native top bar, This
phone). Back: Manage → closes; other tab → P&ID; else asks the page `K.back()` (setup form → choices; index.html closes
lightbox/panel/drawer) and leaves only if the page had nothing to close (WebView.canGoBack doesn't see pushState steps).
Found on the emulator and fixed: AndroidView gives a WebView wrap_content → page 0 px tall, sheet never drawn
(→ MATCH_PARENT); index.html refits once the viewer gets a real size if it was fitted at 0 (ResizeObserver, never
resets a user's view); the app hides admin.html's own header and the Drawings tab (`.app` class, cfg.app). Test
lessons: the emulator's "System UI isn't responding" dialog eats key events (restart it); pick DevTools pages by URL
(two WebViews); file pickers need a real tap (`adb input tap` at the element's rect × dpr + WebView offset), a JS
.click() is ignored. Verified on the Pixel_9_Pro_XL AVD: 16 checks (setup, Back, join, tabs, Account, Sync now,
Approvals with a synced proposal, panel Back, camera chooser).
M3d done 2026-09-27: `PhoneSync` (context, node): NSD announce `kks-<device[:12]>` `_kks._tcp` TXT peer/root[:16]/v
(re-announced when the plant changes), discovery + a serial resolver thread (one resolve at a time), own record =
`self_seen`, other plants skipped; auto loop like syncsvc.py (INTERVAL 120 s, 5 s after a local change, 1 s after a
new same-plant device); syncAll = found devices + remembered addresses (`sync_peers` meta). Discovery/auto only while
an activity is visible (`App.visible`, MainActivity onStart/onStop); `SyncWorker` (WorkManager 2.9.1, periodic 15 min,
NetworkType.UNMETERED): start → look 8 s → syncAll → stop, skipped when not joined or when the app is on screen.
Debug builds only: `DebugSyncReceiver` (`adb shell am broadcast -a kks.explorer.DEBUG_SYNC -p kks.explorer`) runs the
worker once now, because `cmd jobscheduler run -f` doesn't make WorkManager run a periodic job before its period.
Log tag `KKSSync` (announce, found, every sync). Verified on the emulator: announce + self-discovery via NSD, a phone
change reached the server by itself in ~6 s, the worker synced with the app closed; the real periodic job ran 27 min after scheduling (Android batches jobs; eligible after 15 min) with the app closed and received a server change.
NOT verifiable on the emulator: phone ↔ laptop discovery (the emulator's NAT carries no multicast to the host) —
needs real devices on one Wi-Fi. Future: Android's local network permission (opt-in on 16) may become required for
apps targeting a later SDK.
Before M3e (2026-09-27, asked by the user), all three verified on the emulator unless noted:
- Metered networks: Account → Sync → "Sync on metered networks" (meta `sync_metered`). Off: automatic syncs skip
  metered networks (`PhoneSync.autoAllowed`, "paused" shown) and SyncWorker requires UNMETERED; on: CONNECTED (re-
  scheduled with ExistingPeriodicWorkPolicy.UPDATE). "Sync now" always syncs. Laptops: no metered detection.
- Join by invite / QR (PROTOCOL.md §16): admin → Manage → Devices → "Add a device with a QR code" (admin.html, QR via
  vendored `qrcodegen.js` = Nayuki MIT, compiled from TS) shows {root, peer, addrs, one-time token, 15 min}; the new
  device (common.js "Join with a QR code": app scans natively with zxing-android-embedded 4.3.0 + zxing core 3.5.4 via
  `KKSNative.scanQr`; laptops paste the code) sends `{t:join, token, request}` on the sync port instead of `hello`,
  polls `join_ack` (waiting/accepted/refused/used/unknown/bad), admin accepts (same rules as import-request: existing
  username needs OK), then syncs adopting the root. Python `server/invites.py` + `node.InviteJoin`, Kotlin
  `Invites.kt`; invites in memory only. Bundles don't fit a QR: LAN sync replaces the file there; files stay.
  Verified: Python test, Kotlin tests (phone↔phone, phone↔real app.py), emulator phone joined the Python server
  over its LAN IP; the QR rendered by admin.html decodes (OpenCV) to the invite. NOT verified: the phone camera
  actually decoding a QR (the emulator's virtual scene camera could not be aimed at the poster) — try on a real phone.
  After M3e (2026-09-27): computers scan with the webcam (common.js `K.scanQr`: getUserMedia + vendored jsQR 1.4.0,
  Apache-2.0, `vendor/jsqr`; verified with Chromium's fake camera playing the QR). No camera and no code: "Ask an
  admin on this Wi-Fi": mDNS TXT now carries `plant`, `label`, `adm` (both announcers; re-announced when they
  change); `/api/node/nearby` lists admins' devices; the request goes with `token: null` into the answering device's
  lobby (`Invites.lobby`, 50 max, 15 min), admins see it in Devices → "Waiting to join" (`/api/join-requests`; the
  phone badges the Account tab) with a 6-digit code (`node.join_code` = `joinCode`, same vectors in both tests);
  `accepted` carries `root`; the joiner syncs only after its person confirms the code (`confirm`). Verified: Python +
  Kotlin tests, Playwright with 3 real processes and mDNS (server lobby, codes equal, 401 until confirmed, joined).
  Bug found on the emulator and fixed: PhoneSync.announce (PhoneSync lock) read the node (node lock) while the API
  (node lock) asked for snapshot() (PhoneSync lock) → deadlock; announce now reads the node before locking.
- Photos as JPEG XL, distance 1.9 + effort 9 (the user's choice 2026-09-27, after d1.0 turned out no smaller than the
  old JPEG q85): `server/photos.py` (pillow-jxl quality 80 = d1.9), `android/app/.../Jxl.kt` + `src/main/cpp` JNI over
  libjxl v0.12.0 built from pinned, SHA-256-checked sources (Gradle task `fetchLibjxl`; NDK 27.2.12479018, CMake
  3.22.1). The API converts: pages send lossless PNG when local (app, peer laptop), JPEG q0.95 to a server, q0.85 if
  it can't encode (`/api/config.photo_upload`). Nothing is ever converted to JPEG: the server sends the JXL as it is
  (immutable, by hash); a browser without JXL decodes it in common.js (`K.jxl`: MutationObserver on `img[src$=.jxl]`,
  libjxl in WebAssembly = vendored `@jsquash/jxl` 1.3.0 decoder, Apache-2.0, `vendor/jxl`, 850 KB wasm loaded only
  then) into a BMP blob; the Android WebView gets `/photos/*.jxl` as a BMP from the app's libjxl (`Jxl.toBmp`).
  Measured (SSIMULACRA2, 8 photos at 1600 px): JPEG q85 1212 KB/79.0, JXL d1.0 1187 KB/86.6, d1.9 680 KB/78.9; effort
  9 vs 7: −8% size, ~10× time (4.0 s/photo on a 16-thread desktop; 2.7 s on the x86 emulator; real ARM phones NOT
  measured, expect more; the page shows "Compressing…"). Verified: Chromium (no native JXL) shows a server JXL at
  1600×900 through the WASM path; the app loaded its own JXL as a 1600×900 BMP; desktop self-test checks JXL.
M3e done 2026-09-27: release build with R8 + resource shrinking (`proguard-rules.pro`: JS bridge, JNI, worker),
signed with the maintainer's own key: `~/.config/kks-explorer/signing/` (kks-release.jks, PKCS12, alias kks, RSA 4096,
to 2056, + keystore.properties; or `$KKS_SIGNING`), never in the repo or CI — docs/ANDROID_RELEASE.md. Release APK
35 MB (debug 65). `.github/workflows/android.yml`: core tests (with the Python server from .venv), debug + UNSIGNED
release APK as artifacts, libjxl downloads cached. Verified: apksigner (v2, cert SHA-256 1a3a2b53…), release APK
joined the server, showed the viewer, photo → JXL. NOT verified: the Android workflow itself (needs a GitHub run).
Scanner orientation follows the phone (manifest override of CaptureActivity).

## M4 Learning (done 2026-09-27)

`tools/build_courses.py [--fonts]`: source/courses/*.html (gitignored) → `data/courses/` (same file names: the
courses link to each other) with the Google Fonts links → `/vendor/fonts/courses.css` (Latin + Latin Extended woff2,
OFL) and `<script src="/course-bridge.js" data-course="ppt|fnd|hrsg">` before the course's script; `courses.json`
(id = localStorage prefix, title, file, question ids from the Q/O/S calls: 88/96/83). Courses store only
`last`, `skip`, `solved`, `finalBest` (JSON strings) through one `store` helper. `course-bridge.js`: synchronous fill
(XHR, or `KKSNative.progress` in the app) then wraps `Storage.prototype.setItem` for the prefix, debounced POST,
pending list in localStorage until saved; no log (server mode: 404) → plain localStorage.
Progress = `private` entries (PROTOCOL.md §13) `course_progress` {course, items: [[key, string]]} (pairs: canonical
keys must be `[a-z_]…`, `finalBest` isn't). `server/progress.py` / `Progress.kt`: person secrets (Python table
`person_secrets`; phone: `NodeStore.personSecrets`, AES-GCM under the Keystore), write with the lowest-SHA secret,
read trying all, merge objects → union, `…Best` → max, else later. Secrets swap (§17) after a sync with another device
of the owner (`syncsvc._swap_secrets`, `Progress.swapAfterSync`), responder checks same person. Server mode: no
secrets, `/api/progress` 404. UI: learning.html (+ "Learning" in index.html, hidden in the app); Android native
Learning tab (cards with answered/total from `solved` ∩ questions) + course WebView with top bar (Back walks the
course's own links first). sw.js: courses network-first, /vendor/ network-first into the shell cache.
Verified: Python test (two laptops + server: server holds the entries, no secret, reads nothing; after the direct swap
both see the merge), Kotlin test with real app.py server + Python peer laptop + Kotlin phone (swap both ways, merge),
Chromium (list, vendored fonts loaded, zero requests off localhost, progress back from the log after clearing
localStorage), emulator (Learning tab, course renders with the fonts, a real tapped answer → "1 of 83" → private
entry on the server, 0 secrets there), desktop self-test (progress round trip), release APK builds (0.7.0-m4).
Note: `data/courses/` holds the built courses and stays in the repo (public, the user's choice 2026-09-28; they name the plant a few times); source/ is not.

## Field test fixes (2026-09-28, the user's release-build test on two phones; QR join worked)

- Sync failures after a request: `LocalApi.handle` held the node lock across network calls ("Sync now", join-server);
  two phones syncing each other waited on each other's lock until timeout → those routes run unlocked
  (`UNLOCKED`); test `simultaneousSyncNowDoesNotDeadlock` fails on the old code.
- Stale screens: pages poll `/api/sync/status` (`rev` = the store's journal seq in Python, a counter bumped by node
  changes + POSTs in Kotlin; 3 s on a peer, 15 s on a server) and reload on change (index.html re-renders an open panel
  unless something is being edited). Status line on peers: devices reachable (mDNS-found + synced OK in 3 min; a
  failed sync to an address marks that device unreachable), last sync (`last_ok`), internet (Android
  NET_CAPABILITY_VALIDATED; laptops can't tell, show nothing). Server mode keeps Online/Offline.
- Laptops never auto-synced without mDNS: `syncsvc` now remembers addresses (meta `sync_peers`, like the phone) and
  runs the auto loop even with discovery off (`sync_interval: 0` = off; tests use it).
- Removing a device: a denied `entries` answer carries the revoke entry (§15 `revoked`); the device checks it against
  its own log (sig, names it, author admin/manager or same person, not revoked) and wipes: Python `Engine.wipe`
  (all tables, VACUUM, WAL truncate, photos, backups; keeps root.key; in place, Windows-safe), Kotlin `LocalNode.wipe`
  → `SqliteStore.wipe`, app restarts (new device key), WebView storage cleared; setup screen says who removed it.
  A stranger's revoke is refused (tests). Verified on the emulator.
- Camera: the QR library adds CAMERA to the manifest, so ACTION_IMAGE_CAPTURE needs the grant → asked before the
  chooser; photos taken in the app were lost because URI grants on chooser initial intents don't reach the camera app
  → explicit `grantUriPermission` to every camera app + ClipData (+ `<queries>` IMAGE_CAPTURE). Verified: prompt,
  capture, photo saved as JXL.
- Photos: annotation editor before sending (`K.annotate`: arrow/box/circle, 4 colours, undo; burned into the image;
  repaint once a frame + end point from pointerup: on the emulator a swipe lost most of its moves), JXL progress bar
  (`K.progress`: libjxl has no progress callback → estimate from measured ms per megapixel, `photo_upload.ms_per_mp`,
  capped at 95 % until done), pinch/wheel zoom + drag pan viewer (`K.lightbox`, both pages).
- Floor: whole number 0–10 (page, `changes.normalize`, `Payloads`); the location list's levels are elevations
  (`refLoc().elev`, Elevation hint); floor filter = floors in use ("Floor N").
- Editable tag fields read-only until ✎ (per field; custom fields as a group); Save/Cancel appear when unlocked.
- Request notes: optional "Note for the approver" on equipment edits, photos, photo deletions → `comment` entry
  {entry, text} (PROTOCOL §9, side output `comments`, no state change; frozen vectors unchanged); shown in Approvals and
  My submissions (`request_note`).

## M5 Internet sync (done 2026-09-28; decided: Cloudflare Worker relay, direct first)

PROTOCOL.md §18. The §15 sync runs unchanged over a new byte stream: presence in a per-plant room on the relay
(room = sha256("kks-relay-room-v1\n"+root)[:32]; hello signed by the device key, ±300 s), `connect`/`accept` swap
candidates (UDP STUN public address + LAN IPv4s; TCP STUN doesn't exist on public servers, hence UDP), hole punching
with session = first 8 bytes of the connect id, then `peer/rudp.py` / `Rudp.kt` (own reliable UDP: SACK mask,
RFC 6298 RTO 0.2–4 s, window 8–256 halved once per round, fast retransmit after 3 later SACKs, PING after 2 s idle);
else a WebSocket pipe `/v1/pipe/<room>/<id>/<a|b>`. Relay: `relay/` (Worker + SQLite Durable Object, Hibernation
API, pipe buffer 1 MiB, unpaired pipes closed after 30 s; deploy guide relay/README.md) and its twin
`peer/relay_server.py` (tests; `python3 -m peer.relay_server PORT`). Clients: `peer/internet.py` + `peer/ws.py`
(stdlib WebSocket), `Internet.kt` + `WsClient.kt`; Kotlin `Conn` interface (TCP, rudp, pipe) under Sync.kt.
Relay address = `setting` `relay` (manager: `POST /api/settings/relay`, both platforms; admin.html Devices → Internet
card). `syncsvc` / `PhoneSync` run it with the auto loop (phones: on screen or the worker; metered setting); a round
syncs LAN devices first, then relay-online devices no sync reached since the round started (a 60 s "fresh" window
first used here skipped changes made right after a sync: found on the emulator). Restart-safe presence thread
(generation counter: stop()+start() used to leave the old thread running). Status line counts relay-online devices
as reachable.
Verified: Python tests (tests/test_rudp.py: 3 MB clean, 2 % loss ~9 s, 10 %/20 % loss, Noise over it;
tests/test_internet.py: presence needs the key, direct, relay pipe when punching fails, setting + auto round, absent
peer), also against the real Worker under `wrangler dev` (`KKS_RELAY_URL=ws://127.0.0.1:8787`); Kotlin RudpTest (incl.
Python interop via tools/rudp_peer.py), LocalApiTest internetSyncWithPythonLaptop (direct + pipe) and relaySetting;
emulator ↔ app.py server through `wrangler dev` (adb reverse 8787): server change reached the phone in 6 s,
phone proposal reached the server with its LAN path cut, both "internet (direct)".
NOT verified: a real Cloudflare deployment (needs the user's account), real NATs / mobile data / symmetric NATs,
two phones over the internet. Going live needs the same IT approval as remote access.

## M5b Plant data out, public repo, self-updates (2026-09-28/29; history rewritten + force-pushed 2026-09-29)

Decided 2026-09-28: rewrite THIS repo's history (git filter-repo) and make it public; public: glyph library, KKS
tables, the 3 courses; plant name out of docs/config/vectors; updates checked daily, installed only when asked; plant
data published by the manager only.
- Plant data (PROTOCOL.md §19, `server/plantdata.py` / `PlantData.kt` + LocalNode.plantActive/plantFile/plantStatus):
  `setting` `plant_data` {version, files: [[path, sha, size]]}, files are blobs (wanted like photos, always in
  bundles); a node serves the newest version it holds completely (meta `plant_data_active`), `/data/<path>` from
  it, else the program's `data/` (kks.json, courses). Drawings is manager-only; imports/removals publish; working copy
  `plant_dir` (default `plant-data/`, gitignored; first import copies a pre-M5b `data/` once). `app.py publish-data`.
  `/api/sync/status.plant_data`; pages reload on a new active version; index.html shows "Waiting for the drawings".
  Bug found by the Kotlin test + a repro and fixed: after the CLI wrote, the sync listener served a stale view (blob
  list loaded at start; `vv`/`entries_for` read the DB, `blob_get` doesn't) → `peer/sync._fresh` refreshes the
  engine before every session; test_plantdata publishes v3 with new files then syncs with no web request between.
- The plant's files moved to `plant-data/` (copied + compared, then `git rm`); the live server needs
  `python3 app.py publish-data` once (nothing published into the live plant.db by Claude). Plant name removed from
  tracked files; v2-replay/v4-malformed regenerated with "Test plant" (Python + Kotlin pass); plant notes moved to
  CLAUDE.local.md (gitignored). tools/manual_parse.py `--skip HEADER` instead of the plant's page header.
- Self-updates (docs/RELEASES.md): `VERSION` (0.8.0; Android versionCode = a·10000+b·100+c), release.json +
  release.json.sig (Ed25519 over "kks-release-v1\n"+bytes, key `~/.config/kks-explorer/signing/release-ed25519.key`,
  public `YBHkaex0…` pinned in server/updates.py + Updates.kt, test checks both equal), `tools/release.py` (sign;
  `--publish` asks, then gh release create). Python `server/updates.py` (daily check, `update_check`; packaged desktop
  installs into `<user dir>/versions/<v>/` + ready.json, `desktop.py` hands over on start, cleanup keeps 2; source
  installs: notice only), admin.html Account → Updates, one-time notice in index.html. Android `AppUpdates`
  (PackageInstaller session + receiver, REQUEST_INSTALL_PACKAGES), Account tab → Updates; debug-only
  `DebugUpdateReceiver` points it at a test server.
  Verified: Python tests (fake GitHub: signature, tamper, older version, install, handoff, cleanup, hash mismatch),
  Kotlin (Python-signed manifest verifies, redirects, swapped file refused), real PyInstaller build (self-test,
  package has no plant data, 79 MB; staged 0.9.0 took over from 0.8.0), emulator: 0.8.0 → 0.8.1 through the fake
  GitHub (allow-source prompt cancels the first session: "Install cancelled", retry → system dialog → installed,
  still joined, 11 sheets / 1379 tags), and plant data published on the server reached the phone by sync.
  Also fixed: rudp close() waited 3 s for the FIN's ack but one RTO can be 4 s → up to 5 RTOs (heavy-loss test
  failed 2/13, then 0/16).
  NOT verified: a real GitHub release (repo private: the real check gets 404), Windows handoff, the release key
  backed up (the user must do it).
- History rewrite done 2026-09-29 (the user chose force-push over the existing GitHub repo): `~/.config/kks-explorer/
  scrub-history.sh` (outside the repo: it names what it removes) ran git filter-repo (in .venv) on a fresh clone: plant
  files and plant.db dropped from every commit, names scrubbed from old docs (courses and peer/vectors kept byte for
  byte); HEAD tree identical before/after; 35 → 11 MB; force-pushed main. The old history is kept privately in
  `~/kks-explorer-history-before-M5b.bundle` (contains plant data). GitHub may keep old commits reachable by SHA until
  its support purges them. Still to do: the user makes the repo public; first real release (docs/RELEASES.md).

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
- **Distribution:** Microsoft Store (private audience, fallback self-signed MSIX) and Flathub.

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
- **Glyph library:** `extractor/fontlib.kgl` (docs/GLYPHLIB.md, `tools/fontlib_export.py`).
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
- **Not done:** hole punching + reliable UDP (0028); a phone on mobile data skips private LAN addresses, laptops don't.
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

## Backlog (rough priority)

1. When users have marked missed tags (`app.py added-tags`), find why the extractor missed them and fix the cause.
2. Verify a random sample of auto tags per new sheet; build per-sheet verified references like LP.
3. Valve type from symbols (gate/globe/check/motorized/safety) — template-match the legend symbols near each tag.
4. Extract instrument descriptions from the FW/LP junction-box panels (English text next to each instrument).
5. Suggest procedure→equipment links (system code + description matching), user confirms.
6. Attach PDF markup annotations to nearby tags instead of sheet-level notes.
7. Calibration UI in the app for new fonts (label unknown glyph clusters instead of doing it by hand).
8. The live plant server runs from the dev checkout (repo-root plant.db, photos/, backups/, root.key, plant-data/):
   restarting app.py after code edits runs new code on real data. Plan (2026-09-30, deferred by the user): build +
   install the packaged Linux app, delete the empty leftover `~/.local/share/kks-explorer` from the 2026-09-26 package
   test (its config remembers port 8421 = the server's sync port), join it as a second device of the manager ("Join via
   server", http://localhost:8420); then move the server's files out of the repo (e.g. ~/kks-server + its own
   config.json, `KKS_CONFIG=… python3 app.py`), copy + compare before removing anything.
