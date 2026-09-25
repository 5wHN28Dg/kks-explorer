# KKS Explorer — project context for Claude Code

Personal tool built by an I&C Maintenance Engineer at a combined-cycle power plant.
Goal: given only a KKS code (e.g. `11LAB70AA501`), find the equipment on the P&IDs and see everything known
about it: decoded meaning, physical location, photos, notes, and which operation-manual procedures use it.
Also: pick a procedure ("Preparations for Startup — Air Compressor System") → see its steps and highlighted equipment.

The user prefers direct, no-fluff communication and honest pushback. Be explicit about what is verified vs not.

## Run

- `python3 app.py` → http://localhost:8420 (phone: printed LAN URL, same Wi-Fi). Stdlib only. First run prints a
  one-time setup link to create the manager. CLI: `users`, `reset-manager --user X`, `reset-password --user X`,
  `backup`, `restore [--seq N] [--out F]`. Settings: `config.json` (see `config.example.json`, `server/config.py`).
- Tests: `python3 -m unittest discover -s tests` (server end-to-end over HTTP). The UI was verified with Playwright
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
  restore), `auth.py` (scrypt passwords, hashed session/one-time tokens, login throttling), `changes.py` (submissions,
  3-way field merge, apply, revision log, revert, restore-to).
  Live data tables: equipment(kks→json), photos, reviews(tag_id→json), links(proc,step,kks). Also users, sessions,
  tokens, submissions, votes, revisions(before/after per change), meta.
- Multi-user model: users never write live data; every edit is a submission (`POST /api/submit`, idempotent by
  `client_id` for offline replay). Admin/manager submissions apply at once. Applying = plan (conflict check against the
  `base` values the client saw) → set_state per entity → one revision each. Photos files are never deleted (row only),
  so revert/restore is lossless. All journaled tables must be written via `store.put/delete` inside `store.write()`.
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
- `admin.html` — Approvals (grouped by target, photo pick), My submissions (+ voting), Users, History, Account.
- `index.html` — whole front end, vanilla JS, no build step. Pan/zoom viewer, hotspots, panel (floating on desktop,
  bottom sheet ≤720px), search, floor filter, procedures drawer + step↔equipment linking, review queue, sheet notes.
- `data/sheets.json` — `{id,name,file,w,h,notes[]}`; images in `data/sheets/*.png` (grayscale, ≤6400px).
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
- NEVER commit or overwrite `plant.db` / `photos/` / `backups/` / `config.json`: field data and server state.
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
- Flue Gas and Intermittent/CBD sheets extract poorly (unusual layouts, open bubbles).

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

## Plan B (no company server)

`docs/PLAN_B_P2P.md`: design notes only, not built. The app hasn't been presented to the company yet (2026-09-25);
if hosting is refused and no money goes to a server/domain: B0 intermittent laptop server (works today, needs own-CA
HTTPS for phones), B1 file export/import sync, B2 full P2P (signed per-author logs, manager root key, LAN/Syncthing).
Section 0 there: first find out whether the "no" is about hosting or about plant data on personal devices.

## Backlog (rough priority)

1. Verify a random sample of auto tags per new sheet; build per-sheet verified references like LP.
2. Valve type from symbols (gate/globe/check/motorized/safety) — template-match the legend symbols near each tag.
3. Extract instrument descriptions from the FW/LP junction-box panels (English text next to each instrument).
4. Suggest procedure→equipment links (system code + description matching), user confirms.
5. Attach PDF markup annotations to nearby tags instead of sheet-level notes.
6. Calibration UI in the app for new fonts (label unknown glyph clusters instead of doing it by hand).
