# KKS Explorer — HRSG P&IDs (local)

Runs entirely on your laptop. Nothing leaves your machine.

## Start
1. Install Python 3 (already on most laptops).
2. In this folder: `python3 app.py`
3. Laptop: http://localhost:8420 — Phone: the second URL it prints (same Wi-Fi).

The viewer itself needs **no extra packages**. Only the importer does.

## What's loaded
10 sheets: LP, IP, HP, Feedwater, Reheat, Intermittent/CBD, Flue Gas, Block 1 HP/IP/LP steam piping.
~880 tags read automatically, ~590 in the review queue. 77 procedures from the HRSG operation manual.

## Using it
- **Search** any KKS (full or partial: `11LAB70AA501`, `LBA80`, `CP101`), or text you've entered (location, notes).
- **Tap a tag** on a drawing → panel with the decoded KKS (unit, system, component), which sheets it appears on,
  linked procedures, location fields, notes, custom fields and photos. Press **Save** after editing.
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

## Your data
Everything you enter lives in `plant.db` and `photos/`. **Back up those two** (copy to USB/cloud) regularly.
Updating the app later: replace everything except `plant.db` and `photos/`.

## Adding a new P&ID
```
pip install pymupdf opencv-python-headless numpy
python3 import_sheet.py path/to/drawing.pdf "Condensate System"
```
Works on vector PDFs plotted from AutoCAD (all of yours are). Scanned drawings won't work.
It fixes rotation, reads tags with the character library in `extractor/fontlib.pkl`, and adds the sheet.
Characters the library hasn't seen get low confidence and land in the review queue rather than being guessed.
