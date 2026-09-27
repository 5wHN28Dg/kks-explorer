# KKS Explorer — project context for Claude Code

Personal tool built by an I&C Maintenance Engineer at a combined-cycle power plant.
Goal: given only a KKS code (e.g. `11LAB70AA501`), find the equipment on the P&IDs and see everything known
about it: decoded meaning, physical location, photos, notes, and which operation-manual procedures use it.
Also: pick a procedure ("Preparations for Startup — Air Compressor System") → see its steps and highlighted equipment.

The user prefers direct, no-fluff communication and honest pushback. Be explicit about what is verified vs not.

## Run

- `python3 app.py` → http://localhost:8420 (phone: printed LAN URL, same Wi-Fi). Stdlib + `cryptography` (since M1,
  2026-09-26; system python here has it, else `.venv/bin/python app.py`). Photos as JPEG XL need Pillow +
  pillow-jxl-plugin (optional; without them photos stay as uploaded, `app.py check` warns). First run prints a one-time setup link to
  create the manager (also creates `root.key`). CLI: `users`, `reset-manager --user X`, `reset-password --user X`,
  `backup`, `restore [--seq N] [--out F]`, `export-root-key --out F`, `import-root-key --file F`, `added-tags`.
  Settings: `config.json` (see `config.example.json`, `server/config.py`).
- Tests: `.venv/bin/python -m unittest discover -s tests` (64: server end-to-end over HTTP, protocol vectors,
  migration, sync, peer mode, join by invite). Base.tearDown asserts the server never wrote an entry the replay ignores and a fresh replay matches.
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
- `data/sheets.json` — `{id,name,file,vector,rot,w,h,notes[]}`; images in `data/sheets/*.png` (grayscale, ≤6400px),
  vectors in `data/sheets/<id>.svg.gz` (served as `<id>.svg` with Content-Encoding gzip). `rot` = rotation applied to
  the source PDF. Sharp zoom (2026-09-25): `extractor/svgopt.py` bakes per-path transforms and merges all black paths
  per style (PyMuPDF SVG: 40k–140k paths → 13–134; pixel-identical in Chromium 1×–125×). index.html draws it on
  `#sharp` canvas (between `#stage` PNG and `#stage2` hotspots) ~150 ms after the view settles, only when
  view.s·dpr ≥ 0.7; CSS-transforms the old drawing while panning. Max zoom 16× with a vector, 4× without.
  `tools/make_vectors.py ID source.pdf` makes one for an existing sheet: picks the rotation matching the PNG and
  checks alignment by phase correlation (all 11 sheets within 0.9 px). Firefox redraw ~250 ms on desktop.
- `data/tags.json` — one entry per tag occurrence:
  `{id:"sheet:n", sheet, kks, suffix, isa, kind:equipment|instrument, status, conf, bbox:[x0,y0,x1,y1] (image px),
    orient:h|v, read:[top,bottom] (raw reader output), note, flag, suggestion}`.
  status: `auto` (reader, conf ≥0.3) · `verified` (checked by eye) · `review` (needs a human). User decisions live
  in plant.db `reviews` and override tags.json at runtime (`eff()` in index.html). Equipment data is keyed by full KKS
  (kks+suffix), so the same item on several sheets shares data.
- `data/procedures.json` — 77 procedures parsed from the HRSG Operation Manual (English steps, parent path, page).
- `data/locations.json` — 360 rows from `source/KKS LOCATION HRSG.pdf` (level/elevation, cabinet, description, direction),
  built by `tools/parse_locations.py`. The list has no unit prefix → matched on KKS without the 2-digit unit, and on the
  base KKS for suffixed tags (R/K/D). Used as a fallback under the user's own equipment data; never written to plant.db.
  295/354 unique KKS match a drawing tag. Known list issues: LBB80CT5101–5103 (typo, likely CT101–103); conflicting rows
  for LBA90CT101/102 (10 m vs 32 m), LBA70AA001 (14 m vs 0 m), LBA10AA402 (0 m vs outside HRSG).
- `data/kks.json` — decode tables: system codes (from the legend printed on the P&IDs), component codes, ISA letters, unit prefixes.
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

## Accuracy status

- Dropped suffix letters FIXED 2026-09-25 (`reader3.cell_image`: mask = convex hull of the cell contour; a letter touching
  the border was part of the outline blob, so the traced hole cut it out). Regression over all 11 sheets: 146 cell
  readings changed, 97 confident ones gained a suffix (R/K/A), 24 became readable (mostly a leading 1 against a box
  edge), 0 confident readings got worse. Applied to existing sheets with `tools/reread_tags.py` (keeps ids and
  hand-verified tags): 70 suffixes added (LP 6, IP 8, HP 7, FW 32, RH 6, flue 11) + 2 stored `I` suffixes corrected
  to K (ip:154, rh:42). The LP "verified reference" had only 11HAD70CT101R; in fact CT101–106 all carry R.
- Missed tags FIXED at the root 2026-09-25 (found via user report "dozens missing on HP/IP"): (1) bubbles drawn without
  the divider line are one closed cell, never paired → `reader3.read_single` splits unpaired cells ≥10 pt at the widest
  empty row band (mask outside the cell first: a whole bubble's rounded ends lie inside the crop); (2) `reader2.detect`
  area test used the traced hole, which a letter touching the border notches below 75% → hull area; (3) `pair()`
  required equal widths, but text touching both ends of a half shrinks its hole → overlap-based `_fits`; (4) vertical
  text also runs top-to-bottom (function letters in the right cell) → vertical cells are read both ways, keeping the one
  that interprets as a tag. `fontlib.interpret`: G followed by the ISA variable letter in the component code → C
  (11LAB90GP102 → CP102), later ISA letters G → C (TIAG/PIAG were all TIAC/PIAC; no later G exists).
  `tools/add_missed.py ID source.pdf [--apply]` adds only non-overlapping new tags (ids `<sheet>:x<n>`), keeps
  existing ids. Added 57, all checked by eye: HP 21 (2 by hand: 11HAH90CT103K, 11HAD90CL503XB31), IP 12, FW 7, RH 1,
  b1cond 16; corrected hp:19/28/87 (TIAG/PIAG→TIAC/PIAC), hp:ob1531 (T→LE). Regression: new extractor vs stored tags on
  LP/IP/HP/FW: 0 auto tags change; the differences are all hand-verified tags the reader still misreads (HP 69: bold font).
  Most misses were local indicators (PI/TI/FE/LI …501) and vibration probes, which are drawn without a divider.
- From the first user-marked tags (2026-09-25, 7 marks, all correct): (5) pair() now accepts halves that overlap by up to
  3 px across a hairline divider (CBD 0.12 pt lines); (6) single-row cells and empty-top bubbles = code without
  function letters (10LCB..GF001 junction boxes; interpret: empty top + full KKS → instrument, isa None);
  (7) detection renders with `TOOLS.set_graphics_min_line_width(0.5)` so hairline box borders close (reading unchanged,
  the glyph library was trained on the normal rendering); (8) interpret: top 'U' + LLLDD → '11' (two thin 1s merge).
  Added 33 more, all checked by eye: CBD 30 (12 → 42 tags + 5 user marks), b1cond 3. Regression after each step:
  0 stored auto tags changed on all 11 sheets. The user's marks stay in plant.db (not duplicated into tags.json);
  add_missed skips boxes overlapping them.
- Remaining known reader weaknesses: C/G at full confidence (hp:95 reads 11HAD90GT108K; stored value hand-verified),
  M/H and 2/8 at low confidence (b1cond), last digit of panel bubbles squeezed against the arc (conf 0 → review).
- LP sheet: 189 auto tags, 1 wrong (suffix). Verified reference existed in the original workspace.
- Other sheets: not fully verified. Spot check of 40 auto tags on HP found 1 error (11LAE92 read as 11LAE90; fixed).
  Bold font confusions to watch: B/E, 0/2, 0/8.
- Review queue triaged by eye: 448 non-tags removed, 144 verified; hp:ob1305 = LI 11HAD90CL501 (2026-09-25).
  Review queue is empty across all sheets as of 2026-09-25.
- b1cond (Block 1 condensate, added 2026-09-25, re-imported after the suffix fix): 79 review tags triaged by eye
  (61 verified, 18 non-tags removed: title-block cells, "DESUPERHEAT WATER"); all 27 auto tags with conf < 0.7 checked
  by eye (2 wrong: 10HAC05AA151→10MAC05AA151, 10LCE18AA101→10LCE12AA101); a random 30 of the rest were all right.
  Two boxes are printed with the lines swapped (10MAW80AC001, 10LCE18AA003). Undecoded codes there: systems LCW,
  MAL, MAW, LEA; components GH, GF (no document defines them yet).
- Flue Gas sheet: not checked by eye for misses. CBD: hairline drawing, now read after fixes (5)–(8); checked by eye.

## Findings on the drawings (flagged in app)

- Missing-letter tags: `11LCC70/A403` (LP), `11QUB90/A602`, `11HAC90/A403` → likely AA403/AA602/AA403.
- KKS printed twice: 11LAB90AA301–304 (HP), 11QUA71AA601 (LP), 11/12LBA90CF201 (Block 1 HP piping).
- Drawings reference I&C code instruction DOCUMENT (explains number ranges) — not yet obtained.
- The operation manual never uses KKS; procedure steps name equipment by description, so step↔equipment links are made
  manually in the app. Manual appendix drawings are low-res preliminary versions — useless for extraction.

## Multi-user: open items

- Remote access is prepared but NOT live: needs written IT/security approval, a domain, a Cloudflare account and an
  always-on server on the IT (not OT) network. Nothing in the repo can be tested against real Cloudflare until then.
- Offline copies can't be revoked from a device that never reconnects (lease only locks the UI; data isn't encrypted,
  since the key would sit on the same device).
- Rejected/withdrawn photo files stay in `photos/` (no cleanup command yet).
- Sheets imported before 2026-09-25 have image URLs without `?v=`; re-importing one gives it a version.
- `data/` (P&IDs etc.) is still committed in this repo. The repo is private, but for sharing the app with other plants
  the plant data should move out of the repo (`data_dir` in config.json) and history be cleaned.

## v2: server mode + P2P (decided 2026-09-26)

`docs/ARCHITECTURE.md` is the plan of record (supersedes `docs/PLAN_B_P2P.md`). Key decisions: every device runs a
local peer; signed per-device append-only logs + deterministic replay/merge (no host, no election; the server is an
always-on peer); same-Wi-Fi + file/QR sync first, internet P2P later (M5); Android = Material 3 native shell + the
existing web P&ID viewer in a WebView; Windows/Linux = this Python app packaged (double-click, opens browser; the
stdlib-only rule ends for the package: cryptography + zeroconf); one person may have several devices (device keys +
certificates). Build order M0 protocol spec + Python reference + test vectors → M1 server on the log → M2 desktop
package + LAN/file sync → M3 Android → M4 Learning (3 HTML courses, not yet in the repo) → M5 internet.
Answered 2026-09-26: plant Wi-Fi allows device-to-device traffic; courses in `source/courses/` (3 single-file HTML,
localStorage progress, Google Fonts to vendor); quiz progress private (encrypted to the person's devices); photos
on-demand or all, per device, stored as JPEG XL with JPEG fallback for browsers without JXL; manager key: no second
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
  over its LAN IP; the QR rendered by admin.html decodes (OpenCV) to the invite. NOT verified: the camera actually
  decoding a QR (the emulator's virtual scene camera could not be aimed at the poster) — try on a real phone.
- Photos as JPEG XL at distance 1.0 (`server/photos.py`, `android/app/.../Jxl.kt` + `src/main/cpp` JNI over libjxl
  v0.12.0 built from pinned, SHA-256-checked sources by the Gradle task `fetchLibjxl`; NDK 27.2.12479018, CMake
  3.22.1). The API converts: pages send lossless PNG when local (app, peer laptop), JPEG q0.95 to a server, q0.85 if
  it can't encode (`/api/config.photo_upload`). Browsers get a cached JPEG (`cache_dir`/photo-jpeg, `Vary: Accept`),
  the WebView too (cacheDir). Measured (SSIMULACRA2, 8 photos at 1600 px): JPEG q85 1212 KB/79.0, JXL d1.0
  1187 KB/86.6, JXL q80 (d≈1.9) 680 KB/78.9 → d1.0 gives better quality at the old size, NOT smaller files; the
  user asked for visually lossless, so d1.0 stays until they decide. Verified: release APK on the emulator encoded a
  gallery photo to JXL (63 KB), synced to the server, served as JPEG/JXL by Accept; desktop self-test checks it too.
M3e done 2026-09-27: release build with R8 + resource shrinking (`proguard-rules.pro`: JS bridge, JNI, worker),
signed with the maintainer's own key: `~/.config/kks-explorer/signing/` (kks-release.jks, PKCS12, alias kks, RSA 4096,
to 2056, + keystore.properties; or `$KKS_SIGNING`), never in the repo or CI — docs/ANDROID_RELEASE.md. Release APK
35 MB (debug 65). `.github/workflows/android.yml`: core tests (with the Python server from .venv), debug + UNSIGNED
release APK as artifacts, libjxl downloads cached. Verified: apksigner (v2, cert SHA-256 1a3a2b53…), release APK
joined the server, showed the viewer, photo → JXL. NOT verified: the Android workflow itself (needs a GitHub run).
Scanner orientation follows the phone (manifest override of CaptureActivity).

## Backlog (rough priority)

1. When users have marked missed tags (`app.py added-tags`), find why the extractor missed them and fix the cause.
2. Verify a random sample of auto tags per new sheet; build per-sheet verified references like LP.
3. Valve type from symbols (gate/globe/check/motorized/safety) — template-match the legend symbols near each tag.
4. Extract instrument descriptions from the FW/LP junction-box panels (English text next to each instrument).
5. Suggest procedure→equipment links (system code + description matching), user confirms.
6. Attach PDF markup annotations to nearby tags instead of sheet-level notes.
7. Calibration UI in the app for new fonts (label unknown glyph clusters instead of doing it by hand).
