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
