# UI/UX audit 2026-11, pass 1 (blind): Walkdown web client

*Example codes in this record and in its screenshots were replaced with an invented code or blurred on 2026-11-19 (the owner's decision); the findings are unchanged.*

Scope: index.html, admin.html, learning.html, course.html and the scripts they load, in Chromium, WebKit (standing in
for Safari) and Firefox, against docs/UI-UX-POLICY.md. Auditor: helper "web". Code cited as `file:line` on commit
9eb5b09b (main, branch ui-audit-2026-11).

## 1. What was run

- **Builds:** `kks_server` and `kks_import` from this checkout (`Walkdown server 0.10.6 (commit 9eb5b09bb01d)`), built by
  the "desk" helper from the same commit and copied to `~/kks-work/build/ui-audit/web/`.
- **Browsers:** Playwright 1.63.0 (Chromium build 1243, WebKit 2359, Firefox 1543), headless, under memjob (4 GiB),
  one run at a time.
- **Data (synthetic only):** a fresh server with `importer/tests/vectors/kkp-sample.pdf` imported as "Sample sheet";
  `11LAB70AA500` marked, with area/floor/landmark, 8 custom fields, the Arabic fixture note
  `مضخة التغذية 11LAB70AA500 تعمل`, a procedure link and one synthetic JPEG XL photo; 20 marked tags without a code
  (the Review drawer); a user "Tom Tester" with 20 marked tags waiting for approval; sign-up switched on and 20 sign-up
  requests sent (the server's rate limit let 10 through: 10 waiting). No device list was padded (devices need real
  enrolments).
- **Scripts** (scratch, `~/kks-work/build/ui-audit/web/`, worth keeping under `tools/ui_audit/`):
  - `audit_web.py`: the server and data above, then per engine: 14 screens (drawing, tag panel and its end, Review,
    Systems, Coverage, select mode, admin Approvals/Users/Devices/Account/My submissions, Learning, a course page and a
    course question page) at 412×915 and 1280×800 in dark, the main ones in light, and at 640×400 (= 1280×800 at 200 %
    zoom) and 320×640; per screen a screenshot, `aria_snapshot()` and `measure.js`; then probes: Tab walk (70 presses
    on the drawing page, 40 on Approvals), Escape on the panel and each drawer, copy of the panel's code (Chromium
    clipboard), search with case and spaces, long tasks (Chromium), wrong password, a taken username, confirmation
    dialogs, offline (`context.set_offline`, not WebKit).
  - `measure.js`: every clickable or focusable element's `getBoundingClientRect()` (hit-tested, so covered ones don't
    count), overlaps, every text's computed colour against its composited background (WCAG ratio), font sizes, field
    sizes and attributes, horizontal overflow.
  - `analyze.py`: turns the JSON into per-screen fails by rule.
  - `probe2.py`: focus ring, the Arabic note, the photo's delete button and its dialog, Escape/Enter in that dialog,
    typed text after Close and after leaving the page, the open tag after a reload, a tap 12 px beside a tag (412×915),
    landscape 915×412, Chromium `forced_colors`, a course answer with reduced motion.
  - `python3 tools/web_size.py` (exit 0).
- **Evidence:** `~/kks-work/build/ui-audit/web/run2/` (229 screenshots, 209 JSON files with measurements and ARIA
  snapshots), `run2-analysis.txt`; first Chromium run in `run1/`, `probe1/`.
- **Not run:** a real iPhone/Safari and VoiceOver (WebKit-GTK and the ARIA snapshot stand in); the on-screen keyboard
  (R3); WebKit offline (Playwright's WebKit can't emulate it; `test_web_offline` covers it by stopping the server);
  forced colours in WebKit and Firefox (Playwright emulates it in Chromium only); reading the clipboard in WebKit and
  Firefox; the other platforms' label lists (X1, X2: for the coordinator). Screenshots of learning.html are not
  committed: its list shows the plant courses' titles, which carry the plant's name (Z1).

## 2. Results

| Rule | Chromium | WebKit | Firefox |
|---|---|---|---|
| T1 | Fail (WEB-1, WEB-2) | Fail (WEB-1, WEB-2) | Fail (WEB-1, WEB-2) |
| T2 | Fail (WEB-2, WEB-3) | Fail (WEB-2, WEB-3) | Fail (WEB-2, WEB-3) |
| T3 | Fail (WEB-2) [n1] | Fail (WEB-2) [n1] | Fail (WEB-2) [n1] |
| T4 (Advice) | Fail (WEB-5) | Fail (WEB-5) | Fail (WEB-5) |
| T5 | Fail (WEB-4) | Fail (WEB-4) | Fail (WEB-4) |
| R1 | Fail (WEB-6) [n2] | Fail (WEB-6) [n2] | Fail (WEB-6) [n2] |
| R2 | Fail (WEB-7) | Fail (WEB-7) | Fail (WEB-7) |
| R3 | Fail (WEB-8) [n3] | Fail (WEB-8) [n3] | Fail (WEB-8) [n3] |
| R4 (Advice) | Pass [n4] | Pass [n4] | Pass [n4] |
| C1 | Fail (WEB-9) [n5] | Fail (WEB-9) [n5] | Fail (WEB-9) [n5] |
| C2 | Pass [n6] | Not checked [n6] | Not checked [n6] |
| C3 | Fail (WEB-10) | Fail (WEB-10) | Fail (WEB-10) |
| B1 | Fail (WEB-11) [in progress in part] | Fail (WEB-11) | Fail (WEB-11) |
| B2 | Pass [n7] | Pass [n7] | Pass [n7] |
| B3 (Advice) | Not checked [n8] | Not checked [n8] | Not checked [n8] |
| K1 | Fail (WEB-13) | Fail (WEB-12, WEB-13) | Fail (WEB-13) |
| K2 | Fail (WEB-14) | Fail (WEB-14) | Fail (WEB-14) |
| K3 | Fail (WEB-15) [n9] | Fail (WEB-15) [n9] | Fail (WEB-15) [n9] |
| K4 | Fail (WEB-16) | Fail (WEB-16) | Fail (WEB-16) |
| K5 | Pass [n10] | Pass [n10] | Pass [n10] |
| K6 | Fail (via WEB-13 to WEB-16) [n11] | Fail [n11] | Fail [n11] |
| K7 (Advice) | Pass [n12] | Pass [n12] | Pass [n12] |
| S1 | Fail (WEB-18) | Fail (WEB-18) | Fail (WEB-18) |
| S2 | Fail (WEB-17) | Fail (WEB-17) | Fail (WEB-17) |
| S3 | Fail (WEB-9, WEB-19) | Fail (WEB-9, WEB-19) | Fail (WEB-9, WEB-19) |
| F1 | Fail (WEB-20) | Fail (WEB-20) | Fail (WEB-20) |
| F2 | Fail (WEB-21) [n13] | Fail (WEB-21) [n13] | Fail (WEB-21) [n13] |
| F3 | Pass [n14] | Not checked [n14] | Pass [n14] |
| F4 | Fail (WEB-23) | Fail (WEB-23) | Fail (WEB-23) |
| F5 | Fail (WEB-24) | Fail (WEB-24) | Fail (WEB-24) |
| F6 (Advice) | Pass [n15] | Pass [n15] | Pass [n15] |
| D1 | Fail (WEB-22) | Fail (WEB-22) | Fail (WEB-22) |
| D2 | Fail (WEB-22) | Fail (WEB-22) | Fail (WEB-22) |
| D3 | Fail (WEB-25) | Fail (WEB-25) | Fail (WEB-25) |
| D4 | Pass [n16] | Pass [n16] | Pass [n16] |
| X1 | Not checked [n17] | Not checked [n17] | Not checked [n17] |
| X2 | Not checked [n17] | Not checked [n17] | Not checked [n17] |
| X3 | Fail (WEB-26, WEB-22) | Fail (WEB-26, WEB-22) | Fail (WEB-26, WEB-22) |
| A1 | Fail (WEB-4, WEB-26) | Fail (WEB-4, WEB-26) | Fail (WEB-4, WEB-26) |
| A2 | Fail (WEB-26) | Fail (WEB-26) | Fail (WEB-26) |
| A3 | Fail (WEB-26) [n18] | Fail (WEB-26) [n18] | Fail (WEB-26) [n18] |
| A4 | Pass [n19] | Pass [n19] | Pass [n19] |
| A5 | N/A (Plant only) | N/A | N/A |
| L1 | Fail (WEB-27) | Fail (WEB-27) | Fail (WEB-27) |
| L2 | Fail (WEB-17) | Fail (WEB-17) | Fail (WEB-17) |
| L3 | Pass [n20] | Pass [n20] | Pass [n20] |
| L4 (Advice) | Fail (WEB-30) | Fail (WEB-30) | Fail (WEB-30) |
| L5 (Advice) | Fail (WEB-31) | Fail (WEB-31) | Fail (WEB-31) |
| P1 | N/A (Plant only) | N/A | N/A |
| P2 | Pass [n21] | Pass [n21] | Pass [n21] |
| P3 | Pass [n22] | Not checked [n22] | Not checked [n22] |
| P3a (Advice) | Pass [n22] | Not checked [n22] | Not checked [n22] |
| P4 (Advice) | N/A (Android app; web on a phone not measured) | N/A | N/A |
| Z1 | Pass [n23] | Pass | Pass |
| Z2 | Pass [n23] | Pass | Pass |
| Z3 | N/A (no real data used) | N/A | N/A |
| G1 | Fail (WEB-28) [n24] | Fail (WEB-28) | Fail (WEB-28) |
| G2 | Fail (WEB-29, WEB-25) | Fail (WEB-29, WEB-25) | Fail (WEB-29, WEB-25) |
| G3 | Pass [n25] | Pass [n25] | Pass [n25] |
| G4 (Advice) | Fail (WEB-32) | Fail (WEB-32) | Fail (WEB-32) |

Counts per engine (60 rules): Chromium 37 Fail (4 of them Advice), 16 Pass, 3 Not checked, 4 N/A; WebKit 37 Fail,
12 Pass, 7 Not checked, 4 N/A; Firefox 37 Fail, 13 Pass, 6 Not checked, 4 N/A. All engines share the same code, so nearly
every result is the same in all three; the differences are what each engine lets Playwright measure, and WEB-12
(WebKit only).

Notes:
- n1: desktop (1280×800) elements under 24 px that pass by WCAG's spacing exception (no other target within the 24 px
  circle): the panel's and drawers' "×" Close (19–20 × 29), the code links in admin card headings (101 × 16), chips
  (22 px tall), "← All courses" (94 × 19); the Review drawer's checkbox is a native, unrestyled control. Only the
  photo's delete button fails (WEB-2).
- n2: the tag panel passes on phone and desktop: its heading and Close are `position:sticky` (index.html:111) and the
  Close's bounds were `[1234,125,19,29]` before and after scrolling 1552 px of content to the end. Drawers keep their
  head outside the scrolling body; admin's header is sticky (admin.html:18). Fails: course and learning pages
  (WEB-6).
- n3: top and bottom insets are honoured (header, zoom column, select bar, bottom sheet); left/right are not. The
  on-screen keyboard was not checked (no phone).
- n4: the panel's Save/Cancel appear right after the last field (index.js:610–611); admin forms are inline.
- n5: the tag panel's code, names and sheet names are plain selectable text (no `user-select:none` except the sheet
  image, index.html:43); a Copy button in the tag panel is in progress: branch tag-copy-sticky-batch.
- n6: Chromium: selecting the panel's heading and Ctrl+C put exactly `11LAB70AA500` on the clipboard. WebKit/Firefox:
  Playwright can't read their clipboard; same DOM.
- n7: the "… for all" dialogs say "For N codes" before sending (index.js:943–944); adding a note or place removes
  nothing.
- n8: no bulk action that changes a list was available to try (WEB-11).
- n9: the browser's own focus ring is kept and was visible in all three (two-tone in Chromium, blue in WebKit and
  Firefox: `run2/shots/*-focus-header.png`); course.css sets 2 px accent/ink focus outlines. The fails are borders and
  highlights.
- n10: text over the drawing (photo legend, banner, toast) has its own panel (index.html:63, 98, 100).
- n11: index/admin/learning are dark only (light setting ignored, outside this rule); course.css follows
  `prefers-color-scheme`. Dark is complete, but K1, K3 and K4 fail in it.
- n12: the page colours are in an inline `<style>` (course.css is render-blocking): no white page flash. The drawing's
  paper stays white in the dark theme until "Dark drawings" is switched on (index.js:274, a per-device toggle, which is
  what tests/web/test_dark.py specifies).
- n13: the messages seen were plain ("Wrong username or password.", "Cannot reach the server.", the offline notices),
  but the fallback can show raw HTTP text (WEB-21); not triggered in this run.
- n14: Chromium and Firefox offline: "● Offline · 2 days left · 1 queued", toast "Offline, queued: 11LAB70AA500", admin
  pages "You are offline. Approvals, users and history need the server. Changes you make on the drawings are queued…".
  WebKit: not here (see section 1).
- n15: "Nothing waiting for approval.", "Nobody is waiting.", "You haven't submitted anything yet.", search "No match. It
  may be on a sheet not loaded yet…".
- n16: log out with unsent changes asks "N change(s) not sent yet…" (common.js:483), though with `confirm()` (WEB-22).
- n17: needs the GNOME, Windows and Android helpers' label lists; the web's are in the ARIA snapshots
  (`run2/data/*-desk-dark-*.json`, key `aria`).
- n18: search finds every read tag in any case and spacing and Enter opens its card with focus on the code; Systems
  rows are buttons. Unread tags are only in the Review drawer, whose rows can't be focused (WEB-26).
- n19: no running animations on the drawing page (`document.getAnimations().length` 0); course.css adds its 0.12 s
  colour transitions only under `prefers-reduced-motion: no-preference` (course.css:154; with reduce, 0 s).
- n20: elevations "14 m", instrument points "33 m · grid …" (index.js:36–38), course values "150 °C"; values typed by
  people are free text.
- n21: `python3 tools/web_size.py` exits 0 (shell 1,172,113 B, on demand 8,398,776 B, courses 5,874,825 B).
- n22: Chromium long tasks: 74, 398 and 64 ms, all during page load; none during search → Enter → panel. WebKit and
  Firefox have no long-task API.
- n23: only the fixture and generated data above; Playwright screenshots have no browser chrome; committed shots
  checked at the edges.
- n24: search accepts `11lab70aa500`, `11 LAB70 AA500` and `11 lab70 aa500` (all found `11LAB70AA500`); the fields'
  attributes fail.
- n25: 915×412 landscape shows the drawing and the panel side by side (`run2/shots/*-landscape-panel.png`).

## 3. Findings

**WEB-1** T1 (Block). All engines, phone (412×915), every screen. Almost no target reaches 48 × 48 CSS px: header
buttons and links 36 px tall (`select,.btn` padding 7 px, index.html:30), selects 37 px, the search 38 px, zoom column
42 × 42 (index.html:97), the panel's "×" 19–20 × 29 (index.html:107), chips 22 px tall (index.html:120), the "✎" edit
buttons 34 × 34 (index.html:172), admin tabs 36 px and Approve/Reject 34 px, sign-in fields, course "← All courses"
91 × 19 and course answer options 342 × 44. Counts at 412×915 (Chromium): drawing page 19 of 40 targets small, tag
panel 51–59 of 82, Approvals 112 of 132, Users 43 of 46. Evidence: `web-WEB-1-phone-targets.png`,
`run2-analysis.txt`. Size: LARGE (the phone header is already 4 rows, ~240 px, so 48 px buttons need a different phone
header, e.g. an overflow menu). Fix: a phone media query with `min-height:48px` (and `min-width:48px` for icon buttons)
on `.btn, .ghost, .primary, .danger, .x, .pen, .chip, select, input`, plus a collapsed header.

**WEB-2** T1, T2, T3 (Block). All engines, tag panel, Photos. The photo's delete button "✕" is 22 × 19 (Firefox
17 × 19) and sits on top of the photo, which is itself a target (it opens the viewer): the two hit areas overlap and
the destructive one has 0 px distance (index.html:133–134, index.js:615). Evidence:
`web-WEB-2-photo-delete-on-photo.png`, `run2/data/*-probe2.json` (`photo_del_box`, `photo_img_box`). Size: SMALL.
Fix: move Delete under the photo (a row with the caption), 48 px on phones, 8 px from the photo.

**WEB-3** T2 (Block). All engines, desktop 1280×800, tag panel open. The panel (right 12 px, full height,
index.html:108) lies over the zoom column (+, −, fit, mark, photos, dark, select; index.html:96, 202): with a tag open,
none of them can be clicked (Playwright: "`<label for=f_floor>` from `<aside id=panel>` intercepts pointer events"
when clicking `#zcover`). Evidence: `web-WEB-3-panel-covers-zoom.png`. Size: SMALL. Fix: move the zoom column left of
the panel while it is open (or into the panel's free side), as the phone layout already does above the bottom sheet.

**WEB-4** T5, A1 (Block). All engines, drawing. Panning the drawing is possible only by dragging; there are no pan
buttons and the arrow keys do nothing (the only key handlers are the search's, Escape in select mode, and dialogs:
index.js:956, 990; common.js:138, 292, 1023); "+"/"−" keys don't zoom. "Mark a tag the app missed" asks to "Drag a box
around the tag" (index.js:132, 139–147) with no tap or keyboard way to place the box; select mode allows taps (pass).
Size: LARGE (keyboard pan/zoom on the viewer, and a tap-tap way to place the mark box). Fix options: arrow keys pan by
10 % and +/− zoom when the viewer has focus (make `#viewer` focusable); for marking, "tap two corners" or "tap the tag,
then adjust the proposed box".

**WEB-5** T4 (Advice). All engines, 412×915. A tap 12 px to the right of `11LAB70AA500`'s box opened nothing
(`t4_beside_opens: false`); tags are hit only inside their own box (`button.hs`, index.js:431). Size: SMALL–LARGE
(nearest-tag search within 24 px on a click that hits no tag).

**WEB-6** R1 (Block). All engines, course.html and learning.html. Their back links ("← All courses", "← Drawings")
are in headers that scroll away (course.css:35 `header.top` and learning.html's `header` are not sticky); a long
module must be scrolled back to the top to leave it (the in-page "Go to" select scrolls away too on phones). Size:
SMALL. Fix: `position:sticky; top:0` on those headers (with a background), as admin.html:19 does.

**WEB-7** R2 (Block). All engines. Escape closes nothing on the drawing page: with focus in the tag panel, and with
the Systems, Review, Procedures and Coverage drawers open, Escape left each one open (`esc_*` in
`run2/data/*-probes.json`); the photo delete question (`K.ask`) also ignores Escape. Only select mode, the search list,
the lightbox, the About dialog and the sign-in sub-forms handle it. `K.back` (index.js:676) already closes the top
layer for the Android app's Back. Size: SMALL. Fix: a document `keydown` for Escape that calls `K.back()`, and Escape
= Cancel in `K.ask`.

**WEB-8** R3 (Block). All engines (matters on iPhones in landscape). The pages use `viewport-fit=cover`
(index.html:5, admin.html:5, learning.html:5, course.html:5) and pad only the top and bottom safe areas; nothing uses
`env(safe-area-inset-left/right)`, so in landscape on a phone with a notch the header's first button, the drawers and
the admin page's left edge go under the cut-out. Code evidence only (no iPhone). Size: SMALL. Fix: add
`padding-left/right: max(10px, env(safe-area-inset-left/right))` to header, `main`, `.drawer`, `#panel` and
course.css's `body`.

**WEB-9** C1, S3 (Block). All engines, admin Devices. Device IDs and the server's node ID are cut to 12 characters
plus "…" (`${d.device.slice(0,12)}…`, admin.js:283; `${(D.node||'').slice(0,12)}…`, admin.js:295), e.g.
`_GXUPM3MTrkC…`; the full identifier is nowhere on the page to select or copy. Size: SMALL. Fix: show the full ID
wrapping (`word-break:break-all`, as `.linkbox` does) or a Copy button that copies the full ID.

**WEB-10** C3 (Block). All engines, admin (invite/link panel). The Copy button's confirmation says only "Copied"
(admin.js:588), not what was copied. (The tag panel's Copy button is in progress: branch tag-copy-sticky-batch.)
Size: SMALL. Fix: `toast('Copied ' + what)`.

**WEB-11** B1 (Block). All engines. With 20 items waiting, each list offers only one decision per item and no
selection: Approvals has 20 Approve + 20 Reject buttons and 0 checkboxes; Users → Account requests 10 Approve + 10
Reject, 0 checkboxes; Devices removes one at a time; the drawing page's Review drawer lists 20 unread tags as rows that
each open the panel for one Confirm/"Not a tag" (index.js:1152). Deciding 20 takes 20–40 actions. In progress for
admin Approvals/sign-ups/devices (branch tag-copy-sticky-batch); the Review drawer on the drawing page is not part of
that work. Evidence: `web-WEB-11-queue-one-by-one.png`, `queue_buttons`, `signup_buttons`, `review_items` in
`run2/data/chromium-probes.json`. Size: LARGE.

**WEB-12** K1 (Block). WebKit only (WebKit-GTK standing in for Safari). The drawing page's two `<select>`s (sheet, floor)
are drawn by the engine with a light native face, but the page sets their text to `--ink` #e9eef2 (`color:inherit`,
index.html:18), so "Sample sheet" and "All floors" are near-white on light grey, unreadable, on every layout.
Evidence: `web-WEB-12-webkit-select.png`. Needs confirming on a real iPhone (Safari draws selects its own way too).
Size: SMALL. Fix: `appearance:none` with the page's own arrow, or `color-scheme:dark` on the page so the native face
is dark.

**WEB-13** K1 (Block). All engines, dark (the only theme of these pages). Measured from computed colours:
`--bad` #ff5a5a on cards #243440 = 4.18:1 (every "Reject" button, "Log out and remove passwords…", the sign-in error
"Wrong username or password.", `.del` notes); the "approved" badge #4f9cff on #2f4352 = 3.68:1 at 11.5 px
(My submissions, 23 rows); `--muted` #94a6b4 on `--chrome3` #2f4352 = 4.09:1 (search results' second line on the
highlighted row, `.res .m`); course page in light: the alarm note #9a6412 on #f6e7c8 = 4.09:1 ("This course does
not…"). Size: SMALL. Fix: lighten `--bad` to about #ff8080 and `--ok` text to about #7ab4ff on these backgrounds,
darken course `--alarm` text.

**WEB-14** K2 (Block). All engines, phone. Codes and values under 7:1: codes as links in admin cards in the accent
#ff7a1a on #243440 = 4.91:1 (Approvals' 20 headings, My submissions); usernames and device IDs in `.mono.sub` or
`.sub` #94a6b4 on #243440 = 5.1:1 (Devices, Users, Account). The tag panel's code passes (#e9eef2, 10.96:1). Size:
SMALL. Fix: codes in `--ink`, with the accent as an underline or icon.

**WEB-15** K3 (Block). All engines. Borders and highlights under 3:1: field and ghost-button borders `--line` #3a5061
on #1c2730 = 1.81:1 and on #243440 = 1.52:1 (fields' fill #1c2730 against the panel #243440 is 1.2:1, so a field's
edge isn't visible either); on the drawing (white paper), the selected tag's 4 px outline #ff7a1a = 2.61:1, the review
tags' dashed #f2b705 = 1.82:1, the hover outline #4f9cff = 2.79:1, the photo colour "equipment only" #e69600 =
2.41:1; on the course page the rule colour #c6cfd4 on #f8fafa = 1.51:1 (light) and #2b363d on #182026 = 1.33:1 (dark)
where it is a button border. Colours from index.html:11–12, 30, 45–47, 61–62. Size: SMALL (colour values) to LARGE (if the
selected-tag highlight needs a second, dark ring like `.picked` has, index.html:69).

**WEB-16** K4 (Block). All engines, drawing with "Colour tags by photos". The four photo states (both, equipment only,
tag plate only, none) differ on the drawing only by hue: same 2 px solid outline and same fill pattern
(index.html:61–62); the legend says the words but the tags themselves don't (red vs green is the red-green pair).
Size: LARGE (a pattern or line style per state). Fix: e.g. none = dashed, plate only = dotted, equipment only =
double, both = solid, kept in the legend.

**WEB-17** S2, L2 (Block). All engines. At 200 % zoom (640×400): the header wraps to three rows (good) but takes
140 px, and the zoom column (7 × 48 px, bottom-anchored, index.html:96) no longer fits below it: its top buttons
("Zoom in", "Zoom out") sit under the header and can't be reached (`web-WEB-17-zoom200-controls-hidden.png`). At 320 px:
Users → Account requests puts its Approve/Reject buttons outside the card's right edge (page 416 px wide;
`web-WEB-17-w320-signups.png`); the course question page scrolls sideways (page 385 px) because a figure's canvas is
551 px wide and a number span overflows (course page, module 2). Devices (342 px) is a wide table (exempt). Size:
SMALL–LARGE. Fix: let the zoom column scroll or move into a row at low heights; let the sign-up table stack its cells
under 480 px; scale course figure canvases to the container width.

**WEB-18** S1 (Block). All engines. Phone: text under 12 px: the "· by … , date" lines and photo captions 11.5 px
(index.html:174, 175), badges 11.5 px (index.html:36, admin.html:42); much list and row text at 12–13 px (`.sub`
12.5–13 px, `.res .m` 12 px, chips 12.5 px, the sync status 12.5 px, course `.docid`/rail numbers 12 px). Every text
field is 14 px (15 px for the course select), under the 16 px at which iOS Safari zooms the page on focus (25 fields in
the tag panel, 40 in Approvals). Desktop: body text is 14 px (`html,body{font:14px…}`, index.html:17, admin.html:17,
learning.html:13, common.js:115) instead of the browser default 16 px; nothing under 11 px. Size: LARGE (a type-scale
change across every page). Fix: 16 px body and fields, 14 px secondary, 12 px floor.

**WEB-19** S3 (Block). All engines, tag panel. Custom field values are shown in read-only `<input>`s that cut them at
the field's width ("Synthetic value number 4, long enough to wrap in the panel" shows as "Synthetic value number 4";
index.js:660–663); a code or identifier kept in a custom field is clipped the same way. The pick bar's hint is
ellipsised (not an identifier). Size: SMALL. Fix: show read-only values as text (or auto-growing textareas), switch
to inputs only when ✎ is pressed.

**WEB-20** F1 (Block). All engines. No button shows a pressed state: there is no `:active` rule in any page or
stylesheet (index.html, admin.html, learning.html, course.css, common.js `K.css`), and the custom backgrounds replace
the browser's own; on a phone (no hover) a tap gives no feedback until the result arrives. Size: SMALL. Fix: an
`:active` style (darker fill or inset) on `.btn, .ghost, .primary, .danger, .x, .chip, .pen` and course `.opt`/`.btn`.

**WEB-21** F2 (Block). All engines, code. When the server answers an error without a JSON `error`, the message shown
is the raw HTTP status text or "error NNN" (`new Error(d?.error || r.statusText)`, common.js:37;
`'error ' + status`, common.js:20), and many handlers show `e.message` as is (admin.js:46 `toast(… e.message)`,
common.js:140). Not triggered in this run (the server's own errors were plain words). Size: SMALL. Fix: map statuses
without a message to plain sentences ("The server had a problem; try again. Your change is kept here.").

**WEB-22** D1, D2, X3, A2 (Block). All engines. Destructive questions use the browser's `confirm()`, whose buttons
can't be named or styled (OK/Cancel, Enter confirms): removing a hand-added tag (index.js:166), rejecting a sign-up
(admin.js:507), removing a device (admin.js:283–284) or all of a person's devices (admin.js:212, 219), removing a sheet
(admin.js:458), discarding a queued photo (admin.js:176), switching sign-up off (admin.js:252), restore/revert
(admin.js:645, 647), sign out everywhere (admin.js:629), log out with unsent changes (common.js:483). The page's own
`K.ask` (photo delete, common.js:1195–1208) has no `role="dialog"`, styles "Delete" in the accent colour (not
`.danger`), leaves the focus on the "✕" behind the overlay (not on Cancel); Enter there opens a second, stacked
question, and Escape does nothing. Some questions don't name the thing: "Delete this photo?", "Remove this device? It
stops syncing…" (which photo/device). Evidence: `web-WEB-22-delete-ask.png`, `ask*` in `run2/data/*-probe2.json`,
`dialogs` in `*-probes.json`. Size: LARGE (one shared dialog helper, about 15 call sites). Fix: a `<dialog>`-based
`K.confirm(title, text, actionLabel, {danger:true})` with focus on Cancel, Escape = Cancel, `.danger` action button.

**WEB-23** F4 (Block). All engines. The toast that reports most outcomes ("Offline, queued: 11LAB70AA500", "Device
removed", "Request rejected", "Copied", "Saved") is a plain `<div id="toast">` with no `role="status"`/`aria-live`
(index.html:209; admin.html:67; set in index.js:11, admin.js:37), so screen readers never hear them. (Course feedback
has `role="status"`, the sign-in error `role="alert"`: pass.) Size: SMALL. Fix: `role="status" aria-live="polite"`
on both toasts.

**WEB-24** F5 (Block). All engines, admin forms. A field error appears in the toast at the bottom, not at the field,
and the focus stays on the button: "Add an account" with a taken username shows "That username exists." in the toast
(the typed text is kept); the sign-in form shows its error under the button in a shared line, not at the field it
concerns. Size: SMALL–LARGE. Fix: an error line under the offending field (`aria-describedby`), focus moved to it.

**WEB-25** D3, G2 (Block). All engines, tag panel. Text typed into an unlocked field is dropped without a question:
after ✎ Notes, typing "typed but not saved" and pressing Close, reopening the tag showed the old note; typing and then
following a link (to learning.html) left the page with no question (no `beforeunload`; `asked: []`). Size: SMALL.
Fix: keep a per-tag draft in `sessionStorage` (restored on reopen), and ask on Close/leaving while a field is unlocked
and changed.

**WEB-26** A1, A2, A3, X3 (Block). All engines.
- Clickable elements that aren't buttons or links and can't be focused: the panel's "Appears on" and "Used in
  procedures" chips (`span.chip`, index.js:590, 593), procedure rows (`div.proc`, index.js:1031), step chips
  (index.js:1044, 1049), the Review drawer's 20 rows (`div.revitem`, index.js:1152). The Review drawer is the only
  list of unread tags, so those tags can't be reached by keyboard or screen reader (A3).
- Icon-only buttons named by their glyph: the zoom column reads `button "+"`, `"−"`, `"⤢"`, `"✎"`, `"📷"` (title is
  only a description; only "Dark drawings" and "Select tags" have `aria-label`, index.html:202); the Review,
  Procedures and Sheet notes drawers' close is `button "×"` (index.html:210, 219, 223); a custom field's remove `×`
  (index.js:662).
- Unnamed control: the role `<select>` in "Add an account" (`combobox` with no name, admin.js:231).
- The sign-in overlay leaves the page behind it in the accessibility tree (the zoom buttons appear in its ARIA
  snapshot).
- The Tab walk on the drawing page (19 stops, then wraps) never reaches a tag: tags take focus only in select mode.
Size: SMALL (each change is local). Fix: make chips/rows `<button>`s, add `aria-label`s, `inert` the page under the
overlay.

**WEB-27** L1 (Block). All engines, tag panel. User text has no automatic direction: no `dir="auto"` or `<bdi>`
anywhere (fields built in index.js:665–668). The fixture note `مضخة التغذية 11LAB70AA500 تعمل` is laid out
left-to-right and the code is split: it shows as "11 تعمل LAB70AA500مضخة التغذية" (computed `direction: ltr`).
Evidence: `web-WEB-27-arabic-note.png`. Size: SMALL. Fix: `dir="auto"` on user-text inputs, textareas and their
read-only display, notes in admin, names in lists; keep codes in `<bdi>` or `unicode-bidi:isolate`.

**WEB-28** G1 (Block). All engines. The search box (`#q`, index.html:186) has `spellcheck="false"` but neither
`autocapitalize="characters"` nor `autocorrect="off"`; the code fields in the tag panel's "Check this tag" (`#rvK`,
`#rvI`, index.js:568), Approvals' "Code as it should be saved" (admin.js:114) and the Systems filter have none of
the three. (Search itself accepts any case and spaces: pass.) Size: SMALL.

**WEB-29** G2 (Block). All engines. The open tag isn't in the URL: after opening `11LAB70AA500` from search the URL
stayed `/`, and a reload came back with no tag open (`g2_panel_after_reload: false`). A home-screen web app that iOS
reloads in the background therefore loses the sheet's tag and scroll position. (`/?kks=` links do open a tag.) Size:
SMALL. Fix: `history.replaceState` with `?kks=` (and the sheet) when a tag opens; restore the panel's scroll.

**WEB-30** L4 (Advice). All engines, admin and offline lines. Dates use `toLocaleString()`/`toLocaleDateString()`
(admin.js:38, index.js:479, common.js:691, 862, 864): "11/15/2026, 12:46:50 PM" in an en-US browser, ambiguous and
12-hour. Size: SMALL. Fix: one formatter giving "2026-11-15 12:46".

**WEB-31** L5 (Advice). All engines. "N change(s) not sent yet" (common.js:483). Size: SMALL.

**WEB-32** G4 (Advice). All engines, phone. Search and every main action are in the header at the top; on a 412×915
phone the header is four rows (~240 px), and the drawing starts below it. Only the zoom column and the tag sheet are
in the lower two thirds. Size: LARGE (phone layout). Fix: a bottom bar with search, Systems and the panel's photo/note
actions.

## 4. Screenshots in this folder

`shots/web-WEB-1-phone-targets.png`, `web-WEB-2-photo-delete-on-photo.png`, `web-WEB-3-panel-covers-zoom.png`,
`web-WEB-11-queue-one-by-one.png`, `web-WEB-12-webkit-select.png`, `web-WEB-17-zoom200-controls-hidden.png`,
`web-WEB-17-w320-signups.png`, `web-WEB-22-delete-ask.png`, `web-WEB-27-arabic-note.png` (all Chromium except
WEB-12, WebKit; synthetic data; downscaled, each under 60 KB).
