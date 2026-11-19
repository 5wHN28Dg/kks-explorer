# UX profile: Walkdown Plant

Stage: **pre-release** (proposed; the owner confirms: GitHub releases `plant-v…` reach testers, no one relies on it
yet) · Profile version 1 · Reviewed: 2026-11-19, both passes on the PR that added it (1.7).

The rulebook is [docs/ui-policy/UI-UX-POLICY.md](../ui-policy/UI-UX-POLICY.md) (version 4.13); project rules and the
user's carried-over decisions are in [docs/UI-UX-POLICY.md](../UI-UX-POLICY.md). Section numbers are the rulebook's.
Plant's plant is generic and invented. Lines marked *(assumption)* are checked first by the first round with users.

## Purpose (and what it must never do)

A walkable 3D combined-cycle plant where trainees learn to find, operate and maintain equipment, follow procedures,
answer alarms and work under permits, alone or with colleagues, before doing it in a real plant.

It must never teach a wrong procedure or a wrong cause and effect as right, and never claim to replace a plant's own
controlled procedures (TRAIN4).

## Product kinds (7.9)

Training and courses (TRAIN1–4). Godot game module (7.5) with shared sessions (GM10). Field tools' FIELD1 (report a
problem) applies, as to every product with users besides the owner.

## Core objects and verbs

- **Objects:** the plant (areas, floors), equipment (with its card), alarm, procedure or tour (with steps), permit and
  lock, work order, the control room screens, a drawing, a manual, a machine in the Workshop, a run (the saved state),
  a session (with players and roles), the debrief.
- **Verbs:** walk or fly to, look at, open (a card, a screen), operate (a valve, a pump, a breaker), acknowledge,
  follow (a procedure), lock and isolate, take apart and put back, run (on the bench), host and join, pause, save and
  continue, review (the debrief).

## Experience intent and reference products

- **A scenario:** calm, realistic, learnable; consequences feel like the real plant's, nothing is gamified.
  Reference: a well-regarded plant or flight training simulator's normal mode *(assumption: none named yet; the owner
  confirms)*.
- **Walking the plant:** natural and unhurried on every input. Reference: a well-regarded first-person exploration
  game's movement *(assumption)*.
- **The Workshop:** hands-on, curious, clear. Reference: a good exploded-view viewer *(assumption)*.
- **Menus and panels:** quiet and readable, never in the way of the world.

## Core interactions (with feel specs, V14)

| Interaction | Response | Feedback | Success | Failure | Reference |
|---|---|---|---|---|---|
| Walking and looking | input read to frame shown ≤ 3 frames at 30 fps (GM6.2) | footsteps; head bob only if on (GM8.1) | moving where meant at the chosen pace | blocked by a wall: stops, no shake | the reference game's movement *(assumption)* |
| Operating a valve or a breaker (from the card or by Use) | the control shows pressed within 100 ms; the model's change within one model step | the part moves; its sound (with a visual cue, A13); the card's value changes | the step's operation ticks in the procedure | refused with a sentence that says why, where the eye is (GM3.2, #421) | the reference simulator *(assumption)* |
| Acknowledging an alarm | within 100 ms | the row stops flashing; the horn stops | the count drops | — | a real DCS alarm list *(assumption)* |

## Users

| Who | Knows | How often, why | Fears | Evidence |
|---|---|---|---|---|
| Trainee (new operator or I&C technician) | some theory; the plant little; games varies | sessions of 20–60 min while training *(assumption)* | getting it wrong in front of the instructor; getting lost | assumption |
| Instructor (an experienced colleague) | the plant and procedures | runs sessions, injects faults, reads the debrief | a trainee learning a wrong habit | assumption |
| The owner | everything | building and testing | — | own use |

- **Where and how:** at a desk (laptop, keyboard and mouse or a gamepad) or on a phone (two touch sticks), in a
  training room or at home; sessions of 20–60 minutes; interruptions (phone calls) are pauses.
- **Abilities (floor, 1.1):** the floor in full; no group is N/A. Play without sight is the hardest case in a 3D
  world: GM9 applies; the first full audit records what it can and can't give.
- **Age:** adults; not aimed at children (T9: N/A below).
- **Languages:** English UI only (the user, 2026-09-30); no user content beyond player names in sessions (Arabic and
  mixed names: L2).

## Platforms, sizes, inputs, assistive technology, network

| Platform | Versions | Oldest / smallest device | Typical device | First-class inputs |
|---|---|---|---|---|
| Android | 10 and later, arm64 only | Samsung Galaxy Note 9 (Android 10, Mali-G72, 2220 × 1080 at density 420): the frame rules are measured there | the Note 9 and the owner's Honor 600 (Plant only on the Honor) | touch (two sticks), gamepad |
| Windows | 10 and 11 | the owner's Windows 10 laptop (Intel HD 4400, 4 GB): runs only the Compatibility renderer at about 12 fps (#432); Plant's stated minimum GPU comes with the PR for #432 and is added here then | the owner's laptop *(assumption)* | keyboard and mouse, gamepad |
| Linux (Flatpak) | a current GNOME LTS, Godot BaseApp 4.7 | — (the same minimum as Windows, from #432) | the owner's laptop | keyboard and mouse, gamepad |

- **Sizes:** landscape only (the two-stick controls need it: AND4's orientation is essential); the canvas is
  1600 × 900, stretched; desktops from 1280 × 720 *(assumption)*; phones from 360 dp tall.
- **UI size (the user, 2026-11-15 and 2026-11-18):** 100 % to 200 % on every device; each phone starts at the least
  size that gives its buttons 48 dp and its text 14 sp on its own screen (`ui/widgets.gd` `phone_ui_size`: 150 % on
  the Note 9); desktops start at 100 %. It is Plant's text-size setting (A4, GM4.2).
- **Units:** dp = screen px × 160 / density (`adb shell wm density`); on the Note 9 at 100 %, one canvas px is
  0.457 dp. A3's game sizes use the physical density (`xdpi`).
- **Assistive technology (floor, 1.2):** Godot's AccessKit on desktops (Orca on GNOME, Narrator on Windows; recheck at
  each engine upgrade); Plant's own UI size, reduced motion and colour settings, since the engine can't follow the
  system's. Android: Godot has no screen-reader support there yet; recorded as a known gap (A8) in the accessibility
  statement (#440), rechecked at each engine upgrade.
- **Network:** offline single play; LAN sessions; sessions over the internet through Plant's relay.

## Main tasks

Targets set 2026-11-19 *(assumptions until a round with users)*.

| # | Task (users' words) | Who | How often | Done means | Targets |
|---|---|---|---|---|---|
| 1 | "Install it and start walking" | trainee | once | from the release page, through the install warnings (#439), to walking in the plant | first walkable frame ≤ 15 s on the Note 9 (cool start); playing within 60 s of the first input (H1) |
| 2 | "Go to the feed pump and see its state" | trainee | every session | the equipment's card is open | the map or a tour gets there; feels unhurried, never lost |
| 3 | "Start the pump as the procedure says" | trainee | every session | the procedure's steps ticked, the plant in the expected state | most trainees finish the first procedure without help *(target share set with the first round)* |
| 4 | "Answer the alarm" (control room screens) | trainee | most sessions | the alarm acknowledged and its cause dealt with | — |
| 5 | "Isolate it and lock it" (permits) | trainee | some sessions | the permit's steps done; a lock that would trip something asks first | — |
| 6 | "Take the transmitter apart; run it on the bench" (Workshop) | trainee | some sessions | parts named, put back; the bench run | — |
| 7 | "Train together" (host or join a session, take a role) | trainee, instructor | some sessions | everyone in, roles taken; a dropped player rejoins | joining ≤ 1 min |
| 8 | "Inject a fault; restart in a scenario" (instructor) | instructor | some sessions | the fault applied; the restart asked first (#437) | — |
| 9 | "What did I do wrong?" (debrief) | trainee | after each scenario | the steps beside the right ones (TRAIN2) | — |
| 10 | "Carry on tomorrow" / "start again" (the saved run) | trainee | every session | the run continues, or a new one starts and the old one is kept | progress lost on a crash ≤ one scenario step or 5 minutes (GM5.2) |
| 11 | "Make it fit me" (UI size, controls, pace, quality, motion) | anyone | once | the setting applied and kept | — |
| 12 | "Report a problem" | anyone | rare | a prefilled public issue after seeing the redacted diagnostics, or a private report (FIELD1) | — |

## Screen table

There is no `screens` group yet (1.4 asks for one; added with the coverage test in phase 2). The shared panel
template is `W.panel(title, on_close)` in `ui/widgets.gd`: one row covers all panels built from it.

| Screen or group | Job (tasks) | Visible at the smallest size | Primary action | Input per method | Intent order |
|---|---|---|---|---|---|
| The walk layer: HUD and top bar (clock, Alarms, Procedures, Permits, Crew, Tools, Control room, Drawings, Together, Instructor, Pause, speeds; More on phones) | 2–5 | the world; the touch sticks (phones); the clock; Alarms with its count; More | — (the world is the content) | touch: sticks and buttons; gamepad: sticks and the bound buttons; keyboard and mouse: WASD and mouse, the shortcut keys (README "Controls") | 1. the world; 2. alarms waiting; 3. the clock and the current step |
| Side panels from `W.panel` (Alarms, Procedures and tours, Permits, Crew, Instructor, Work orders, Stores, Debrief, Together, Tools, the equipment card) | 2–9 | the title, Close, the first rows, the panel's main action | per panel: Acknowledge, Next step, the permit's next action, Take me there, Start or Join | tap, click, gamepad focus and A, keyboard focus and Enter; Escape, B and Back close it (GM4.5) | 1. what needs doing now; 2. the main action; 3. the rest |
| Close-up views (work view, condition monitoring, thermal picture) | 3, 6 | the close-up, its few actions, Close | Record the reading | as panels | 1. the equipment up close; 2. the action |
| Full-screen viewers: control room screens, P&ID drawings, the manual reader | 3, 4 | the screen's content, its tabs, Close | operating on the screen; acknowledging | tap or click on the screen's objects; gamepad and keyboard focus | 1. the process picture and alarms; 2. tabs; 3. Close |
| The Workshop (top bar, parts tree, Info, Tools, the bench's run panel, the step line) | 6 | Back to the plant, the machine, the parts tree or Info (one at a time on phones), the step line | the take-apart slider / Run | as panels; drag to orbit with tap and key alternatives (A20) | 1. the machine; 2. the selected part's name; 3. the tools |
| Map | 2 | the plant overview, Close | go to a floor | tap a floor; gamepad and keys per README | 1. where I am; 2. where to go |
| Settings and About | 11 | UI size, Close | — | as panels | 1. UI size; 2. controls; 3. the rest |
| Start-up offer ("Continue the saved run?") | 10 | the question, Continue, New run | Continue | as panels | 1. the question; 2. Continue |

## Budgets (with tolerance) and the benchmark walk

- **Frames (GM6.1), the Note 9, normal play, from Android's present times:** at least 99.9 % of frames at 30 fps or
  better outside the Workshop (the old policy's P1, decision 0041), and no frame over 100 ms after the first 5 s
  (`docs/plant3d/MILESTONES.md`); fast-forward's frames are not judged (the user, 2026-10-27). **Inside the
  Workshop:** no frame over 100 ms that the app causes, and at least 95 % at 30 fps over the Workshop walk (the user,
  2026-11-15, #392; `docs/plant3d/WORKSHOP.md` §8).
- **Desktop frames:** the floor follows Plant's stated minimum GPU from #432 *(open)*.
- **Input latency (GM6.2):** ≤ 3 frames at 30 fps *(default; not measured yet)*.
- **Start (P3, GM6.3):** first walkable frame ≤ 15 s on the Note 9 from a cool start (every first start ≤ 13.5 s,
  decision 0060's margin); the load shows progress and something useful. P3's 5 s to an interactive screen or a
  skippable splash: *not measured yet (phase 2)*.
- **Memory:** peak PSS ≤ 1.5 GB on the Note 9.
- **Size:** APK ≤ 250 MB (the user, 2026-11-01); MSIX packages and the Flatpak bundle ≤ 300 MB (the user,
  2026-10-23); `tools/plant_release.py` refuses more.
- **Tolerance:** 5 % or the walk's noise; frame shares are judged per walk as MILESTONES.md says.
- **The benchmark walk:** `apps/plant3d/phone/frames.sh` on the Note 9 from a cool start (the 10-minute frames walk and its
  `crews` and `gate` variants: apps/plant3d/README.md), plus the Workshop walk; on the desktop, the bench under
  `tools/plant3d/bench/offscreen.sh`.

## Real-data evaluations

None: the plant is invented. Content is checked by TRAIN1 and TRAIN4 instead (procedures follow the textbooks and
standards their sources name).

## Declarations (1.5)

- **Realistic training.** Relaxes GM2.1's skips and invincibility inside assessed scenarios. Fallback: practice modes
  with hints and assists exist for every scenario, and the assessed mode says what it doesn't allow and why. Plant
  has no assessed mode yet, so today nothing is relaxed; the declaration is recorded so that one can be added with its
  fallback.

## Modules

GM (7.5) including GM10; AND (7.3) where it applies to a Godot app (back, insets, permissions); WIN (7.4) and GNOME
(7.2) only through the engine (no native widgets); the TRAIN kind.

## Design system

- Godot's `Control` nodes with the layer's theme from `ui/widgets.gd` (`W.make_theme()`, `W.button`, `W.label`,
  `W.panel`, `W.PRIO_COLOURS`, `W.BAD_COLOUR`, the UI size scale): the tokens live there; a literal colour or size in
  a panel is a V3 fail unless listed there with a reason. A destructive button style is still missing (#437).
- The user's choices: the UI size behaviour above; one compact top row on phones with More; a translucent backing
  panel for HUD text over the 3D view (#412).
- **Voice:** plain operator's English; the plant's own words for its equipment; no jokes about failure.
- **Glossary:** KKS code, P&ID, procedure, step, tour, permit to work, lock, isolation, work order, alarm priority,
  acknowledge, scenario, run, session, role, debrief, the Workshop. *(Definitions to be written with the first full
  audit; the words are already used consistently in the README's "Controls" and docs/PLANT3D.md.)*

## Evidence tools and synthetic data

- **Tools:** `tools/ui_audit/plant_audit.gd` and `plant_analyze.py` (every panel's controls, fonts, colours, rects;
  `--phone`); `plant_a5.py` (the AT-SPI tree under the headless GNOME session); `apps/plant3d/tests/` (`ui_shots.gd`,
  `mimic_shots.gd --phone`, `manual_shots.gd`, the `test_ui_*.gd`, `test_inputs.gd`, `test_gamepad_switch.gd`);
  `tools/plant3d/bench/offscreen.sh` (never the desktop); `apps/plant3d/phone/frames.sh` on the Note 9 within the owner's phone
  window. The Plant evidence runs must stop using the real Godot user folder (#438).
- **Synthetic data:** the invented plant itself; made-up player names, Arabic and mixed included.
- **Evidence store:** as Walkdown's (PR comments, `docs/ui-audit/`).

## Applicability list (N/A per platform, with reasons)

| Rule | Platforms | Reason |
|---|---|---|
| WEB, TUI, CLI, MSG, READER, SHARE, ALERT, FILTER, VIEW, HAND1 | all | none of these surfaces (the command-line options are developer tools) |
| FIELD2 | all | not a field tool (FIELD1 applies) |
| A15 | all | no prerecorded video |
| A12 for walking the 3D world | — | not N/A: GM9 decides what play without sight gives; recorded at the first full audit |
| AND4's orientation | Android | landscape only is essential to the two touch sticks (WCAG 1.3.4) |
| A8 and GM7.3 on Android | Android | not N/A: a known gap while Godot has no Android screen-reader support (A8 lets the profile record it; #440) |
| T9 | all | not aimed at children; no tracking, no ads; sessions only with people who share a join code |
| T13 | all | it republishes nothing |
| L1's other languages, L6 | all | English UI only |
| S8 | all | it changes no live system |

## Accepted Not-checked reasons (9.3)

| Reason | Covers | Expires |
|---|---|---|
| The Note 9's frame walk outside the owner's phone window: the change's walk waits for the window; the desktop's probe stands in meanwhile | GM6.1, GM6.2, P1 on the phone | 2027-05-19 |
| Plant's arm64 build doesn't run on the x86-64 emulator: the phone layout on the desktop (`--phone`) stands in until a phone session | phone-only checks of A19, A3, GM1.5 | 2027-05-19 |

## Third-party surfaces

Godot's built-in popups (an OptionButton's list, `PopupMenu`), the system's on-screen keyboard, the gamepad's own OS
mapping, the OS's install and permission dialogs. Rechecked at each Godot upgrade.

## Review brief

[review-brief.md](review-brief.md), version 1.

## Waivers

None.

## T0 and owner items

T0's checklist is the owner's (#442); places: GitHub releases (APK, MSIX, Flatpak bundle) and Plant's relay. The owner
items for both products are listed in #442.
