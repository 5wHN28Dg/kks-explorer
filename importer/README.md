# kks-import: the drawing importer in Nim (M6 phase 4, decision 0026)

This adds a P&ID to the plant data:
- it reads the KKS tags with the glyph reader;
- it writes the path store (`.kkp`), the overview pyramid and the source PDF;
- it updates `sheets.json` and `tags.json`.

It replaces `import_sheet.py` + `extractor/`, and **reads exactly what the Python importer reads**. That is the gate
of decision 0026, met on 2026-10-01.

    kks-import DRAWING.pdf "Display name" [SHEET_ID] [--rotate auto|0|90|180|270] [--replace]
               [--data-dir plant-data] [--glyphs extractor/fontlib.kgl] [--effort 7]

The last output line is `RESULT {json}`. Formats: docs/PATHSTORE.md (the files), docs/GLYPHLIB.md (the glyph
library).

## Build

1. MuPDF 1.28.2, the version PyMuPDF 1.28.2 bundles. Same renderer means the same glyph images. Fetch it once,
   pinned by SHA-256:

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
    the Python extractor. Vectors: `tests/vectors/cv2-ops.json.gz`, made by `tests/make_op_vectors.py` with
    `OPENBLAS_NUM_THREADS=1`.
  - `tests/test_kkp.nim`: the `.kkp` writer on a synthetic drawing. The page has /Rotate and a crop box, every path
    kind and style, an RGBA image and a turned one. It is compared with `ref/pathstore.py` (`make_kkp_vectors.py`).
- Local gate on the real sheets (plant data; reference dumps go to a folder outside the repository):
  1. `.venv/bin/python importer/tests/dump_ref.py REF` (renders, clips, drawings);
  2. `OPENBLAS_NUM_THREADS=1 .venv/bin/python importer/tests/dump_cells.py REF` (the reading, call by call);
  3. `dump_kkp.py REF` and `dump_kkp_images.py REF`;
  4. then `tests/diff_render.nim`, `diff_holes.nim`, `diff_trace.nim REF extractor/fontlib.kgl` and
     `diff_kkp.nim REF`.

## Result (2026-10-01, all 11 sheets)

- **Every step identical:** orientation scores, 5,350 cell crops and masks (hashes), 27,847 glyphs (label,
  confidence and all 5 similarities, bit for bit), 2,130 tags.
- **Time:** 3.5 min single-threaded for all 11 sheets, 4 orientation scores each. The Python importer took 11 min on
  11 processes.
- **LP against its hand-checked tags:**
  - 203 of 207 read the same.
  - The other 4 are hand-verified tags the reader can't read. They go to the review queue; none is misread.
- **.kkp:** vectors byte-identical; images as described in docs/PATHSTORE.md.
