# 0034 The browser client draws the v2 plant data

Date 2026-10-01 · Scope: phase 8 (R1 in the browser client: Safari/iOS, borrowed computers; decisions 0014, 0015,
0016, 0018, 0019) · Status: **decided by Claude under the user's standing instruction to continue**; the user can
revisit.

**Question:** the Nim importer writes no sheet PNG or SVG. It writes a path store (`sheets/<id>.kkp`, PATHSTORE.md) and an
overview pyramid (`sheets/<id>.o<k>.jxl`). How does `index.html` draw them, in Blink, WebKit and Gecko, without
weakening the web policy (platform first, graceful degradation, no framework)?

## Findings (MDN browser-compat-data and caniuse, fetched 2026-10-01)

| Need | Blink (Chrome / Edge) | WebKit (Safari, iOS) | Gecko (Firefox) | Choice |
|---|---|---|---|---|
| zlib inflate (`.kkp` flag bit 0) | `DecompressionStream('deflate')` 80+ | 16.4+ | 113+ | the platform; no library |
| Vector drawing | Canvas 2D + `Path2D` 36+ | 8+ | 31+ | the platform |
| Drawing tiles off the main thread | `OffscreenCanvas` + its 2D context in a Worker, 69+ | 16.4+ | 105+ | a module-less classic Worker |
| JPEG XL decode | Chrome 155+; **Edge: no** | Safari 17+ (still images; "partial" because animation and progressive decoding are missing) | Firefox 158+ | `<img>` / `createImageBitmap` when the browser decodes it; else libjxl in WebAssembly (0018) |
| QR from a camera | `BarcodeDetector`: Chrome on Android, macOS and ChromeOS only (0019) | behind a preference | no | `BarcodeDetector` where present, else zxing-cpp in WebAssembly (0019); pasting the text always works |

The oldest engines that pass every row are Chrome 80, Safari 16.4 and Firefox 113. The pages already need Safari 16.4
for module-less service workers on iOS, so the requirement does not rise.

## Choice

- **`view2.js` + `tiles.js` (a Worker):**
  - The main thread keeps today's pan and zoom, hotspots and panel. The overview pyramid is an `<img>`, or a bitmap
    decoded by the worker's libjxl when the browser lacks JXL.
  - The worker inflates the `.kkp` with `DecompressionStream` and parses it, the way PATHSTORE.md's reference reader
    does. It renders 512 px tiles on an `OffscreenCanvas` (Path2D with the style rules: hairline, minimum one device
    pixel, miter 10, fill before stroke, images interleaved at `after`), and returns `ImageBitmap`s.
  - The tiles appear above the overview from the zoom where the overview stops being sharp, as in the native viewers.
- **v1 data keeps working:** a sheet without `levels` still uses its PNG and SVG. The Python server stays in service
  until the cutover (phase 9).
- **JPEG XL in WebAssembly:** the decoder the pages already vendor (`vendor/jxl`, @jsquash/jxl 1.3.0 = libjxl 0.8 in
  WebAssembly, Apache-2.0, audited in 0011) is reused for the pyramid now. Replacing it with our own libjxl 0.12 build
  (0018) needs Emscripten (emsdk) and is a separate step with its own record.
- **No new dependency** in this record.

**When to revisit:**
- when Edge decodes JPEG XL (the WebAssembly path then serves only old browsers);
- when the plant's iPads and phones are known (if all are iOS 17+, the WebAssembly path matters only for Edge).

Sources: https://github.com/mdn/browser-compat-data (api/DecompressionStream, api/OffscreenCanvas,
api/OffscreenCanvasRenderingContext2D, api/Path2D, api/BarcodeDetector) ·
https://github.com/Fyrd/caniuse/blob/main/features-json/jpegxl.json · docs/PATHSTORE.md · docs/decisions/0011,
0016, 0018, 0019

## Results 2026-10-01

- **Verified in Chromium (headless shell 1243), Firefox 1543 and WebKit 26.6 (Playwright 1.63)**, by
  `platform/linux/e2e/test_web_v2.py`:
  - the Nim server with the synthetic sample sheet;
  - the overview level decoded (natively or by K.jxl);
  - the tag hotspots;
  - the sharp layer from the worker at 8× zoom.
- WebKit needed two host libraries (libmanette, hidapi), unpacked without sudo; see the test's docstring.
- **v1 data still works** in all three engines, against a temporary Python server on a copy of the plant data: PNG
  overview, SVG sharp layer, panel, review crops.
- **Module worker:** `tiles.js` imports the WebAssembly decoder, so the floor is Firefox 114 (module workers), not 113.
- **Escaping audit (web policy: every `innerHTML` with data audited):**
  - **A stored cross-site scripting hole, found and fixed, live since v1.**
    - Where: admin.html → People, the "Edit details" button: `onclick="editDetails(…,'${esc(full_name)}',…)"`.
    - Why: HTML escaping turns `'` into `&#39;`, which the browser turns back into `'` before running the handler.
    - Effect: a member whose full name contained `');…` ran script in the page of any admin who opened People.
    - The same shape existed in other handlers (device IDs, person IDs, sheet names, link codes, tag IDs).
  - **Fix:**
    - every value inside an inline handler now goes through `jsa()` (a JSON string, then HTML-escaped);
    - attribute values through `esc()`;
    - numbers are coerced with `+`.
  - Checked by listing every `${…}` in an `innerHTML` string across index.html, admin.html, common.js and
    learning.html (377), and reading each one not plainly escaped or numeric.
  - **Not done:** inline handlers (`onclick="…"`) still exist. Moving to `addEventListener` with `data-` attributes
    would remove the whole class of bug, and is the better long-term shape.
- **Not verified yet:**
  - a real iPhone or iPad (WebKit on Linux is not Safari on iOS);
  - keyboard-only use and a screen reader on the pages (the policy asks for both).
