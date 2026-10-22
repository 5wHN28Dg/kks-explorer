# Walkdown Plant: the site beyond the train (content plan)

**Status: DRAFT 2026-10-22**, before any content or code. Extends the plot plan of FIRST-TRAIN.md §3 (same
coordinates: x east, y north, metres from the south-west corner of the turbine hall's ground floor). Decision: 0066.
Format: docs/PLANT3D.md (areas §3; format 2 parts and interiors §18.5–§18.6). Everything is invented (R1).

## 1. Plot plan

```
   y
 140 ┤ ┌ admin ┐                                                                  ┌─────── wtp ────────┐   ┌intake┐≈≈≈≈≈≈ river ≈≈≈
 110 ┤ │offices│                                                                  │ clarifiers  filters│   │screens│≈≈≈ (x 470–560)
  90 ┤ │workshp│   ┌─ GT1 hall ─┐┌──── HRSG 1 ────┐                               │ RO/demin bldg, lab │   │pumps │≈≈≈
  60 ┤ └───────┘   └────────────┘└────────────────┘ ◯ stack                      │ demin tanks, pit   │   └──────┘≈≈≈
  45 ┤        [trafo1]   ═══ raw water main (buried, y 80) ═══════════════════════└────────────────────┘
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
| `admin` | −110, 40 – −50, 140 | administration building (offices of the managers, engineers and HSE; a meeting room; the permit office), workshops (I&C with its calibration bench, mechanical, electrical), the store, the plant's parking under shade canopies | site |
| `gate` | −140, 0 – −110, 40 | the plant gate: gate house, barriers in and out, turnstile, bus stop, the fence's corner | site |
| `road_west` | −260, 10 – −140, 30 | the road and its walkway between the camp gate and the plant gate (130 m), street lamps | site |
| `camp` | −480, −40 – −260, 120 | the camp (§3) | camp |

- **The river** runs north–south at x 470–560: water drawn as the existing site's ground is (builder/site.gd), not
  walkable, with the intake's bank and a handrail. The raw water main (DN 500, buried) runs along y = 80 from the
  intake to the WTP.
- **Water to the train:** cooling tower makeup (DN 400, on sleepers along y = 40 then south to `ct`'s makeup valve
  30PAR10AA001); demin transfer (DN 100, on the same sleepers to `bop`'s demin tank 00GHC10BB001).
- **The fence** encloses the plant from x −140 to 475, y −130 to 145 (train 2 included), the camp separately; a
  fence is a structure (`fence`, PLANT3D.md §5), not walkable through. One gate for people and vehicles at the
  plant's west, one at the camp's east.
- **Roads** at least 6 m wide (two buses pass), a 1.5 m walkway along each road that people use; crossings marked;
  bus stops at the camp gate, the plant gate and the control building. Everything walkable is reached on foot from
  the control room, the camp too (the walking test, 0059).
- **Distances** (for the staff's ways, STAFF.md): camp gate to plant gate 130 m; plant gate to the control building
  110 m; the control building to the WTP 330 m (a bus or the pickup for jobs there, or a walk of about 4 minutes).

## 2. What the trainee sees from the train

The WTP stands north-east of the cooling tower, low (clarifiers, tanks 12 m, the treatment building 10 m): from the
HRSG platforms it reads as a separate plant across the road. The camp is west, behind the admin area: low two-storey
blocks under shade, seen from the control building's door.

## 3. The camp

| Building | Size | Inside (walkable interiors marked ●) |
|---|---|---|
| Accommodation blocks 1–4 | 2 storeys, 48 × 12 m, 24 single rooms each (96 rooms for 89 people and visitors) | ● block 1: the corridors, stairs, one room of each kind (bed, desk, wardrobe, bathroom door); every room has its door and number; other blocks are shells with their doors (`load: inside`, PLANT3D.md §18.5) |
| Mess hall and kitchen | 40 × 20 m | ● dining hall (tables for 120), serving counter, the kitchen behind it (ranges, cold room door, washing up) |
| Prayer room | 12 × 10 m | ● carpeted hall, shoe racks and an ablution area at the door |
| Gym | 16 × 10 m | ● racks and machines |
| Laundry | 10 × 8 m | ● washers, dryers, folding table |
| Recreation room | 16 × 10 m | ● sofas, a wall screen, tables for games |
| Camp office and first aid | 12 × 8 m | shell; a desk at the window |
| Camp gate | gate house, barrier, guard booth | the guard's post |
| Parking and bus stop | under shade canopies | |
| Walkways | covered walkways between the blocks, the mess and the gate | |

Generic and neutral: buildings in light, sand and grey tones (the user's choice of neutral colours, 2026-10-21),
signs in the plant's own style (PLANT3D.md §5).

## 4. Performance

- **Packs:** `wtp`, `site` and `camp` are packs of their own (0054 §6), shipped in the one package while it stays
  under its budget (150 MB); each milestone measures the package size.
- **What the far view costs:** each new area is built like the train's (12 m cells, visibility ranges, merged far
  pieces; 0041, PLANT3D.md §10). Budget per new area, measured on the Note 9 in its milestone: draw calls in any view
  that sees it ≤ 25 % of the first train's in its busiest view, triangles likewise; the frame rules unchanged.
- **Interiors** are scenes loaded near their doors (PLANT3D.md §18.5): the load happens on a worker thread
  (`ResourceLoader.load_threaded_request`) as the trainee approaches, and the interior is shown only when loaded; its
  surfaces use the plant's one lit shader (0060: no new pipelines).
- **Lightmaps:** each pack has its own baked lightmap (0057).
- **The walking test** (0059) covers every new area, and every walking way of the staff (PLANT3D.md §18.1).

## 5. KKS of the site

Structures by the public key's U letters ([E2] p. 80–85): `00UYC10` administration building, `00UST10` workshops,
`00USU10` store, `00UYE10` gate house, `00UZA10` plant roads, `00UZD10` parking, `00UZJ10` fence and gates, `00UZW10`
the camp (the key's housing and residential area: the camp's blocks `00UZW11`–`00UZW14`, the mess `00UZW20`, the
prayer room `00UZW30`, the gym `00UZW31`, the laundry `00UZW32`, recreation `00UZW33`, the camp office `00UZW40`: our
convention under UZW). Furniture and vehicles carry no codes (structures, PLANT3D.md §5).
