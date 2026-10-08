# kks-import: the drawing importer in Nim (M6 phase 4, decision 0026)

This adds a P&ID to the plant data:
- it reads the KKS tags with the glyph reader;
- it writes the path store (`.kkp`), the overview pyramid and the source PDF;
- it updates `sheets.json` and `tags.json`.

It replaced the old Python importer (`import_sheet.py` + `extractor/`, removed with the old app on 2026-10-03; in git
history) and **read exactly what that importer read**. That was the gate of decision 0026, met on 2026-10-01.

    kks-import DRAWING.pdf "Display name" [SHEET_ID] [--rotate auto|0|90|180|270] [--replace]
               [--data-dir plant-data] [--glyphs importer/fontlib.kgl] [--effort 7] [--legend auto|hrsg|none]

The last output line is `RESULT {json}`. Formats: docs/PATHSTORE.md (the files), docs/GLYPHLIB.md (the glyph
library).

## Valve types from the drawn symbols (`src/kksi/valves.nim`)

Each valve tag (a full KKS with component `AA`) may get an optional `symbol` field in tags.json:

    "symbol": {"type": "globe valve", "actuator": "none", "nc": false, "conf": 0.93, "bbox": [x0, y0, x1, y1]}

- `type`: the HRSG legend's name: `globe valve` (a plain bowtie), `gate valve` (a full centre line), `check valve`
  (an inner bar near one end), `min-flow valve` (inner bar and a stem), `control valve` (the body in a box),
  `jam valve` (a stem ending in a T).
- `actuator`: `motor` (a stem to a square: the legend's ELECTRIC valves) or `none`. The legend has no pneumatic
  actuator, so none is reported.
- `nc`: the body is hatched. Read as "drawn closed"; the legend doesn't define hatching, so it is a hint.
- `conf`: a heuristic for what to check first (body complete, hatch clear, link close and unambiguous), not a
  probability.
- `bbox`: the symbol's body in level-0 px, like the tag's.

How:
1. **Symbols.** The X finder looks for points where diagonal strokes reach out symmetrically in all four diagonal
   directions; the strokes around each X give the body (sides, box) and the marks. Text beside a valve has upright
   strokes too, so an actuator box only counts when the stem reaches it.
2. **Legend.** Types are only written on a sheet that carries the HRSG legend table, recognised on the sheet: a row
   of same-size symbols that includes a gate, a globe, a motorised gate, a motorised globe, a control and a check
   valve. Other drawing families (the Block 1 / MA piping sheets) draw the same shapes with other meanings and have
   no legend on the sheet, so their valves get no type. `--legend hrsg|none` overrides the search.
3. **Link.** A tag links to its nearest symbol when the gap between their boxes is at most 25 units (12.5 pt), the
   symbol's nearest valve tag is this tag, and the next symbol is at least 15 units further. A symbol that is
   another tag's mutual nearest doesn't count as "the next" (stacks of valves, each tag touching its own). The
   legend's symbols are never linked. Anything else stays without a type.

The field is written on every import; `--keep-tags` refreshes it (removed where no symbol is linked any more) and
changes nothing else of any tag. `tests/test_valves.nim` covers each legend shape, the legend row, the link rules and
the --keep-tags annotation on synthetic drawings.

**Gate on the real sheets (2026-10-08):** the previous importer and this one, on copies of all 17 sheets: every tag
identical apart from `symbol`. Results and the eye check: the pull request that added this.

## Build

1. MuPDF 1.28.5. The importer was matched against PyMuPDF 1.28.2 (MuPDF 1.28.2: same renderer, same glyph images);
   1.28.3-1.28.5 fix memory-safety bugs (#51). Checked on all 17 plant sheets (2026-10-08): the same tags and the
   same `.kkp`, byte for byte; the overview pyramid identical on 16, on one ~300 anti-aliased pixels of 16 MP differ.
   Fetch it once, pinned by SHA-256:

       sh importer/fetch_mupdf.sh          # into ~/.local/kksdev (KKS_DEV)

2. libjxl: the system's `libjxl.so.0.11`. Its headers come from `libjxl-dev`; without root, unpack the .deb into
   `$KKS_DEV/root`:

       apt-get download libjxl-dev && dpkg-deb -x libjxl-dev_*.deb ~/.local/kksdev/root

3. Build and test:

       cd importer && nim c -d:release kks_import.nim && nim test

## How it stays identical to the Python importer

**MuPDF** (`src/kksi/kks_mupdf.c`) mirrors PyMuPDF call by call:
- `show_pdf_page` (the rotated copy);
- `get_pixmap`;
- `get_drawings` (PyMuPDF's line-art device: paths, styles, fill+stroke merging; the unrotated page);
- the matrix arithmetic, which mixes Python doubles and MuPDF floats exactly as PyMuPDF does.

One difference: the page's display list is cached between renders. PyMuPDF builds the same list on every call;
reusing it changes no pixel.

**OpenCV** (`src/kksi/imgops.nim`, `contours.nim`): ported from OpenCV 5.0.0 (Apache-2.0) where pixels matter.
- `convexHull` (Sklansky), `fillPoly` (edge collection with LINE_8 outlines) and `erode`.
- `connectedComponentsWithStats`: labels in the order of each component's first 2×2 block, as OpenCV's Spaghetti
  labeller numbers them.
- `findContours` holes, without porting Suzuki: each hole is a 4-connected background region enclosed by an
  8-connected component. Its border is that component's pixels next to it. Order: descending (the component's
  first pixel, the hole's start).
- `resize` INTER_AREA and the 3×3 Gaussian on float32, bit for bit. The Gaussian uses fused multiply-adds like
  cv2's AVX2 build.

**numpy/OpenBLAS** (`src/kksi/kks_dot.c`): the kNN similarities follow OpenBLAS 0.3.34's Haswell kernels.
- 8 FMA lanes for groups of 4 library rows.
- SSE multiply-then-add for the 2 leftover rows.
- `sdot` for the norm.
- With more than one thread, OpenBLAS splits the rows by thread, and the chunk tails use the SSE kernel. **So the
  Python reference itself depends on the thread count.** The gate is checked against a single-thread trace
  (`OPENBLAS_NUM_THREADS=1`).
- Exactly tied neighbours are duplicate library vectors with the same label, so their order never changes a
  reading.

**Python's number rules:**
- `round()` (ties to even, through printf for 1 and 2 decimals);
- `int()` truncation, `np.median`, numpy's float32 promotion (NEP 50).

## Tests

- `nim test`: synthetic cases only, no plant data (CI-safe).
  - `tests/test_reader.nim`: every OpenCV operation against cv2, plus clean, split, interpret and classify against
    the old Python reader. Vectors: `tests/vectors/cv2-ops.json.gz`, frozen (made by `make_op_vectors.py` with
    `OPENBLAS_NUM_THREADS=1`; the script went with the Python reader, see git history).
  - `tests/test_kkp.nim`: the `.kkp` writer on a synthetic drawing. The page has /Rotate and a crop box, every path
    kind and style, an RGBA image and a turned one. It is compared with `ref/pathstore.py` (`make_kkp_vectors.py`).
- Local gate on the real sheets (plant data; reference dumps in a folder outside the repository):
  - the reading was checked against the Python reader's dumps (`dump_ref.py`, `dump_cells.py`: removed with it; the
    dumps made on 2026-10-01 still work as the reference for `diff_render.nim`, `diff_holes.nim` and
    `diff_trace.nim REF importer/fontlib.kgl`);
  - `dump_kkp.py REF` and `dump_kkp_images.py REF` (from `ref/`), then `diff_kkp.nim REF`.
  - **A change to the reader** is checked against the *previous* Nim importer's output on all sheets: every tag cell
    old vs new, and look at every changed crop.

## Result (2026-10-01, all 11 sheets)

- **Every step identical:** orientation scores, 5,350 cell crops and masks (hashes), 27,847 glyphs (label,
  confidence and all 5 similarities, bit for bit), 2,130 tags.
- **Time:** 3.5 min single-threaded for all 11 sheets, 4 orientation scores each. The Python importer took 11 min on
  11 processes.
- **LP against its hand-checked tags:**
  - 203 of 207 read the same.
  - The other 4 are hand-verified tags the reader can't read. They go to the review queue; none is misread.
- **.kkp:** vectors byte-identical; images as described in docs/PATHSTORE.md.
