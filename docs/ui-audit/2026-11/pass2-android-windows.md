# UI audit 2026-11, pass 2 (adversarial): Walkdown Android and Windows

*Example codes in this record and in its screenshots were replaced with an invented code or blurred on 2026-11-19 (the owner's decision); the findings are unchanged.*

Pass 1's results: android.md and windows.md in this folder. This pass ran nothing on the emulator or a VM: it reads
the code at 9eb5b09b (the checkout pass 1 built) and pass 1's raw outputs in `~/kks-work/build/ui-audit/vm/`
(uiautomator dumps and their `.txt` reports, UIA dumps and `.issues.txt`, screenshots). Contrast ratios are computed
with the WCAG formula from the colours in the code. "From code" means the result is read from the source and was not
seen on screen.

Known and excluded (in progress elsewhere): copying the code from the tag panel, the panel's heading and Close staying
in view, bulk approve/reject, and the History rows (AND-2, WIN-6).

## Android

### Corrections to pass 1

| Rule | Pass 1 | Pass 2 | Evidence |
|---|---|---|---|
| R2 | Pass | **Fail** | The rule itself says Back must never drop typed input without asking. Pass 1 saw it do that (note [a], AND-24) but still passed R2. More cases: Back in the photo editor closes it and throws away the photo, its marks, the caption and the note (`Dialog(onDismissRequest = onCancel)`, Photos.kt:291); Back or a tap outside "Mark a missing tag" drops the typed code and note (`AlertDialog(onDismissRequest = { onDone(false) })`, Root.kt:562); Back on a join form (Setup.kt:32) drops the server address, username and names. Back is not handled in mark mode or full view (the `BackHandler` at Root.kt:268 leaves out `marking` and `ui.fullView`), so Back there leaves the app while a mode is on. See AND2-1. |
| D1 | Pass | **Fail** | One tap, with no question and no Undo, throws away something a person made: **Reject** and **Use this one** in Approvals (Manage.kt:151, 154; "Use this one" also rejects every other proposed photo of that kind); **Refuse** on a join request (Manage.kt:382); **Unlink** (✕) on a procedure step's chip (Procedures.kt:82-85; the policy names "a link"); **Not a tag** in the review section (Panel.kt:222); the photo editor's **Cancel** and Back (Photos.kt:388, 291), which throw away an annotated photo. Pass 1 checked only the actions that do ask. See AND2-2. |
| K1 | Pass | **Fail** | Course scenario panels (Learn.kt:714-717) show readings in CourseColors (Learn.kt:132-133) on surfaceVariant. Light theme, on #E7E0EC: alarm #9A6412 is 3.87:1 and ok #2E7A4E is 4.06:1. Dark theme, on #49454F: act #F0776B is 3.36:1 and ok #62C08A is 4.19:1. This is 16 sp bold, which is not "large", so the limit is 4.5:1. The shipped courses use these states (data/courses/hrsg.json and inc.json, 29 readings with a state). The photo viewer's Close button is primary #6750A4 on black (3.26:1) in the light theme (Photos.kt:88-95). See AND2-3 and AND2-4. |
| K3 | Pass | **Fail** | Pass 1 checked only Material's outlines. The drawing's highlights are covered by this rule too. In light mode, a tag that needs checking is outlined in amber #F28C00 on the white sheet: 2.46:1. The coverage colour for "equipment photo only", #E69600, is 2.41:1 and "both" #2EA043 is 3.37:1 (SheetView.kt:633-655). So when the selected tag is one waiting for review, its highlight is under 3:1. The panel's drag handle (onSurfaceVariant at 50 % alpha, Panel.kt:96) is about 2.4:1. See AND2-5. |
| K5 | Pass | **Fail** | The photo viewer puts the caption (white) and Close straight on top of the photo, with no backing (Photos.kt:93-95). The course image viewer does it right with a 60 % black pill (Learn.kt:666). See AND2-4. |
| K7 | Not checked | **Pass** (from code) | The window theme is `@android:style/Theme.Material.NoActionBar`, which has a dark window background (manifest line 19), and every Compose dialog takes the colour scheme, so dark mode can't flash white. The reverse does happen: in the light theme the cold start and splash are dark, which no rule covers. |
| C2 | Not checked | **Pass** (from code, for the Copy buttons there are) | The invite's Copy puts exactly `code` on the clipboard (Manage.kt:434). Diagnostics copies the report JSON, which is meant to be copied whole. |
| S1 | Fail (AND-16) | Fail, **more**: | The bottom bar's labels shrink to 0.7 × labelMedium = **8.4 sp** (Root.kt:164-170), well under the 12 sp floor. At font scale 1.3 they are already shrunk below the size the system asked for. A course `small` run inside bodySmall text is 0.85 × 12 = 10.2 sp (Learn.kt:145). |
| S3 | Fail (AND-18) | Fail, **more**: | Sheet names are identifiers (the copy rule lists them) and they are cut with "…": the app bar title (Root.kt:329-330, 2 lines), the sheet line in Equipment by system (Systems.kt:171, 1 line) and Coverage titles (Coverage.kt:158). |
| T2 | Fail (AND-8) | Fail, **more**: | On a procedure step, the unlink ✕ sits inside the chip that opens the tag (Procedures.kt:79-86): the two targets overlap, the destructive one has 0 dp of space around it, and the ✕ is a bare `Text` about 20 dp across (T1 too). Pass 1 never saw it because the test data had no procedures ("No procedures yet"). On the Devices page, Accept and Refuse for a join request are adjacent TextButtons in a bare `Row` with no spacing (Manage.kt:381-385). Under a photo with no credit line, the panel's Delete button sits right under the clickable thumbnail (Photos.kt:157-162), with no gap. |
| T5 | Fail (AND-10) | Fail, **more**: | The photo viewer zooms and pans only with a pinch or a drag (Photos.kt:89-91): there are no buttons. The photo editor has zoom buttons, but panning there needs two fingers. |
| A2 | Fail (AND-26) | Fail, **more**: | Photos are named "Open photo" or "Open photo: caption", not by their tag and date as the rule asks (Photos.kt:77, 92). Every photo's button is just "Delete", so TalkBack can't tell which photo each one deletes (Photos.kt:162). |
| F2 | Fail (AND-3) | Fail, **more**: | When the core sends no message, the fallback is the raw HTTP status, "error 500" (Common.kt:25, Panel.kt:32). A join that isn't accepted says "Not accepted: <raw state> (<why>)" (Setup.kt:121). |
| L5 | Fail (AND-27) | Fail, **more**: | "1 tags" in the Sheets drawer (Root.kt:484) and "1 steps" in Procedures (Procedures.kt:45). |
| G3 | Fail (AND-5) | Fail, **more**: | In landscape the app bar, the search field and the bottom bar leave the drawing about 29 % of the height. After a rotation the sheet is not fitted again (`onSizeChanged` fits only when it isn't fitted yet, SheetView.kt:440), so only a sliver of it shows. Evidence: android/landscape-main.png. |
| K4 | Fail (AND-15) | Fail, **more**: | The course scenario readings tell "within limits", "alarm" and "beyond limit" apart only by colour: all three are bold monospace, with no word or icon (Learn.kt:716-717). See AND2-3. |

### New findings

**AND2-1** R2/D3 (Block). Back and dismissing a dialog drop typed input without asking. (1) The photo editor:
system Back closes it and loses the picture, its marks, the caption and the note (Photos.kt:291, `onDismissRequest = onCancel`).
(2) "Mark a missing tag": Back or a tap outside the dialog drops the code, letters and note (Root.kt:562).
(3) The setup screen's join forms: Back goes to the method list and loses everything typed (Setup.kt:32).
(4) The Add-a-device dialog cancels the live invite when someone taps outside it (Manage.kt:426-428), which is easy
to do by accident with a gloved hand. Mark mode and full view don't catch Back (Root.kt:268), so Back leaves the app
from them. Size SMALL: `DialogProperties(dismissOnClickOutside = false)` plus a `BackHandler` that asks "Discard the
photo / the typed code?" whenever something was typed or drawn; add `marking` and `fullView` to Drawings' `BackHandler`.

**AND2-2** D1 (Block). These actions throw away people's work in one tap, with neither Undo nor a question: Reject, Use
this one (it rejects the rival photos too), Refuse a join request, ✕ unlink a procedure step, Not a tag, and Cancel in
the photo editor. Evidence: Manage.kt:151-154 and 382, Procedures.kt:82-85, Panel.kt:222-225, Photos.kt:388.
Size SMALL: a snackbar with Undo (Reject, Unlink and Not a tag can be undone by sending the opposite) or a `Confirm`
that names the thing (photo editor Cancel when marks or text exist; Refuse).

**AND2-3** K1/K2/K4 (Block). Course scenario panels: the readings' state colours fail contrast (light: alarm 3.87:1, ok
4.06:1; dark: act 3.36:1, ok 4.19:1; measured values need 7:1 on phones) and colour is the only signal (all three
states are bold). Learn.kt:131-135 and 714-717. The shipped courses (hrsg, inc) use them. Size SMALL: darker light /
lighter dark tokens (COURSES.md §9.3 and figdraw.nim share them, so change all clients together), plus a word or
symbol after each value ("552 °C  alarm").

**AND2-4** K1/K5 (Block). The photo viewer (Photos.kt:83-99) puts the white caption and the Close TextButton
straight on the photo, with no backing: over a bright photo the caption disappears, and Close (primary #6750A4) is
3.26:1 even on the black margin. Size SMALL: put the top row on a translucent dark bar as the course image viewer does
(Learn.kt:666), and give Close a light colour.

**AND2-5** K3 (Block). On the drawing in light mode, the amber "needs checking" outline (#F28C00, 2.46:1 on white) and
the coverage "equipment only" outline (#E69600, 2.41:1) fall under 3:1. "both" (#2EA043, 3.37:1) only just passes.
SheetView.kt:633-655. The same values are on Windows (viewer.nim:364-374) and, by the comments, on GNOME and the
web. Size SMALL: darker amber (for example #B36200 is about 4:1) on every client together.

**AND2-6** T1/T2/D1 (Block). The procedure step's unlink ✕ (Procedures.kt:79-86): a bare `Text("✕")` about 20 dp
across, inside the chip that opens the tag, so the two targets overlap with 0 dp between them; one tap unlinks.
Not seen in pass 1 (no procedures in the test data). Size SMALL: a separate 48 dp IconButton after the chip, with
Undo in the snackbar.

**AND2-7** T5 (Block). Photo viewer: zoom and pan only by pinch and drag (Photos.kt:89-91). Size SMALL: +, −, Fit
buttons as in the photo editor.

**AND2-8** S1 (Block). The bottom bar's labels can shrink to 8.4 sp (Root.kt:164-170). Fold it into AND-4's fix (don't
shrink; hide the labels of items that aren't selected, or allow two lines). Size SMALL.

**AND2-9** S3 (Block). Sheet names are cut with "…" (Root.kt:329-330, Systems.kt:171, Coverage.kt:158). Size SMALL:
let them wrap (the app bar can drop to titleSmall, or use a larger top app bar).

**AND2-10** A2 (Block). Photos are named "Open photo[: caption]" instead of by tag and date, and every photo's Delete
has the same name (Photos.kt:77, 92, 162). Size SMALL: "Photo of 11LAB70AA500, 2026-11-15" and "Delete photo of …,
2026-11-15".

**AND2-11** G3 (Block). After a rotation the sheet isn't fitted to the new size, and in landscape the drawing gets
about 29 % of the height (landscape-main.png; SheetView.kt:440). Size SMALL: fit again when the orientation changes;
in landscape put the search field in the app bar.

**AND2-12** L5 (Advice). "1 tags" (Root.kt:484), "1 steps" (Procedures.kt:45). Size SMALL.

## Windows

### Corrections to pass 1

| Rule | Pass 1 | Pass 2 | Evidence |
|---|---|---|---|
| K1 | Pass | **Fail** (from code: likely, needs a screenshot) | Course text is RichEdit with a fixed RTF colour table: ink #16222B, accent #1F5F8B, muted #56646E and the state colours (coursertf.nim:63-66). Its background is COLOR_WINDOW (ui.nim:775). In "High Contrast Black" (and Windows 11's dark contrast themes) the window is black, so body text is #16222B on black at **1.30:1**, links 3.07:1 and muted text 3.44:1. Pass 1 looked only at the main screen in the contrast theme (hc-main). Light theme: alarm #9A6412 on white is 4.99:1 and ok #2E7A4E is 5.24:1 (passes K1). See WIN2-1. |
| K3 | Pass | **Fail** | The same drawing colours as Android: amber "review" #F28C00 is 2.46:1 and coverage "equipment" #E69600 is 2.41:1 on the white sheet (viewer.nim:364-374, coverage.nim:31-34). See AND2-5. |
| K4 | Fail (WIN-10) | Fail, **more**: | Course scenario readings tell their state apart only by colour: every value is bold, coloured \cf4/\cf5/\cf6 (coursertf.nim:209-218). |
| D1 | Pass | **Fail** | One click, no question and no Undo: **Reject** and **Use this one** (manage.nim:118-127), **Unlink <code>** (side.nim:196-201), **Not a tag** (panel.nim:71-74). The photo mark-up window's **Cancel** and close box throw away the marks, caption and note (annotate.nim:327; no onClose question). The "Discard" of a photo that wasn't sent does ask (photos.nim:584), so the app already has the pattern. |
| R2 | Fail (WIN-7) | Fail, **more**: | Several windows ignore Escape because they are opened without `escape = true`: "Mark a missing tag" (kks_explorer.nim:167), "Mark up the photo" (annotate.nim:283), "Add a device with a QR code" (manage.nim:379) and the QR scanner (camera.nim:27). Compare the ones that pass it: coverage.nim:207, links.nim:90/117, systems.nim:89 and others. See WIN2-3. |
| R3 | Fail (WIN-8) | Fail, **more**: | Pop-up windows are created at a fixed logical size and never clamped to the work area (ui.nim:995-996): "Mark up the photo" is 1000 × 860, "Add a device" 520 × 820, About 680 × 780 and Coverage 680 × 760. On the audit VM's 1280 × 800 screen (about 752 px of work area under the Windows 11 taskbar) the bottom rows, the mark-up's Send/Cancel and the invite's Accept/Refuse, land under the taskbar or off the screen. From code: pass 1 did not open these windows. See WIN2-2. |
| R1 / L2 | R1: in-progress fail only | **Fail** (from code) | The main window is created at 1280 × 820 *physical* pixels (kks_explorer.nim:399-400) while the sidebar (380) and the tag panel (420) are scaled by DPI (lines 40-50). At 150 % scaling, which is common on Windows 10 and 11 laptops, the window opens at 853 × 547 logical px. With a tag open, the drawing is then `max(10, 1280 − 570 − 630)` = 80 physical px wide. At the policy's 360 × 640 window the panel starts at a negative x and covers the sidebar. Pass 1 ran only at 96 dpi. See WIN2-4. |
| T5 | Not checked | **Fail** (from code) | Marking a missing tag needs a mouse drag (viewer.nim:578-620): there is no click or keyboard alternative. Photo mark-up places arrows, boxes and circles only by dragging (annotate.nim:210-232), and pans only with a right-button drag (it does have Zoom buttons). The drawing pans with the arrow keys (fine). |
| A1 | Pass, partly | **Fail** (from code) | The same two features can't be done from the keyboard at all (mark a missing tag, photo mark-up). The photo viewer takes only Escape from the keyboard: zoom is by wheel and pan by drag (photos.nim:96-116). |
| F3 | Not checked | **Fail** (from code) | The status line says only "Last sync HH:mm", "Syncing…" or the relay state (kks_explorer.nim:128-139). There is no offline state and no count of changes waiting to be sent, the same as AND-20. Photo failures read "not sent: <exception message>" (photos.nim:366-368), which is also an F2 fail. |
| F5 | Not checked | **Fail** (from code) | Field errors go to the status line, not to the field: "That is not a valid KKS" (panel.nim:63-64), "Floor: a whole number…" (panel.nim:125-126), "Box too small" (kks_explorer.nim:161-163). The focus is not moved and nothing marks the field. |
| F6 | Not checked | **Pass** (from code) | Empty screens say why: "Nothing to check: every reading was confirmed or rejected." (side.nim:266), "No changes yet." (manage.nim:280), "No other device of yours can pair yet…" (learn.nim:731). |
| C2 | Not checked | **Pass** (from code) | `copyToClipboard` puts the text exactly as given (ui.nim:906-921). Identifiers in read-only edit fields are copied by the system as they are. |
| C3 | Not checked | **Fail** (from code) | Diagnostics' Copy says "Copied" without naming what (manage.nim:583-584). About's "Copy details" does name it (about.nim:86-89). |
| A4 | Not checked | **Pass** (from code) | Course figures read SPI_GETCLIENTAREAANIMATION and start reduced (coursefig.nim:165-179). There is no other animation. |
| R4 | Not checked | **Pass** (from code) | Save/Cancel come right after the panel form's last field (panel.nim:110-147). Send/Cancel come right after the mark-up's fields (annotate.nim:316-327). |
| B2 | Not checked | **Pass** (from code) | Select tags says the count and what will be replaced: "x of N already have …; it will be replaced." (multi.nim:386), "Sent for N codes" (multi.nim:312). |
| L5 | Pass | **Fail** (Advice) | "(1 tags)" in the Sheets list (side.nim:34) and "1 votes" on a photo to vote on (manage.nim:223). |
| L4 | Pass | **Fail** (Advice) | The status line's "Last sync 13:14" has no date (kks_explorer.nim:131), so a sync from days ago reads as today. |
| WIN-3 evidence | "only course figures read the theme" | **Corrected** | `coursefig.dark()` always returns false (coursefig.nim:110-112): nothing in the app reads the theme. |
| WIN-2 size | SMALL to LARGE | **SMALL** | Every question goes through one helper, `ask`/`askYesNo` (ui.nim:889-894), and the manifest already loads Common Controls v6 (res/kks.manifest), so `TaskDialogIndirect` with named buttons and Cancel as the default is a change to one place (plus the button names at each call). |
| WIN-11 size | SMALL to LARGE | **LARGE** | The fonts are fixed in px (ui.nim:138-147), and the layout constants (SideW 380, tab width 92, PanelW 420, kks_explorer.nim:16-18) don't grow with text. Scaling the text needs the layout made fluid (WIN-4, WIN2-4) as well. |

### New findings

**WIN2-1** K1/X3 (Block; from code, check with a screenshot in a contrast theme). Learning's course text keeps
fixed RTF colours on the system window colour: in a dark contrast theme, body text is #16222B on black (1.30:1), so
almost invisible (coursertf.nim:63-66, ui.nim:775). The light colours are also fixed in dark contrast themes, and the
app doesn't listen for WM_SYSCOLORCHANGE or WM_SETTINGCHANGE, so a theme switched while the app runs leaves the old
background. Size SMALL: when `SPI_GETHIGHCONTRAST` is on, build the colour table from GetSysColor (WINDOWTEXT,
HOTLIGHT, GRAYTEXT) and rebuild the page on WM_SYSCOLORCHANGE.

**WIN2-2** R3 (Block; from code). Pop-up windows aren't kept inside the work area (ui.nim:985-1003). On the VM's 1280
× 800 screen, "Mark up the photo" (860 tall) and "Add a device with a QR code" (820 tall) put their buttons under the
taskbar or off the screen. Size SMALL: clamp the size to `SystemParametersInfo(SPI_GETWORKAREA)` of the owner's
monitor, and centre the window on its owner.

**WIN2-3** R2 (Block). Escape doesn't close "Mark a missing tag", "Mark up the photo", "Add a device" or the QR
scanner (no `escape = true`: kks_explorer.nim:167, annotate.nim:283, manage.nim:379, camera.nim:27). Size SMALL: pass
`escape = true` and ask first where something was typed or drawn (WIN2-5).

**WIN2-4** R1/L2 (Block; from code, not seen at 96 dpi). The first window size is in physical pixels (1280 × 820,
kks_explorer.nim:399-400), but the side (380) and the panel (420) are in logical pixels. At 125 % and 150 % scaling
(the usual setting on 1080p laptops, Windows 10 included) the window opens at 1024 × 656 or 853 × 547 logical. With a
tag open, the drawing then shrinks to `max(10, …)` px: about 80 px at 150 %. Below about 800 logical px of width, the
panel and the sidebar overlap. Size SMALL for the first part (scale the first size by the DPI and clamp it to the work
area) and LARGE for the rest (the panel over the drawing, or the sidebar folding away, in narrow windows).

**WIN2-5** D1/D3 (Block). Typed or drawn work is lost without a question by: Cancel or the close box of "Mark up the
photo" (annotate.nim:327); Cancel or the close box of "Mark a missing tag" (kks_explorer.nim:182); closing the main
window while the panel's edit form holds changes (WM_CLOSE asks only about photos, kks_explorer.nim:303-316). Also,
in one click with no question and no Undo: Reject and Use this one (manage.nim:118-127), Unlink (side.nim:196), Not a
tag (panel.nim:71). Size SMALL: the existing `ask` (with WIN-2's named buttons) when the form or the marks differ
from where they started; Undo for Reject, Unlink and Not a tag.

**WIN2-6** T5/A1 (Block). Mark a missing tag and photo mark-up work only with a mouse drag, and the photo viewer can't
be zoomed or panned from the keyboard (viewer.nim:578-620, annotate.nim:210-232, photos.nim:96-116). Size LARGE for
mark-up and marking (click two corners, or a default box moved and sized with the arrow keys), SMALL for the viewer
(+, −, the arrow keys and 0, as the drawing has).

**WIN2-7** F3/F2 (Block). There is no offline state and no count of changes waiting to be sent (kks_explorer.nim:128-139),
and photo failures show raw exception text (photos.nim:366-368). Share AND-20's core count. Size LARGE, the same as
AND-20.

**WIN2-8** F5 (Block). Field errors appear in the status line (panel.nim:63, 125; kks_explorer.nim:161), not at the
field. Size SMALL: a message under the field (a static text) and SetFocus to it.

**WIN2-9** S1/S2 (Block; from code, not seen). On WM_DPICHANGED (the window moved to a monitor with another scale, or
the scale changed) `makeFonts` deletes the HFONTs every existing control still holds and makes new ones
(ui.nim:132-147, kks_explorer.nim:299-302), without sending WM_SETFONT to the controls already built. Those controls
then draw with a deleted font handle; Windows usually falls back to the System font, which would make the text the
wrong size until the page is rebuilt. Size SMALL: keep the old fonts until every page has been rebuilt (or re-send
WM_SETFONT to every control), then delete them.

**WIN2-10** L4/L5 (Advice). "Last sync 13:14" has no date (kks_explorer.nim:131); "(1 tags)" (side.nim:34) and "1 votes"
(manage.nim:223). Size SMALL.

### Where Windows 10 may differ (kks-win10 was not run in pass 1)

Read from the code. None of these was seen, and every Windows result above stands until kks-win10 has run.

- **TLS (Schannel):** Windows 10 has no TLS 1.3 in Schannel, so sync and wss:// run on TLS 1.2 with the AEAD-only cipher
  list (kks_schannel.c:4, 39-42, 74, 191). The UI is the same, but the failures differ. A refused or failed handshake
  reports Schannel's own function name and status code (`set_err`, the error passed back by `kks_tls_error`). So the
  join and sync errors (WIN-12, F2) can read differently, and less clearly, on Windows 10: trigger them there too.
  `SCH_CREDENTIALS` needs Windows 10 1809 or later, and the UTF-8 code page in the manifest needs 1903 or later.
- **Dark mode (K6, WIN-3):** nothing changes today, because the app never reads the theme (corrected above). The fix
  is where Windows 10 differs: `DWMWA_USE_IMMERSIVE_DARK_MODE` is attribute 20 from 20H1 (19 before it), and Windows 10
  has no documented dark theme for common controls (scroll bars, list boxes, edits). Owner-drawn colours will be
  needed, and the fix must be tested on kks-win10.
- **Contrast themes (K1, WIN2-1):** Windows 10's themes are "High Contrast Black/White/#1/#2", while Windows 11's are
  Aquatic, Desert, Dusk and Night sky, with other COLOR_* values. Pass 1 set "High Contrast Black" through
  SPI_SETHIGHCONTRAST on Windows 11. WIN2-1 affects every theme with a dark window colour on both versions.
- **DPI and scaling (WIN2-4, WIN2-9, S2):** Windows 10 laptops usually default to 125 % or 150 %. Pass 1 ran only at
  96 dpi, so every T3 size and the WIN-4/WIN2-4 layout results are unverified above 100 % on both versions. Windows 10's
  "Make text bigger" writes the same TextScaleFactor, so WIN-11 should behave the same.
- **Work area (WIN-8, WIN2-2):** Windows 10's taskbar is 40 px against 48 px on Windows 11, so a 1280 × 800 screen
  leaves 760 px. The 820 px main window and the 820/860 px pop-ups still overflow.
- **Same on both:** MessageBox and TaskDialog (Common Controls v6 is in the manifest), Segoe UI and the message font,
  RichEdit 5 (Msftedit), UIA notifications (UiaRaiseNotificationEvent exists since 1709, relevant to the WIN-13
  fix), PerMonitorV2 (1703+), and edit controls without RTL reading (WIN-1).

## Summary

- Android: 15 corrections (R2, D1, K1, K3, K5 turn from Pass to Fail; K7 and C2 turn from Not checked to Pass; S1, S3,
  T2, T5, A2, F2, L5, G3 and K4 get more evidence) and 12 new findings (AND2-1 to AND2-12).
- Windows: 22 corrections (K1, K3, D1, R1/L2, L5 and L4 turn from Pass to Fail; T5, A1, F3, F5 and C3 turn from Not
  checked to Fail; F6, C2, A4, R4 and B2 turn from Not checked to Pass; K4, R2 and R3 get more evidence; WIN-3's
  evidence and the sizes of WIN-2 and WIN-11 are corrected) and 10 new findings (WIN2-1 to WIN2-10).
- Most serious: in a dark contrast theme, Windows' course text is almost invisible (WIN2-1); the windowing assumes 100 %
  scaling, so the drawing nearly disappears at 150 % (WIN2-4); one-tap Reject, Unlink and Not a tag, with no Undo, on
  both apps (AND2-2, WIN2-5); Back discards the annotated photo on Android (AND2-1); the course scenario readings are
  coloured only, and under the contrast limits (AND2-3).
