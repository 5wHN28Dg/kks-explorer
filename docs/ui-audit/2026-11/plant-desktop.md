# UI/UX audit 2026-11, pass 1 (blind): Walkdown Plant on the desktop

Auditor: desk. Policy: `docs/UI-UX-POLICY.md`. Code: main at 9eb5b09b. Godot 4.7.2 (`~/.local/kksdev/godot`).

## 1. What was run

- **Content:** not rebuilt. The main checkout's `apps/plant3d/built/` (built from 6f016e62 with local changes), its
  `.godot` import cache, `kit/tex/` and `voice/bin/` were copied into the audit checkout (all gitignored). Main changed
  `data/plant3d` model/workshop files since 6f016e62; panels and HUD code are main's. Generic Plant content only.
- **Walk** (`plant_audit.gd`, scratch; `tools/plant3d/bench/offscreen.sh godot --path apps/plant3d --script …`,
  memjob 6 via heavyslot): HUD, settings, About, map, card (30PAC10AP001) and the card scrolled to its end, alarms,
  procedures, a running procedure, instructor, permits, work orders, crew, drawings, session, control room screens,
  manual, debrief, a toast. Each: screenshot plus every visible `Control` (class, text, rect in canvas px, font size
  and colour, focus mode). Desktop: 1600 × 900 (canvas 1668 × 900). Phone layout: `ui_scale` 1.35 as
  `mimic_shots.gd --phone` sets it, window 2220 × 1043 (canvas 1915 × 900); dp = canvas px × 0.457 (policy §2).
- **A5:** Plant run in the GNOME headless session (`headless.sh`, Wayland driver) with `--accessibility always`, the
  a11y bus's `IsEnabled`/`ScreenReaderEnabled` set true, AT-SPI tree read with `atspi.walk`.
- **Code reading:** `ui/widgets.gd`, `app/hud.gd`, `ui/mimic.gd`, `ui/manual_view.gd`, `ui/alarm_panel.gd`,
  `ui/debrief_panel.gd`, `ui/wo_panel.gd`, `ui/trainer_panel.gd`, `ui/autosave.gd`, `ui/plant_ui.gd`; tests
  `test_gamepad_switch.gd`, `test_inputs.gd` (sim inputs, not keys), the UI tests that send `InputEventKey`/joypad.
- **Not run:** the Godot test suite itself (keyboard/gamepad coverage taken from the tests' code), the Note 9 frame walk
  (P1), Plant on Android, the Workshop, the map's gestures, A5 for panels (the card from `--panels=card:…` did not open
  in that start; only the HUD was in the tree).
- **Scripts** (scratch `~/kks-work/build/ui-audit/desk/`): `plant_audit.gd` (walk + Control dump), `plant_analyze.py`
  (targets in dp, font sizes, overlaps), `plant_a5.py` (A5 AT-SPI probe), `contrast.py`.

## 2. Results

Columns: **Desk** = Plant on a desktop at 1600 × 900; **Phone** = the phone layout rendered on the desktop (stands in
for Plant on Android, policy §4 limits).

| Rule | Desk | Phone | Note |
|---|---|---|---|
| T1 | N/A | **Fail** | PLANT-1: 104 enabled targets under 48 dp |
| T2 | Pass | **Fail** | no overlapping enabled targets on screen (the overlaps the dump lists are controls scrolled out or under the full-screen manual); phone: PLANT-3 card over the look stick |
| T3 | Pass | N/A | no enabled target under 24 px (smallest HUD 120 × 64, buttons 52 px high) |
| T4 | Advice: not checked | Advice: not checked | |
| T5 | Not checked | Not checked | screens: drag/pinch have −, +, Fit buttons and arrows (`mimic.gd:127`); map drag/rotate alternatives not checked |
| R1 | Pass | Pass | Close in each panel's title row outside its ScrollContainer (`widgets.gd:105-118`); card's Close at the same rect before and after scrolling to the end (`*_05_card`, `*_05b_card_scrolled`) |
| R2 | Pass | Pass | Esc / B / Start close the top panel (`plant_ui.gd:2167`, `about.gd:151`, `manual_view.gd:210`) |
| R3 | N/A | **Fail** | PLANT-3: card covers the right stick's area; settings panel runs off the bottom of the screen |
| R4 | N/A | N/A | no forms with Save |
| C1 | **Fail** | **Fail** | PLANT-4: no Copy button anywhere (no `clipboard_set` in ui/app/workshop); card codes, About's version and commit |
| C2 | N/A | N/A | nothing to copy |
| C3 | N/A | N/A | |
| B1 | Pass (partial) | Pass (partial) | alarms "Acknowledge all"; other repeated lists not checked |
| B2, B3 | Not checked | Not checked | |
| K1 | **Fail** | **Fail** | PLANT-5: manual's buttons 3.6:1; priority-1 red text 3.6:1 (debrief, work orders) |
| K2 | N/A | Pass | white on panel 14.5:1, DIM grey 7.9:1 (over a white sky) |
| K3 | Pass | Pass | focus ring (1, 0.75, 0.2) 6.9:1 on buttons, 8.8:1 on panels |
| K4 | Pass | Pass | alarm priority as a numbered badge; work-order priority in words; ✓/✗ with words on cards |
| K5 | Pass | Pass | panels 92 % opaque; HUD status and distance labels have a 6 px black outline (not a panel, but holds contrast over sky at noon and night) |
| K6 | N/A | N/A | Walkdown rule; Plant's panels checked under K1–K5 |
| K7 | Advice: N/A | Advice: N/A | Plant is dark by design |
| S1 | Pass | **Fail** | desktop smallest 16 px; phone PLANT-2: body 12.3 dp, settings 7.3 dp, HUD 9.1–10.1 dp |
| S2 | **Fail** | **Fail** | PLANT-6: no text size setting |
| S3 | Pass | Pass | codes in labels autowrap; mimic ellipsises names only (`mimic.gd:406`) |
| F1 | Not checked | Not checked | |
| F2 | Not checked | Not checked | |
| F3 | N/A | N/A | Plant runs offline by design |
| F4 | **Fail** | N/A (exempt) | PLANT-7: no live region; toasts are plain Labels |
| F5, F6 | Not checked | Not checked | |
| D1 | **Fail** | **Fail** | PLANT-8: instructor "Restart in it" and the start offer's "New run" drop the run without asking |
| D2 | Pass (where used) | Pass (where used) | permit lock warning (PLANT3D §15.6) not re-checked |
| D3 | Not checked | Not checked | |
| D4 | N/A | N/A | |
| X1 | Not checked | Not checked | |
| X2 | N/A | N/A | |
| X3 | Pass | Pass | every HUD action has a key and a gamepad button (README "Controls"; `test_gamepad_switch.gd` "focus") |
| A1 | Pass (tests) | N/A | keyboard and gamepad reach panels (`focus_top`, `test_gamepad_switch.gd`, UI tests with InputEventKey); HUD buttons themselves take no focus (`hud.gd:131`) but each has a key |
| A2 | Pass (HUD) | N/A | AT-SPI: 15 HUD buttons, 2 labels, frame "Walkdown Plant (DEBUG)", all named; the application node is named after the binary |
| A3 | N/A | N/A | |
| A4 | Pass | Pass | Settings "Reduced motion" (camera shake, head bob; `plant_ui.gd:441`); camera flights ("Show me") not checked |
| A5 | Pass (partial) | N/A | AccessKit exposes Controls with `--accessibility always`; panels not reached in this probe |
| L1 | N/A | N/A | no user text in Plant |
| L2 | Not checked | **Fail** | phone: settings panel clipped at the bottom (PLANT-2); at 150 % there is no setting to test (S2) |
| L3 | Pass | Pass | MW, %, bar, °C, kPa(a), m³/h, mm on the screens; "164 m" |
| L4 | Pass | Pass | model time h:mm:ss |
| L5 | Pass | Pass | "3 others met", "Trips (3)" |
| P1 | N/A | Not checked | needs the Note 9 window |
| P2 | N/A | N/A | Walkdown rule |
| P3 | Not checked | Not checked | |
| P4 | N/A | N/A | |
| Z1–Z3 | Pass | Pass | generic content only; About shows the build commit only |
| G1–G4 | N/A | N/A | Walkdown phone rules; Plant landscape by design |

## 3. Findings

**PLANT-1 (T1) Phone targets ~32 dp.** `W.button` is 52 × `scale` = 70 canvas px high = 32 dp
(`widgets.gd:72-77`); HUD Fly/Use/Map/Settings are 120 × 64 canvas px, not scaled (`hud.gd:127-131`) = 55 × 29 dp;
the bar's Alarms…Fast 35 dp high, "1×" 29 × 35 dp; panel Close 47 × 32–43 dp; settings OptionButtons and CheckBoxes
14 dp high; mimic tabs 44 × 1.35 px = 27 dp. 104 controls in 18 screens. Evidence:
`plant-PLANT-1-phone-card-targets.png`, `phone_*.json`. LARGE (target 105 canvas px at ui_scale 1.35 means a bigger
scale or a phone layout: design choice).

**PLANT-2 (S1, L2) Phone text sizes.** Default font 20 × 1.35 = 27 px = 12.3 dp (body under 14 sp); labels at 16–18
→ 9.9–11 dp; the settings panel and HUD are not scaled at all: 16 px = 7.3 dp, status 20 px = 9.1 dp, HUD buttons
22 px = 10.1 dp; About's commit line 8.2 dp; mimic names 14–15 px × readable zoom 1.6 = 10.2 dp (`mimic.gd:408,564`).
The settings panel also runs past the screen's bottom. Evidence: `plant-PLANT-2-phone-settings-unscaled.png`.
SMALL for scaling the settings panel and HUD by `W.scale`; LARGE for reaching 14 dp body text.

**PLANT-3 (R3, T2, phone) Card over the right stick.** With touch controls shown, the card (right side, to y 920 of
940) covers the look stick's 420 × 420 area at the bottom right (`hud.gd:61-67`), whose ring shows under the card;
the card's lower buttons sit where a thumb looks around. Evidence: `plant-PLANT-1-phone-card-targets.png`. LARGE
(layout: card above the stick area or sticks move aside).

**PLANT-4 (C1) No copy.** No Copy button on cards (KKS code, linked codes), About (version, commit) or permits; policy
asks a Copy button in Plant. SMALL per place (`DisplayServer.clipboard_set` + toast "Copied …").

**PLANT-5 (K1) Low-contrast text.** Manual reader's grey buttons (Close, section list, "Specifications →"): text
(220,220,219) on (114,113,110) = 3.6:1 (`plant-PLANT-5-manual-button-contrast.png`); priority-1 red
(0.95, 0.2, 0.15) used as text colour on the dark panel = 3.6:1 at 16–17 px (`debrief_panel.gd:230`,
`wo_panel.gd:384`). SMALL (darker button fill in the manual; a lighter red for text).

**PLANT-6 (S2) No text size setting.** Godot ignores the system text size and Settings has none (`hud.gd` settings,
`plant_ui.gd:441` toggles). LARGE.

**PLANT-7 (F4) No status announcements on desktop.** Toasts (`plant_ui.gd:1394`) and status lines are plain Labels; no
`accessibility_live` anywhere in `ui/`, `app/`. SMALL once A5 is in place (set the toast label's live region).

**PLANT-8 (D1) A run dropped without asking.** Instructor panel "Restart in it" calls `ui.restart(id)` at once
(`trainer_panel.gd:92`); the start offer's "New run" sits 8 px from "Continue" and replaces the saved run without a
question (`autosave.gd:816-818`). SMALL (confirmation naming what is lost).

## 4. Screenshots

In `shots/`: `plant-PLANT-1-phone-card-targets.png`, `plant-PLANT-2-phone-settings-unscaled.png`,
`plant-PLANT-5-manual-button-contrast.png`. All 76 shots and dumps (desk_*, phone_*) are in
`~/kks-work/build/ui-audit/desk/plant-out/`; the A5 tree in `plant-a5.json`.

Counts (rows): Desk Pass 20, Fail 5, N/A 18, Not checked 10 (1 Advice). Phone Pass 15, Fail 9, N/A 18, Not checked 10 (1 Advice).
