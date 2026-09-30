# 0005 Importer: PyMuPDF, OpenCV, NumPy

Date 2026-09-30 · Scope: the P&ID importer only (manager's machine, `.venv`, not in the desktop package) · Status: keep

**Needed for:**
- rendering vector PDFs at chosen resolutions and exporting SVG (PyMuPDF);
- contour detection and image operations for tag reading (OpenCV, NumPy).

**Platform:**
- Windows (`Windows.Data.Pdf`) and Linux (Poppler, per distribution) can render PDF pages to bitmaps.
- Neither gives per-path SVG export or `show_pdf_page` placement.
- No platform has contour analysis.

The importer runs on one machine, as a batch tool.

**Dependency check:** all three pass.

| | Releases | Activity | License |
|---|---|---|---|
| PyMuPDF | 1.28.2 on 2026-08-06 | 7 committers in the last 12 months (Artifex) | AGPL-3.0, same as this project |
| opencv-python-headless | 5.0.0.93 on 2026-07-29 | — | Apache-2.0 |
| NumPy | 2.5.3 on 2026-09-06 | — | BSD-3-Clause |

**Decision:** keep. This is a single-machine tool with no platform equivalent. Its outputs are pinned by the
regression checks described in CLAUDE.md.

**Revisit:** if the importer ever ships to users.

Sources: https://pypi.org/pypi/PyMuPDF/json · https://pypi.org/pypi/opencv-python-headless/json · https://pypi.org/pypi/numpy/json · https://github.com/pymupdf/PyMuPDF
