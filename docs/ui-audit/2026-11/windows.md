# UI audit 2026-11, pass 1: Walkdown Windows (helper "vm")

*Example codes in this record and in its screenshots were replaced with an invented code or blurred on 2026-11-19 (the owner's decision); the findings are unchanged.*

## 1. What was run

- Build: main at 9eb5b09b, cross-built with `apps/windows/build.sh` (llvm-mingw, x86_64) → Walkdown.exe (16.5 MB) and
  uiadrive.exe. Server and importer from the same commit.
- VM: kks-win11 only (Windows 11 26H2, 1280 × 800 screen, 96 dpi), under `vm.lock`, shut down afterwards. kks-win10 not
  run (time). Notifications off during the run (test_windows.toasts_off/back).
- Data (synthetic only): the same server as Android (sample sheet, 21 marked tags, 11LAB70AA500 with the Arabic fixture
  note and long text, 20 open proposals by a member), joined as the manager.
- Driven with `apps/windows/e2e/run.ps1`/`runapp.ps1` and the UIA driver. For rectangles, a scratch copy of uiadrive
  (`uiadrive-rects.cpp`: its `dump` also prints BoundingRectangle, IsKeyboardFocusable, IsOffscreen and AccessKey),
  not committed. Screens: setup, join form (server down), main, tag panel (top and scrolled to the end), Manage,
  Approvals, History (and its Revert question), Devices, Account, Equipment by system (Escape); light; dark
  (AppsUseLightTheme = 0, app restarted); a contrast theme (SPI_SETHIGHCONTRAST "High Contrast Black"); text size 150 %
  (TextScaleFactor = 150, VM restarted); keyboard: Tab, Escape on the panel and on Equipment by system.
- Scripts (scratch `~/kks-work/build/ui-audit/vm/`): `waud.py` (run a uiadrive script, dump, virsh screenshot, T3/T2/A2
  report), `uiadrive-rects.cpp`, `hc.ps1` (contrast theme on/off), `hold-vm.sh`, `wrun.sh`. Raw output:
  `~/kks-work/build/ui-audit/vm/windows/`. The VM's settings were put back (contrast off, text size removed, dark off).
- Not run: Narrator speech, Windows 10, the photo editor and mark-up, copy/paste checks.

## 2. Results

| Rule | Windows (kks-win11) |
|---|---|
| T1 | N/A (phone rule) |
| T2 | Pass (Approve/Reject and Revert/Restore 8 px apart; no overlaps between targets) |
| T3 | Pass [a] |
| T4 | Not checked |
| T5 | Not checked (mark a missing tag and photo mark-up not driven; arrow keys pan and +/− zoom the drawing, viewer.nim:646-652) |
| R1 | Fail: in progress, branch tag-copy-sticky-batch (panel's Close at y = -393 after tabbing to the end of 11LAB70AA500's panel) |
| R2 | Fail (WIN-7) |
| R3 | Fail (WIN-8) |
| R4 | Not checked |
| C1 | Fail (WIN-9); the panel's code heading: in progress, branch tag-copy-sticky-batch |
| C2 | Not checked |
| C3 | Not checked |
| B1 | Fail: in progress, branch tag-copy-sticky-batch (Approvals: 20 cards, one Approve/Reject each) |
| B2 | Not checked |
| B3 | Not checked |
| K1 | Pass (system colours: COLOR_WINDOW/WINDOWTEXT, ui.nim:541, 709-712; contrast theme followed, shot hc-main) |
| K2 | N/A (phone rule) |
| K3 | Pass (standard Win32 focus rectangles and borders, system colours) |
| K4 | Fail (WIN-10) |
| K5 | Pass (panel and sidebar are opaque system-colour panes beside the drawing) |
| K6 | Fail (WIN-3) |
| K7 | N/A (no dark mode, WIN-3) |
| S1 | Pass (message font at 15 px ≈ 11 pt, small 13 px ≈ 10 pt, title 20 px; ui.nim:138-147) |
| S2 | Fail (WIN-11) |
| S3 | Fail (WIN-9: device IDs cut with "…") |
| F1 | Not checked |
| F2 | Fail (WIN-12) |
| F3 | Not checked (server not stopped on Windows) |
| F4 | Fail (WIN-13) |
| F5 | Not checked |
| F6 | Not checked |
| D1 | Pass (Revert, Restore, Remove device, Delete/Discard photo, Withdraw ask first: manage.nim:201/288/295/451, photos.nim:584/778, panel.nim:303) |
| D2 | Fail (WIN-2) |
| D3 | Fail (WIN-5) |
| D4 | Not checked (no sign-out found on the pages driven) |
| X1 | Fail (see android.md AND-25: "About Walkdown…" vs "About Walkdown", "This device" vs "This phone: …") |
| X2 | N/A (full audit, no change) |
| X3 | Fail (WIN-14) |
| A1 | Pass, partly checked [b] |
| A2 | Fail (WIN-15) |
| A3 | Pass (tags are UIA buttons "11LAB70AA500, verified" on the drawing pane; search list) |
| A4 | Not checked |
| A5 | N/A (Plant) |
| L1 | Fail (WIN-1) |
| L2 | Fail (WIN-4) |
| L3 | Pass |
| L4 | Pass ("2026-11-15", "yyyy-MM-dd HH:mm") |
| L5 | Pass on the screens seen ("(21 tags)", "1 tag" forms in code) |
| P1 | N/A (Plant) |
| P2 | Not checked |
| P3 | Pass (every scripted action answered within the driver's 1-2 s waits; no hang) |
| P3a | Not checked |
| P4 | N/A (phone) |
| Z1 | Pass (synthetic only) |
| Z2 | Pass (screenshots show the VM's own taskbar: weather, clock; no names or paths) |
| Z3 | N/A |
| G1-G4 | N/A (phone rules) |

Notes:
- [a] Under 24 px only toolkit-drawn, not restyled controls (exempt): list-box items 20 px (Sheets, Floor), scroll bar
  arrows 17 px, MessageBox buttons 75 × 23. App buttons 30-32 px tall.
- [b] Tab moves through the tab buttons and sidebar with a visible focus rectangle; Escape closes "Equipment by system";
  arrow keys/+/− on the drawing (code). Escape does not close the tag panel (WIN-7).

## 3. Findings

**WIN-1** L1 (Block). Tag panel, Near / landmark and Notes (read-only edits): the fixture note shows as
`11 مضخة التغذيةLAB70AA500 تعمل`, left-to-right, with `11` split from `LAB70AA500`. No WS_EX_RTLREADING anywhere in the
app (grep). Evidence: shots/windows-WIN-1-arabic-note-splits-code.png. Size SMALL: set the reading direction from the
first strong character and isolate KKS runs (as the policy says), shared with AND-1's helper.

**WIN-2** D2 (Block). Every destructive question is a MessageBox with OK/Cancel or Yes/No (ui.nim:889-894): "Revert this
change?" shows OK (default, focused) and Cancel, so Enter reverts. Same for Restore, Remove device, Delete/Discard photo,
Remove this tag, Withdraw, Replace values. Evidence: shots/windows-WIN-2-revert-ok-default.png. Size SMALL to LARGE: a
TaskDialog with named buttons ("Revert", "Cancel") and Cancel default (TDF + nDefaultButton).

**WIN-3** K6 (Block). With the app theme set to dark (AppsUseLightTheme = 0) and the app restarted, every window stays
light; only course figures read the theme (coursefig.nim:111). Evidence: shots/windows-WIN-3-dark-mode-not-followed.png.
Size LARGE (Win32 dark mode: DwmSetWindowAttribute DWMWA_USE_IMMERSIVE_DARK_MODE, owner-drawn colours, dark list/edit
backgrounds).

**WIN-4** L2/R1 (Block). The five tab buttons need 12 + 5 × 92 = 472 px but the sidebar is SideW = 380 px
(kks_explorer.nim:17, 329-336): "Manage" (380-468 px) lies under the drawing pane (starts at 388) and is hidden at
first paint (shots/windows-WIN-4-manage-tab-covered.png; it shows again only after a repaint). Also the window opens
1280 × 820 on a 1280 × 800 screen, so the "Last sync" line (y 788-810) is under the taskbar. Size SMALL: lay the tabs
out within the sidebar (wrap or narrower), clamp the first window size to the work area.

**WIN-5** D3 (Block). Tag panel → Edit, set Building / area to new text, Close: the panel closes without a question and
the text is gone (reopened: the old value). Size SMALL: ask "Discard your changes?" when the form differs.

**WIN-6** X1/F2 (Block; a plain bug). Manage → History rows show `#` and ` ·  · added_tag e44970b8…`: manage.nim:283-284
reads `n`, `summary`, `note`, `by_name`, `at`, which /api/revisions does not send (`rev`, `ts`, `full_name`). Same as
AND-2. Size SMALL.

**WIN-7** R2 (Block). Escape with the keyboard in the tag panel (an edit) leaves the panel open: there is no Escape
handling for the panel (grep: only photos.nim:115 and the viewer). Size SMALL.

**WIN-8** R3 (Block). At the VM's 1280 × 800 the main window is 1280 × 820, so its bottom 20 px (the "Last sync" status
line) are under the taskbar (WIN-4). Size SMALL.

**WIN-9** C1/S3 (Block). Device IDs in Manage → Devices are cut to 16 characters with "…" in a static text
(manage.nim:442): not copyable, not complete. The panel's code heading `11LAB70AA500` is a static Text (its parts are in
read-only edits, which can be copied; in progress, branch tag-copy-sticky-batch). Account's "This device" is a read-only
edit (pass). Size SMALL.

**WIN-10** K4 (Block). Tag states on the drawing differ only by outline colour (viewer.nim:371: "verified" 0x269940
etc.). Same as AND-15. Size LARGE.

**WIN-11** S2 (Block). Text size 150 % (TextScaleFactor = 150 after a restart; the taskbar's text grew): Walkdown's text
is unchanged; the fonts are fixed at px(15)/px(20)/px(13) from the DPI only (ui.nim:138-147). Size SMALL to LARGE:
scale the fonts by the text scale factor (UISettings.TextScaleFactor or the registry value) and re-layout; the 380 px
sidebar (WIN-4) then needs to grow.

**WIN-12** F2 (Block). Join, server down: "cannot reach HOST:1: The remote computer refused the network
connection." No next step and a technical form; better than Android's (no errno). Size SMALL (same wording as AND-3's
fix).

**WIN-13** F4 (Block). No UIA notification or LiveRegionChanged anywhere (grep for UiaRaiseNotificationEvent,
LiveRegion, NotifyWinEvent: none): the status line, join errors and "Saved"-type messages are not announced. Size SMALL to
LARGE (a shared `announce()` with UiaRaiseNotificationEvent).

**WIN-14** X3 (Block). No Alt-key accelerators on buttons or tabs: every element's AccessKey is empty in the dump, and
labels.nim:1-9 doubles every "&" because "the app has no such shortcuts". Size LARGE (choose and keep unique mnemonics
per page).

**WIN-15** A2 (Block). The search results list has no name (List at 24,143, 331 × 180; the label names the edit only).
Size SMALL.

## 4. Screenshots (in shots/)

windows-WIN-1-arabic-note-splits-code.png, windows-WIN-2-revert-ok-default.png,
windows-WIN-3-dark-mode-not-followed.png, windows-WIN-4-manage-tab-covered.png.
