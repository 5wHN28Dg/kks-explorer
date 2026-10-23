# 0066 Walkdown Plant's site and camp: a camp 130 m from the plant gate, packs per zone, interiors loaded near their doors

Date 2026-10-22 · Scope: docs/plant3d/SITE.md; areas `wtp`, `intake`, `admin`, `gate`, `road_west`, `camp`; format 2's
`load: inside` (PLANT3D.md §18.5) · Status: **proposed**, before any content (the user's decision of 2026-10-22: a camp
zone, walkable, with a few interiors, where the people go off shift) · Extends 0054, 0057, 0059, 0060

**Question:** where do the water treatment plant and the camp stand, how far from the train, and how are their
buildings and interiors loaded so that the first start (8.8 s of 15 on the Note 9, 0060) and the frame rules hold?

## Findings

| | Finding | Source |
|---|---|---|
| Distances | camps at remote plants are often kilometres away; at 1.3 m/s a 2 km walk is 26 minutes of model time, and a bus ride over terrain we don't have | ours |
| Loading while walking | `ResourceLoader.load_threaded_request` loads a scene on a worker thread; the app shows it when done | [D] class_resourceloader |
| What the start waits for | pipelines, not geometry: the plant loads in ~0.7 s; every surface's pipelines are queued before the first frame, hidden ones too (0060) | [V] 0060 |
| The far view | 12 m cells, merged far pieces and visibility ranges kept the first train's draw calls down 93 % (0041) | [V] 0041 |
| Packs | areas already name their pack; packs can become `.pck` files loaded at run time if the APK passes 150 MB, a desktop package 300 MB (0054 §6, the user 2026-10-23) | 0054 |

## Choice

- **Layout** (SITE.md): the WTP north-east of the cooling tower (x 270–390), its intake on a river bank at x 430–470;
  the admin building, workshops and the plant gate west of the control building; the camp 130 m beyond the plant
  gate (x −480 to −260), joined by a road with a walkway: walkable in 2–4 minutes, with buses at the shift changes.
  Clear of train 2's mirror (y −92 to −45) and the buried CW pipes (y −30 to −33).
- **Packs** `wtp`, `site`, `camp`, in the one package while the APK stays under 150 MB and the desktop packages (MSIX, Flatpak) under
  about 300 MB (the user, 2026-10-23).
- **Interiors** (the camp's block 1, the mess and kitchen, prayer room, gym, laundry, recreation; the plant's admin
  building and workshops) are areas of their own with `load: inside`, loaded on a worker thread within 15 m of their
  doors, freed beyond 30 m; same shader and materials as the plant (no new pipelines). Other buildings are shells
  with doors.
- **Budget** per new area: ≤ 25 % of the first train's draw calls and triangles in its busiest view, measured on the
  Note 9 in its milestone (W1, C1).

**When to revisit:** the APK passes 150 MB or a desktop package about 300 MB (packs on demand: a network permission, the user's call, MILESTONES.md);
the Note 9's walk misses the frame rules near the camp; train 2 is built (its mirror must stay clear).

## As built (milestone C1, 2026-10-23)

Note 9 (release exports **without the lightmap's bake**, same day, plugged in, `lean+vis`; the bake needs more than the
4 GiB this task's memory share allowed, main's own bake too):

| | Rule | Main | C1 |
|---|---|---|---|
| First start (5 runs) | ≤ 15 s (≤ 13.5 s margin) | 9.43–9.93 s | 7.68–9.09 s |
| `frames` walk (the train), frames ≥ 30 fps | ≥ 95 % | 98.72 % | 98.32 % |
| `frames` walk: p95 / GPU median / peak PSS | ≤ 1.2× main | 37.4 ms / 23.7 ms / 694 MB | 39.6 ms / 24.8 ms / 745 MB |
| `camp` walk (gate, road, camp, block 1, mess), frames ≥ 30 fps | ≥ 95 % | — | 99.61 % |
| `camp` walk: frames over 100 ms after the first 5 s | none | — | one, 102.6 ms (GPU 94 ms) at the plant gate on the way back, near the walk's end; an earlier run had one of 116.8 ms, another a burst while the phone's own services started; not traced |
| `camp` walk: peak PSS | ≤ 1.5 GB | — | 747 MB |

Packages (unbaked exports): APK 108.6 → 111.0 MB; Windows exe 2.3 MB larger compressed. With main's lightmap share
the MSIX x64 (147.9 MB in 0.2.1) comes to about 150–153 MB: within the desktop packages' budget of about 300 MB, which the user set on
2026-10-23 (the 150 MB is the APK's alone).
The APK stays about 128 MB.

What it took: interiors put into the tree twelve pieces a frame (whole, the Note 9 held 104–127 ms frames); a far view
per 48 m square (HLOD) for the site and the camp; planting instanced and left out of the bake; walls, not palisades,
round the camp; shells drawn from outside only.
