# The grid-indexed path store (`.kkp`), version 1

**Status: draft, M6 phase 1 (2026-09-30).** Decision records 0015 (format) and 0016 (rendering). Reference
implementation: `ref/pathstore.py` (test-only). Vectors: `ref/vectors/pathstore-v1.json`. The vectors, not the prose,
are the tiebreaker.

One `.kkp` file holds the drawing of one sheet, made once by the importer from the source PDF and published as plant
data (PROTOCOL-v2 §19). A viewer draws any rectangle of the sheet at any zoom by visiting only the grid cells that
the rectangle touches, and drawing their paths with the platform's own 2D API:
- Direct2D on Windows;
- Cairo or GSK on GNOME;
- `Canvas` on Android;
- HTML canvas in browsers.

## What the drawings contain (evidence, 2026-09-30, all 11 plant sheets)

- 16k–119k paths per sheet, 59k–331k segments (lines, cubic curves, rectangles, quads).
- **No dash patterns:** dashed lines are already separate strokes.
- Line caps butt or round; joins miter, round or bevel.
- Width 0 (hairline) is common.
- Fills use both the nonzero and the even-odd rule.
- Colours: black plus a few (red, blue, white). No transparency.
- **2–6 raster images per sheet:** title-block logos, the revision stamp, the scanned approval table with signatures.

The format stores exactly these features. A feature the importer finds that the format can't hold is an import error,
never silently dropped.

## Encoding basics

- Little-endian for fixed-size integers and floats.
- **varint** = unsigned LEB128, at most 5 bytes (values < 2^32).
- **svarint** = zigzag-encoded signed value in a varint: `(n << 1) ^ (n >> 31)`.
- **Units:** coordinates are integers in **1/64 point** (a quantum of 0.0055 mm), in the sheet's display
  orientation: the source page's rotation and the importer's chosen rotation already applied, origin top-left, y down.

## Layout

```
magic      4 bytes  "KKP1"
version    u16      1
flags      u16      bit 0: everything after this field is one zlib stream (RFC 1950, deflate) holding the rest
                    of the file; other bits 0 (readers reject them). The importer always sets bit 0; readers
                    accept both.
width      u32      sheet width in quanta
height     u32      sheet height in quanta
grid_x     u16      columns of the grid (1..1024)
grid_y     u16      rows of the grid (1..1024)
n_styles   varint
n_paths    varint
n_images   varint
styles     n_styles × style
paths      n_paths × path
grid       grid_x × grid_y cells, row by row (cell (0,0) first, then (1,0) …)
images     n_images × image
```

A reader rejects the file if anything is left over after the last image, or anything is missing.

### style

```
kind       u8    bit 0 stroke, bit 1 fill, bit 2 even-odd fill rule (else nonzero), bit 3 hairline;
                 other bits 0. At least one of stroke/fill.
cap        u8    0 butt, 1 round, 2 square
join       u8    0 miter, 1 round, 2 bevel
width      varint  stroke width in quanta; 0 when hairline or not stroked
stroke     3 bytes  R, G, B (0..255); 0,0,0 when not stroked
fill       3 bytes  R, G, B; 0,0,0 when not filled
```

- **Hairline:** draw one device pixel wide at any zoom (PDF width 0).
- **Thin strokes:** a stroke narrower than one device pixel at the current zoom is drawn one device pixel wide. This
  matches Poppler and MuPDF, and was measured in 0015 (at 1× thin lines otherwise render lighter).
- **Zoomed out:** below one device pixel per point, a renderer may draw hairlines and thin strokes half a device pixel
  wide instead, so dense lettering doesn't fill in when the whole sheet is in view (the GNOME app does, since 2026-10-07).
- **Miter limit:** fixed at 10 (the PDF default).
- **Fill and stroke:** when both are set, fill first, then stroke, with the same geometry.

### path

```
style      varint   index into styles
bbox       4 × varint   x0, y0, x1, y1 in quanta; x0 ≤ x1, y0 ≤ y1; bounds the path's points, stroke width included
n_cmds     varint   number of commands (≥ 1)
cmds       ceil(n_cmds / 4) bytes: 2 bits per command, first command in the lowest bits
           0 move (1 point), 1 line (1 point), 2 cubic (3 points: control 1, control 2, end), 3 close (no point)
points     for each point in command order: dx, dy as svarint
```

- The first point's delta is from (x0, y0) of the bbox. Each later point's delta is from the previous point
  (control points included), across commands.
- **Command rules:**
  - The first command is a move.
  - `close` goes back to the last move point.
  - A `line` or `cubic` right after a `close` continues from that move point, as in PDF.
  - Unused bits in the last command byte are 0.
- **Paint order** is file order. Paths are stored in the order the PDF paints them.

### grid

For each cell, in row order:
```
count      varint   number of paths touching the cell
first      varint   index of the first (if count > 0)
deltas     (count − 1) × varint   each index minus the previous one, > 0
```

- Cell (i, j) covers x from `i·width/grid_x` to `(i+1)·width/grid_x` (integer division), and the same for y.
- A path is listed in every cell its bbox touches.
- Indices are in ascending order, so drawing a cell's list keeps the paint order. A viewer drawing several cells merges
  their lists in ascending order, without duplicates.
- **Grid size:** the importer makes cells of about 100 pt: `g = clamp(ceil(longer side / 100 pt), 8, 64)` on the
  longer side, proportionally on the other. Readers accept any valid size.
  - Measured 2026-09-30: finer grids list long paths (frames, pipe runs) in many cells. A 512×263 grid on LP cost
    500 KB of index against 56 KB at 33×17, for little gain in drawing time.
- **Compression** (measured 2026-09-30 on LP, FW and b1cond):
  - uncompressed, the file is 2–2.5× the source PDF;
  - deflated, it is 0.6–1.0×. The PDF itself is deflate-compressed.
  - The quantum barely matters: 1/16 pt saves under 10 %.
  - Deflate is platform-provided on Android (`java.util.zip`), GNOME (zlib / GLib) and in browsers
    (`DecompressionStream`). Windows has no deflate in its API (its Compression API offers MSZIP, XPRESS and LZMS
    only), so the Windows app links **zlib** (v1.3.2, 2026-02-17, 7 authors in the last year, zlib license; decision
    0015).

### image

```
after      varint   number of paths painted before this image (0..n_paths); images with the same value keep file order
rect       4 × varint   x0, y0, x1, y1 in quanta: where the image is drawn (axis-aligned, stretched to fill)
length     varint   byte length of the image data
data       JPEG XL codestream or container, lossless (docs/decisions/0018)
```

Images are few and small, so they are not in the grid. A viewer tests each image's rect against its view.

## Measured on the 11 plant sheets (2026-09-30, `tools/m6/pathstore_measure.py`)

- **Size:** 210–1 574 KB per sheet, **5.6 MB in total against 8.0 MB of source PDFs**. The largest relative size is
  IP, 1.7× its PDF, because of its 356 KB lossless signature scan.
- **Import time:** 2–13 s per sheet in the Python reference.
- **Picture against MuPDF** (the importer's renderer), 4 spots × 3 zooms per sheet, drawn by Cairo from the decoded
  file:
  - 5 sheets match to ≤ 0.03 % of pixels at 4× and 16× (FW, HP, IP, Flue, Reheat).
  - The others differ by up to 3 % at 4×. The cause, seen on the tiles, is rendering policy, not data: MuPDF draws
    width-0 hairlines, and strokes thinner than a pixel, lighter than this spec's "at least one device pixel" rule.
    That makes small logo lettering (hundreds of tiny fills outlined with hairlines) look bolder here.
  - Kept deliberately: on the hairline CBD sheet the rule is what makes 0.12 pt lines readable.
- **Bugs this found in the reference encoder, fixed:**
  - image masks (the POWERCHINA logo drew on a black square);
  - pages with /Rotate (images must be turned in their pixels);
  - the reference-tile origin, which MuPDF snaps to whole pixels.

## The importer's output (M6 phase 4, 2026-10-01)

`kks-import` (importer/, Nim) writes per sheet, into the manager's plant-data working copy:
- `sheets/<id>.pdf`: the drawing as given, the source of record.
- `sheets/<id>.kkp`: this format.
- `sheets/<id>.o<k>.jxl`, k = 0, 1, …: the **overview pyramid** (decision 0016).

**The overview pyramid:**
- Level 0 is the sheet rendered by MuPDF in RGB at `scale` px/pt, where `scale = min(2, 6400 / longer page side in
  points)`. This is the scale of v1's sheet PNG, so tags keep their v1 pixel coordinates.
- Each further level is rendered directly at half the previous scale, not downsampled.
- The last level is the first one whose longer side is at most 512 px. It is also the sheet's thumbnail.
- Encoding: lossless JPEG XL, effort 7.
- Measured on LP: 5 levels, 1.75 MB together, against 1.17 MB for v1's greyscale PNG.

**The vector paths:**
- They are byte-identical to `ref/pathstore.from_pdf_page` on all 11 sheets (`importer/tests/diff_kkp.nim`).
- They take 0.1–0.6 s per sheet.

**The images:**
- Placement (`after`, `rect`) is identical to the reference.
- The pixels are the image as MuPDF draws it:
  - decoded by MuPDF, with colour-key transparency and the soft mask as straight alpha;
  - turned to sRGB by MuPDF, like every vector colour.
- PNG/Flate images match the reference exactly.
- JPEG images differ by up to 84 levels in single pixels (same means): the reference decodes them with Pillow's
  libjpeg-turbo, while MuPDF uses its own libjpeg. The importer follows MuPDF, the renderer the reading is calibrated
  on. Its pixels equal MuPDF's own decode of the same PDF object.

**sheets.json** (v2 entry):

    {"id", "name", "rot", "w", "h", "scale", "levels", "notes": [...], "links": [...]}

- `w`, `h`: level 0's size in px.
- `rot`: the rotation applied to the source page after its own /Rotate is reset to 0 (the importer's `rotatedCopy`).
  The overview, the tags and the .kkp all share that frame; kks-import gets the .kkp there with
  `from_pdf_page(page, extra)`, extra = −(rot + the page's /Rotate) mod 360 (`kkp.sheetExtra`).
- `levels`: the number of pyramid files.
- `links` (since 2026-10-07; optional, absent = none): the sheet's off-page connectors, `{"label", "bbox", "conf"}`.
  - `label`: the code in a connector circle, a capital letter and 1–2 digits (`"C16"`, `"D2"`). The same label on
    another sheet is where the line continues; twice on one sheet, the line continues there.
  - `bbox`: the circle's box in level-0 pixels, like a tag's.
  - `conf`: the lowest glyph confidence of the reading (0–1).
  - Written by kks-import in both modes (`--keep-tags` too: it leaves the tags' readings alone) from the circles found in the
    drawing's vectors (importer/README, "Off-page connectors"). Readers ignore entries without a label or a 4-number
    box. core `model.parseSheets` reads them, `views.linksView(sheet)` gives each connector with its targets.
- tags.json is as in v1. A tag's `bbox` is in level-0 pixels. A valve tag may carry an optional `symbol`
  (the drawn valve symbol's type, actuator and `nc`: hatched, meaning normally closed; importer/README "Valve
  types"); readers ignore fields they don't know.

## Drawing a view (informative)

A viewer:
1. converts the view rectangle to quanta;
2. collects the cells it touches;
3. merges their path lists;
4. draws each path whose bbox intersects the view, with its style;
5. draws the images, interleaved at their `after` positions.

Decisions 0016: tiles are drawn on the CPU on background threads and cached, and the GPU composites them.

## Limits

- Sheet up to 2^32 quanta per side (about 1 000 km; no practical limit).
- Up to 2^32 − 1 paths and styles.
- A file larger than 256 MiB, compressed or not, is rejected by readers.
