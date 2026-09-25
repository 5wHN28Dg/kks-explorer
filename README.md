# KKS Explorer — HRSG P&IDs

Multi-user, works offline, standard-library Python server. Plant data is only served to signed-in users.

## Start
1. Install Python 3 (already on most laptops).
2. Optional: `cp config.example.json config.json` and edit (plant name, port, paths, HTTPS). Defaults work.
3. In this folder: `python3 app.py`
4. **First run:** the console prints a one-time **setup link**. Open it and create the **manager** account
   (valid 24 h; a new link is printed on every start until a manager exists).
5. Laptop: http://localhost:8420 — Phone: the LAN URL it prints (same Wi-Fi).

The server needs **no extra packages**. Only the importer does. Tests: `python3 -m unittest discover -s tests`.

## What's loaded
10 sheets: LP, IP, HP, Feedwater, Reheat, Intermittent/CBD, Flue Gas, Block 1 HP/IP/LP steam piping.
~880 tags read automatically, 145 checked by eye, 1 left in the review queue. 77 procedures from the HRSG operation manual.

## Using it
- **Search** any KKS (full or partial: `11LAB70AA501`, `LBA80`, `CP101`), or text you've entered (location, notes).
- **Tap a tag** on a drawing → panel with the decoded KKS (unit, system, component), which sheets it appears on,
  linked procedures, location fields, notes, custom fields and photos. Press **Save** after editing. Your changes
  that aren't live yet (awaiting approval, or queued offline) are listed at the top of the panel.
- **Floor filter** (top bar) lists every floor you've entered; picking one highlights that floor's equipment.
- **Procedures** → pick one → steps. Use **+ Link equipment** on a step, then tap the tags on the drawing.
  The manual never uses KKS codes, so this linking is done once by you. Linked equipment is highlighted.
- **Review** → tags the reader wasn't sure about, with a crop of the drawing. Confirm (fix the code if needed) or mark
  “Not a tag”. On the LP sheet, most have a pre-filled value I checked visually.
- **Sheet notes** → markup text added to the PDFs (e.g. "KKS is wrong, has been revised", set-points).

## Accuracy — read this
- LP sheet: checked against a fully verified reading: 1 wrong among 189 auto-read tags (a dropped suffix letter).
- Other sheets: **not fully verified**. Known issue: a suffix letter (R, K) touching an instrument bubble's edge can be
  dropped. Treat auto-read tags as very likely right, and confirm in the field when it matters.
- Flue Gas and Intermittent/CBD sheets read poorly (unusual layouts); most of their tags are in the review queue.
- The drawings reference an I&C code instruction document (DOCUMENT). It would explain what
  the valve number ranges mean; it isn't loaded.

## Accounts and approvals
- **Manager** (exactly one) > **admins** > **users**. The manager creates admins, promotes/demotes them, and can hand the
  role to an admin (Manage → Account; the admin must accept; the old manager becomes an admin). Admins approve changes
  and manage users. Users browse and propose changes.
- No email: creating an account gives a **one-time link** (7 days) that you pass on; the person sets their own password.
- **Every change is a proposal.** A user's edits (location, notes, photos, procedure links, review decisions) wait in
  Manage → Approvals. Admin/manager edits apply at once (`admins_apply_directly`), and are still logged.
- **Conflicts:** edits to different fields of the same item merge automatically. If a field changed after someone
  proposed a new value for it, the proposal is flagged and an admin chooses (overwrite or reject).
- **Photos:** several proposed photos for one item appear side by side. Users can vote; votes are only a hint.
  An admin picks one (“Use this one” rejects the rest) or adds several.
- **Lost manager** (left, forgot password): on the server, `python3 app.py reset-manager --user NAME`. It prints a
  password link. This works only from the server's console, never over the network. `reset-password --user NAME`
  prints a link for anyone. `python3 app.py users` lists accounts.

## History, restore and backups
- **Manage → History** lists every applied change. *Revert* undoes one; *Restore to here* puts all plant data back to
  that point. Both are logged too, so they can be undone.
- **Automatic backups** in `backups/`: every write is appended to a journal (`journal-*.jsonl`, fsynced) and a full DB
  snapshot (`snap-*.db`) is taken at start, every 200 writes, and on Ctrl+C. `python3 app.py backup` takes one now.
- **Disaster restore:** `python3 app.py restore [--seq N]` rebuilds the DB from snapshot + journal into a **new** file and
  tells you how to swap it in. It never touches the live `plant.db`.
- **Not covered by that:** `backups/` sits on the same disk as the live data, and photos are separate files. Copy
  `backups/` and `photos/` to another machine regularly (restic, rsync, or at least a USB drive). Photo files are never
  deleted by the app, so an incremental copy is enough. Do a test restore now and then.

## Offline
- The app installs as a PWA ("Add to home screen"). Drawings and data you have opened keep working without the server,
  including search. Changes made offline are queued on the device and sent automatically on reconnect.
- **Needs HTTPS** (or localhost). Over plain `http://192.168.x.x` the page works only while connected. Tailscale
  (`tailscale serve`) gives you HTTPS with no certificate work.
- Offline access lasts `offline_days` (default 7) after the device last reached the server. Logging out, or an admin
  deactivating the account, removes the cached plant data the next time the device connects. **A device that never
  reconnects keeps its copy.** Offline data cannot be taken back, so choose who gets accounts with that in mind.

## Access from outside the plant network
Chosen setup: **Cloudflare Tunnel + Cloudflare Access**, one HTTPS address for everyone, on every network. Step-by-step,
tests and the reasoning (vs Tailscale) are in **[docs/REMOTE_ACCESS.md](docs/REMOTE_ACCESS.md)**; templates in `deploy/`.
Get written approval from plant IT/security first: P&IDs and KKS indexes are sensitive infrastructure documents.
`python3 app.py check` audits a deployment (loopback-only listening, Secure cookies, cloudflared enforcing Access
tokens, backups) and exits non-zero on any FAIL.

## Another plant
Code and data are separate: point `data_dir`, `db`, `photos_dir` and `backup_dir` in `config.json` at that plant's
files and set `plant_name`. Run one server per plant. Build the data with `import_sheet.py` (P&IDs),
`tools/parse_locations.py` (location list) and `tools/manual_parse.py` (procedures).

## Your data
Field data lives in `plant.db` and `photos/`, history and backups in `backups/`. None of them go in git.
Updating the app later: replace everything except `plant.db`, `photos/`, `backups/` and `config.json`.

## Adding a new P&ID
One-time setup on the server (creates `.venv` in the app folder; nothing is installed system-wide, and the server
itself keeps running on plain `python3`):
```
python3 app.py setup-importer
```
Then **Manage → Drawings** (admins): choose the PDF, check the name and id, Import. About a minute per sheet; progress
shows live. Afterwards check the preview is upright. If not, use the re-import button (the PDF is kept, so no
re-upload). Re-import and Remove are in the sheet list; every change backs up `sheets.json`/`tags.json` first,
a failed import puts them back, and History logs who added or removed what.

From the command line instead:
```
.venv/bin/python import_sheet.py path/to/drawing.pdf "Condensate System" [sheet_id] [--rotate auto|0|90|180|270] [--replace]
```
Works on vector PDFs plotted from AutoCAD (all of yours are). Scanned drawings won't work. Only page 1 is read.
It picks the rotation with the most horizontal text and, if almost no tags read, retries upside down and keeps the
better result. Tags are read with the character library in `extractor/fontlib.pkl`; characters it hasn't seen get
low confidence and land in the review queue rather than being guessed.
