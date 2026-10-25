# Walkdown Plant: milestones for the staff, the water treatment plant and the camp

**Status: DRAFT 2026-10-22.** Specs: docs/PLANT3D.md (format 2, §14–§19), STAFF.md, WATER-TREATMENT.md, SITE.md.
Decisions 0062–0066.

Every milestone ends **shippable**: a plant release could be made from it (0054's release gates: every CI run green,
tried on the Note 9 first). Every milestone that changes what is drawn or run is measured on the Note 9 against the
frame rules (≥ 95 % of frames shown at ≥ 30 fps in the 10-minute walk, none over 100 ms after the first 5 s, peak PSS
≤ 1.5 GB, first walkable frame ≤ 15 s, and 0060's margin of ≤ 13.5 s per first start) and the 1.2× regression rule,
with the walk extended into the milestone's new areas or crowds. A milestone that misses them is not done; cutting
scope to meet them is the user's call ("When to stop and ask the user", below).

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

**W1 and C1, not yet done (2026-10-24, #249):** on the merged code (W2, W3, P1b, S1) with far views for the train,
the WTP and the intake, occluders on every building and buildings' insides drawn only near them, the Note 9's walks
over the train, the WTP and the camp hold ≥ 98.8 % of frames at ≥ 30 fps, peak PSS at most 1.16 GB, first walkable frame
11–12 s and the APK at 139.4 MB; one build passed all three walks with no frame over 100 ms, but the final one had 3
(`wtp`) and 1 (`camp`) single GPU frames of 102–148 ms with no Android cause found (0066, "Frame spikes and the far
views"). Those frames are what is left before W1 and C1 are done.

**A1 as built (2026-10-25):** KayKit's CC0 clips (committed, pinned) on bodies, work clothes and PPE of our own
made by the build (eight looks by role, each with a road variant); our own work poses; skinned avatars near, posed
meshes further, nothing beyond; bound to the staff engine (place, way, task step, look by role, the hat off the
process areas). The Note 9 holds 12 skinned people within the frame rules (decision 0064, as built); the laptop 24.

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

**Order** (two tracks that join): P1 → S1 → A1 → S2, with W1 → W2 → W3 and C1 alongside; S3 needs both tracks, S4
needs all. In time: P1 and W1 first (independent), then S1 with W2, A1 with W3, S2 with C1, then S3, then S4.

**Why this order keeps the rules:** the model and staff work (P1, S1, W2, W3) adds no drawing; each drawing milestone
(W1, A1, C1) adds one kind of load and is measured alone before the next adds another; S4, the busiest hour, comes
last, when the per-tier counts are known from A1.

## When to stop and ask the user (the user, 2026-10-22)

- **If A1 measures fewer than 4 animated (skinned) people on the Note 9** within the frame rules: stop and ask before
  going on.
- **If the APK passes 150 MB** (W1, A1, C1 or later): stop and ask before going on (packs on demand, 0054 §6,
  would need a network permission). The desktop packages (MSIX, Flatpak) may grow to about 300 MB (the user,
  2026-10-23); stop and ask if one passes that. Compress wherever it costs nothing. `tools/plant_release.py` refuses
  a package over its budget.
- Decided already: animations from KayKit (CC0) first; CMU's motion capture allowed if they look too stiff, its
  notice in the About screen (0063). The camp as SITE.md describes it; planting by SITE.md §4.
