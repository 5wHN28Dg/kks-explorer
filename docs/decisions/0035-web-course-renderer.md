# 0035 The browser client renders the JSON courses

Date 2026-10-01 · Scope: phase 8 (R8 courses in the browser client: Safari/iOS, borrowed computers; decisions 0025,
0034) · Status: **decided by Claude under the user's standing instruction to continue**; the user can revisit.

**Question:** the courses now exist in the JSON content model (docs/COURSES.md, built by
`tools/m6/convert_courses.py`). How does the browser client show them in Blink, WebKit and Gecko, without a framework
and without running course code?

## Findings (MDN browser-compat-data, fetched 2026-10-01)

| Need | Blink | WebKit | Gecko | Choice |
|---|---|---|---|---|
| Figure drawing | Canvas 2D + `Path2D` 36+ | 8+ | 31+ | the platform (as the viewer, 0034) |
| Frame clock | `requestAnimationFrame` 24+ | 7+ | 23+ | the platform |
| Freeze figures off screen (§9.6) | `IntersectionObserver` 51+ | 12.1+ | 55+ | the platform |
| Reduced motion (§9.6) | `prefers-reduced-motion` 74+ | 10.1+ | 63+ | `matchMedia` |
| Slider | `<input type=range>` 4+ | 3.1+ | 23+ | native control, labelled |
| JPEG XL photos | see 0034 | | | `<img>`; K.jxl's WebAssembly decoder where the browser lacks JXL |

Every row is older than the floor set by 0034 (Chrome 80, Safari 16.4, Firefox 114). The requirement does not rise.

## Choice

- **`course.html` + `course.js`**, vanilla JS, no build step, no dependency:
  - reads `/data/courses/<id>.json`, validates the parts it draws and refuses unknown versions (§10);
  - builds every page with DOM calls and `textContent` (no `innerHTML` with course data), native `<button>`,
    `<input type=range>`, `<label>`, headings and lists;
  - figures: an evaluator that ports `ref/courses.py` (values, flows, templates), drawn on a `<canvas>` per figure;
    the canvas carries `role="img"`, the title as its name and the alt text as its description.
- **Progress:** the same four keys in localStorage under the course id (`ppt.solved`, …), so v1 progress carries over;
  `course-bridge.js` keeps syncing them to the log where there is one.
- **Tested by** running `ref/vectors/courses-v1.json`'s frames through `course.js`'s evaluator in all three engines,
  and Playwright walks of the three real courses.

**When to revisit:** if the courses gain features the vanilla renderer handles badly (e.g. long tables on phones).

Sources: https://github.com/mdn/browser-compat-data (api/Path2D, api/Window requestAnimationFrame,
api/IntersectionObserver, css/at-rules/media prefers-reduced-motion, html/elements/input/range) · docs/COURSES.md ·
decisions 0025, 0034
