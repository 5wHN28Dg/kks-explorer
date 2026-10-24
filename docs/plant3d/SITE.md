# Walkdown Plant: the site beyond the train (content plan)

**Status: DRAFT 2026-10-22**, before any content or code. Extends the plot plan of FIRST-TRAIN.md §3 (same
coordinates: x east, y north, metres from the south-west corner of the turbine hall's ground floor). Decision: 0066.
Format: docs/PLANT3D.md (areas §3; format 2 parts and interiors §18.5–§18.6). Everything is invented (R1).

## 1. Plot plan

```
   y
 140 ┤ ┌ admin ┐                                                                  ┌─────── wtp ────────┐   ┌intake┐≈≈≈ river (x 500–590) ≈
 110 ┤ │offices│                                                                  │ clarifiers  filters│   │screens│≈≈≈ 
  90 ┤ │workshp│   ┌─ GT1 hall ─┐┌──── HRSG 1 ────┐                               │ RO/demin bldg, lab │   │pumps │≈≈≈
  60 ┤ └───────┘   └────────────┘└────────────────┘ ◯ stack                      │ demin tanks, pit   │   └──────┘≈≈≈
  45 ┤        [trafo1]   ═══ raw water main (buried, y 79) ═══════════════════════└────────────────────┘
  20 ┤ ══ gate ══ ┌control┐ ┌── turbine hall ──┐ [rack][bop] [cw]  ┌── cooling tower ──┐
   0 ┤ (x −120)  └───────┘ └──────────────────┘                    └───────────────────┘
 −45 ┤                       (train 2, later: the mirror of train 1 across y = 0)
     ┼──────┬───────┬────────┬────────┬────────┬────────┬────────┬────────┬────────┬────── x
         −480 camp  −260    −120      0       100      200      300      400      500
```

| Area (`id`) | Plan bounds (x0, y0 – x1, y1) | What is in it | Pack |
|---|---|---|---|
| (first train) | FIRST-TRAIN.md §3 | unchanged | base |
| `wtp` | 270, 45 – 390, 135 | the water treatment plant (WATER-TREATMENT.md): rapid mixer, two clarifiers Ø 17 m, six filter cells and their gallery, filtered water tank, treatment building 40 × 25 m (RO trains, degasser, mixed beds, the WTP control panel, the lab), two demin tanks Ø 13 m, chemical storage in bunds, neutralisation pit, thickener, filter press house | wtp |
| `intake` | 430, 60 – 470, 110 | the intake structure on the river bank: bar screen, two band screens, three raw water pumps in a wet well, hypochlorite dosing | wtp |
| `admin` | −140, 40 – −53, 135 | a three-storey office block (offices of the managers, engineers and HSE; a meeting room; the permit office) with a shade canopy over the path to its door, workshops (I&C with its calibration bench, mechanical, electrical), the store, the plant's parking under shade canopies (pickups and SUVs); interiors `admin_in`, `workshop_in` | site |
| `gate` | −140, 0 – −53, 40 | the plant gate: gate house, barriers in and out, bus stop; the road from the gate to the ring road (y 12–19), its walkway (y 21–23) with the palms' verge between, and the admin building's entrance road | site |
| `road_west` | −260, 10 – −140, 30 | the road and its walkway between the camp gate and the plant gate (120 m), street lamps, fenced on both sides (the country beyond is not walkable) | camp |
| `camp` | −480, −40 – −260, 120 | the camp (§3); interiors `block1_in`, `mess_in`, `prayer_in`, `gym_in`, `laundry_in`, `rec_in` | camp |

- **The river** runs north–south along the plant's east side: as built (W1), 5 m beyond the boundary wall's east
  side, 90 m wide (x 500–590 while the wall stands at x 495: builder/site.gd places it from the wall, so it follows
  the wall if the fence moves), its water at −1.5 m, drawn by the site (builder/site.gd), not walkable; the wall
  keeps walkers off the bank. The intake's channel (x 441–469.5) runs on under the intake house's east wall, the
  ring road and the wall to a headwall on the river bank. The raw water main (DN 500, buried) runs along y = 79
  from the intake to the WTP's rapid mixer.
- **Water to the train** (as built, W1): overhead on steel posts (the build's pipe supports), walkable under:
  cooling tower makeup (DN 400, +5 m) from the makeup pumps along x = 271 and y = 38, then under the ground into
  the cooling tower's makeup pipe 30PAR10BR001 before its valve 30PAR10AA001; demineralised water transfer (DN 100,
  +6.5 m) along x = 274 and y = 39.5 to x = 133, then south to `bop`'s demin tank 00GHC10BB001. (The plan first
  said sleepers along y = 40: pipes at ground level would cut the walkways between the train and the WTP.)
- **The fence** encloses the plant from x −140 to 495 (the river beyond it, W1), y −130 to 160 (train 2 included; as built the wall runs 25 m beyond the process areas), the camp separately; a
  fence is a structure (`fence`, PLANT3D.md §5), not walkable through. One gate for people and vehicles at the
  plant's west, one at the camp's east.
  - **As built (C1):** the builder's boundary wall (`builder/site.gd`) goes round the process areas (every pack but
    `site` and `camp`) with the ring road and a verge, joined with the `site` areas, whose west edge (x −140) is the
    wall's line. It is open where a road the content lays at ground level crosses it (the plant gate: road and
    walkway, 11 m), and nowhere else. The `camp` pack's areas (the camp, the road to it) stand outside on flat ground
    of their own, fenced by their content; the terrain is flat round them. An area that adds to the process areas
    (W1's `wtp`, `intake`) moves the wall with it.
  - The plant gate's turnstile is left for S4: it turns for people walking through it.
- **Roads** at least 6 m wide (two buses pass), a 1.5 m walkway along each road that people use; crossings marked;
  bus stops at the camp gate, the plant gate and the control building. Everything walkable is reached on foot from
  the control room, the camp too (the walking test, 0059).
- **Distances** (for the staff's ways, STAFF.md): camp gate to plant gate 120 m (as built, C1); plant gate to the control building
  110 m; the control building to the WTP 330 m (a bus or the pickup for jobs there, or a walk of about 4 minutes).

## 2. What the trainee sees from the train

The WTP stands north-east of the cooling tower, low (clarifiers, tanks 12 m, the treatment building 10 m): from the
HRSG platforms it reads as a separate plant across the road. The camp is west, behind the admin area: low
single-storey blocks shaded by date palms (§4), seen from the control building's door.

## 3. The camp

| Building | Size | Inside (walkable interiors marked ●) |
|---|---|---|
| Accommodation blocks 1–8 (`00UZW11`–`00UZW18`) | prefabricated, single storey with a porch along the front, 40 × 10 m, 12 single rooms each with its own bathroom (96 rooms for 91 people and visitors) | ● block 1: the central corridor, every room's door and number, two rooms open (bed, desk, wardrobe, the bathroom); other blocks are shells with their doors (`load: inside`, PLANT3D.md §18.5) |
| Mess hall and kitchen | 40 × 20 m | ● dining hall (tables for 120), serving counter, the kitchen behind it (ranges, cold room door, washing up) |
| Prayer room | 12 × 10 m | ● carpeted hall, shoe racks and an ablution area at the door |
| Gym | 16 × 10 m | ● racks and machines |
| Laundry | 10 × 8 m | ● washers, dryers, folding table |
| Recreation room | 16 × 10 m | ● sofas, a wall screen, tables for games |
| Camp office and first aid | 12 × 8 m | shell; a desk at the window |
| Camp gate | barrier, guard booth | the guard's post |
| Parking and bus stop | under shade canopies | |
| Sports court | 28 × 15 m, fenced, floodlit | outdoor, walkable |
| Walkways | covered walkways between the blocks, the mess and the gate; roads with painted kerbs and street lamps; planting by §4 | |


Generic and neutral: buildings in light, sand and grey tones (the user's choice of neutral colours, 2026-10-21),
signs in the plant's own style (PLANT3D.md §5).

## 4. Planting

The user's rule (2026-10-22): planting suits the place, a desert plant site in southern Iraq, and every plant has a
purpose: **shade**, a **windbreak**, **dust control**, or a recognised camp landscape (a shaded court by the mess, the
entrance). Nothing is planted for decoration alone, and there is little or no lawn: the ground between plantings is
gravel or bare compacted soil, as on such sites. Everything planted outdoors is drip-irrigated from the service water (the
WTP's `00GHA10`; not modelled). Species are ones commonly grown in hot, dry, saline conditions of the region:

| Plant | Where | Purpose |
|---|---|---|
| Date palm (*Phoenix dactylifera*) | in rows along the camp's main walkway and the road to the plant gate; by the mess hall's court; at the admin building's entrance | shade on the walkways people use at shift changes; the camp's recognised landscape |
| Tamarisk (*Tamarix* species) | a belt along the camp's west and north fence, and along the plant's west boundary by the admin area and the gate | windbreak and dust control against the prevailing north-westerly wind (the shamal) |
| Oleander (*Nerium oleander*) | hedges along the camp's roads and between the parking and the blocks | dust control and screening along roads; drought and salt tolerant (poisonous: not by the mess or where food is) |
| Bougainvillea | on the blocks' porches and the covered walkways' posts | shade on porches and walkways; the camp's landscape |
| Drought-tolerant shrubs (saltbush, *Atriplex*; caper, *Capparis*) | low beds by the camp office, the gate houses and the admin building | dust control on bare ground by doors |
| Dracaena (*Dracaena fragrans*), in pots | indoors only: the admin building's lobby, by its entrance | the entrance's recognised landscape (a lobby's plants); watered by hand |

Not planted: lawns, flower beds, plants inside the process areas (the train, the WTP, the transformer yard: gravel and
concrete only, for fire safety, access and drainage), and anything near the cooling tower's drift or the switchyard.
Planting is a structure (`planting`, PLANT3D.md §18.6): drawn with the `form` and `detail` classes (§10 of
PLANT3D.md: a palm's trunk and crown are `form`, its fronds' cut-outs `detail`), static, baked into the lightmap.

**The first train's site** (builder/site.gd: concrete yards, gravel, the ring road, the boundary wall) has no
planting and nothing to remove. What it should gain is listed under milestone C1 (MILESTONES.md).

**As built (C1),** checked by `tests/test_plant3d_site.py` (each plant where its purpose is) and
`apps/plant3d/tests/test_site.gd` (the windbreak):

- *Date palms* stand in the verge on the south side of the east-west walkways (the plant gate's, the road to the
  camp, the camp's main walkway): the sun is in the south, so their shade falls on the walkway; north of the control
  building along its walkway from the gate; by the admin building's door and along its forecourt and parking; in a
  grid on the mess hall's court (on its west side).
- *Tamarisk*, the windbreak: two staggered rows 2.5 m apart along the inside of the boundary wall's north and west
  sides (the builder plants them, clear of the roads and the areas' buildings), and along the camp's west and north
  fence.
- *Oleander* hedges between the road to the camp and its north fence, along the south side of the camp's main road
  (stopping 16 m short of the mess hall's court), and round the camp's parking on the side of the blocks.
- *Bougainvillea* at every third post of the blocks' porches and at every other post of the covered walkway between
  the blocks.
- *Saltbush and caper* in low beds by the doors of the gate house, the control building, the admin building, the
  workshops and the camp office, and by the camp gate's booth.
- Everything planted outdoors is drip-irrigated: a row's drip line is drawn along it, a tree's basin and emitter ring round its
  foot. The ground between is the site's gravel.

**As built (photo pass 3, 2026-10-25),** from the user's reference photos of a plant in service (private, not in
the repository; neutral colours, nothing of that plant's own):

- **Roads:** every kerb painted in yellow and white blocks 1 m long, the ring road's too (it was black and yellow);
  the walkways along the site's and the camp's roads block paved (grey concrete pavers in half bond: the road
  surface `pavers`, drawn by the plant's one shader), and a block-paved footpath 1.5 m wide along the ring road's
  outer kerb; red pillar fire hydrants, each with a red bollard beside it, every 60 m along the ring road beyond the
  footpath (builder/site.gd, clear of the gate, the site's yards and the overhead pipes' posts) and by the site's
  and the camp's roads. The water treatment plant's yard is gravel (its tank farm and vessel rows stand in gravel),
  as the open yards were already; the intake's too (the `wtp` pack's areas).
- **Camp and admin:** the parking under arched white shade sails (posts at the back of the stalls, two cars a bay),
  steel skip bins by the store and by the mess hall's kitchen, a lattice telecom mast behind the office block, an air
  conditioner's outdoor unit under every window of the accommodation blocks and of the office block (not the ground
  floor's front, where its beds and canopy are), its pipe climbing beside the window, and the camp's ambulance parked
  at the kerb of the camp road's north lane by the first-aid point (the camp office): a pale van with a red band and a
  blue light bar, the one pale vehicle (ambulances are pale the world over; the user's "no white vehicles" is the
  fleet's).
- **The telecom mast** is drawn from afar (past its 48 m square's far view, about 120 m) as a slim shaft in the area's
  far view, so it does not vanish from the skyline.
- **The admin lobby:** glazed light tiles (the office block's ground floor), two groups of brown leather sofas round
  carved wooden side tables, the reception counter, and dracaenas in pots by the entrance and in the corners.

`tests/test_plant3d_site.py` checks the kerbs' paint, the walkways' paving and where the props stand (each hydrant by
a road with its bollard, the ambulance on the camp road by the first-aid point, each air conditioner under a window,
the sails' posts clear of the cars); `apps/plant3d/tests/test_site.gd` the ring road's kerbs and hydrants.

## 5. Performance

- **Packs:** `wtp`, `site` and `camp` are packs of their own (0054 §6), shipped in the one package while it stays
  under its budget (the APK 150 MB, the desktop packages about 300 MB: the user, 2026-10-23); each milestone
  measures the package sizes.
- **What the far view costs:** each new area is built like the train's (12 m cells, visibility ranges, merged far
  pieces; 0041, PLANT3D.md §10). Budget per new area, measured on the Note 9 in its milestone: draw calls in any view
  that sees it ≤ 25 % of the first train's in its busiest view, triangles likewise; the frame rules unchanged.
- **Interiors** are scenes loaded near their doors (PLANT3D.md §18.5): the load happens on a worker thread
  (`ResourceLoader.load_threaded_request`) as the trainee approaches, and the interior is shown only when loaded; its
  surfaces use the plant's one lit shader (0060: no new pipelines).
- **Lightmaps:** each pack has its own baked lightmap (0057).
- **The walking test** (0059) covers every new area, and every walking way of the staff (PLANT3D.md §18.1).

## 6. KKS of the site

Structures by the public key's U letters ([E2] p. 80–85): `00UYC10` administration building, `00UST10` workshops,
`00USU10` store, `00UYE10` gate house, `00UZA10` plant roads, `00UZD10` parking, `00UZJ10` fence and gates, `00UZW10`
the camp (the key's housing and residential area: the camp's blocks `00UZW11`–`00UZW14`, the mess `00UZW20`, the
prayer room `00UZW30`, the gym `00UZW31`, the laundry `00UZW32`, recreation `00UZW33`, the camp office `00UZW40`: our
convention under UZW; as built the eight blocks are `00UZW11`–`00UZW18`). The roads carry `00UZA10` (the plant
gate's), `00UZA20` (the admin building's), `00UZA30` (the road to the camp) and `00UZA40` (the camp's main road), the
parking `00UZD10` (admin) and `00UZD20` (camp). Furniture and vehicles carry no codes (structures, PLANT3D.md §5). A
building's code is on its node in the built plant, so a tour stops at it (`camp_path`) and a tap on it opens its
card.
