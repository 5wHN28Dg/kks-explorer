# The glyph library format (`.kgl`, version 1)

The reader classifies each character of a tag box by comparing it with labelled glyphs (decision 0026). Until M6
the library was `extractor/fontlib.pkl`, a Python pickle of `(X, Y)`. That format can't be read outside Python, so
the library is now also written as `extractor/fontlib.kgl` by `tools/fontlib_export.py`. The Nim importer
(`importer/src/kksi/fontlib.nim`) reads only this file.

The file is one gzip stream. Inside it:

| Offset | Size | Field |
|---|---|---|
| 0 | 8 | magic `KKSGLYPH` (ASCII) |
| 8 | 4 | format version, `1` (u32, little-endian) |
| 12 | 4 | `n`: number of glyphs (u32 LE) |
| 16 | 2 | glyph width `GW` = 20 (u16 LE) |
| 18 | 2 | glyph height `GH` = 32 (u16 LE) |
| 20 | n·GW·GH·4 | the glyph vectors: `n` rows of GW·GH float32 LE, each row a normalised 32×20 image in row-major order |
| … | … | `n` labels: one length byte, then that many bytes of UTF-8 |

A reader must reject a wrong magic, an unknown version, another glyph size, a truncated file and trailing bytes.

**Vectors.** Each row is a glyph image made by `norm()` (extractor/segment.py; fontlib.nim):
1. The glyph is scaled to height 32 with OpenCV's INTER_AREA.
2. It is centred on a 20-wide canvas (cut on the right if wider).
3. The canvas is blurred with a 3×3 Gaussian, σ 0.8.
4. The result is divided by its Euclidean norm.

The vectors are stored exactly as the pickle held them.

**Labels.**
- A label is usually one character (`0`–`9`, `A`–`Z`).
- A label can also be several characters: glyphs that touch and can't be split, such as `11` or `AD90`.
- The empty label marks noise that the reader skips.
- Identical vectors always carry the same label: checked on 2026-10-01, 1837 groups of duplicates, none with mixed
  labels. So the order among exactly tied neighbours never changes a reading.

**Version 1 content** (2026-10-01): 13,794 glyphs, 49 labels. The gzip file is 9.4 MB; the pickle is 35 MB.

Rebuild after changing the library:

    .venv/bin/python tools/fontlib_export.py extractor/fontlib.pkl extractor/fontlib.kgl

The output is deterministic (gzip level 9, mtime 0).
