# Dependency record: MuPDF 1.28.2

Added: 2026-10-01 (the Nim importer, decision 0026; before that through PyMuPDF, decision 0005)   Pull request: @@PR@@   Recorded by: Claude for Hashim, 2026-10-05
Kind: runtime (server side: linked statically into `kks-import`, which the server runs for the Drawings page)
Packages covered: MuPDF (`libmupdf.a` and `libmupdf-third.a` from the pinned source release)

## Purpose
Opens the P&ID PDFs, renders them at the resolutions the tag reader needs, and walks their vector paths for the
drawing store (`importer/src/kksi/mupdf.nim`, `kks_mupdf.c`).

## Platform alternative checked
Decision 0026: the importer runs on the Linux server host. GNOME/Ubuntu provide Poppler + Cairo, which render and
expose vector geometry [V there]; Windows' `Windows.Data.Pdf` only rasterizes. Poppler falls short for a reason
specific to this project: the glyph library (`importer/fontlib.kgl`, 27,847 samples) was trained on MuPDF's
rasterization, and the reader's accuracy depends on pixel-identical glyph images. Switching renderer means retraining
and re-verifying every sheet (CLAUDE.md, "Lessons"; 0026 "Revisit").

## Custom implementation considered
A PDF parser and rasterizer of our own: PDF object syntax, compression filters, content streams, fonts and
anti-aliased rendering that matches the trained glyphs. That is a large body of parsing code for files that come from
outside (contractor drawings), far beyond what this project can own safely.

## Transitive dependencies
Count: 12   How counted: the third-party libraries the release build actually compiles into `libmupdf-third.a`
(`importer/fetch_mupdf.sh`: `make HAVE_X11=no HAVE_GLUT=no HAVE_CURL=no HAVE_LIBCRYPTO=no build=release libs`), that
is the directories in `build/release/thirdparty/`: brotli 1.2.0, cmark-gfm 0.29.0.gfm.13, extract (Artifex),
FreeType 2.14.3, gumbo-parser 0.10.1, HarfBuzz 13.0.1, jbig2dec (Artifex), lcms2mt (Artifex's fork of Little CMS),
libjpeg 10, MuJS 1.3.8 (Artifex), OpenJPEG, zlib 1.3.2. They come vendored inside the one pinned source tarball (MuPDF's
git submodules at the commits the release names). Tesseract, Leptonica, zint, zxing-cpp, curl and freeglut are in the
tarball but not built.

## License
AGPL-3.0-or-later (or a commercial license from Artifex). Compatible: the project itself is AGPL-3.0. Copyleft, so it
would be "review-needed" under a typical allowlist; the review is this record and 0026. Transitive: MIT (brotli,
HarfBuzz, lcms2mt), BSD-2-Clause (cmark-gfm, OpenJPEG), FTL (FreeType, dual FTL/GPL-2.0), Apache-2.0 (gumbo), IJG
(libjpeg), ISC (MuJS), AGPL-3.0 (extract, jbig2dec), Zlib (zlib).

## Maintenance signals
- Recent releases: 1.28.5 on 2026-09-25, 1.28.4 on 2026-09-15, 1.28.3 on 2026-08-26, 1.28.2 on 2026-08-04, 1.28.0 on
  2026-06-26, 1.27.0 on 2025-12-12 ([release history](https://mupdf.com/releases/history)).
- Security response: no SECURITY.md or GitHub advisories (the GitHub repository is a mirror; bugs go to Artifex's
  Bugzilla). CVEs are filed and fixed regularly, e.g. CVE-2026-3308 (integer overflow in `pdf-image.c`, 1.27.0) and
  CVE-2026-25556 (double free, 1.23.0–1.27.0) ([OpenCVE list](https://app.opencve.io/cve/?product=mupdf&vendor=artifexsoftware)).
  The releases after our pin fix several memory-safety bugs found by fuzzing: 1.28.5 lists OOB reads and writes, a
  stack overflow in recoloring and TTF-subsetting overruns.
- Active maintainers: Artifex staff; 7 commit authors in the last 12 months, led by robinwatts (352), artifex-tor
  (274) and sebras (232) (GitHub contributor statistics, 2026-10-05).
- Age across major versions: first released in 2005 ([Wikipedia](https://en.wikipedia.org/wiki/MuPDF)); 1.x since
  2012, with C API changes between minor releases (our shim `kks_mupdf.c` isolates them).

## Size impact
`kks-import` (Linux x86_64, release) is 44.8 MB. By symbol name: MuPDF's built-in font and resource blobs 34.6 MB,
MuPDF code 1.8 MB, its third-party libraries about 1.9 MB (HarfBuzz 1.0, FreeType 0.3, brotli 0.3, others); the rest
is our importer (`nm --size-sort -S`). It ships only on the server host, never to devices.

## Replacement cost
High. Every reading depends on MuPDF's rendering: replacing it (or changing its version in a way that moves pixels)
means a full re-verification of the reader on every sheet with the regression harness (CLAUDE.md, "Lessons").
The C surface itself is small (one shim file).

## Decision
Keep. The glyph library and the verified readings bind the reader to MuPDF's rendering, and no platform renderer or
own parser can match that at lower cost. The pin to 1.28.2 is deliberate (the version the Python reference used, so
the Nim port could be gated bit for bit, 0026), but it now lags three patch releases with memory-safety fixes. Input
is limited to PDFs the plant's manager uploads after signing in, which lowers the exposure without removing it. Action
for the owner: move to the current 1.28.x patch release and re-run the importer's gate (`importer/tests/`, all
sheets old vs new) before the next release audit.
