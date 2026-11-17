# UI/UX audit 2026-11, pass 2 (adversarial): Walkdown web client

Scope: what pass 1 (`web.md`) says about index.html, admin.html, learning.html, course.html and their scripts, on commit
9eb5b09b. Method: I read the code behind every Pass, N/A and Not checked, read pass 1's raw outputs
(`~/kks-work/build/ui-audit/web/run2/`), and ran one extra Playwright probe in Chromium, WebKit and Firefox (memjob 5,
pass 1's server and importer builds, synthetic data only, the server stopped by PID afterwards). The probe is
`~/kks-work/build/ui-audit/web2/probe3.py`; its results are in `probe3.json` and its screenshots in `shots/` there.
It reuses pass 1's setup and adds a second sheet with an 80-character name. The probe opened the plant course `fnd`
only to measure a figure's canvas. It took no screenshot there.

## 1. Corrections to pass 1's table

| Rule | Pass 1 | Pass 2 verdict | Evidence |
|---|---|---|---|
| G3 | Pass, all engines [n25] | **Fail, all engines** (WEB2-3) | At 915 × 412 (phone landscape) the zoom column's "Zoom in" and "Zoom out" are under the header: they span y 70–160 while the header ends at y 144–153, and `elementFromPoint` at their centres hits the header in all three engines (`probe3.json` `landscape`). Pass 1's own landscape screenshot (`run2/shots/chromium-landscape-panel.png`) shows the column's top button cut off under the header, and the panel then covers the rest (WEB-3). |
| A4 | Pass, all engines [n19] | **Fail, all engines** (WEB2-4) | With `prefers-reduced-motion: reduce`, a course figure starts still ("Play"). After one tap on one of its toggles it loops forever: the canvas still changed 3–4 s and 4–5 s after the tap, and the button read "Pause" (`probe3.json` `course_after_toggle`). Code: `toggle()` and `setMode()` set `this.playing = true` whatever the setting (course-figure.js:135–136; the setting is used only in the constructor, :119). Pass 1 checked only the drawing page at rest and the 0.12 s colour transitions. |
| K3 | Fail (WEB-15) [n9: "the browser's own focus ring is kept and was visible"] | **Fail stands; n9 is wrong for the drawing** (WEB2-1) | In select mode, tags take keyboard focus, and their focus ring is `outline:3px solid #fff; outline-offset:3px` (index.html:70). That is white drawn on the white paper (index.html:43), so the contrast is 1:1. In all three engines the computed outline is `rgb(255,255,255) solid 3px`, and the screenshot shows no ring at all (`shots/p3-*-tag-focus.png`). |
| K4 | Fail (WEB-16, photo colours only) | **Fail, wider than pass 1 says** (WEB2-2) | The selected tag loses its highlight in two cases. When "Show equipment on a floor" is on, `.hs.floor` comes after `.hs.sel` with the same specificity, so the selected tag's outline is the same `#4f9cff solid 3px` as every other tag on that floor. When "Colour tags by photos" is on, `body.cover #layer .hs:not(.pendmark)` overrides `.sel`, `.review`, `.hl`, `.floor` and `:focus-visible`, so the selected tag looks like any other tag with the same photo state (computed `rgb(220,40,40) solid 2px`, the same as a review tag). Evidence: `probe3.json` `sel_floor`, `sel_cover`, `review_cover`; `shots/p3-floor-sel.png`, `p3-cover-sel.png`. |
| F3 | Not checked, WebKit [n14] | **Pass, WebKit** | `platform/linux/e2e/test_web_offline.py` runs in WebKit with the server stopped (`test_webkit`, :387). It asserts "Offline" (:198), "4 queued" (:264) and the expiry notice (:284). It runs on CI (`tests.yml`:320–322). |
| B3 (Advice) | Not checked [n8: "no bulk action … available"] | **Pass** | Select mode's "Photo/Place/Note for all…" is a bulk action. Afterwards the drawing stays where it was, and the page says what happened: "Sent for N codes · M await approval · K held" (index.js:883), or "Offline, queued for N codes" (index.js:878). (Its toast is not announced to screen readers and lasts 2.2 s: WEB-23, WEB2-8.) |
| P4 (Advice) | N/A | **Not checked** | The web client is used on phones too (iPhones, REQUIREMENTS.md N8), so P4 applies. It simply wasn't measured. |
| K1 (forced colours) | Treated as checked in Chromium (§1 "Not run" lists only WebKit and Firefox) | **Only partly checked** | probe2 stopped in Chromium after its first forced-colours screenshot. The `#zcover` click timed out because the panel covers the zoom column (`run2/data/chromium-probe2.json` `error`), so `chromium-forced-colors-cover`, `chromium-forced-colors-admin` and Chromium's course answer were never taken. The one shot taken (`run2/shots/chromium-forced-colors-panel.png`) also shows the panel's "Appears on" and "Used in procedures" chips as plain text, with no shape left to show they can be pressed (they are `span`s styled only by background: WEB-26). |
| C1, S3 | Fail (WEB-9: admin.js:283, 295) | **Fail, more places** (WEB2-10) | More identifiers are cut to a prefix plus "…" with no full copy anywhere: peers in Devices (admin.js:296, `s.peer.slice(0,12)+'…'`), devices online at the relay (admin.js:306, `p.slice(0,8)+'…'`), and the join screen's "Device …" line (common.js:329). |
| F2 | Fail (WEB-21, "not triggered") | **Fail; real paths found** (WEB2-12) | Server messages that reach a toast unchanged through `e.message` (admin.js:46): `"sync with " & addr & " failed: " & e.msg` (server.nim:1697; the OS/TLS error text after a failed "Sync now"); "admin only" / "manager only" (server.nim:1446, 1455, …) for a page left open after a role change; "login required" (server.nim:413, 747); "not found". "Not saved: " + e.message on a failed bulk send (index.js:876). |
| D1 | Fail (WEB-22: `confirm()` call sites) | **Fail, one more place with neither a question nor an Undo** (WEB2-5) | A procedure step's "×" Unlink removes the link at once, with no question and no Undo (index.js:1050, 1058). D1 names links explicitly. |
| R3 | Fail (WEB-8, left/right) [n3: "top and bottom insets are honoured"] | **Fail, bottom too** (WEB2-13) | n3 is not right for every bottom element. `#toast` sits at `bottom:24px` (index.html:100, admin.html:51), the photo-colour legend at `bottom:8px` (index.html:63), and the drawers' bodies end at `padding-bottom:20px` (index.html:102–106). None of them adds `env(safe-area-inset-bottom)`, so on an iPhone (a 34 px home-indicator inset) they sit under the home indicator. |
| WEB-16 size | LARGE | **SMALL on the web** (CSS only: one `outline-style` per `.p-*` class) | It becomes LARGE only because index.html:59 says the colours are "the same colours on every client". Matching the patterns on GNOME, Windows and Android (X1) is the large part. |
| X1 | Not checked | Not checked (one data point for the coordinator) | Coverage labels its review count "Readings to review" on the web (index.js) and GNOME (coverage.nim:84), "Readings to review:" on Windows (coverage.nim:73), and "To review" on Android (Coverage.kt:109). |

Everything else in pass 1's table holds as far as I could check. In particular: R4, C2 (Chromium), B2 ("Place for all" warns
"N of M already have …; it will be replaced" and needs a second press, "Replace and send": index.js:921–938), K5, K7,
D4, L3, P2, Z1/Z2.

## 2. New findings

**WEB2-1** K3, A1 (Block). All engines, drawing in select mode with "Dark drawings" off (the default). A tag that has
keyboard focus shows no focus ring. The ring is white with a 3 px offset (index.html:70), drawn on white paper
(index.html:43), so the contrast is 1:1. With "Colour tags by photos" on, the cover rule overrides the ring altogether
(see WEB2-2). Evidence: `probe3.json` `tag_focus` (outline `rgb(255,255,255) solid 3px`, `darkdwg: false`);
`shots/p3-chromium-tag-focus.png`, `p3-webkit-tag-focus.png`, `p3-firefox-tag-focus.png` show only the tag's faint fill.
Size: SMALL. Fix: a two-tone ring like `.picked`'s (`outline:3px solid #000; box-shadow:0 0 0 6px #fff`), placed after the cover rule
or given `!important`, or `body.darkdwg`-dependent colours.

**WEB2-2** K4, K3 (Block). All engines, drawing. The selected tag can't be told apart in two common modes:
- With a floor chosen in "Show equipment on a floor", `.hs.floor` (index.html:49) comes after `.hs.sel` (index.html:47)
  at equal specificity. The selected tag gets the floor's `#4f9cff solid 3px` outline and fill, the same as every other tag on that
  floor. The same happens to a procedure step's highlight (`.hl`, index.html:48).
- With "Colour tags by photos" on, `body.cover #layer .hs:not(.pendmark)` (index.html:61) wins over `.sel`, `.hl`,
  `.floor`, `.review` (dashed) and `:focus-visible`. The selected tag, a review tag and a step's highlighted tags all
  become a plain 2 px photo-colour outline.
Evidence: `probe3.json` (`sel_floor`: class `hs sel p-none floor`, outline `rgb(79,156,255) solid 3px`; `sel_cover`
and `review_cover`: both `rgb(220,40,40) solid 2px`); `shots/p3-floor-sel.png`, `shots/p3-cover-sel.png`. Size:
SMALL. Fix: give the states their own CSS property so they stack (e.g. the selection as a `box-shadow` ring in two
tones, the photo state as `outline`, the floor as fill), and order the rules so that selection and focus come last.

**WEB2-3** G3, S2 (Block). All engines, phone landscape (915 × 412). "Zoom in" and "Zoom out" are under the header and
can't be tapped (`probe3.json` `landscape`: column top at y 70, header bottom at y 144–153, `elementFromPoint` hits the
header). Once a tag is open, the panel covers the rest of the column (WEB-3). This is the same cause as WEB-17's 200 % case: the
column is bottom-anchored and 7 × 48 px tall (index.html:96). Size: SMALL. Fix: same as WEB-17. Let the column wrap into two columns, or
scroll, when `max-height` is under about 520 px.

**WEB2-4** A4 (Block). All engines, course pages with animated figures (2 figures with toggles and 1 with modes in
`fnd`, 2 and 1 in `hrsg`, 3 in `ppt`). With reduced motion on, a figure starts still. The first tap on a toggle or mode
starts its endless loop (flow particles and the period), and it keeps running until the person finds Pause
(course-figure.js:135–136). Evidence: `probe3.json` `course_after_toggle` (canvas still changing 3–5 s after the tap; button
"Pause"). Size: SMALL. Fix: under reduced motion, a toggle or mode change jumps to (or quickly eases to) the new state,
then sets `playing = false`; pass `reduceMotion` into `toggle()` and `setMode()`.

**WEB2-5** D1, T2 (Block). All engines, Procedures drawer, a step's linked equipment. The "×" that unlinks a code
(index.js:1050) removes the link at once (index.js:1058), with no question and no Undo. It sits 4 px from the code
chip it belongs to (chip `margin-right:4px`, index.html:120; `.x` with `padding:0 4px`, index.html:107), at
`font-size:14px`. A tap meant for the chip (which opens the tag) can unlink it. Size: SMALL. Fix: an Undo
toast for at least 4 s (resend `on:true`), and put the unlink 8 px or more from the chip, or move it behind an "Edit links" mode.

**WEB2-6** S3, S2, L2 (Block). All engines, phone. A long sheet name (80 characters, the server's limit:
server.nim:1351) makes the sheet `<select>` 565–574 px wide. On a 412 px phone and at 320 px the page then scrolls sideways
(`document.scrollWidth` 575–584), and the sheet name, an identifier, is cut off at the screen's edge
(`probe3.json` `longname_412`, `longname_320`; `shots/p3-longname-412.png`). Size: SMALL. Fix: `max-width:100%` on
the header's selects, with the full name shown when the select is opened, plus the sheet's name as a wrapping line
(e.g. in the drawing's corner, or as the select's label).

**WEB2-7** A1 (Block; WCAG 2.4.11). All engines. When moving backwards with Shift+Tab, the focused control ends up under a
sticky header:
- tag panel: on the desktop 2–4 stops are fully or partly under `.phead` (e.g. "Edit Notes" and the Notes field,
  y 107–185 under a heading that ends at y 183–198); on the phone sheet 8–11 stops, 2–6 of them fully hidden;
- admin Approvals on a phone: of 80 Shift+Tab stops, 13–24 are partly hidden under the sticky header and 11–20 fully
  hidden (Chromium 24/20, Firefox 13/11).
There is no `scroll-padding-top` anywhere. Evidence: `probe3.json` `focus_under_phead_*`, `admin_focus_under_header`;
`shots/p3-admin-focus-under-header.png`. Size: SMALL. Fix: `#panel{scroll-padding-top:<.phead height>}` and
`html{scroll-padding-top:<header height>}` on admin.html (set from the measured height, since the header wraps).

**WEB2-8** F5, K1 (Block). All engines, the "Photo/Place/Note for all…" dialogs (and every `dialog()` of index.js:814). A
check that fails ("Fill at least one field", "Write the note first", "Floor: a whole number from 0 to 10…",
"The floor first…") is shown in `#toast`. The toast lies under the modal dialog's 60 % black backdrop (the dialog is in the
top layer), so it is dimmed well below 4.5:1. It disappears after 2.2 s (index.js:11), and the focus stays on Send. Evidence:
`probe3.json` `modal_toast` (`elementFromPoint` at the toast's centre returns the dialog/backdrop, not the toast; hidden
again at 2.5 s); `shots/p3-chromium-modal-toast.png`, `p3-webkit-…`, `p3-firefox-…`. Size: SMALL. Fix: show the
message inside the dialog under the field it concerns (`role="alert"`), focus that field, and keep it until the field changes.

**WEB2-9** T5, A1, A2 (Block). All engines, tag panel photos and the photo viewer.
- The panel's photos open the viewer only by a mouse click: they are `<img onclick>`, not buttons, so a keyboard user can't open them
  (index.js:614).
- In the viewer, a zoomed photo can be moved only by dragging. Zoom has a tap alternative (double tap) and the wheel,
  but there are no buttons and no keys for zooming or moving; only Escape is handled (common.js:999–1022).
- The focus doesn't move into the viewer. The viewer has no `role="dialog"`, and its photo has `alt=""`
  (common.js:982), so a screen reader hears nothing. The panel's photos are named by caption or just "Photo" (index.js:614),
  but the policy wants a photo named by its tag and date.
Size: SMALL–LARGE (buttons and keys for zoom and pan in the viewer, a `<button>` around each thumbnail, names).

**WEB2-10** C1, S3 (Block). Admin Devices and the join screen. Besides WEB-9's two places, three more show identifiers cut
to a prefix and "…" with the full value nowhere on the page: peers (admin.js:296), devices online at the relay
(admin.js:306), and "Device …" on the join screen (common.js:329). Size: SMALL (the same fix as WEB-9).

**WEB2-11** C2 (Block, minor). Join flow and admin Devices. The 6-digit join confirmation code is printed with a
space in the middle (admin.js:536, common.js:462), so selecting and copying it gives `123 456`. Size: SMALL. Fix: two
spans with a margin between them instead of a space character (it then looks the same and copies as `123456`).

**WEB2-12** F2 (Block). See the correction table: real server messages that reach the user raw. The worst is
"sync with HOST:PORT failed: <OS or TLS error>" after "Sync now" in peer mode (server.nim:1697 → admin.js:518 → toast).
Size: SMALL (map them to sentences on the server, and keep the detail for diagnostics).

**WEB2-13** R3 (Block). iPhone home screen app (`viewport-fit=cover`). The toast (index.html:100, admin.html:51), the
photo-colour legend (index.html:63) and the end of every drawer's list (index.html:102–106) don't add
`env(safe-area-inset-bottom)` and sit under the home indicator. Code evidence only (no iPhone). Size: SMALL.

**WEB2-14** K2 (Block). Phone, Review drawer. The reader's suggested code ("→ 11…") is shown in the accent colour
(index.js:1153, `color:var(--accent)`): #ff7a1a on #243440 is 4.91:1, under 7:1 for a code. Pass 1's WEB-14 covers the
same colour in admin cards but not here. Size: SMALL.

## 3. Not checked by pass 2

- Real iPhone/Safari, VoiceOver, the on-screen keyboard: no device.
- Forced colours beyond pass 1's one Chromium panel screenshot (see the K1 correction). Not re-run, to keep to one probe.
- P3 for heavier interactions than search → panel (the Systems drawer on a full plant, box-select of many tags):
  needs a large synthetic sheet set.
