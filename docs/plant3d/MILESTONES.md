# Walkdown Plant: milestones for the staff, the water treatment plant and the camp

**Status: DRAFT 2026-10-22.** Specs: docs/PLANT3D.md (format 2, §14–§19), STAFF.md, WATER-TREATMENT.md, SITE.md.
Decisions 0062–0066.

Every milestone ends **shippable**: a plant release could be made from it (0054's release gates: every CI run green,
tried on the Note 9 first). Every milestone that changes what is drawn or run is measured on the Note 9 against the
frame rules (≥ 95 % of frames shown at ≥ 30 fps in the 10-minute walk, none over 100 ms after the first 5 s that the
app causes, peak PSS ≤ 1.5 GB, first walkable frame ≤ 15 s, and 0060's margin of ≤ 13.5 s per first start) and the 1.2× regression rule,
with the walk extended into the milestone's new areas or crowds. **Frames the app causes** (the user, 2026-10-25): a frame
inside the kernel's memory reclaim is excluded, and its evidence is kept. "Inside" means a `phone/frames.sh SAMPLE=1`
sample (every 0.2–0.3 s) overlapping the frame shows kswapd or direct reclaim scanning at least one page, or a
direct-reclaim stall. A walk without `SAMPLE=1` excludes nothing. A walk that would pass only by excluding frames is
walked again if it was a `STRESS=1` walk or had reclaim in more than 1 % of its samples. `tools/plant3d/bench/reclaim_frames.py` writes the judgement to the walk's
`rule.txt` (decisions 0057 and 0066). A milestone that misses them is not done; cutting scope to meet them is the user's call ("When to stop and ask the user", below).

Sizes: **S** one pull request; **M** two to four; **L** five to eight.

| # | Milestone | Size | Needs | Ships |
|---|---|---|---|---|
| P1 | **Permits and isolations in the model** (PLANT3D.md §15, `hold`): the reference, the vectors' `steps` for them, the GDScript engine bit for bit; works and isolations for the first train (the CW pumps, the CCW pumps, the condenser pressure transmitters, a cooling tower fan); the permit form; the trainee runs the whole permit as several roles in turn, from free mode (no NPCs yet) | M | — | a trainee locks out CW pump B and sees the start refused and the auto-start skipped; an isolated transmitter on the screen |
| W1 | **WTP, walkable** (SITE.md `wtp`, `intake`): the new kit parts, the areas, the raw water main, signs, the lightmap pack; the walking test and the Note 9 walk through it | L | — | the WTP to walk through, tour `wtp_path` |
| W2 | **WTP, operable** (WATER-TREATMENT.md §5–§7): its model, screens and local panel (screens.json `desks`), alarms, procedures `wtp_start`, `filter_backwash`, `ro_stop_flush`, faults; the ties to the train (§8) and the train's vectors made again | L | W1 | the WTP started from cold by procedure; the train's makeup depends on it |
| W3 | **WTP, maintenance procedures**: `ro_cip`, `mb_regeneration`, the remaining faults and the scenarios `wtp_normal`, `wtp_flood` | M | W2 | the WTP's day work, without people |
| S1 | **Staff engine** (PLANT3D.md §16–§17): staff.json and its validator, the reference step 9, random streams, the walking network with its `next` table (made by the content tools), the `steps` and `day` vectors, the GDScript engine bit for bit and its cost on the Note 9 (≤ 0.3 ms a step); places and ways made by the content tools, the build's check of every way against the navigation mesh; the operators' crews only; people shown as dots on the map and in the radio log; role selection, task list, radio panel | L | P1 | a shift with the trainee as CCR operator or field operator, NPC colleagues on the map and the radio, their rounds and calls |
| A1 | **Avatars** (0063, 0064): the CC0 body exports, our work clothes and PPE props, the CC0 animations retargeted, the posed band's meshes made by the build; the measurement of PLANT3D.md §18.4 on the Note 9 with the walk among 6, 12 and 24 people, which fixes the tier counts | L | S1 | the operators and the people of S1 visible in the control room and the field |
| S2 | **Maintenance and safety**: the maintenance disciplines and their supervisors, works for the first train's faults, calibrations, preventive jobs, the full permit flow between NPCs and the trainee, PPE and zones, the HSE officer's walks and unsafe acts, contractors | L | A1 | the trainee as technician, supervisor or HSE officer; jobs that change the plant |
| S3 | **WTP staff**: the WTP operator and chemists, the WTP's jobs (cartridge change, calibrations), samples and the lab | M | W3, S2 | the WTP worked by its people |
| C1 | **Site and camp, walkable** (SITE.md): `admin`, `gate`, `road_west`, `camp` with the interiors loaded near their doors, vehicles' kit parts, the planting of SITE.md §4, the walking test over it all. **The first train's site** (it has no planting today) gains: a tamarisk windbreak along the boundary wall's north and west sides (dust and wind from the shamal), date palms shading the walkway from the plant gate to the control building and the admin parking, low drought-tolerant shrubs by the control building's door; nothing inside the process areas | L | — (A1 for people in it) | the camp and the gate to walk through |
| S4 | **The full day**: off-duty routines in the camp, buses, meals, the jump to the next shift, managers and meetings, drivers and guards, the whole roster; the debrief per role; the `day` vector over the full content; the Note 9 walk at the busiest hour (the shift change at the plant gate) | L | S2, S3, C1 | every role of STAFF.md to play through a day |

**P1 as built (2026-10-22):** the reference and the GDScript engine bit for bit on `plant3d-v2.json` (PLANT3D.md §19);
eight works on the first train (CW pumps A–C, CCW pumps A and B, condenser pressure transmitters 2 and 3, cooling
tower fan 3); the permit form (the bar's Permits, T, a card's permit button, the procedures panel), padlocks and
permit numbers on the screens and cards, the debrief's Permits tab, saved runs with permits open. The first train's CW
pumps have no standby auto-start (format 1's behaviour, unchanged): the auto-start skipped by a lock is shown on the CCW
pumps. Locks are not yet drawn in the field (chains, padlocks and tags on the parts: with the kit work of S2).

**W2 as built (2026-10-23):** the WTP's model (WATER-TREATMENT.md §8b) with 11 sequences (six filters' backwash, two
RO trains, two mixed beds, the coagulant tank's fill), 18 trips in five first-out groups, 8 interlocks and 44 alarms;
its six screens on its own desk (screens.json `desks`, PLANT3D §14), its overview also on the main control room's;
the procedures `wtp_start`, `filter_backwash` and `ro_stop_flush`; 20 faults; the ties to the first train (makeup and
the plant's demin tank, its low alarm on the train's screens). The vectors: `plant3d-v2.json` gains `wtp` (the start
from cold and 26 forks), the train's tie forks and the `desks` rejects; format 1's `train` and `hot` keep every input,
event and value they had (the WTP's values added; W1's two placeholder constants `wtp_in_service` and
`intake_in_service` removed). Not yet: the WTP's local panel apart from its desk, CIP, the mixed
beds' regeneration and the scenarios `wtp_normal` and `wtp_flood` (W3).

**S1 as built (2026-10-23):** the reference (`ref/plant3d_staff.py`) and the GDScript engine (`sim/staff.gd`) bit
for bit on `plant3d-v2.json`'s `staff` (a synthetic plant: rejects and seven runs) and `day` (the first train's day
shift with seed 1, and four runs with a trainee or a fault); what S1 settles and what waits for S2 and S4 is PLANT3D.md
§17.8. The first train's staff (`tools/plant3d/train_staff.py`): four crews of a shift supervisor, two control room
operators, three field operators (each with their round: GT and HRSG, ST and auxiliaries, CW and cooling tower) and
an electrical authorised person; two mechanical, one electrical and one I&C technician on days (they take the
operators' permits; their own jobs and play come with S2); places and ways measured on the navigation mesh
(`tests/staff_layout.gd`) and checked against it by the build (`tests/test_staff_ways.gd`). The scenario
`shift_cold`; the Crew panel (role, tasks, readings sheet, radio, sleep to the next shift); people as capsules and map
dots. Step cost on the laptop: 17 µs mean, 56 µs at the shift change (an estimated 0.18 ms on the Note 9: not
measured on the phone yet, and so the Note 9 walk of the frame rules is not run for S1, which draws only capsules).

**W3 as built (2026-10-23):** the RO's cleaning in place with its skid (tank, heater, pump), a mixed bed's
regeneration, the neutralisation pit's batch, eight more faults (with a chlorine damage only new membranes repair and a
resin leak repaired under a permit), the scenarios `wtp_normal` and `wtp_flood`, the procedures `ro_cip` and
`mb_regeneration` (WATER-TREATMENT.md §8c); `plant3d-v2.json` gains the runs `wtp_cip` and `wtp_regen` with their forks
and the WTP's fault forks. A `screens:` link opens its screen at a desk that has it (the WTP's own for its screens).
The CIP skid and the pit's dosing skids are new drawing (five small parts); not yet walked on the Note 9.

**W1 and C1 done (2026-10-25, #258):** on the merged code (W2, W3, P1b, S1, A1) with far views for the train,
the WTP and the intake, occluders on every building and buildings' insides drawn only near them. The last frames over
100 ms that #249 left came from the phone's memory reclaim (0066, "The last frame spikes"). By the rule as the user
decided it (frames the app causes, above), every `wtp` and `camp` walk of the final and the merged builds passes:
- 6 walks with no frame over 100 ms at all, and 1 frame excluded as reclaim in the merged `camp` walk;
- 97.09–99.66 % of frames at ≥ 30 fps;
- peak PSS at most 1.15 GB, 1,084 MB on the merged `wtp` walk with the staging buffers capped at 16 MB (0066, "The
  app's memory");
- first walkable frame 11.1–11.9 s;
- the APK at 142.0 MB.

**S2 as built (2026-10-25):** zones, PPE, unsafe acts, the safety walk and stopping work in the reference and the
GDScript engine bit for bit (PLANT3D.md §17.11, with what §16–§17 left open settled there), and slots by weekday;
an unlocking task goes first to the lock's owner. The first train's staff gains the maintenance disciplines at
STAFF.md §1's numbers, three maintenance supervisors (their week's list of preventive works and calibrations; the
mechanical one hosts the contractors), two HSE officers (toolbox talk, safety walks, stopping what they see), a
contractors' supervisor and eight contractors on two works without isolation, a locker room and zones over the
process areas; the corrective works gain the CW discharge valves' limit switches (I&C), and the condenser pressure
transmitters' calibration puts a drift right. Every role but the guards' plays. The vectors: `plant3d-v2.json`'s
`staff` gains the safety staff's runs and rejects, `day` follows the S2 content (seed 8: two contractors' shortcuts
found and stopped) with five more forks; format 1's `train` and `hot` keep every input and event (the new values
added). The app: the Crew panel's PPE part, zone inputs from the walker, "Stop the work" within reach, the people's
hard hats by what they wear and where, the debrief's Safety and Your tasks tabs (`tests/test_ui_maintenance.gd`
plays an I&C technician's calibration and corrective repair, an HSE officer's stop and an NPC calibration seen from
the control room). Tools and PPE on the avatars stay A1's looks by role; only the hard hat follows what is worn.
From the reviews: a resumed `work` step goes back to its place first (a calibration held overnight was finished
from the plant gate), the stop step waits for a trainee between places, nobody stops their own act, PPE is put on
before a held job and before the supervisors' handover, and the staff step is back within §18.4's budget (62 µs
at the shift change on the laptop, about 0.20 ms on the Note 9). A job held overnight keeps every lock on its
isolation, whoever placed it (the user, 2026-10-25: the technician who isolated for a colleague's job keeps theirs on
and removes it when the job resumes).

**S2 measured on the Note 9 (2026-10-26):** main at #259 (44c6f31), a release build with the bake, test-signed,
`lean+vis`, a first start each, `SAMPLE=1` and `probe=1`, every walk started at a battery of at most 30.0 °C. The APK
is 141.6 MB (budget 150). The evidence (`rule.txt`, `samp.txt`, the logs) is kept on this laptop, not in the repository.

| Walk (600 s) | Start | Frames at ≥ 30 fps | Frames over 100 ms: the app's / excluded as reclaim | Worst | Reclaim in the samples | Peak PSS | First walkable frame | Rule |
|---|---|---|---|---|---|---|---|---|
| `frames` | 25.4 °C | 98.67 % | 0 / 0 | 74.6 ms | 4.44 % | 1,084 MB | 12.3 s | passes |
| `frames` | 29.9 °C | 99.44 % | 0 / 0 | 65.8 ms | 0.79 % | 1,096 MB | 11.4 s | passes |
| `wtp` | 29.9 °C | 99.34 % | 0 / 0 | 77.6 ms | 2.69 % | 1,124 MB | 11.6 s | passes |
| `wtp` | 30.0 °C | 99.24 % | 0 / 0 | 80.6 ms | 1.26 % | 1,084 MB | 11.4 s | passes |
| `camp` | 29.8 °C | 99.50 % | 0 / 1 | 103.3 ms | 1.93 % | 1,107 MB | 11.5 s | not judged: walked again |
| `camp` | 29.9 °C | 99.65 % | 0 / 0 | 75.1 ms | 1.18 % | 1,101 MB | 11.7 s | passes |
| `camp` (again) | 29.8 °C | 99.62 % | 0 / 0 | 82.9 ms | 1.04 % | 1,109 MB | 11.5 s | passes |

The first `camp` walk's one frame over 100 ms (103.3 ms at 490 s, GPU 104 ms, near the plant gate on the way back,
where #258's excluded frame was too) fell inside the kernel's reclaim, but the walk had reclaim in 1.93 % of its
samples, so the rule does not judge it; the walk again passed with no frame over 100 ms. Six walks pass.

These three walks start in `cold_iron`, which has no staff: S2's people are not in them. The people were measured
with extra `frames` walks among 24 (`crowd=24`): the Note 9 draws at most 12 skinned (`skinned=12`, 12 posed, 11
posed draws) every time. Alone (A1's measurement again): 98.34 % at ≥ 30 fps (A1: 98.59–99.10 %), no frame over
100 ms, the people's CPU 1.20 ms a frame on average (4.47 ms at most; budget 2 ms), peak PSS 1,108 MB. With the crews
running too (`scenario=shift_cold`, `speed=fast`: five minutes of fast-forward, then normal speed, the Crew panel
open) two walks gave 95.06 % and 94.94 % at ≥ 30 fps, people's CPU 1.41 ms (at most 5.52 ms), model step 1.36–1.45
ms at normal speed (budget 2.1), no frame over 100 ms that the app caused (one walk not judged: 1.03 % reclaim, its
two frames of 100.0 and 101.3 ms both inside reclaim). The scripts there took 11.7 ms a frame in fast-forward and
5.3 ms after it, against 4.3 ms in the crowd alone: fast-forward's model, the staff's steps and the Crew panel together.
(Those walks' Crew panel was not open: `panels=crew` was not an option then; it is now.)

**The scripts' time with the staff (2026-10-26).** The `crews` walk (`crews=1`: S2's and S3's staff at work in free
mode, at normal speed) and `probe=1`'s `SCRIPTS` lines, which give each part's time in the scripts a frame. Then: the
model's work in a frame capped at 8 ms whatever the frame before (`ui/sim_clock.gd` `FRAME_MS`, cut within the frame
in fast-forward), the bar's alarms and clock once a step (4 times a second in fast-forward), the Crew panel's radio
lines written into fixed labels, the bindings' and the people's work once a step or when the eye has moved, the staff
step's loops without repeated field lookups; every vector unchanged. Note 9, lean+vis, release builds, cool starts
(≤ 30.0 °C), `SAMPLE=1`, two walks each (the stress walk: `scenario=shift_cold`, `speed=fast`, `crowd=24`):

| walk | before: ≥ 30 fps | after: ≥ 30 fps | scripts a frame, mean / worst (ms) |
|---|---|---|---|
| `crews` | 99.39 %, 97.21 % | 99.41 %, 97.86 % | 4.08–4.44 / 22 → 2.58–2.82 / 21 (the UI 1.4 → 0.2) |
| stress, fast-forward part | 93.01 %, 91.02 % (no Crew panel) | 94.41 % (no panel); 90.91 %, 94.59 % (Crew panel open) | 12.3–12.4 / 65–73 → 10.1–10.7 / 26–49 (model and staff at most 7.5 ms a frame, was 32 + 13) |
| `frames` (no staff) | | 98.70 % | |

No frame over 100 ms that the app caused, except one of 104.3 ms in the first stress walk with the Crew panel (in
normal speed, scripts 13 ms: the GPU; that walk had reclaim in 2.15 % of its samples, so it is walked again by the
rule: the second passed). The stress walk stays near 91–95 %: its frames over 33 ms are the GPU's (24 skinned and
posed people, the median GPU time 23–27 ms), not the scripts'. The first build of this work rebuilt the Crew panel for
each of the radio's first ten lines (up to 94 ms in a frame on the Note 9): the radio's lines are in fixed labels now.

**S3 as built (2026-10-26):** the water treatment plant worked by its people (PLANT3D.md §17.12): a WTP operator and
a shift chemist in each crew and two chemists on days, at STAFF.md §1's numbers; the WTP's places measured on the
navigation mesh (its control room with the WTP desk and lockers, the laboratory, the sample panel, the walk from the
train and to the intake) and its zones (yards, the hall's hearing protection, face shield and apron in the chemical
areas); the WTP operator's rounds and the chemists' samples and stock checks, each reading checked against the
model; the sequences run from the WTP's desk: a filter's backwash ordered by the shift supervisor, a mixed bed's
regeneration on the laboratory's silica finding, an RO train's cleaning in place, an RO trip's reset and flush, the regenerant
tanks' bulk delivery; the train's control room calling the WTP when its demineralised water runs low; the WTP's jobs
under permits (cartridge changes and the RO analysers' calibrations added to the model, a mixed bed's internals with
its gas test), the other stream put in service and the process points locked by the WTP operator. Two engine
additions, bit for bit in both engines: reactions limited to the alarms and trips of named areas, and reactions on a
finding (a reading out of its range). The scenario `shift_wtp`; the vectors' `staff.runs`, `reject` and `day` forks
(PLANT3D.md §19). `tests/test_ui_wtp_staff.gd` plays the WTP operator through a filter backwash ordered by the NPC
supervisor and the chemist logging a high silica result that the NPC operator acts on with a regeneration. Not built:
the chemical tanker's delivery under a permit (WATER-TREATMENT §9 leaves the unloading out, and vehicles are S4's).
The staff step (apps/plant3d/sim/tests/bench_step.gd, the laptop, back to back): 78 µs at the shift change with the
WTP's people against 62 µs on main before them (64 µs against 51 µs at the day workers' arrival), after S3's value
reactions were looked at alone on steps without events (a pass over every reaction each step had made it 100 µs);
by S2's ratio about 0.25 ms on the Note 9, within §18.4's 0.3 ms (not measured on the phone: the phone was in use
for another measurement, and S3 adds no drawing but ten people of A1's kind).

**Order** (two tracks that join): P1 → S1 → A1 → S2, with W1 → W2 → W3 and C1 alongside; S3 needs both tracks, S4
needs all. In time: P1 and W1 first (independent), then S1 with W2, A1 with W3, S2 with C1, then S3, then S4.

**Why this order keeps the rules:** the model and staff work (P1, S1, W2, W3) adds no drawing; each drawing milestone
(W1, A1, C1) adds one kind of load and is measured alone before the next adds another; S4, the busiest hour, comes
last, when the per-tier counts are known from A1.

**Multiplayer** (the user, 2026-10-26): its own milestones MP1–MP6 in docs/plant3d/MULTIPLAYER.md §13 (decisions
0067–0069). MP1 needs S3 (the engine's staff as built); it changes the engine (several trainees), so it goes before
S4 or alongside it with S4 rebased on it. **MP1 built 2026-10-26** (PLANT3D.md §17.13–§17.14, MULTIPLAYER.md §3.3, §4),
all but one check: the state digests on Android (the Note 9 ran only the digest's timing), MP2's first step
(MULTIPLAYER.md §12).

**MP2 built 2026-10-27** (LAN sessions; MULTIPLAYER.md §14): sessions of 2 to 8 players on one Wi-Fi, through
"Together" on the bar; the harness of headless players in CI's `multiplayer` job; the Note 9 ran every engine vector
with Linux's digests, joined the laptop's session on the Wi-Fi by its broadcast query, and played in one session with
the laptop and the Windows VM. Its measurements are in MULTIPLAYER.md §14. **Not done yet:** the frame rules' walk
with two players is still to be judged (the walk made had too much reclaim, and the phone did not cool for a second),
the session's memory is still to be measured, and the session layer's worst frame (2.57 ms) misses its 2 ms budget.

## When to stop and ask the user (the user, 2026-10-22)

- **If A1 measures fewer than 4 animated (skinned) people on the Note 9** within the frame rules: stop and ask before
  going on.
- **If the APK passes 150 MB** (W1, A1, C1 or later): stop and ask before going on (packs on demand, 0054 §6,
  would need a network permission). The desktop packages (MSIX, Flatpak) may grow to about 300 MB (the user,
  2026-10-23); stop and ask if one passes that. Compress wherever it costs nothing. `tools/plant_release.py` refuses
  a package over its budget.
- Decided already: animations from KayKit (CC0) first; CMU's motion capture allowed if they look too stiff, its
  notice in the About screen (0063). The camp as SITE.md describes it; planting by SITE.md §4.
