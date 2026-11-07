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
`rule.txt` (decisions 0057 and 0066). **Normal play only** (the user, 2026-10-27): the two frame-time rules (≥ 95 % at ≥ 30 fps, none over 100 ms) judge
the frames played at 1× (or paused); fast-forward may drop frames on phones. The app counts fast-forward's frames
apart (`app/walk_frames.gd`: the frame that starts or stops it counts as fast-forward's; its `FASTFORWARD` and
`SPIKE_FF` lines), and `phone/frames.sh` counts what the screen showed without them (`sf_frames.py --speeds`, from
the walk's `SPEED` lines on the phone's monotonic clock); both tools say in their output that they judged the frames
at 1×. Walks measured before this change judged every frame, fast-forward's included (the stress walks' fast-forward
parts below among them). **Clear weather** (the user, 2026-11-03): every measured walk (`walk=…`, `phone/frames.sh`), the view shots (`shot=…`, `phone/shots.sh`)
and the step bench (`step=bench`, `sim/tests/bench_realism.gd`) run in clear weather unless they name another
(`weather=KIND`, `--weather=KIND`), so that a scenario's season (free play's weather, REALISM.md §5.6) changes no
measurement; free play keeps its seasonal weather. A walk with `mp=` takes the host's weather. A milestone that misses the frame rules is not done; cutting scope to meet them is the user's call ("When to stop and ask the user", below).

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

**LIFTS** (the user, 2026-10-27; PLANT3D.md §20, decision 0071): a working rack-and-pinion service lift on HRSG 1 (call
stations, interlocked gates, a cab that carries the trainee and the NPCs; the staff ride it on long climbs) and working
hoists (the HRSG roof's monorail hoist, the turbine hall's crane in procedures). Size L, after S3 and MP1 (it adds
inputs to the engine), before S4. Its parts, one pull request each:
- **L1, the engine:** `lifts`, `board`/`alight`, lift ways and the ride in both engines, the vectors (**built 2026-10-30**, PLANT3D.md §20.10; the content tool's lift `tools/plant3d/lift_model.py`);
- **L2, the lift in the app:** the content (kit parts, the lift on HRSG 1, its model and screen), the cab, gates and
  controls, riding; measured on the Note 9 before and after (**built 2026-11-01**, PLANT3D.md §20.11);
- **L3, the staff on it:** staff.json's lift and ways, the riders drawn, the day made again (**built 2026-11-01**,
  PLANT3D.md §20.12);
- **L2 and L3 measured on the Note 9, 2026-11-01** (main with L2, L3 and L4 in it: these are L4's judged walks too). A
  release build without the lightmap, signed with the test key, as the baseline's; `frames` walk, `crews=1`,
  `probe=1`, 600 s, each from a battery at 29.3 to 30.0 °C, `SAMPLE=1`. With L2 and L3 as merged: the first walk saw
  reclaim in 1.75 % of its samples (not judged), the next two 0.14 and 0.66 %: frames median 26.2 and 27.2 ms, p95
  36.4 and 36.6 ms, frames over 34.2 ms 22.5 and 21.7 %, none over 100 ms (the rule passes), scripts 3.39 and 3.57 ms
  a frame (people view 1.08 and 1.16, bindings, the lift's view among them, 0.47 and 0.48), VRAM 159 MB, peak PSS 826
  and 833 MB. Over §20.8's 0.1 ms for the lift's and the hoists' scripts, so the lift's view now does nothing while
  still and the people view looks riders up once a step: measured again (reclaim 0.37 and 0.70 %, both judged),
  median 28.6 and 28.1 ms, p95 37.1 and 36.7 ms, over 34.2 ms 23.9 and 22.6 %, none over 100 ms (passes), scripts
  3.36 and 3.42 (people view 0.99 and 1.01, bindings 0.44 and 0.45), peak PSS 822 and 864 MB. The baseline before
  L4 (two runs, reclaim 0.09 %): median 20.7 and 23.6 ms, p95 36.5 and 36.3 ms, over 34.2 ms 23.5 and 21.5 %,
  scripts 3.09 and 3.19 (people view 0.87 and 0.91, bindings 0.32 and 0.33). The medians sit in the 30 fps band more
  often than the baseline's (the frames over 34.2 ms, p95 and the rule are unchanged); the lift's and the hoists'
  scripts together are about 0.1 ms in bindings and 0.1 ms in the people view. The `lift` walk (up HRSG 1's lift to the
  roof and down again, 2 min 22 s of model time, reclaim 0.00 %): median 28.4 ms, p95 36.4 ms, max 56 ms, the rule
  passes.
- **L4, hoists and the crane:** their content, the procedures, the view; measured on the Note 9. **Built
  2026-10-30, measured 2026-11-01** (PLANT3D.md §20.5 "As built"): the roof hoist and the crane as model
  content, `roof_hoist_lift` and `crane_lift`, the pendants' hold-to-run buttons, the pieces drawn between steps;
  the roof hoist adds 1,324 triangles at full detail (596 of them in 4 moving pieces, a draw call each: trolley, hook,
  chain, load; the rest in its cells' meshes, one more there), the crane 952 (904 in 5 moving pieces: bridge,
  trolley, hook, ropes, crate; its end stops in the runway's four corner cells) in place of the parked crane's 2
  meshes. They are never in view together: §20.8's 12 draw calls and 20,000 triangles hold with the lift's share.
  On the Note 9 (a release build without the lightmap, as the baseline before it; `frames` walk, `crews=1`,
  `probe=1`, 600 s, from a battery at 28.0 and 30.0 °C): frames median 22.4 and 29.3 ms, p95 36.5 and 37.1 ms, none
  over 100 ms, scripts 3.16 and 3.35 ms a frame (bindings 0.35 and 0.36), VRAM 159 MB; the baseline (two runs before
  L4): median 20.7 and 23.6 ms, p95 36.5 and 36.3 ms, scripts 3.09 and 3.19 (bindings 0.32 and 0.33), VRAM 159 MB.
  The `hoist` walk (up HRSG 1's stair to the roof hoist's pendant, 300 s): median 19.1 ms, p95 36.6 ms, one frame of
  128 ms that the rule excludes as the kernel's memory reclaim. All three walks saw reclaim in 1.1 to 1.7 % of their
  samples, over the rule's 1 %, so the frame rule does not judge them (the baseline's was 0.09 %).
- **The medians' rise is not the lifts' (checked 2026-11-01).** The user asked why the frames walk's median rose about
  5 ms over LIFTS. The baseline build (badd6da) and main (0b3dbcbf), built alike and walked alternately on the Note 9
  the same day (`crews=1`, 600 s, from 30.0 °C or below, judged walks): medians 28.5 and 29.8 ms against 29.5 and
  29.0 ms; mean frame 26.06 and 26.57 ms against 26.64 and 26.33 ms; GPU median 20.2 and 21.2 ms against 21.2 and
  20.8 ms; scripts 3.28 and 3.34 ms against 3.58 and 3.53 ms; p95 36.5 to 37.3 ms, none over 100 ms. So the baseline
  build "regressed" too. Two causes:
  - this walk's frames fall almost half and half into one refresh (16.7 ms) and two (33.3 ms), so a few percent
    moving between them moves the median 5 to 8 ms and the mean about 0.6 ms (over all 11 walks the median follows
    the share at 60 fps: 51.6 % gives 20.7 ms, 44 % gives 29.5 ms);
  - from about 400 s on, some walks get their GPU clock capped (311 to 351 MHz while 80 to 84 % busy, against 373 to
    385 MHz in walks without it; the phone's thermal service at cooling level 1 from minutes 4 to 5), on either build
    at random. The 10-30 baseline walks heated less (to 29.9 and 32.7 °C, against 34.1 to 34.9 °C on 11-01).

  What the lifts do cost, route segment by segment before the cap: scripts about +0.2 ms (accepted by the user), GPU
  +0.1 to 0.3 ms (within noise), and the lift's sound players about 0.5 s of audio-thread CPU over a walk. **From now
  on, frames walks are compared by their mean frame time and their share at 60 fps, with the late-walk GPU clock
  (samp.txt) beside them; their median is not compared.** Evidence: `~/kks-work/build/lifts-perf/runs/` on the
  maintainer's laptop (each walk's thermals and thread CPU).

**S4, the full day: the plan (2026-11-01; PLANT3D.md §21).** Four pull requests, each measured and reviewed:
- **S4a, the engine** (**built 2026-11-01**, PLANT3D.md §21.11)**:** homes and off site, off-duty routines, `go: "home"`, `sleep`, vehicles, `drive` ways, runs
  and drivers, `ride` and the trainee's `ride` input, in the reference and the GDScript engine bit for bit; the
  validator's rules; `staff.runs` on a synthetic plant with a camp and `staff.reject` (every earlier vector item
  unchanged: the S4 keys are new, and a file without homes or vehicles runs as before, checked by a JSON comparison
  of the old and new file).
- **S4b, the content** (**built 2026-11-01**, PLANT3D.md §21.12)**:** the missing roles (guards, managers and engineers, drivers, the storekeeper, the camp staff:
  91 people), homes in the camp, the camp's and the admin building's places measured on the navigation mesh, the gate
  at the plant gate, the buses' stops, drive ways and runs, meals, the morning meeting, the evening; `day` made again
  over 24 clock hours with its forks and the new ones (§21.9); the staff step's cost on the laptop.
- **S4c, the app** (**built 2026-11-02**, PLANT3D.md §21.13)**:** the vehicles drawn and on the map, people at hidden places and in unloaded interiors not drawn,
  the trainee's bus ride, the off-duty Crew panel, the debrief per role.
- **S4d, the Note 9** (**measured 2026-11-02**, PLANT3D.md §21.14: one judged walk of two, the frame rule passes in all three; the staff step about 1.07 ms, over its 0.3 ms)**:** the `gate` walk at the shift change (PLANT3D.md §21.10), two judged cool runs, the staff step on
  the phone.

**Answered (S4, the user, 2026-11-02):** the staff step on the Note 9 at the gate was about 1.07 ms, over §21.10's
0.3 ms: profile it and speed it up, with no change of behaviour. **Made faster** (PLANT3D.md §21.15): riders asleep at
the stop, the bus's next run cached, phase 5's people found natively; the work in the gate's hour 52,637 → 10,072 task
steps; on the laptop 170 → 60 µs a step. **Then the waits asleep too** (the user, 2026-11-03: people waiting for a
place or for a meeting's others): 1,752 task steps in the hour, 39 to 46 µs a step on the laptop, and **0.27 ms a step
on the Note 9** at the gate (two judged cool walks: 268.6 and 267.2 µs; about 1.32 ms before, one judged walk of the two asked), within §21.10's 0.3 ms;
mean frame 25.1 ms and 53 % at 60 fps, as before (PLANT3D.md §21.15).

**Answered (S4, the user, 2026-11-02):** a trainee who plays a driver steers the bus. **S4e, the driver steers**
(PLANT3D.md §21.16): the `drive` input (wheel, stop, go, auto) in both engines with vectors (every earlier item as it
was), the app's driving (a kinematic bus, the automatic brake for people, the controls on keyboard, gamepad and touch,
off route and lateness for the debrief), the driven bus seen by the session's other players, and a `drive` walk on the
Note 9 (two judged cool runs).

**Multiplayer** (the user, 2026-10-26): its own milestones MP1–MP6 in docs/plant3d/MULTIPLAYER.md §13 (decisions
0067–0069). MP1 needs S3 (the engine's staff as built); it changes the engine (several trainees), so it goes before
S4 or alongside it with S4 rebased on it. **MP1 built 2026-10-26** (PLANT3D.md §17.13–§17.14, MULTIPLAYER.md §3.3, §4),
all but one check: the state digests on Android (the Note 9 ran only the digest's timing), MP2's first step
(MULTIPLAYER.md §12).

**MP2 built 2026-10-27** (LAN sessions; MULTIPLAYER.md §14): sessions of 2 to 8 players on one Wi-Fi, through
"Together" on the bar; the harness of headless players in CI's `multiplayer` job; the Note 9 ran every engine vector
with Linux's digests, joined the laptop's session on the Wi-Fi by its broadcast query, and played in one session with
the laptop and the Windows VM. Its measurements are in MULTIPLAYER.md §14.
- **Done since (2026-10-28):** the two-player walk from a cool start passed the frame rules (99.54 % of frames at
  ≥ 30 fps, no frame over 100 ms); the session's memory is about 21–23 MB against 30 MB (one two-player and one solo
  walk compared, the other player's avatar included).
- **Not done yet:** the session layer's worst frame is 2.13 ms against its 2 ms budget, in 2 of 24,193 frames. The
  join's slow parts are fixed. What remains looks like the thread not getting the CPU, which is not proven on
  Android.

**Workshop** (the user's spec of 2026-11-01; docs/plant3d/WORKSHOP.md, decision 0072): a mode of the app where a
trainee takes one piece of equipment apart, puts it back in order, runs it on a bench model and looks inside. Its own
rules on the Note 9 are WORKSHOP.md §8 (entry ≤ 2.0 s, no frame over 100 ms after it, ≤ 120,000 triangles and ≤ 300
draw calls per kind, ≤ 20 MB for the whole Workshop); the plant's walk is run again when a shared kit piece changes.

| # | Milestone | Size | Needs | Ships |
|---|---|---|---|---|
| K0 | **The plan, before code:** WORKSHOP.md, decision 0072, these rows, the capability matrix; the spec's claims checked against the code, the kit's closed shells and the package's bytes per triangle measured (**done 2026-11-01**) | S | — | the plan |
| K1a | **The component tag and the pre-built scene:** `comp` and `only` in `kit/mesh.gd`, `Kit.make`'s Workshop mode, `builder/workshop_build.gd` and `built/workshop/<part>.scn`, the Workshop data file's validator (`ref/plant3d_workshop.py`); proved on the **pressure transmitter** (its tree: housing and covers, electronics module, display, terminal block, the sealed sensor module, process flange and bolts, vent/drain valves) with the plant unchanged (every part's plant arrays byte for byte, `BUDGET` and `test_kit.gd` as they were; the covers as `"workshop"` halves of a `"plant"` stand-in, small outside pieces listed); `Kit.register` and the data-only fixture kind, built and loaded | M | K0 | the transmitter's Workshop scene, built and tested; nothing new on screen |
| K1 | **The space:** the Workshop's world, orbit camera, the tree and properties panels, the explode function, free handling, hide/isolate, reset; entry from the card and the settings, the plant paused in single play and running in a session (the Workshop's own `SubViewport`, the plant's 3D drawing off); the Workshop walk and the Note 9's entry and frame rules, alone and in a session; pictures on the wiki | M | K1a | the transmitter taken apart and handled, from the plant and back |
| K2 | **Guided assembly and disassembly** for the transmitter: steps, ghost, snapping, refusals with their two sentences, fastener groups, the pile; `ws_xray` for the ghost, its pipelines counted and pre-warmed | M | K1 | the transmitter put back together in the right order |
| K3 | **Run it and see inside** for the transmitter: the bench format, `ref/plant3d_bench.py`, `sim/bench_model.gd`, `plant3d-bench-v1.json` bit for bit; its run (diaphragm, sensed pressure, 4–20 mA on display and terminals), faults (over-range, blocked impulse line, open loop); `ws_lit`, `ws_cap`, `ws_flow` with their pipelines counted and pre-warmed; X-ray, cutaway, section plane; the Note 9, alone and in a session | M | K2 | the transmitter running, cut open, with its faults |
| K4a | **Steam turbine geometry:** its insides (lagging, casing halves at the horizontal joint, inner casings, rotor with blade rows, blade carriers, bearings and caps, glands, valves, couplings, exhaust hood) from cited public sources, its tree, explode, guided assembly; the plant's outside matched (`"plant"` stand-ins checked against their halves, or the lightmap baked again and the walk run); the Note 9 (the first big scene) | L | K3 | the steam turbine taken apart and rebuilt in overhaul order |
| K4b | **Steam turbine running:** its bench made from the plant's `st_start` and trips by `make_bench.py`; steam through valves and stages in order, the rotor turning the right way, pressure and temperature falling along the path, flow, heat and pressure views, sound; the Note 9 | M | K4a | the turbine rolled, loaded and tripped on the bench |
| K5a | **Gas turbine geometry:** intake, compressor stages, combustor, fuel nozzles, turbine stages, exhaust; tree, explode, assembly; the Note 9 | L | K4b | the gas turbine taken apart and rebuilt |
| K5b | **Gas turbine running:** from `gt1_start` and its trips; air, compression, fuel and flame, expansion, exhaust; the views and sound; the Note 9 | M | K5a | the gas turbine started on the bench |
| K6 | **The other kinds**, a few per pull request (pumps, control valve with actuator, butterfly, gate and globe valves, motor, generator, fan, the heat exchangers), data and generators only; then the **mirror** from the live plant (WORKSHOP.md §6.5: bench values from the equipment's bindings, read only; the overwrite after step 2 in both engines with vectors) | L | K5b | every rotating machine and valve kind in the Workshop; the plant's equipment opened as it stands |

**Order:** K0 → K1a → K1 → K2 → K3 → K4a → K4b → K5a → K5b → K6. Each draws or runs something new and is measured on
the Note 9 (K1, K3, K4a, K4b, K5a, K5b at least), with the APK's size before and after (limit 250 MB). The realism programme's
hands-on work builds on K1a–K3 (REALISM.md).

**K4a as built (2026-11-03):** the steam turbine kind for the HP turbine: 54 components, 3 fastener groups (the joint's
studs and the coupling's bolts replacing the plant's stand-ins; the coupling's keep `beyond`), 15,296 triangles; the
plant's warm-up now waits while the Workshop shows (WORKSHOP.md "As built (K4a)"). The Note 9, fresh installs, cool
starts, with the warm-up / `cold=1`: first entry 163 ms / 4,023 ms (≤ 5.0 s); no pipeline compiled after the machine's
first frame; no frame over 100 ms; 99.79 / 99.89 % at ≥ 30 fps, mean frame 19.64 / 19.68 ms, 88.5 / 89.5 % at 60 fps;
peak PSS 868 / 886 MB; at most 95 draw calls in any view. The walk's guided phases leave 14 of its parts loose.
Pictures: the wiki's Workshop page.

**K4b as built (2026-11-07):** the steam turbine runs on its bench, made from the plant's st model by
`tools/plant3d/workshop/make_bench.py` (the start-up machine, five trips and the breaker's opening by protection,
four alarms, the excitation's, breaker's, bias and reset ops, 134 values; WORKSHOP.md §6.6): the steam path's eight
stages (pressure in proportion to the flow, temperature falling with it), the stop and control valves on their stems,
seven flow paths, Heat and Pressure toggles with the legend, the blade-pass tone; two turbine runs in
`plant3d-bench-v1.json`, bit for bit in both engines. The Workshop follow-ups (#325): the kinds' warm-up spread over
frames, its MultiMeshes made new, the Compatibility warm draw's cushion, the walk's steps scaled (every turbine step
walked). The Note 9 (fresh install, cool start, `bench_speed=6`), with the warm-up / `cold=1`: first entry 406 ms /
4.17 s, back to the plant 14–21 ms / 1.52 s the first time (the plant's own pipelines, entered 80 ms after its first
frame), 14 ms after; no pipeline compiled in the walk; no frame over 100 ms in it; 99.88 % at ≥ 30 fps, mean frame 19.85 ms,
88.5 % at 60 fps; peak PSS 1,116 MB; at most 103 draw calls; the bench step 0.171 ms mean. Not fixed: the plant's
705 ms frame 4.8 s after the start (the Workshop's shaders' first compilation; a question for the user). APK 145.2 MB
(K4b's own files about 120 KB). Pictures: the wiki's Workshop page.

**K3 follow-ups as built (2026-11-03):** the step sentence on a canvas layer of its own (the pile's ~510 draw calls
were its letters: now at most 58 on the laptop and 59 on the Note 9), the bench's engine logs bounded (bit for bit
with an engine that keeps everything), and every kind's machine warmed in the plant after its first walkable frame
(WORKSHOP.md "As built (K3 follow-ups)"). The Note 9, fresh installs, cool starts, with the warm-up / `cold=1`: first
entry 407 ms / 4,285 ms (≤ 5.0 s); no pipeline compiled after the machine's first frame; no frame over 100 ms; 99.84 /
99.90 % at ≥ 30 fps, mean frame 19.40 / 19.41 ms, 89.9 / 91.2 % at 60 fps; peak PSS 851 / 834 MB.

**K3 as built (2026-11-03):** the bench format `walkdown-plant-bench` (`ref/plant3d_bench.py`, `sim/bench_model.gd`,
`ref/vectors/plant3d-bench-v1.json`: 2 valid files, 53 rejects, 2 runs, both engines bit for bit, no engine change);
the transmitter's bench (supply, applied pressure to past its range, damping, 4–20 mA with NAMUR saturation, faults
over-range, blocked impulse line, open loop: the 3051 manual and Lipták); `ws_lit`, `ws_cap`, `ws_flow` (and
`ws_xray` for the X-ray), pre-warmed in the plant and in the machine's first frame; X-ray, cutaway with capped cut
faces, section plane, the Run panel (WORKSHOP.md "As built (K3)"). The Note 9, alone / in a LAN session: first entry
4.77 / 4.47 s with an empty pipeline cache (≤ 5.0 s), again 48 / 47 ms; no pipeline compiled after the machine's
first frame; no frame over 100 ms; 99.93 % at ≥ 30 fps, mean frame 19.41 / 18.96 ms, 91.3 / 93.8 % at 60 fps; peak
PSS 859 / 876 MB; the bench step 0.12 / 0.11 ms mean. K2's pile assembly draws ~510 calls (over §8's 300; the same
before K3). Pictures: the wiki's Workshop page.

**K2 as built (2026-11-02):** guided assembly and disassembly for the transmitter (WORKSHOP.md "As built (K2)"):
Assemble from exploded, Assemble from a pile, Take apart step by step; the next step's ghost in `ws_xray`; snapping
within 2 % of the machine's box diagonal and 10° modulo `sym`; the two sentences; the pile; 16 steps from the 3051
manual (13 by hand). The Note 9 (lean+vis, a test-signed copy of the unsigned, unbaked export CI makes, from faf6d008,
the Workshop walk with the steps; SAMPLE=1), a cool start (29.4 °C at the start, 30.8 °C at the end), installed fresh
so the pipeline cache was empty: first entry 2.2 s (≤ 5.0 s), again 17 ms; back to the plant 21–65 ms; **no pipeline
compiled after the machine's first frame**; no frame over 100 ms (the frame rule passes, 0 caused by the app; the
longest 59 ms); 99.92 % of the frames shown at ≥ 30 fps, mean frame 19.1 ms, 68.7 % within 17.5 ms (the share at
60 fps); peak PSS 832 MB. Getting there: one warm ghost per vertex format, hidden, left two pipelines to the first
ghosts (a plain and an instanced one); drawn unseen (alpha 0) in the machine's first frame, one still came at the set
screw's first ghost (the cool run before this one; the laptop's Mobile renderer compiled it at the same step), so the
load now draws every part's own ghost, built as its step builds it and standing at home (§7.1). The APK (unsigned export, without voice) is 117.5 MB; K2's own files in it are under 10 KB.

**K1 as built (2026-11-02):** the Workshop's space, tree, take-apart slider, handling, hide/isolate, Reset, Reassemble
all; entry from the card and the settings; the plant paused in single play and running in a session, with the `pos`
flag and the others' mark (WORKSHOP.md "As built (K1)"). The Note 9, the transmitter, alone and in a LAN session with
the laptop hosting: first entry 1.8 / 1.7 s with an empty pipeline cache (≤ 5.0 s), again 32 / 19 ms; back to the plant
17–67 ms; no frame over 100 ms the app caused, 99.9 % of frames at ≥ 30 fps, mean frame 19.5 / 19.2 ms; peak PSS
836 / 837 MB. Pictures: the wiki's Workshop page.

**K1a as built (2026-11-02):** `comp` and `only` in the mesh builder, `Kit.make(..., workshop = true)`,
`Kit.register` with the data-only fixture kind (`tests/fixtures/workshop_gadget.*`), `builder/workshop_build.gd`
making `built/workshop/pressure_transmitter.scn` (14 components, 2 fastener groups, 1,396 triangles; the plant's part
272), `ref/plant3d_workshop.py`. The plant is unchanged: `tests/test_kit_frozen.gd` holds every part's plant output
(1,397 cases) to what main made, and every built plant scene was compared by content with main's build (identical);
`BUDGET` and `tests/test_kit.gd` as they were. Nothing new on screen, so no Note 9 run (K1 measures).

**Decided by the user (Workshop, 2026-11-02):** in single play the mirror (K6) freezes at the moment the trainee
left; in a session the other players see an "in the Workshop" mark over a player who is in the Workshop (one flag in
`pos`, MULTIPLAYER.md §6.3), built with K1.

## When to stop and ask the user (the user, 2026-10-22)

- **If A1 measures fewer than 4 animated (skinned) people on the Note 9** within the frame rules: stop and ask before
  going on.
- **If the APK passes 250 MB** (raised from 150 MB by the user, 2026-11-01; W1, A1, C1 or later): stop and ask before going on (packs on demand, 0054 §6,
  would need a network permission). The desktop packages (MSIX, Flatpak) may grow to about 300 MB (the user,
  2026-10-23); stop and ask if one passes that. Compress wherever it costs nothing. `tools/plant_release.py` refuses
  a package over its budget.
- Decided already: animations from KayKit (CC0) first; CMU's motion capture allowed if they look too stiff, its
  notice in the About screen (0063). The camp as SITE.md describes it; planting by SITE.md §4.

## Realism (the user, 2026-11-01; docs/plant3d/REALISM.md, decision 0073)

The user chose to add all of: hands-on work and tools, ageing and breakdowns, weather, documents and discussions, work
management, HSE in depth, electrical and mechanical crafts with condition monitoring, and engineering and compliance.
On the same day they added every other part of the job they listed (REALISM.md J1–J8: operations, electrical, I&C,
mechanical, HSE and environment, chemistry, stores and planning, people and administration). The Workshop
(WORKSHOP.md, K0–K6, decision 0072) is built first, and the realism pieces that don't need it are built alongside it
(the user, 2026-11-01): RE1, AG1, WX1 and DC1. Hands-on work waits for the Workshop's K3; the rest follows the Needs
column. Every milestone below is shippable and measured as the rules at the top of this file say; the
programme's own budgets are REALISM.md §11.

| # | Milestone | Size | Needs | Ships |
|---|---|---|---|---|
| RL0 | **The plan:** REALISM.md, decision 0073, these rows, CAPABILITIES.md | S | — | the plan |
| RE1 | **Realism engine base** (REALISM.md §2.1, §2.7–§2.9): the world seed, streams by id, clock values and time bases, the step order's new places, the digest's new parts, `plant3d-realism.json` with its first items, the byte check of the v1 and v2 vectors; the model step measured on the Note 9 on a synthetic model of the planned size (§11's 600 values, and 1,000 for the question below) (**built 2026-11-01**, REALISM.md §2.10: the Note 9's model step 0.418 ms as built, +0.087 ms with 600 values, +0.136 ms with 1,000) | S | S4a | the base every realism engine piece builds on; nothing new drawn |
| HW1 | **Hands-on engine** (REALISM.md §2.3–§2.7): `tools.json` and carried tools, `hands`, `meters` and `read via`, HART ops, hidden causes and `cures`, NPC slips, in the reference and the GDScript engine bit for bit, with vectors; the step's cost | M | RE1, K3 | jobs can be written and checked; nothing new drawn |
| HW2 | **The transmitter in the field:** the work view (§3.3), the builder's unmerged equipment with jobs, the tool tray, the multimeter, clamp meter and HART communicator screens; the condenser pressure transmitters' jobs (open up, connect, read, reconfigure, replace, close up, loop check) generated from the Workshop's tree; the Note 9 walk with `job=` | M | HW1 | an I&C technician's transmitter job, step by step with tools |
| HW3 | **Hidden causes:** the transmitter's five causes and the tests that tell them apart, the debrief's diagnosis tab, the failed part opened in the Workshop (§3.5) | M | HW2, DC2 | troubleshooting where the cause must be found |
| HW4 | **Commissioning and decommissioning** (§3.4): works of kind `commission`, loop checks, stroke tests, a motor's first run, `in_service` states, decommissioning with the drawing's revision | M | HW3, HW5, EC2, DC1 | a new instrument and a motor brought into service; equipment taken out |
| HW5 | **More kinds in the field:** the control valve and positioner, a horizontal pump, a motor, from the Workshop's trees (K6) | L | HW2, K6 | hands-on jobs on valves, pumps and motors |
| HW6 | **Ordering the work:** supervisors and engineers give jobs to NPC technicians, NPCs' hand actions drawn, hold points checked by the trainee | M | HW5 | do it yourself or order it |
| AG1 | **Wear engine** (§2.2, §4.2): `draw` and `wear` nodes, `renews`, wear across jumps, `age_rate`, the `count` node (J0), their vectors (**built 2026-11-02**, REALISM.md §2.11) | S | RE1 | ageing can be written |
| AG2 | **The first train ages:** wear items on pumps, fans, valves, transmitters, filters, the condenser, the GT compressor; early signs bound (sound, heat, trends, shake); seeded failures; the scenarios' ages; the Note 9 walk | L | AG1 | equipment that wears and fails on its own, with signs to find |
| AG3 | **Condition monitoring** (§9.3): the vibration data collector and spectrum, the thermal camera (the Workshop's heat view), oil samples and lab results | M | AG2, HW2, K4b | vibration, thermography and oil analysis rounds |
| WX1 | **Weather engine** (§5.1): `weather.json`, step 1w, the driven `ext` values, seasons by `year_day`, scripted and fixed weather, the instructor's input, vectors (**built 2026-11-02**, REALISM.md §2.12) | S | RE1 | weather that the model and every player share |
| WX2 | **Weather in the model** (§5.2): the GT's ambient tables, inlet filters and compressor fouling, the cooling tower, water ingress causes, frozen impulse lines, lightning; filter change and compressor wash procedures | M | WX1, AG2 | weather that changes output, alarms and faults |
| WX3 | **Weather seen and heard** (§5.4): sky, fog, particles, wet and dusty surfaces, sounds; pipelines counted; the Note 9 walk with `weather=sandstorm` and `weather=rain` (**built 2026-11-02**, REALISM.md §5.5) | M | WX1 | weather to see and hear |
| WX4 | **Weather and people** (§5.3): stopped outdoor work, slippery stairs and `pace`, `ppe_when`, visibility and driving; the heat rule comes with HS3 | M | WX1, HS1 | the staff work in the weather |
| DC1 | **Generic P&IDs** (§6.1): the generator, `walkdown-plant-drawing`, the viewer with hot spots, revisions (**built 2026-11-02**, REALISM.md §6.1.2) | M | — | the first train's P&IDs in the app |
| DC2 | **Equipment manuals** (§6.2): the format, the transmitter's, the control valve's and a pump's manuals with figures from the Workshop | M | K3, DC1 | manuals read from the card and the job |
| DC3 | **Discussions** (§6.3): the format, the `discuss` step in both engines with vectors, the first five discussions | M | DC2, S4b, AG2 | two engineers who differ talk it through, the trainee takes part |
| WM1 | **Work orders and job history** (§7.1): `wo` states and inputs, failure codes, generated history, the work order panel | M | HW1, S4b | work orders from notification to closure |
| WM2 | **Stores and spares** (§7.2): the catalogue, stock, issue and order inputs, deliveries, look-alike parts checked at fitting; the storekeeper's tasks; jumps to a date | M | WM1, DC2 | the wrong part and waiting for a delivery |
| WM3 | **Handover and logbooks** (§7.3): `log` inputs, NPC entries, the handover sheet and its check | M | WM1 | shift handover that can miss something |
| WM4 | **Outage planning** (§7.4): the plan tool, critical path and conflicts, `plan` slots, the outage run over days | L | WM2, HW5, MC2, MC3, HS2, AG2, AG4 | a major outage planned and run |
| HS1 | **JSA and toolbox talks** (§8.1): the hazard library, the `jsa` input and the issue refusal, toolbox talks with content | M | HW1, S4b | every job starts with its JSA and toolbox talk |
| HS2 | **Confined space, hot work, height** (§8.2): continuous gas monitoring, entry log, standby person, fire watch, scaffold tags | M | HS1 | the three high-risk permits in depth |
| HS3 | **Reports, drills and heat** (§8.3, §8.4): report input, incident investigation, emergencies and muster headcounts, the heat rule in the staff step | M | HS1, WX1 | near-miss reports, drills, heat stress |
| EC1 | **Switching and racking** (§9.1): the MV switchgear's positions and interlocks, `switch_effects`, switching programmes, prove dead, arc-flash zones | M | HW2 | the electrical authorised person's switching |
| EC2 | **Electrical tests** (§9.1): megger and PI, relay secondary injection, battery and UPS checks | M | EC1, AG2 | an electrician's test day |
| MC1 | **Alignment and balancing** (§9.2) | M | HW5, AG3 | laser alignment and balancing of a pump set |
| MC2 | **Bearings, seals, lubrication, packing** (§9.2) | M | HW5, AG2 | the mechanical technician's jobs |
| EN1 | **Root-cause analysis** (§10.1): the RCA tool over the run's evidence, checked against the hidden cause | M | HW3, DC3 | an RCA after a trip |
| EN2 | **Management of change** (§10.2): change objects, `approve_change`, setpoints behind a change, drawing revisions | M | DC1, HW4 | a change from request to the revised drawing |
| EN3 | **Alarm management** (§10.3): alarm KPIs, bad actors, `priority_of`, rationalisation through changes | S | EN2 | alarm rationalisation with its effect on the next run |
| EN4 | **Emissions and cycle chemistry** (§10.4, §10.5): NOx/CO/O₂ and the CEMS, averages and reports; the sample panel, lab analyses, action levels, dosing, a condenser tube leak | M | HW2, WM3 | emissions reports and the chemist's cycle chemistry |
| | **The rest of the job** (REALISM.md J1–J8; J0 for the engine additions and the step's cost) | | | |
| OP1 | **Grid events** (J0): `grid.json`, `world.grid`, the instructor's `grid` input, `grid_hz` and `grid_demand` driven in step 1w, vectors in both engines | S | RE1, WX1 | the grid that every player shares |
| OP2 | **Dispatch and frequency response** (J1): the grid operator's instructions on the radio and their repeat back, load ramps, droop and deadband | M | OP1, S4b | the block dispatched by the grid |
| OP3 | **Islanding and black start** (J1): house load or trip on grid loss, the black-start diesel, the dead-block restart, energising to the grid | M | OP2, OP5, EC3, EC6 | a restart from dead |
| OP4 | **Fuel gas and dual fuel** (J1): the fuel gas station, the distillate system, the online changeover; the filters as wear items | M | AG2 | fuel supply rounds and a changeover under load |
| OP5 | **Emergency diesel** (J1): the diesel and its transfer, the monthly test run, the auto start on loss of the essential board | M | EC1, AG1 | the diesel's test day |
| OP6 | **Fire protection tests and CO₂ lockout** (J1): fire pumps, deluge and detection tests, the GT enclosure's CO₂ locked out before entry | M | HS2 | fire system tests; a safe enclosure entry |
| OP7 | **Duty/standby changeovers** (J1): the rota, the standby's auto-start test | S | S4b | routine changeovers |
| OP8 | **Performance and heat rate** (J1): heat rate and corrected output, losses found, the weekly report | M | WX2, AG2 | performance monitoring with its causes |
| EC3 | **Excitation and synchronising** (J2): AVR auto and manual, capability limits, synchronising within limits | M | EC1, OP2 | a generator synchronised by hand |
| EC4 | **Transformer oil DGA** (J2): the oil sample, lab gases by hidden cause, the decision | M | AG3, HW1 | DGA interpreted and acted on |
| EC5 | **Earthing, cathodic protection, cable faults** (J2): fall-of-potential test, pipe-to-soil potentials, TDR location | M | EC2 | three electrical test jobs |
| EC6 | **Switchyard operations** (J2): switching under the grid operator's instructions, interlocks | M | EC1, OP2 | switchyard switching with the grid operator |
| EC7 | **Emergency lighting tests** (J2): monthly and yearly tests, a failed fitting | S | AG1, EC2 | the lighting test round |
| IC1 | **Forces and bypasses** (J0, J3): the `forces` key, `approve_force`, the register, handover facts, vectors in both engines | M | RE1, WM3 | the forcing and bypass register |
| IC2 | **SIS proof tests** (J3): a trip loop proof-tested end to end under a bypass | M | IC1, HW2 | a proof test recorded |
| IC3 | **PID loop tuning** (J3): step tests, gains, stiction told from tuning | M | AG2 | a loop tuned |
| IC4 | **Instrument air** (J3): compressors, dryers, header, fail positions, moisture causes | M | AG2, OP7 | the air system and its failures |
| IC5 | **Calibration traceability and bump tests** (J3): tools' calibration days, certificates, portable and fixed gas detector bump tests | M | HW1 | traceable tools; bump-tested detectors |
| IC6 | **DCS backups, removable media, patching** (J3): backups, the scan kiosk, patches through a change | M | EN2, HW1 | control system housekeeping |
| IC7 | **Vibration monitoring system setup** (J3): probes' gap and scale factor, alarm and trip settings | M | AG3, IC2 | a machinery protection check |
| IC8 | **GT combustion tuning** (J3): dynamics and emissions per mode, tuning, seasonal retune | M | EN4, WX2, OP4 | combustion tuned |
| IC9 | **Compression fittings and Ex inspections** (J3): tube fitting make-up and leak test, Ex inspections | M | HW5 | tubing work; a hazardous-area inspection |
| MC3 | **GT inspections** (J4): borescope with graded findings, combustion and hot-gas-path packages | M | AG2, AG4, HW5 | what an inspection finds |
| MC4 | **HRSG tube leaks and NDT** (J4): leak signs, location, NDT methods, the cause tied to chemistry | M | AG2, HS6, EN4 | a tube leak found and its cause |
| MC5 | **Safety valves and pressure vessels** (J4): in-place set-pressure tests, the written scheme and due dates | M | AG1, HW5 | statutory inspections |
| MC6 | **Lifting gear and lift plans** (J4): examination dates and tags, a lift plan with wind limits | M | HW5, WX4 | certified gear and a planned lift |
| MC7 | **Steam traps and CUI** (J4): a trap survey, CUI locations inspected | M | AG3 | trap and CUI rounds |
| MC8 | **Chemical cleaning** (J4): an HRSG or condenser clean as an outage job | M | MC4, EV1 | a chemical clean |
| MC9 | **Welding qualifications** (J4): welder and procedure checks before hot work | S | PA1, HS2 | qualified welding |
| HS4 | **Induction, first aid, ERT** (J5): inductions, the first response and CPR steps, the emergency response team | M | HS3, PA1 | site inductions and first response |
| HS5 | **Audits and simultaneous operations** (J0, J5): permit and lockout audits, permit conflicts (`conflicts`, vectors) | M | HS2 | audited permits; conflicting work refused |
| HS6 | **Hydrogen, chlorine, radiation** (J0, J5): zone barriers (`barrier_when`, vectors), hydrogen purging, chlorine drills, gauges' shutters, radiography barriers | M | HS2 | the special hazards |
| HS7 | **Personal audio and the phone** (REALISM.md §8.5; the user, 2026-11-03): staff.json's `audio` (banned zones, Ex zones, noticing delays, the missed-call mask; vectors), the `audio` and `phone` inputs and acts, the device held to the end of the duty; the phone's music player with our own procedural tracks, the plant's sounds masked by the volume, missed calls in the radio log, the consequence ladder in the debrief; follow-ups (the user, 2026-11-03): music banned in the control room (`audio.rooms`), a device taken off duty held to the end of the next duty, music refused at the wheel, radio calls missed, the phone at a locker only (the engine), earbuds drawn on avatars | M | S2, RE1 | music on the character's phone, and what it costs |
| EV1 | **Waste and spills** (J5): segregation, records, a spill contained and reported | S | HS3 | spill response |
| EV2 | **Wastewater and noise** (J5): discharge monitoring against the IFC limits, a noise survey, hearing protection zones | M | EN4, WX4 | environmental monitoring |
| CH1 | **Cooling tower treatment** (J6): cycles, blowdown, inhibitor and biocide, Legionella risk and samples | M | AG2, EN4 | the cooling tower's chemistry |
| CH2 | **Fuel gas analysis** (J6): the chromatograph, Wobbe index, the fuel specification | S | OP4, EN4 | fuel gas quality |
| CH3 | **Lab calibration and the chemical inventory** (J6): buffers and standards, the log, GHS labels and SDS | S | EN4, IC5 | a traceable lab and safe chemicals |
| WM5 | **Requisitions and OEM engineers** (J0, J7): order approvals (vectors), the OEM's engineer under the service agreement (arriving as a scheduled task) | M | RE1, WM2, S4b | parts bought and the OEM on site |
| WM6 | **KPIs and budgets** (J7): availability, forced outage rate, MTBF, PM compliance, backlog; hours and parts against budget (no currency) | M | WM1, OP8 | the maintenance manager's numbers |
| WM7 | **Critical spares, shelf life, stock audits** (J7): criticality, preservation, expiry, cycle counts | M | WM2 | a store that is kept honest |
| AG4 | **GT intervals in equivalent hours and starts** (J7): factored hours and starts (`count`), tied to AG2's wear, inspections due | M | AG2, OP4 | the next outage's date from the machine's history |
| PA1 | **Training records and authorisations** (J0, J8): the `auth` key, expiry, the training matrix, vectors | S | RE1, S4b | authorisations that expire |
| PA2 | **Fatigue and overtime** (J0, J8): duty hours, limits, the `fatigue` act, vectors | M | RE1, S4b | callouts within the limits |
| PA3 | **Reports and audits** (J8): daily and monthly reports; ISO and insurance audits | M | WM6, HS5 | reports and audits |
| PA4 | **Visitors, passes, languages** (J0, J8): passes at the gate, languages at talks and handovers, vectors | M | S4b, HS4 | the gate and multinational crews |

The K rows (the Workshop) come with WORKSHOP.md's own plan (K0), written in parallel; the K numbers here follow the
user's Workshop spec.

**Order** (the user, 2026-11-01). RL0 now. Alongside the Workshop: RE1, then AG1 and WX1 (no drawing; each with its
vectors), and DC1 (documents, measured alone on the Note 9). After the Workshop's K3: HW1, then the tracks (the
new tracks' rows that don't need K3, such as OP1, OP7, PA1 and PA2, wait by choice, to keep the Workshop first, not
because they need it), each
adding one kind of load measured alone on the Note 9 before the next: HW2 (the work view), WX3 (weather drawn).
Then, as dependencies allow and memory and the one Note 9 permit, in parallel: hands-on HW3–HW6, ageing AG2–AG4,
weather WX2 and WX4, documents DC2–DC3, work management WM1–WM3 and WM5–WM7, HSE HS1–HS7 and EV1–EV2, crafts EC1–EC7
and MC1–MC9, engineering EN1–EN4, operations OP1–OP8, I&C IC1–IC9, chemistry CH1–CH3, people PA1–PA4. The engine
pieces among them (OP1, IC1, HS5, HS6, WM5, PA1, PA2, PA4: J0) come first among their track's new rows, and AG1
gains the `count` node. WM4, the outage, comes last.

**When to stop and ask the user (realism):** the model step passes 2.1 ms on the Note 9 with realism content (fast-
forward below 12×); a public source can't be found for a procedure, failure mode or limit (don't invent it and
present it as real); an engine milestone would alter `plant3d-v1.json` or `plant3d-v2.json`, or a content milestone an input, event or
earlier value of their runs or any synthetic item (REALISM.md §2); the APK passes
250 MB; the frame rules can't be met without cutting something the trainee learns from.

**Decided by the user (realism, 2026-11-01):** the seven questions of decision 0073 (alongside the Workshop: RE1, AG1,
WX1, DC1; ageing at a training rate per scenario with real rates available; free-play weather on, seeded by season;
emissions against the IFC / World Bank Group EHS guidelines; costs as man-hours, parts and MWh lost; P&IDs in the
plant app only; NPC speech text only), and every other part of the job added (J1–J8).

**Decided by the user (realism, 2026-11-02):** the new plant systems of J1–J4 (fuel gas and distillate, emergency
diesel, instrument air, fire water and CO₂, switchyard, excitation: an estimated 300–400 values) **load per scenario**:
optional content each scenario loads or not, so §11's 600 values and 0.4 ms stay the share of a scenario without them,
and one that loads some counts them on top, measured with its milestone; an "everything" day is allowed on laptops and
measured on the Note 9 (REALISM.md J0, decision 0073). This unblocks OP4, OP5, OP6, IC4, EC3 and EC6 (RE1 had measured
+0.087 and +0.136 ms at 600 and 1,000 added values in the model alone on the Note 9, REALISM.md §2.10).
