# Dependency record: Python packages for tests and tools (requirements-dev.txt)

Added: 2026-09-30 to 2026-10-03 (the protocol reference `ref/`, the e2e drivers, tools/m6; the file itself on
2026-10-03)   Pull request: https://github.com/5wHN28Dg/kks-explorer/pull/23 (record written for an existing dependency)   Recorded by: Claude for Hashim, 2026-10-05
Kind: dev-only (nothing here ships: no app, the server or the web pages import Python)
Packages covered (one shared record, as DEP-2 allows for dev-only packages that never ship; each field is given per
package where they differ): `cryptography` 50.0.1, `Pillow` 12.3.0, `numpy` 2.5.3, `opencv-python-headless`
5.0.0.93, `pymupdf` 1.28.2, `playwright` 1.63.0, `pillow-jxl-plugin` 1.3.8. The first five are pinned in
`requirements-dev.txt` today; `playwright` and `pillow-jxl-plugin` are imported by tests and tools and are added to the
file, with the transitive packages, by PR #19 (#14).

## Purpose
| Package | Used by |
| --- | --- |
| cryptography | `ref/` (the independent Python reference of PROTOCOL-v2: P-256, AES-GCM, ECIES vectors), the relay twin `relay/twin.py`, the Android e2e drivers, `tools/release.py` (the release manifest's P-256 signature) |
| Pillow | the e2e tests of the three apps (screenshots, photo checks), `ref/pathstore.py`, `importer/tests/make_kkp_vectors.py`, `tools/procedure_import.py`, `tools/m6`, `packaging/windows/make-msix.sh` (logos) |
| numpy | the importer's reference dumps (`importer/tests/dump_*.py`, `make_kkp_vectors.py`) |
| opencv-python-headless | the QR test video for the camera tests (`apps/gnome/e2e/make_qr_video.py`) |
| pymupdf | `ref/pathstore.py` (the path store reference), `importer/tests/dump_kkp.py`, `tools/manual_parse.py`, `tools/m6` |
| playwright | the web e2e tests in Chromium, Firefox and WebKit (`platform/linux/e2e`, `tests/web`), `tools/m6/convert_courses.py` |
| pillow-jxl-plugin | JPEG XL in Pillow for `tools/m6/pathstore_measure.py` |

## Platform alternative checked
The test machine's platform is Ubuntu 26.04 with Python 3 and its standard library (`hashlib`, `json`, `unittest`,
`urllib`). The standard library has no P-256/AES-GCM (so no independent crypto reference without `cryptography`), no
image codecs, no PDF reader and no browser driver. Ubuntu packages some of these (`python3-cryptography`,
`python3-pil`, `python3-numpy`, `python3-opencv`), but at other versions; the references the Nim code is checked
against bit for bit need the exact versions (pymupdf 1.28.2 renders with the same MuPDF as `kks-import`; 0026). For
browser tests, there is no platform way to drive all three engines.

## Custom implementation considered
- An independent P-256/AES-GCM implementation for `ref/` would defeat its purpose (an independent, well-reviewed
  implementation to check the Nim core against).
- Image codecs, a PDF reader, a QR video generator and a three-engine browser driver are each far larger than the
  tests that use them.

## Transitive dependencies
Count: 6 Python packages   How counted: `requires_dist` on PyPI for each pinned version, confirmed by `pip list` in
the project's `.venv` and by the complete `requirements-dev.txt` of PR #19: `cffi` 2.1.1 and `pycparser` 3.0 (via
cryptography), `typing_extensions` 4.16.0 (via cryptography and pyee), `pyee` 13.0.1 and `greenlet` 3.5.6 (via
playwright), `packaging` 26.3 (via pillow-jxl-plugin). The wheels also bundle native libraries that pip doesn't list
(OpenSSL in cryptography, OpenBLAS in numpy, MuPDF in pymupdf, image libraries in Pillow and OpenCV, libjxl in
pillow-jxl-plugin), and `playwright install` downloads three browser builds and a Node.js driver.

## License
| Package | License |
| --- | --- |
| cryptography | Apache-2.0 OR BSD-3-Clause |
| Pillow | MIT-CMU |
| numpy | BSD-3-Clause (bundled parts 0BSD, MIT, Zlib, CC0-1.0) |
| opencv-python-headless | MIT (wrapper), Apache-2.0 (OpenCV) |
| pymupdf | AGPL-3.0 (or Artifex commercial) |
| playwright | Apache-2.0 |
| pillow-jxl-plugin | GPL-3.0 |

Transitive: MIT (cffi, greenlet), BSD-3-Clause (pycparser), PSF-2.0 (typing_extensions), MIT (pyee), Apache-2.0 OR
BSD-2-Clause (packaging). AGPL-3.0 and GPL-3.0 are copyleft ("review-needed" under a typical allowlist); both are
compatible with the project's AGPL-3.0, and neither ships.

## Maintenance signals
From PyPI and GitHub, 2026-10-05 (authors = commit authors in the last 12 months, bots excluded where named):

| Package | Latest release (ours) | Security response | Active maintainers | Age, majors |
| --- | --- | --- | --- | --- |
| cryptography | 50.0.2 on 2026-09-30 (50.0.1, 2026-08-25) | [advisories](https://github.com/pyca/cryptography/security/advisories), 19 published, fixed in releases | 52 authors; alex, reaperhulk core | since 2014; versions 0.x → 50 |
| Pillow | 12.3.0 on 2026-07-01 (ours) | [SECURITY.md](https://github.com/python-pillow/Pillow/blob/main/.github/SECURITY.md), many advisories, quarterly releases with fixes | 60 authors; radarhere, hugovk | since 2010; majors to 12 |
| numpy | 2.5.3 on 2026-09-06 (ours) | [security policy](https://github.com/numpy/.github/blob/main/SECURITY.md) (reports through Tidelift), no advisories published on GitHub | 90 authors | since 2006; 1.x → 2.x (2024) |
| opencv-python-headless | 5.0.0.93 on 2026-07-02 (ours) | OpenCV's [SECURITY.md](https://github.com/opencv/opencv/blob/5.x/SECURITY.md) (security@opencv.org); none in the wrapper repo | 7 authors in the wrapper (asmorkalov leads); OpenCV itself many | since 2018; OpenCV 3 → 5 |
| pymupdf | 1.28.2 on 2026-08-06 (ours) | none published; follows MuPDF's fixes | 18 authors, Artifex staff | since 2017 on PyPI; 1.x |
| playwright | 1.63.0 on 2026-09-15 (ours) | [SECURITY.md](https://github.com/microsoft/playwright-python/blob/main/SECURITY.md) (Microsoft MSRC) | 15 authors in the Python binding, 98 in Playwright | since 2021; 1.x |
| pillow-jxl-plugin | 1.3.8 on 2026-07-17 (ours) | none | 1 main maintainer (Isotr0py) | since 2023; 1.x |

## Size impact
None (dev-only). On the development machine the `.venv` is 520 MB (playwright 146 MB with its driver, OpenCV
159 MB, pymupdf 67 MB, numpy 69 MB), plus the browsers in `~/.cache/ms-playwright` (Chromium 410 MB, its headless
shell 273 MB, Firefox 320 MB, WebKit 283 MB).

## Replacement cost
- cryptography: the reference `ref/` and the release signing (`tools/release.py`) are built on it; replacing it means
  rewriting their crypto calls (contained, a few hundred lines).
- Pillow, numpy, pymupdf: the path store reference, the importer's reference dumps and the measurement tools depend
  on their exact output; replacing them means regenerating the references (0026's gate).
- opencv-python-headless: one script (the QR test video); any image library plus ffmpeg would do.
- playwright: every web e2e test is written against its API; Selenium/WebDriver would be a rewrite of those tests.
- pillow-jxl-plugin: a few calls; `cjxl`/`djxl` (libjxl's tools) already do the same job in other scripts.

## Decision
Keep, as test and tooling dependencies that never reach a device. They are the standard tools for what they do, with
large teams and security routes, except pillow-jxl-plugin (one maintainer, no security policy), which is acceptable
for a dev-only image plugin with a drop-in alternative (libjxl's own command-line tools). The wheels carry native
code (OpenSSL, OpenBLAS, MuPDF), so the pins and the vulnerability scan matter even though nothing ships;
`requirements-dev.txt` pins every package with `==` and the CI scan reads it.
