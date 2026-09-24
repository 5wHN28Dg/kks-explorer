# KKS Explorer — project context for Claude Code

Personal tool built by an I&C Maintenance Engineer at a combined-cycle power plant.
Goal: given only a KKS code (e.g. `11LAB70AA501`), find the equipment on the P&IDs and see everything known
about it: decoded meaning, physical location, photos, notes, and which operation-manual procedures use it.
Also: pick a procedure ("Preparations for Startup — Air Compressor System") → see its steps and highlighted equipment.

The user prefers direct, no-fluff communication and honest pushback. Be explicit about what is verified vs not.

## Run

- `python3 app.py` → http://localhost:8420 (phone: printed LAN URL, same Wi-Fi). Stdlib only.
- `python3 import_sheet.py drawing.pdf "Name" [id]` adds a sheet. Needs `pymupdf opencv-python-headless numpy`.

## Layout

- `app.py` — HTTP server + SQLite (`plant.db`). Tables: equipment(kks→json), photos, reviews(tag_id→json), links(proc,step,kks).
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
- `data/kks.json` — decode tables: system codes (from the legend printed on the P&IDs), component codes, ISA letters, unit prefixes.
- `extractor/` — the tag reader (see below). `fontlib.pkl` = labeled glyph library (~13.8k glyphs).
- `tools/` — manual parser and the calibration scripts used to build the glyph library (written for a scratch
  workspace; paths like `norm/`, `calib/`, `ext/` need adapting).
- NEVER commit or overwrite `plant.db` / `photos/` — that is the user's field data.

## How extraction works (and why)

P&IDs are AutoCAD plots: no text objects, no layers, every character is loose vector strokes (SHX fonts), many
glyphs split into several paths, box edges are zero-height paths. Pipeline:

1. Normalize orientation (`extractor/orient.py`): place page 1:1 via `show_pdf_page`, try 0/90/180/270, keep the one
   with most horizontal text lines. Score can't reliably tell upright from upside-down → check visually for new sheets.
2. Detect tag containers (`reader2.detect`): render 200 dpi, contour holes = box halves / instrument-bubble halves; pair
   stacked cells. Threshold <215 (thin line weights) and size window H 4–24pt, W 15–110pt (Block 1 sheets use bigger text).
3. Read each half (`reader3`): re-render at 600 dpi, trim border blobs with the contour mask, split characters by column
   projection (wide blobs split at ink minima), classify each glyph by kNN against `fontlib.pkl`, then family rules
   C/G (lower-right ink), B/8 (left edge straight), 0/D/Q (tail + straight left edge).
4. KKS grammar (`fontlib.interpret`): `DDLLLDD` over `LLDDD[L]` = equipment; ISA letters over `DDLLLDDLLDDD[suffix]` =
   instrument. I→1 / O→0 only in digit slots (KKS never uses letters I or O). Confidence = min char confidence.
5. Second pass for open-ended instrument bubbles: long vector text lines not inside a container, read with the same reader.

Lessons (don't repeat):

- Tesseract/general OCR on this condensed SHX font produced confident wrong KKS after grammar coercion. Removed entirely.
- Per-glyph geometric rules tuned on one font break another (a mid-height 0/8 rule turned Q→B, then B→D, 0→8).
  Prefer adding labeled samples to the library over new rules. Always re-check the LP sheet after any reader change:
  it has a fully verified reference (1 known error: dropped `R` suffix on 11HAD70CT101R).

## Accuracy status

- LP sheet: 189 auto tags, 1 wrong (suffix). Verified reference existed in the original workspace.
- Other sheets: not fully verified. Spot check of 40 auto tags on HP found 1 error (11LAE92 read as 11LAE90; fixed).
  Bold font confusions to watch: B/E, 0/2, 0/8.
- Review queue triaged by eye: 448 non-tags removed, 144 verified, 1 left (HP sheet, LI 11HAD90CL50?, last digit unclear).
- Known bug: suffix letters (R, K) touching a bubble's arc can be dropped silently.
- Flue Gas and Intermittent/CBD sheets extract poorly (unusual layouts, open bubbles).

## Findings on the drawings (flagged in app)

- Missing-letter tags: `11LCC70/A403` (LP), `11QUB90/A602`, `11HAC90/A403` → likely AA403/AA602/AA403.
- KKS printed twice: 11LAB90AA301–304 (HP), 11QUA71AA601 (LP), 11/12LBA90CF201 (Block 1 HP piping).
- Drawings reference I&C code instruction DOCUMENT (explains number ranges) — not yet obtained.
- The operation manual never uses KKS; procedure steps name equipment by description, so step↔equipment links are made
  manually in the app. Manual appendix drawings are low-res preliminary versions — useless for extraction.

## Backlog (rough priority)

1. Fix dropped suffix letters on instrument bubbles.
2. Verify a random sample of auto tags per new sheet; build per-sheet verified references like LP.
3. Valve type from symbols (gate/globe/check/motorized/safety) — template-match the legend symbols near each tag.
4. Extract instrument descriptions from the FW/LP junction-box panels (English text next to each instrument).
5. Suggest procedure→equipment links (system code + description matching), user confirms.
6. Attach PDF markup annotations to nearby tags instead of sheet-level notes.
7. Calibration UI in the app for new fonts (label unknown glyph clusters instead of doing it by hand).
