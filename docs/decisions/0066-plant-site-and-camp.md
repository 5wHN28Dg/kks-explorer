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

## Frame spikes and the far views (#249, 2026-10-23/24)

After W2 and C1 the Note 9 (release builds, baked, `lean+vis`, first starts after the phone cooled to ≤ 31 °C) showed
frames over 100 ms on all three walks. `--probe=1` (frames.csv: each frame's physics, scripts, draw, GPU time, draw
calls, pipelines compiled and the app's own events) traced every one to the GPU; none had an Android cause in the
logcat, and none was a pipeline compiled late (0 to 2 per walk after the first 5 s, none in a long frame).

| Cause | Seen | Fix |
|---|---|---|
| The WTP's and intake's merged far view held every valve and fitting (a quarter of its vertices), which on the phone are never drawn past about 200 m | `frames` walk: 3 frames of 101–107 ms on HRSG 1's roof, single GPU frames of 115–160 ms over the train, 10 SurfaceFlinger holds over 100 ms | detail pieces left out of the far view, with their own range by size (0 frames over 100 ms in the next two walks) |
| The first train had no far view: from the plant gate's road on the camp walk's way back it was about 1,000 of the view's 1,400 draw calls | GPU 65–80 ms a frame for 20 s, frames to 135 ms | a far view for the train's areas too, simplified within 0.2 m (Godot's own simplifier) |
| The halls' insides merged into the train's far view were drawn with the walls from every distance | WTP's north side: GPU 30.5 ms a frame on average (21 ms before), frames to 139 ms | what stands wholly inside a building, under its roof, stays out of the far view (not a door, nor a cell of pipework reaching outdoors, nor the filter house on GT 1's roof) |
| Drawn as pieces instead, the halls' insides were not culled by the occluders from 300 m and more | camp walk's way back: about 1,000 draw calls (500 merged), single GPU frames to 125 ms | a building's inside is drawn only near it: within 30 m plus its size (as the site's and camp's), at most 200 m (every door is shut from farther off: app/door.gd opens one within 2 m). At 200 m alone, the turbine hall's lamps, roof steel and frame (45,000 vertices) came in at once on the camp walk's way back with a 111 ms GPU frame |

An experiment ruled out the interiors' loading (`fx_off=interiors`: the camp walk with no room ever loaded showed the
same spikes on its way back). The occluders now stand 0.3 m inside every wall panel's edges, so clear of doorways, corners and the roof's
edge (Godot's occlusion buffer is coarse; an edge exactly on a doorway can cull what is seen just past it), and every building's walls and
roof are an occluder (occlusion culling on: 1,576 → 475 draw calls in the WTP hall's view west). Seen on the laptop
from 200–500 m (the plant gate's road, the WTP's west and the train from the WTP), the far views look the same as the
pieces they replace; their lighting is the sky's and the sun's without the bake's shadows, which shows nowhere in
those views.

**On the merged main (W3, P1b, S1 and the engine's speed-up); release builds, baked, test-signed; Note 9 `lean+vis`,
plugged in, a first start each, begun at 28–31 °C.** Two builds: "before review" (b11) and the final one (b13), which
adds the reviews' fixes (inside means the whole box within the walls and under the roof, doors merged shut, a detail
inside a building capped at its insides' range):

| Walk | Build | Frames at ≥ 30 fps | Frames over 100 ms after 5 s (app / SurfaceFlinger) | Worst | GPU median / p95 | Peak PSS | First walkable frame |
|---|---|---|---|---|---|---|---|
| `frames` (the train and the WTP) | before review | 99.39 % | 0 / 0 | 66.0 ms | 20.4 / 26.2 ms | 1,128 MB | 11.2 s |
| | final | 99.49 % | 0 / 0 | 56.0 ms | 20.6 / 26.1 ms | 1,077 MB | 11.0 s |
| `wtp` | before review | 98.89 % | 0 / 0 | 72.9 ms | 20.5 / 29.3 ms | 1,068 MB | 11.0 s |
| | final | 98.82 % | 3 / 2 | 114.4 ms | 20.4 / 29.5 ms | 1,091 MB | 10.9 s |
| `camp` (gate, road, camp, block 1, mess) | before review | 99.44 % | 0 / 0 | 89.1 ms | 18.5 / 24.0 ms | 1,156 MB | 12.1 s |
| | final | 99.27 % | 1 / 2 | 147.5 ms | 18.4 / 24.1 ms | 1,107 MB | 11.6 s |

**The rule (none over 100 ms) does not hold reliably yet.** What is left is single frames whose GPU work takes
100–160 ms between frames of about 20 ms, in views that cost the same on average in every build (the WTP's north side:
GPU 23.1 and 23.5 ms on average in the two builds, 734 draw calls in both), with nothing in the logcat and no pipeline
compiled: the final `wtp` walk's three at the WTP's north side, the final `camp` walk's one (GPU 156 ms, 147 draw
calls) on the way into the mess hall. They come and go between runs of the same build (the build before the S1 merge:
one at the WTP's posts at the moment the phone's Samsung Cloud started at the top of the hour, 698 log lines in that
second against 2 the second before, an Android cause; its `camp` walk one at the 200 m switch of the turbine hall's
inside, which the "near it" rule above removed). Not traced: they don't follow the autosave (11 of 168 such frames
within three frames of a save, 6.5 % against 3.4 % by chance), the interiors' loading (`fx_off=interiors` had them too)
or the phone's warmth. The first walkable frame went from about 9.3 s to 11–12 s with S1's staff (not this change);
the rule is 15 s.

Packages (the final build): APK 139.4 MB (budget 150); the desktop packages, estimated from their contents deflated
(the MSIX and the Flatpak were not built here: a Windows VM packs the MSIX): MSIX x64 about 161 MB, ARM64 about
152 MB, Flatpak about 125 MB (budget about 300).

The Honor 600 was not attached on either day, so it was not measured (its last runs, 2026-10-23 morning, before the far
views: `lean+vis` and `full` with no frame over 100 ms).

## The last frame spikes: the phone's memory reclaim (#252, 2026-10-25)

**What they are.** The single GPU frames of 100–160 ms that #249 left (the final build's `wtp` and `camp` walks) come
when the phone's kernel reclaims memory, not from anything the app draws or does at that moment. While it reclaims,
any of the app's GPU frames can take two to seven times as long; when the phone does not reclaim through a walk, no
frame is long. Whether a walk meets the rule therefore depends on what the phone's own services do in those ten
minutes (a Samsung app starting, the top of the hour), which is why builds "passed" and "failed" from run to run.

How it was found ([V] measured on the Note 9, `lean+vis`, release builds with the bake, test-signed; `wtp` walks of
600 s unless named):

| | Finding | Source |
|---|---|---|
| A system trace of a walk (Perfetto, `apps/plant3d/phone/trace.pbtxt`: scheduler, clocks, reclaim, SurfaceFlinger's and the app's atrace) | Each GPU frame's time from Swappy's own atrace marks (Godot's frame pacing): 43 of 16,592 frames over 45 ms, the longest 156 ms. kswapd0 (the kernel's reclaim) ran 31.5 % of those frames' time against 1.6 % of the others'; kworker/0:0 (the kernel worker on CPU 0, where the Mali driver's interrupts and page faults are handled) 47.9 % against 13.2 %. In the 156 ms frame the GPU ran at 546 MHz and 100 % busy, kworker/0:0 ran 34 ms; 0.7 s before it Samsung's account app (com.osp.app.signin) started and went into direct reclaim. Nothing in the log, no pipeline compiled, SurfaceFlinger composed by the hardware composer after the start (no client composition) | [V] `tools/plant3d/bench/pftrace.py` |
| The same views standing still (`phone/shots.sh`, a shot's GPU time) | the WTP hall's views where the walk's long frames clustered cost 18.5–22.8 ms of GPU, the yard 14.6 ms; no effect switch (shadow, occlusion, far view, stencils, lightmap) makes one of them heavy | [V] |
| The trace itself | streamed to the phone's storage at about 2 MB/s, it fills the page cache the kernel must then reclaim: that walk had 120 GPU frames over 45 ms (Godot's measure), the walks without it 0–1 | [V] |
| Reclaim reproduced (`phone/frames.sh` `STRESS=1`: 2 MB a second written to a file in /data/local/tmp, nothing to do with the app) | 99–196 GPU frames over 45 ms a walk, up to 2 over 100 ms; of the frames while kswapd scanned (a 200 ms sampler of /proc/vmstat) 8–28 % were over 45 ms, of the others 0.06–0.07 % | [V] |
| Less GPU work | the sun's shadow off (`fx_off=shadow`, GPU p95 31 → 22 ms) under the same stress: 41 frames over 45 ms instead of 99–192, and still one of 105 ms. What stands inside buildings casting no shadow (342,000 → 263,000 of the RO hall view's triangles in the shadow pass) changed nothing measurable (192, the phone warmer) and was taken out again | [V] |
| The build before #249's review fixes (b11, 3fb5d16a) | under the same stress as bad as the final one: 196 frames over 45 ms, one frame of 122.7 ms. It passed its three walks because the phone did not reclaim during them | [V] |

| `wtp` walk (600 s) | stress | start | GPU frames > 45 / > 66 / > 100 ms | frames > 100 ms after 5 s (app) | worst | frames at ≥ 30 fps | GPU p95 |
|---|---|---|---|---|---|---|---|
| main, Perfetto tracing | the trace's writes | 30.8 °C | 120 / 37 / 2 | 4 | 172.3 ms | 98.45 % | 29.8 ms |
| main | none | 31.2 °C | 1 / 0 / 0 | 0 | 74.2 ms | 98.36 % | 30.8 ms |
| main, sun's shadow off | none | 31.2 °C | 0 / 0 / 0 | 0 | 59.2 ms | 99.68 % | 21.9 ms |
| main | `STRESS=1` | 31.3 °C | 99 / 21 / 1 | 0 | 90.0 ms | 97.88 % | 31.1 ms |
| inside buildings no shadow | `STRESS=1` | 31.4 °C | 192 / 60 / 2 | 0 | 97.0 ms | 97.38 % | 30.3 ms |
| the same, sun's shadow off | `STRESS=1` | 32.2 °C | 41 / 13 / 0 | 1 | 105.0 ms | 99.49 % | 22.2 ms |
| before #249's review (b11) | `STRESS=1` | 32.5 °C | 196 / 58 / 2 | 1 | 122.7 ms | 96.29 % | 31.8 ms |

**What this means for the rule.** The app's own frames hold the rule when the phone leaves its memory alone; when the
phone reclaims, the Mali driver stalls the GPU on CPU 0 for tens of milliseconds, and no setting tried here removes
that (with the sun's shadow off, 19 % less GPU time, a 105 ms frame remained). Kernel stacks or the driver's own
trace events (mali_page_fault_insert_pages and the like exist in this kernel) would name the work kworker/0:0 does,
but the Note 9 is not rooted and Android 10's Perfetto cannot record them; so "the Mali driver's page faults" is the
likeliest reading of the trace, not a proven one. Whether "none over 100 ms" can be met on this phone, or should be
judged on walks without reclaim, is the user's decision.

**Tools added** (to see it again): a shot's line gives its GPU time, and `shot=` works on a phone (`phone/shots.sh`:
views × effect switches in one run); `phone/frames.sh` `STRESS=1`; the trace's config `phone/trace.pbtxt` and its
reader `tools/plant3d/bench/pftrace.py` (no Perfetto tools needed: the long frames and the kernel threads' share of
them).
