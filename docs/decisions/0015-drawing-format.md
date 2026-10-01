# 0015 Drawing format for the viewer: PDF, SVG, or indexed paths

Date 2026-09-30 · Scope: R1 (viewer), R21/R22 (import, plant data) · Status: **accepted by the user 2026-09-30**, measured on
the laptop and on a phone

**Question (the user):** which renders faster, PDF or SVG? Is it the same on every platform? Does the content favour
one?

**Content:**
- Our P&IDs are AutoCAD plots: 39k–119k separate stroke paths per sheet. All text is strokes.
- The original PDFs are 0.4–1.6 MB.
- Today's viewer data: merged SVG, 13–134 paths, 3–10 MB, drawn by the browser (Skia).

**Measured** on this laptop (i7-12700H, one thread, CPU Cairo, 512 px tiles, median of 5; tools/m6/):

| Sheet | Renderer | Tile 1× | Tile 4× | Tile 16× |
|---|---|---|---|---|
| lp | Poppler, original PDF | 102 ms | 91 ms | 91 ms |
| lp | librsvg, merged SVG | 112 ms | 349 ms | 4092 ms |
| lp | **grid-indexed paths** | **10 ms** | **0.9 ms** | **0.2 ms** |
| fw | Poppler, original PDF | 254 ms | 235 ms | 237 ms |
| fw | librsvg, merged SVG | 277 ms | 300 ms | 336 ms |
| fw | **grid-indexed paths** | **15 ms** | **0.9 ms** | **0.3 ms** |
| b1cond | Poppler, original PDF | 310 ms | 294 ms | 293 ms |
| b1cond | librsvg, merged SVG | 235 ms | 480 ms | 4268 ms |
| b1cond | **grid-indexed paths** | **16 ms** | **1.9 ms** | **0.1 ms** |

- Merging paths into fewer, bigger ones did **not** help: a merged PDF was slower than the original in Poppler, and
  raw vs merged SVG were alike apart from load time.
- Grid-indexed paths: the paths are extracted once at import (0.6–1.7 s per sheet), bucketed on a 32×32 grid, and each
  tile draws only the paths touching it. This ran in Python.
- Picture check against Poppler: at 4×, 0.14–0.45 % of pixels differ; at 1× thin lines render lighter (Poppler
  enforces a 1-pixel minimum line width, which is a setting to copy).

**Findings:**
- The cost comes from the **structure**, not the file format. Poppler walks the whole page for every tile, so every
  tile costs the whole sheet. librsvg gets worse the further you zoom in.
- A spatial index makes a tile cost only what it shows, whatever the format.
- "The same on every platform?" Not for the formats:
  - Android's framework renders PDF (PdfRenderer) but not SVG;
  - Windows renders both (Windows.Data.Pdf, Direct2D SVG);
  - GNOME renders both;
  - Safari renders SVG, not PDF.
- An indexed path store needs only "draw a path", which every platform's 2D API has: Direct2D, Cairo/GSK, Android
  Canvas, HTML canvas. So the same data renders natively everywhere.

**Decided:**
- At import, convert each sheet into an **indexed path store**: our own small format of paths plus a grid index,
  published as plant data.
- Each platform draws tiles with its own 2D API.
- The original PDF stays as the source of record (re-import, opening in the system viewer).
- Our own format needs a specification and test vectors, like the protocol.

**Measured on a phone:** Galaxy Note 9 (SM-N960F, Exynos 9810, Android 10), a 2018 flagship that is roughly lower
mid-range today. Same 512 px tiles, median of 5; `tools/m6/android-bench`.

| Sheet | Android PdfRenderer, original PDF (open · 1× · 4× · 16×) | Grid paths on a software Canvas (read file · 1× · 4× · 16×) |
|---|---|---|
| lp | 214 ms · 86 · 7.3 · 1.6 ms | 206 ms · **7.4 · 1.5 · 0.5 ms** |
| fw | 224 ms · 64 · 4.0 · 1.9 ms | 373 ms · **8.5 · 1.1 · 0.6 ms** |
| b1cond | 385 ms · 123 · 6.1 · 1.6 ms | 313 ms · **10.1 · 1.7 · 0.4 ms** |

- Picture check on the phone (4× tiles, PdfRenderer vs grid): 0.07–0.13 % of pixels differ (anti-aliasing).
- The first run found hollow arrowheads. That was a bug in the benchmark's path building, fixed: the fixed version
  keeps a sub-path going when a segment starts at the current point.
- Android's PdfRenderer (PDFium) skips content outside the tile, unlike Poppler, so it is fast when zoomed in. It is
  still 2–4× slower than the grid store zoomed in, and 7–12× slower at 1×.
- So the answer to "the same on every platform?" is no for PDF: its speed depends on each platform's renderer. The
  grid store behaves the same everywhere.
- File size: the benchmark's naive binary is 3.4–9 MB per sheet (0.9–2 MB gzipped). The real format should quantize
  coordinates (e.g. 16-bit within a grid cell) to get well below the original PDFs.

**GPU drawing:** measured in 0016. It is not faster for this content; tiles are drawn on the CPU and the GPU only
composites. Windows is unmeasured: no Windows machine.

Sources: tools/m6/tile_bench.py, tools/m6/grid_bench.py, tools/m6/write_paths.py, tools/m6/android-bench/ (investigation tools, not product code; run in a folder holding <sheet>.pdf, <sheet>-merged.svg/.pdf); docs/m6/CAPABILITIES.md §2

**Addendum 2026-09-30, while writing docs/PATHSTORE.md:**
- The `.kkp` body is deflate-compressed: uncompressed it measured 2–2.5× the PDF, compressed 0.6–1.0×.
- Deflate is platform-provided except on Windows. There the app links zlib (v1.3.2, 7 authors in the last 12 months,
  zlib license), which passes the maintenance test.
- The drawings' raster images (logos, stamps, the signed approval table) are stored in the file as lossless JPEG XL,
  in paint order.
