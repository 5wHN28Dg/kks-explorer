# UI/UX audit 2026-11, pass 2 (adversarial): Walkdown Plant on the desktop and Android

Auditor: pass 2, Plant. Policy: `docs/UI-UX-POLICY.md`. Code: main at 9eb5b09b (`apps/plant3d`, Godot 4.7).
Read-only: no Godot, emulator or phone runs. Evidence: pass 1's files (`plant-desktop.md`, `plant-android.md`), its
raw outputs in `~/kks-work/build/ui-audit/desk/plant-out/` (76 screenshots and Control dumps), `plant-a5.json`, and the
code (file:line below). Small scripts over those outputs only: pass 1's `plant_analyze.py` re-run, colour pairs
through its `contrast.py`, pixels sampled from its screenshots with PIL. Generic Plant content only (Z1).

Columns as in pass 1: **Desk** = Plant on a desktop at 1600 × 900; **Phone** = the phone layout on the desktop
(`ui_scale` 1.35, dp = canvas px × 0.457), standing in for Plant on Android.

## 1. Corrections to pass 1 (desktop and phone layout)

| # | Rule | Pass 1 | Pass 2 verdict | Evidence |
|---|---|---|---|---|
| 1 | R1 | Desk Pass, Phone Pass | **Fail, Fail** (PLANT2-1) | The Settings panel is not a `W.panel`: its Close and About sit at the bottom of a plain VBox after the long help text (`hud.gd:139-208`), with no scroll. Its rect in the dumps is y 280, height 898 on a 900 px canvas, on the desktop too (`desk_02_settings.json`: `[504, 280, 660, 898]`; phone `[628, 280, 660, 917]`). Close and About are below the screen's bottom (`desk_02_settings.png`: the help text runs out of the window; neither button is in the dump). Pass 1 saw the overflow on the phone only and filed it under R3/L2, not R1. |
| 2 | R2 | Phone Pass | **Fail** (PLANT2-2) | Android system Back: nothing sets `application/config/quit_on_go_back` (not in `project.godot`) or handles `NOTIFICATION_WM_GO_BACK_REQUEST` except autosave (`autosave.gd:971-975`: save, then Godot's default quits). README "Saved runs" confirms "Back is pressed" saves the run. So Back with a panel open leaves the app, not the panel. Seen in code only (no phone run). |
| 3 | R2 | Desk Pass | **Fail (minor)** (PLANT2-2) | With the map shown and no panel, Esc (`menu`) goes to `close_top()` (no map case, `plant_ui.gd:1796-1829`), then `main.gd:646-650` opens Settings **over** the map instead of closing it. Gamepad B (`ui_cancel`) does nothing on the map. |
| 4 | S1 | Desk Pass | **Fail** (PLANT2-3) | The control room screens draw text themselves (`mimic.gd` `_text`), outside the Control dump: KKS codes and labels at 13 px, trend axis "20 min" at 11 px (`mimic.gd:1100,1122,1324`), times the zoom, which `fit()` clamps to 0.9-1.3 on a desktop (`mimic.gd:563-606`). At 0.9: codes 11.7 px, "20 min" 9.9 px, under the 13 px floor. Visible in `desk_15_screens_overview.png` (the "20 min" labels). |
| 5 | S1 | Phone Fail (PLANT-2) | Fail stands; **gap bigger** | Not in PLANT-2: mimic KKS codes 13 px × 1.44-1.6 zoom = 8.6-9.5 dp (pass 1 quoted names at 10.2 dp); trend axis 11 px = 7.2-8.0 dp; `runs.gd:26` `[font_size=15]` and `permit_panel.gd:640` 17 px are not scaled (6.9 and 7.8 dp). |
| 6 | K1 | Fail (PLANT-5) | Fail stands; **more places** (PLANT2-4) | Red text under 4.5:1 also: mimic "TRIP" (TRIP colour on the cell, 13-14 px, 4.13:1, `mimic.gd:1116,1150,1165`); a blinking unacknowledged priority digit drawn in PRIO red on the cell or banner (`mimic.gd:1076,1424`, 2.9:1 on the cell); the HUD's Alarms button tinted priority-1 red while blinking (`plant_ui.gd:2143-2144`; text 0.875 × red on button × red = 3.5:1 at 22 px); condition monitoring's zone D words (0.95, 0.25, 0.2) = 3.8:1 at 17 px (`monitoring_view.gd:26,616`). |
| 7 | K2 | Phone Pass | **Fail** (PLANT2-5) | KKS codes on the control room screens are drawn in `INK_DIM` (0.32, 0.33, 0.35) on `CELL` (0.90, 0.905, 0.91) = **6.1:1** (`mimic.gd:38,35,1100,1122`); K2 asks 7:1 for codes on a phone. (Values in `INK` are 13.8:1.) Pass 1 checked only Control text over the panels. |
| 8 | K3 | Pass, Pass | **Fail, Fail** (PLANT2-6) | Unchecked check boxes are Godot's default icon, not themed (`widgets.gd` styles no CheckBox icon; `hud.gd:186-189`). Sampled from `desk_02_settings.png` at (486-504, 626-642): box (33, 35, 37) on panel (41, 45, 49) = about 1.1:1. The four Settings check boxes and "Pause when a step is done" can't be seen as boxes; state off vs on depends on that box. |
| 9 | K5 | Pass, Pass | **Fail by the rule's wording; the user to decide** | K5 says text over the 3D view "sits on a panel". The HUD status, time, hint and distance labels have a 6-8 px black outline instead (`hud.gd:48-57`, `plant_ui.gd:273,343-345,2219`). The outline likely holds contrast (pass 1's view), but that is a waiver of the rule's letter, which only the user can grant (policy §5). |
| 10 | T2 | Phone Fail (PLANT-3) | Fail stands; **another cause** (PLANT2-7) | Destructive buttons keep only the theme's gap from their neighbours: `int(8 × 1.35)` = 10 canvas px = **4.9 dp** < 8 dp (`widgets.gd:53-54`). "New run" beside "Continue" (`autosave.gd:816-818`), "Restart in it" rows (`trainer_panel.gd:92`), "Leave/End the session" (`session_panel.gd:269`), "Remove by authority…" stacked buttons (`permit_panel.gd:821-826`). Desktop: exactly 8 px, passes. |
| 11 | T5 | Not checked, Not checked | **Fail, Fail** (PLANT2-8) | Map: zoom only by wheel or pinch, rotate only by right-drag or two-finger turn; no buttons, keys or gamepad for either (`map_view.gd:88-122`; keyboard and stick only pan, `map_view.gd:84-86`). Drawings: on touch, zoom only by pinch and pan only by drag; the bar has Previous, sheet, Next, Fit, Close but no + / − or pan buttons (`drawing_view.gd:71-90`). Work view: zoom only by the magnify gesture (`work_view.gd:840`). The control room screens do have −, +, Fit (`mimic.gd:127`). |
| 12 | A1 | Desk Pass (tests) | **Fail** (PLANT2-1, PLANT2-8) | (a) Settings: the only two focusable buttons, About and Close (`hud.gd:205-207`, "these two take the keyboard and gamepad focus"), are below the screen: the focus is invisible. (b) The map's zoom, rotate and "go there" (tap a floor) have no key or gamepad button. |
| 13 | A4 | Pass, Pass | **Fail, Fail** (PLANT2-9) | "Go there" (card, procedure) flies the camera through the plant for 0.4-2.5 s (`plant_ui.gd:1300-1335`, a tween on position and heading) whatever "Reduced motion" says; that setting covers only shake and head bob (`plant_ui.gd:441,509-510`). Pass 1 left flights "not checked". |
| 14 | A5 | Desk Pass (partial) | **Fail** (PLANT2-10) | No `accessibility_*` property is set anywhere in `ui/`, `app/`, `workshop/` (grep: none). The control room screens' items (codes, values, states), which the keyboard and gamepad select and open (arrows, Enter), are drawn on one canvas and have no accessible element; so are the drawings' tags and the trends. The session panel's three `LineEdit`s have no name but their placeholder (`session_panel.gd:122-149`; dump `desk_14_session.json`: `a11y_name` empty), and the code and address fields have no visible label. A "Pass (partial)" with panels unreached is at best Not checked (policy §4); the code shows the fail. |
| 15 | A3 | N/A, N/A | **Fail (desk)** | A3 is not a Walkdown-only rule, and Plant has a P&ID viewer (DC1). A sheet's tags are reachable only by panning a tag under the centre and pressing Enter (`drawing_view.gd:565,601`); there is no list of the sheet's tags. (Cards are reachable other ways: the screens, procedures; but not from the sheet.) |
| 16 | L2 | Desk Not checked | **Fail** | At the default size the desktop Settings panel already clips (correction 1). Phone, also: with "Instructor" in the HUD bar the time label is pushed to x ≈ 0 (`phone_13_drawings.png`, "0:00:00 paused" touching the left edge): at 150 % the bar has no room. |
| 17 | B1 | Pass (partial) | **Fail (minor)** | "Acknowledge all" and "Acknowledge screen" don't say the count (B1: "The button says the count"; `alarm_panel.gd:42`, `mimic.gd:146`). The count is on the "Active (N)" tab beside it, so SMALL. |
| 18 | D2 | Pass (where used) | Pass stands, with a warning | The policy names the permit lock warning as conforming, but "Lock it anyway" has no destructive style (none exists in `widgets.gd`) and sits first in the row (`permit_panel.gd:723-728`). Any new confirmation (PLANT-8's fix) would fail D2's "styled as destructive" unless a destructive style is added to `widgets.gd` first. |
| 19 | D3 | Not checked | **Pass from code (desk, phone layout); app stop not checked** | Typed text survives panel rebuilds and Esc: the session's code and address are kept (`session_panel.gd:102-109,144`), the name is saved as typed (`:126`), a permit's removal reason is kept in `_reasons` (`permit_panel.gd:811-819`), the crew's reading entry is kept across rebuilds (`crew_panel.gd:354-375`), the work order comment in `pick[3]` (`wo_panel.gd:528`). Panels are hidden, not freed, on close. Not checked: the card's set-point entry and the work view's value entries across a close, and process death. |
| 20 | T1 | Phone Fail (104 targets) | Fail stands; **count is low** | The dump lists only controls on the screen: Settings' About and Close (off-screen), the fly Up/Down buttons (120 × 100 canvas px, unscaled, `hud.gd:91-101` = 55 × 46 dp) and the session panel's three LineEdits (45 canvas px = 20.6 dp high, `phone_14_session.json`) add to it. |

Pass 1's other cells stand as far as the evidence goes: T3 desk (smallest enabled target 31 px high, settings OptionButtons
and CheckBoxes, `desk_02_settings.json`), T2 desk (the dump's overlaps are scrolled-out card buttons and the HUD under
the full-screen manual, `desk_16_manual.png`), R1 for `W.panel` panels, the manual reader and the screens and drawings
bars, K4 (alarm badges carry the number, monitoring rows carry zone and level words, valves and drives differ by
filled vs hollow shape), F4, D1 (PLANT-8), C1 (PLANT-4), S2 (PLANT-6), L3, L4 (the saved run's time is
`YYYY-MM-DD HH:MM:SS`, `autosave.gd:812`).

Size estimates: PLANT-2 "SMALL for scaling the settings panel and HUD" is too low once the settings panel also needs a
scroll and the HUD's fixed positions (`hud.gd:61-90`: the bar at x −560, the sticks at ±440, Up/Down at −140) have to
follow the scale: medium, call it LARGE with PLANT-3. The others look right.

### Plant on Android (`plant-android.md`)

Pass 1's "Not checked" on every rule is the accepted limit (arm64 build, no phone window). Two corrections:

| Rule | Pass 1 | Pass 2 | Evidence |
|---|---|---|---|
| R2 | Not checked | **Fail from code** | PLANT2-2: system Back quits the app (Godot's default `quit_on_go_back`, no handler but the save). Needs no phone to see; a phone run should confirm it. |
| A4, T2, T5, K2, K3 | Not checked | **Fail from code** (same as the phone layout above) | The code is the same on Android; the phone-layout findings PLANT2-5 to PLANT2-9 apply there too. |

## 2. New findings

**PLANT2-1 (R1, A1, L2; Block) Settings panel runs off the screen, its Close and About out of reach.** Where:
Settings (`app/hud.gd:139-208`), desktop and phone. What: the panel is a fixed 660 px wide VBox anchored 170 px above
the middle, with no ScrollContainer; the touch-controls note, the Workshop row and the keyboard/gamepad help push it
to 898 px (desktop) and 917 px (phone) high on a 900 px canvas. Close and About, the only two controls that take the
keyboard and gamepad focus, are below the screen; with the mouse only Esc closes it. Evidence: `desk_02_settings.png`,
`desk_02_settings.json` (panel rect), pass 1's `plant-PLANT-2-phone-settings-unscaled.png`. SMALL: build Settings with
`W.panel` (title row with Close, scrolling body) or put the body in a ScrollContainer and Close at the top; fold the
long help into a "Controls" section.

**PLANT2-2 (R2; Block) Android Back leaves the app; Esc on the map opens Settings.** Where: `project.godot` (no
`application/config/quit_on_go_back`), `ui/autosave.gd:971-975`, `app/main.gd:644-650`. What: on Android, Back with a
panel open saves the run and quits (Godot's default) instead of closing the panel; on the map, Esc opens Settings over
it and B does nothing. Evidence: code; README "Saved runs" ("at once when … Back is pressed"). Not seen on a phone.
SMALL: set `quit_on_go_back` false, on `NOTIFICATION_WM_GO_BACK_REQUEST` call the same close-the-top-layer path as Esc
(map included) and quit only when nothing is open; add the map to `close_top()`.

**PLANT2-3 (S1; Block) Control room screen text under the floor on desktops too.** Where: `ui/mimic.gd` (`_text`
calls at 11-15 px, `fit()` zoom ≥ 0.9 on desktops, ≥ 1.44 on phones). What: codes 13 px → 11.7 px on a desktop and
8.6 dp on a phone; trend axis 11 px → 9.9 px and 7.2 dp; equipment names 14-15 px → 12.6-13.5 px. Evidence:
`desk_15_screens_overview.png`. SMALL to raise the minimum sizes to 15 (desktop at 0.9 = 13.5 px), LARGE to reach 14 dp
on a phone (the layout's cells are sized for today's text: `CELL_W` 248).

**PLANT2-4 (K1; Block) More red text under 4.5:1.** Where and evidence: correction 6 (mimic TRIP 4.1:1, blinking
priority digit 2.9:1, HUD Alarms button red tint 3.5:1, monitoring zone D 3.8:1). SMALL: one lighter red for text on
dark (as `BAD_COLOUR`, 5.4:1) and a darker one on the light screens (TRIP on the cell ≥ 4.5:1, e.g. (0.7, 0.05, 0.05));
tint the HUD button's background or add a badge rather than modulating its text.

**PLANT2-5 (K2; Block, phone) KKS codes on the screens at 6.1:1.** Where: `mimic.gd:1100,1122` (`INK_DIM` on `CELL`).
SMALL: draw codes in `INK` or darken `INK_DIM` to about (0.25, 0.26, 0.28).

**PLANT2-6 (K3; Block) Check boxes invisible when off.** Where: Settings (`hud.gd:186-189` and the toggles from
`plant_ui.gd:441`), procedure panel "Pause when a step is done". What: Godot's default unchecked icon on Plant's dark
panels, about 1.1:1. Evidence: pixels of `desk_02_settings.png` (486-504, 626-642). SMALL: theme `checked` and
`unchecked` icons in `widgets.gd` (a light outline ≥ 3:1), or use CheckButton toggles with a themed track.

**PLANT2-7 (T2; Block, phone) Destructive buttons 4.9 dp from their neighbours.** Where: correction 10. SMALL: a
spacer of at least 18 canvas px (8 dp) before and after destructive buttons (a `W.danger_button` that adds it).

**PLANT2-8 (T5, A1; Block) Map, drawings and work view need gestures.** Where: `app/map_view.gd:88-122`,
`ui/drawing_view.gd:71-90`, `ui/work_view.gd:840`. What: map zoom and rotate (and "go there") only by wheel, drag,
pinch or two-finger turn; drawings zoom and pan on touch only by pinch and drag; work view zoom only by the magnify
gesture. Evidence: code; README "Controls" (Map line). SMALL: + / − and rotate buttons on the map (and keys: + − Q E,
gamepad triggers and shoulders), + / − on the drawings bar, as the screens have.

**PLANT2-9 (A4; Block) "Go there" flies the camera even with Reduced motion.** Where: `ui/plant_ui.gd:1300-1335`.
SMALL: with `bindings.reduced_motion`, place the trainee at once (or fade) instead of the tween.

**PLANT2-10 (A5, A2; Block, desktop) Canvas-drawn items and fields have no accessible names.** Where:
`ui/mimic.gd` (items selected with arrows and Enter), `ui/drawing_view.gd`, `ui/trends.gd`, `ui/session_panel.gd:122-149`.
What: nothing in Plant sets `accessibility_name` or any other AccessKit property; the screens' selected item, a sheet's
tags and the session fields reach a screen reader only as a canvas or a bare value. Evidence: grep (no
`accessibility_` in `ui/`, `app/`, `workshop/`); `desk_14_session.json`. LARGE for the canvases (an accessible element per
selected item, or a live line naming it, ties in with PLANT-7), SMALL for the fields (`accessibility_name` "Your name",
"Session code", "Host's address"; visible labels for the last two).

**PLANT2-11 (A3; Block, desktop) A sheet's tags are not reachable as a list.** Where: `ui/drawing_view.gd`. What: only
by panning a tag under the centre and pressing Enter. LARGE (a tag list per sheet, opening the same card).

**PLANT2-12 (K5; needs the user's decision) Outlined HUD text instead of a panel.** Where: correction 9. Either a
policy waiver for outlined text, or SMALL: a translucent backing behind the status and time lines.

## 3. Counts

- Corrections: 20 on the desktop/phone-layout table (11 Pass or N/A/Not checked → Fail, 5 existing fails widened,
  1 size estimate, 1 Not checked → Pass from code, 1 warning on a Pass, 1 rule-wording question) and 2 on the Android
  table.
- New findings: 12 (PLANT2-1 to PLANT2-12), 11 of them on Block rules.
- Not re-checked here: anything that needs Plant running (A5 tree of the panels, focus order, P1, P3, F1/F2 by trial).
