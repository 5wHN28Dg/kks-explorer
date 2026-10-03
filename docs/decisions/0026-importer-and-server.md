# 0026 Where the drawing importer and the always-on server run

Date 2026-09-30 · Scope: R19, R21, R22 · Status: **decided by the user 2026-09-30: importer and server in Nim** (the Python proposal below was rejected)

## Gate result (2026-10-01): met

The Nim importer (`importer/`, README there) reproduces the Python importer's reading on all 11 sheets, bit for bit:
- orientation scores;
- 5,350 cell crops and masks;
- 27,847 glyphs (labels, confidences, all kNN similarities);
- 2,130 tags.

On LP, 203 of the 207 stored tags read the same. The other 4 are hand-verified tags the reader can't read; they go
to review, and none is misread.

What exactness took:
- MuPDF 1.28.2, built from the pinned source.
- OpenCV's operations ported where pixels matter (OpenCV 5.0.0 source, Apache-2.0).
- The float order of numpy's OpenBLAS kernels for the kNN.
- Found on the way: **the Python reference itself depends on OpenBLAS's thread count**. Rows at thread-chunk
  boundaries use another kernel, which moves similarities by 1 ulp. The gate therefore compares against a
  single-thread trace.

The glyph library is in the documented format (`extractor/fontlib.kgl`, docs/GLYPHLIB.md). The Python importer can
retire once the server's Drawings page calls `kks-import`.

## User decision (2026-09-30)

**The importer and the server are written in Nim**, like the desktop core (0027). The Python proposal below is kept
for the record, with the risks it named. Consequences for the importer port:
- **Rendering stays MuPDF.** PyMuPDF is a binding over MuPDF's C library, so Nim calls MuPDF's C API directly (a
  small C shim for its `fz_try`/`fz_catch` error handling). With the same MuPDF version and render settings, the
  glyph images stay the same and the trained glyph library stays valid.
- **OpenCV is replaced by our own Nim code** for the 12 operations actually used (grep of extractor/, 2026-09-30):
  - `findContours` with the hole hierarchy (RETR_CCOMP, CHAIN_APPROX_NONE), `contourArea`, `boundingRect`,
    `convexHull`, `fillPoly`;
  - `connectedComponentsWithStats`;
  - `erode`, `GaussianBlur`;
  - `resize` (INTER_AREA), `rotate`, `copyMakeBorder`, `imread`.

  OpenCV 5's API is C++ only. Contour tracing (Suzuki–Abe), area resampling and Gaussian blur must match OpenCV
  **pixel for pixel**, or readings shift. Each operation gets its own test against OpenCV's output on the real crops
  before the whole pipeline is compared.
- **Acceptance gate:** the Nim importer must reproduce the Python importer's reading of every tag cell on all 11
  sheets (the regression harness pins the Python output as the reference), plus the LP reference. Until it does, the
  Python importer remains the one used.
- The glyph library moves to a documented binary format (as proposed below), readable by Nim.

## The importer (R21): the original proposal

**What it does:**
- orient each PDF page;
- find the tag boxes (contours);
- read the text strokes with a kNN glyph library (35 MB, trained on **MuPDF's** rendering);
- apply the KKS grammar.
- v2 adds: the grid-indexed path store (0015) and the overview pyramid (0016).

It runs on one machine, the manager's, as a batch job.

**Platform facts:**
- Vector geometry and rendering of PDFs: ✅ Poppler + Cairo on GNOME [V]; ❌ on Windows (Windows.Data.Pdf only
  rasterizes) [D].
- Contour detection and classification: ❌ no platform anywhere. That's our code, or OpenCV.

**The evidence that matters most:**
- The glyph library was trained on MuPDF's rasterization.
- CLAUDE.md records how easily accuracy regresses: one geometric rule broke other fonts, and a harness compared new
  code against new code by mistake.
- Switching the renderer to Poppler, or porting the pipeline to another language, means retraining and re-verifying
  every sheet against the LP reference and the regression checks.

**Proposed:**
- **Keep the importer as today's Python pipeline:** PyMuPDF (AGPL-3.0, like this project), OpenCV, NumPy.
- **Extend it** to write the v2 plant-data files: path store, JXL pyramid, tags. It is a manager tool on one machine,
  not an app the team installs, so the native policy's bundled-runtime concern doesn't apply to it.
- It runs on **Linux (GNOME)**, the manager's machine today.
- If a future manager works on Windows, it runs there under Python as well (PyMuPDF and OpenCV have Windows wheels
  [K]). That is not a supported target of the apps.
- **Replace the pickle glyph library** (`fontlib.pkl`, a Python-only format) with a documented binary format. Then the
  library isn't tied to Python, and could be ported later with a way to check the port.
- Any change to rendering or reading is gated by the existing regression rules: compare every cell old vs new on all
  sheets, pin the old behaviour in the harness itself.

## The always-on server (R19): the original proposal (now in Nim)

**Role:**
- a peer that is always up;
- the password sign-in for browser clients (Argon2id, 0023);
- serving the web UI (0014);
- the "join via server" path;
- backups (0020).

**Platform:** headless Linux (no GNOME):
- systemd unit (deploy/);
- `systemd-creds` + TPM2 for its storage key (0020);
- OpenSSL ≥ 3.2 for Argon2id (0023);
- the system's SQLite and TLS.
- Remote access through Cloudflare Tunnel + Access, once IT approves (https://github.com/5wHN28Dg/kks-explorer/wiki/Remote-access).

**Proposed:**
- The server is **the desktop core built without a UI**: same language and code (the language decision, next), plus
  an HTTP server for the web UI.
- The relay stays a Cloudflare Worker, with its test twin (0012).

**Costs:**
- The importer keeps Python and its three libraries for one machine.
- The glyph library needs converting once, with a check that the classifier gives identical results before and
  after.

**Revisit:**
- if the importer must run on many machines;
- if a retraining/verification campaign for a Poppler-based reader becomes worth doing (e.g. to drop PyMuPDF).

Sources: CLAUDE.md ("How extraction works", "Lessons", accuracy status in CLAUDE.local.md); docs/m6/CAPABILITIES.md §6; docs/decisions/0005, 0012, 0015, 0016, 0020, 0023
