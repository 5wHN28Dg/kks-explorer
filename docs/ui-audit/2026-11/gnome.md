# UI/UX audit 2026-11, pass 1 (blind): Walkdown GNOME app

Auditor: desk. Policy: `docs/UI-UX-POLICY.md` (adopted 2026-11-15). Code: main at 9eb5b09b.

## 1. What was run

- **Builds** (from 9eb5b09b, Nim 2.2, each through heavyslot + memjob 4): `kks_server`, `kks_import` (MuPDF 1.28.5),
  the GNOME app `kks_explorer` (GTK 4.22.4, libadwaita 1.9.1, system libraries).
- **Data:** synthetic only: `test_gnome.py`'s `Plant` fixture (server on loopback, `importer/tests/vectors/kkp-sample.pdf`
  imported twice as "Sample sheet" and "Second sheet", tag 11LAB70AA500, draft description, location row and
  instrument point). Arabic note `مضخة التغذية 11LAB70AA500 تعمل` typed into the tag's Notes.
- **Session:** `apps/gnome/e2e/headless.sh` (private mutter 1280 × 900, own D-Bus, XDG dirs) under
  `flock ~/kks-work/build/gnome-e2e.lock`, memjob 8. Desktop checked before and after every run (doc mount ID 579
  unchanged; keyrings, flatpak/db and dconf/user mtimes unchanged; desktop `text-scaling-factor` still 1.0).
- **Walk** (`gnome_audit.py`, scratch): join through the server, search (`lab70aa500`, `11 lab70 aa500`), tag panel,
  Edit form with the Arabic note, Save, the seven sidebar pages (Procedures, Equipment by system, Coverage, Learning,
  Review queue, Connectors, Notes), Manage and its pages (Approvals, My proposals, History, People, Devices, Account).
  Each step: window screenshot (`KKS_SHOT_ON_SIGNAL`) and AT-SPI dump (role, name, states, extents).
  Modes, one app start each: light (`ADW_DEBUG_COLOR_SCHEME=prefer-light`), dark (`prefer-dark`), high contrast
  (`ADW_DEBUG_HIGH_CONTRAST=1`), Large Text (`gsettings text-scaling-factor 1.25` inside the headless session only).
  84 screens dumped (1,881 control instances).
- **Keyboard only:** real key presses through mutter's RemoteDesktop D-Bus API (`NotifyKeyboardKeysym`) in the
  headless session: 40 × Tab from the tag panel, the focused node read after each.
- **Not run:** a 360 × 640 window (R1/S2 at the smallest size), reduced motion (`gtk-enable-animations` off), server
  down / errors (F2, F3), clipboard round trip (C1–C3), the About dialog, destructive dialogs opened on screen (read
  from code instead), Approvals with 20 items (B1; the queue was empty), the photo editor, the courses.
- **Scripts** (scratch, `~/kks-work/build/ui-audit/desk/`, worth keeping under `tools/ui_audit/`): `gnome_audit.py`
  (the walk + RemoteDesktop keyboard helper), `gnome_analyze.py` (sizes, names, overlaps from the dumps),
  `contrast.py` (WCAG ratios).

## 2. Results

| Rule | GNOME | Note |
|---|---|---|
| T1 | N/A | phone rule |
| T2 | **Fail** | GNOME-3: History's Revert and Restore 6 px apart |
| T3 | Pass | 1,881 targets, none under 24 × 24 px; no partial overlaps (all four modes) |
| T4 | Advice: not checked | needs a pointer on the drawing |
| T5 | **Fail** | GNOME-6: Mark a tag and photo boxes/arrows only by dragging |
| R1 | Pass | tag panel's Close is in its header bar outside the scroller (`kks_explorer.nim:342-347`); pushed pages keep Back in the header. 360 × 640 not checked |
| R2 | Pass (partial) | drawing modes: e2e `test_zzzzzz_escape`; dialogs: `adw_alert_dialog_set_close_response` cancel (`ui.nim:128,143`). Escape on pushed sidebar pages not checked |
| R3 | N/A | desktop |
| R4 | Pass | Save directly after the last field (Account, Edit form) |
| C1 | **Fail** | GNOME-4: device IDs cut to 16 chars and not selectable; sheet names not selectable. KKS heading selectable (`panel.nim:427`). Copy button: in progress (branch tag-copy-sticky-batch) |
| C2 | Not checked | no clipboard round trip in the headless session |
| C3 | **Fail** (in progress: branch tag-copy-sticky-batch) | selection + Ctrl+C gives no confirmation; no Copy button on main |
| B1 | **Fail** | GNOME-7: Approvals (in progress: branch tag-copy-sticky-batch), review queue, devices one by one |
| B2 | N/A | no bulk action on main besides "… for all" forms (place/note/photo), which state the codes |
| B3 | Advice: not checked | |
| K1 | **Fail** | GNOME-1: row subtitles / dim labels 3.0:1 light, 3.6–4.1:1 dark; high contrast passes (7.8–9.3:1) |
| K2 | N/A | phone rule |
| K3 | **Fail** | GNOME-2: focus ring 2.2–2.6:1; review-tag outline 2.0–2.5:1 on white |
| K4 | **Fail** | GNOME-5: tag status and photo coverage on the drawing by hue only |
| K5 | Pass | no text drawn over the drawing; banner and toasts on their own surfaces |
| K6 | Pass | every screen follows `prefer-dark`; drawings follow their own opt-in dark toggle (README) |
| K7 | Advice: not checked | |
| S1 | Pass | libadwaita type classes only (no custom font sizes in `apps/gnome`); smallest is `caption` |
| S2 | Pass | Large Text 1.25: sidebar and panel grow, rows wrap, nothing overlapping (`large-*` shots) |
| S3 | **Fail** | GNOME-4: device IDs ellipsised (Devices, Account "This device") |
| F1 | Pass (partial) | toasts after Save ("Nothing changed"), photo queue line; long imports not exercised |
| F2 | **Fail** | GNOME-8: core error strings shown raw ("not found", "conflict", "error 404" fallback) |
| F3 | Not checked | server-down run not done |
| F4 | Pass | `gtk_accessible_announce` (`panel.nim:69`, `multi.nim:26`); libadwaita 1.9 announces toasts (imports `gtk_accessible_announce`) |
| F5 | Not checked | join form's "needs a position" message seen in e2e, focus placement not checked |
| F6 | Advice: **Fail** | GNOME-10: Procedures page is blank when there are none |
| D1 | Pass | confirms for delete photo, remove tag, remove device, revert, restore, withdraw (`ui.nim:122`, callers in photos/manage/panel). Note: Approvals' Reject acts at once (someone else's proposal) |
| D2 | Pass | named confirm buttons, `ADW_RESPONSE_DESTRUCTIVE`, default and close response Cancel (`ui.nim:122-145`) |
| D3 | Pass | "Discard your edits?" on leaving a form (`win.nim:123`; e2e `test_zzzzzzzz_form_ask`) |
| D4 | N/A | no sign-out / leave-plant action in the GNOME app |
| X1 | Not checked | cross-platform label comparison left to the coordinator (labels are in the dumps) |
| X2 | N/A | full audit, no change |
| X3 | Pass | header bars, Adw dialogs/toasts, destructive/suggested styles |
| A1 | **Fail** | GNOME-2/6: the drawing shows no focus indicator; marking a tag needs a mouse drag. Tab order otherwise follows the reading order and reaches header, sidebar, panel and drawing |
| A2 | Pass | 0 unnamed controls in 84 dumps; icon buttons named ("Zoom out (−)", "Close the panel", "Sync now") |
| A3 | Pass | search and Equipment by system list every tag; result opens the same panel |
| A4 | Pass (code) | course figures follow `gtk-enable-animations` (`coursefig.nim:150`); libadwaita animations follow it; not run |
| A5 | N/A | Plant rule |
| L1 | Pass | Arabic note with the code renders right-to-left with the code intact (`*-04b-saved-arabic`) |
| L2 | **Fail** | GNOME-3: History rows squeeze title/code into a ~50 px column, words broken mid-word ("equipme-nt", "11LAB70 / AA500") at 100 %; header subtitle "Test plant · 1 device reacha…" cut at 100 % and 125 % |
| L3 | Pass | units shown where values appear (location "33 m", coverage %) |
| L4 | Pass | dates as 2026-11-15 |
| L5 | Advice: **Fail** | GNOME-9: "1 tags" in the sheet list |
| P1 | N/A | Plant |
| P2 | Not checked | no measurements run |
| P3 | Not checked | no action timings taken (every walk step completed within its wait) |
| P3a, P4 | Not checked / N/A | |
| Z1–Z3 | Pass | fixture data only. Raw shots of Devices/Account show this laptop's host name as the device label and Learning shows the plant courses' names: those shots were not copied; the Devices crop shows other rows only |
| G1 | Pass | `lab70aa500` and `11 lab70 aa500` both find 11LAB70AA500; GTK has no autocorrect on desktop |
| G2–G4 | N/A | phone rules |

Counts (table rows): Pass 22, Fail 14 (12 Block, 2 Advice), N/A 10, Not checked 9 (3 of them Advice).

## 3. Findings

**GNOME-1 (K1) Secondary text below 4.5:1.** AdwActionRow subtitles and `dim-label` text (row values such as "11
Block 1, HRSG #1", "1 tags", the tag's kind line) measured 3.0:1 (149 grey on white) and 2.8:1 in light, 3.6–4.1:1
in dark; high contrast 7.8–9.3:1. Evidence: `gnome-GNOME-1-dim-subtitles.png`, darkest-glyph sampling of
`light/dark-03-panel.png`. Values the user reads (Floor "2", location, notes) are subtitles. SMALL: one CSS provider
raising the dim opacity (or `.subtitle`/`.dim-label` colour) to ≥ 4.5:1 in light and dark; test by sampling a shot.

**GNOME-2 (K3, A1) Focus indicator.** Toolkit focus ring (50 % accent) measured (209,141,117) on white/grey: 2.6:1 and
2.2:1. The drawing (`kks_view`, custom widget) takes focus in the Tab order (`image 'Drawing Sample sheet'`) and draws
no indicator at all (pixels at its edge unchanged). Review-tag outline amber at α 0.75: 2.0:1 on white
(`viewer.nim:436-441,702`). Evidence: `gnome-GNOME-2-focus-ring.png`, `light-keyboard-tab-order.json`. SMALL for the
drawing (draw a ring when focused) and the ring opacity (CSS `outline-color`); amber outline SMALL (darker amber).

**GNOME-3 (T2, L2) History rows.** Revert and Restore are 6 px apart (both destructive; [81,188,81,34] and
[168,188,88,34]). The row's title/subtitle get ~50 px: "#", "· ·", "equipme-nt", "11LAB70 / AA500",
"74105c36f4cd85c8…" broken across 3–6 lines. Evidence: `gnome-GNOME-3-history-rows-crushed.png`,
`light-21-History.json`. SMALL: buttons under the text (or in a menu) with ≥ 8 px gap.

**GNOME-4 (C1, S3) Device IDs cut and not copyable.** Devices shows `dev[0 ..< 16] & "…"` in a non-selectable
subtitle (`manage.nim:403`); Account's "This device" shows the ID ellipsised. Sheet names in the sidebar are not
selectable either. Evidence: `gnome-GNOME-4-device-ids-cut.png`. SMALL: full ID, selectable, wrapping (or a Copy
button); `row(..., selectable = true)` for sheet rows.

**GNOME-5 (K4) Hue-only states on the drawing.** Tag outlines: verified green, review amber, auto blue (pending is
dashed); Coverage colouring green/amber/blue/red with no pattern (`viewer.nim:427-441`). Red vs green in Coverage is
the CVD worst case. LARGE (design: dash/fill patterns or corner marks per state, shared with web/Windows/Android).

**GNOME-6 (T5, A1) Drag-only actions.** Mark a tag: "drag a box on the drawing" (`mark.nim:1`, `viewer.nim:814`), no
click or keyboard alternative; photo annotation boxes, arrows, circles are drag-only (`photos.nim:225`). LARGE-ish:
two clicks for corners plus a keyboard-placed box.

**GNOME-7 (B1) One-by-one decisions.** Approvals (Approve/Reject per item, `manage.nim:113-118`; in progress: branch
tag-copy-sticky-batch), the review queue (`sidepages.nim:168`, up to 250 items, each opened alone), removed devices
(Hide per row). LARGE.

**GNOME-8 (F2) Raw errors.** API failures are toasted as the core's message (`w.toast(e.msg)`, 32 sites), which
includes "not found", "conflict", "method not allowed" (`core/src/kks/api.nim`) and the fallback `"error " & status`
(`apps/common/appstate.nim:273`). LARGE (shared core wording across clients).

**GNOME-9 (L5, Advice)** "1 tags" under a sheet (`light-01-main.png`). SMALL.

**GNOME-10 (F6, Advice)** Procedures page empty with no sentence when no procedures are published
(`light-10-procs.json`: only the title). SMALL.

## 4. Screenshots

In `shots/`: `gnome-GNOME-1-dim-subtitles.png`, `gnome-GNOME-2-focus-ring.png`,
`gnome-GNOME-3-history-rows-crushed.png`, `gnome-GNOME-4-device-ids-cut.png`. All 84 shots and dumps (light, dark, hc,
large) are in `~/kks-work/build/ui-audit/desk/gnome-out/` (first, partial run in `gnome-out-1/`).
