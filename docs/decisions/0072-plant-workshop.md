# 0072 Walkdown Plant's Workshop mode: component trees from the kit's generators, pre-built scenes, a bench format of its own, one new lit shader

Date 2026-11-01 · Scope: docs/plant3d/WORKSHOP.md, `apps/plant3d/kit`, `apps/plant3d/builder`, a new
`apps/plant3d/workshop/`, `apps/plant3d/sim` (a bench loader), `ref/` (two validators, a vector file),
`tools/plant3d/workshop/`, `data/plant3d/workshop/` and `data/plant3d/bench/` · Status: **proposed**, written before
any code (milestone K0) under the user's Workshop spec and their decisions of 2026-11-01 (this record's number; the
APK limit raised to 250 MB; the plant not paused in a session; hands-on work later) · Extends 0041, 0054, 0055, 0057,
0060, 0067; no new dependency

**Question:** how does a trainee take any kit part apart, put it back in the right order, run it and look inside it,
so that (a) the outside is the one they walk past in the plant (one source, R5), (b) the Workshop's code knows no
specific equipment, (c) running uses the behaviour engine bit for bit with the reference, (d) the Note 9 keeps the
frame rules and the package its limit, and (e) the later hands-on programme (0073) builds on it without rework?

## Findings

[V] verified here (2026-11-01), [D] Godot 4.7 documentation, [S] source read.

| | Finding | Source |
|---|---|---|
| The spec's parts | `pressure_transmitter`, `steam_turbine` and `gas_turbine` are kit parts (kit.json, `MAKERS` in `kit/kit.gd`). The transmitter is 272 triangles today (manifold, sensor flange, housing, display, cable gland); it has no process-flange bolts, covers or terminal block yet. The steam turbine takes `casings` (hp/ip/ip_lp/lp records), as the spec says | [V] |
| Pieces are merged | `kit/mesh.gd` keys layers by material, class and size bucket only; anim channels are the only separate nodes | [V] the code |
| Closed meshes (needed for capping) | partly: 94 % of the transmitter's triangles lie in closed shells (the display's disk is open), 74 % of the steam turbine's, 64 % of the gas turbine's, 66–90 % of a pump, control valve and motor (shells joined by shared positions, closed when every edge is used an even number of times; measured with `Kit.make` in Godot 4.7.2 headless) | [V] |
| Pipelines | one lit shader and one vertex format (0060); on the Note 9 a lit ubershader compiles in 0.6–0.9 s, one at a time; the first frame compiles 13 surface + 7 specialization pipelines. 0057's two-sided variant cost 20 (with the structures' own vertex format, since removed), a discarding one 7. Hidden surfaces' pipelines compile on worker threads without a frame waiting (the walking directions' chevron) | [V] 0057, 0060 |
| Godot | `ALPHA` sends a material to the transparent pipeline; `discard` defeats the depth prepass for that shader; `cull_front`, `blend_mix`, `blend_add`, `depth_draw_never` are render modes; per-instance uniforms: at most 16 a shader, scalars and vectors only; stencil support exists in 4.7 and is marked experimental | [D] spatial_shader, shading_language |
| Package | the APK was 143.0 MB in plant-v0.3.0 (2026-10-30; the spec's 139.4 MB is older, 0066); limit 250 MB since 2026-11-01. The kit's meshes pack at 12–19 bytes a triangle (compressed `.scn` with LODs: transmitter 5.2 KB, steam turbine 68.7 KB, gas turbine 104.9 KB) | [V] the release's assets; a packed scene measured |
| The engine | a model object (values, ops keyed by `(kks, do, trip)`, machines, trips, alarms, faults) stepped by `sim/engine.gd` and the reference's `Engine`; nothing in the step needs a KKS code's grammar | [S] `sim/plant_model.gd`, `sim/engine.gd` |
| The plant's sequences | `st_start` (9 states) and `gt1_start` (11) with their trips, made by `tools/plant3d/train_model.py` and checked against the committed files | [V] |
| Building by script on the phone | 0041's 20–28 s first frame was mostly the bench reading meshes back from the GPU; still, the app builds no geometry (0054 §4) | [V] 0041 |
| Multiplayer | the session's clock is the host's; any player may pause it; positions travel as `pos` at 5 Hz outside the engine | [V] MULTIPLAYER.md §6.3, §7.1 |

## Alternatives

Geometry: (1) **each generator emits a component tree in a Workshop mode, sharing its pieces with the plant** (a
`comp` tag and an `only` tag in the mesh builder); (2) a second generator per kind for the Workshop: two sources of
one outside, which drift; (3) imported CAD models: licences and money, against R5 (the user's call, not taken).

Running: (a) **a bench format of its own, stepped by the plant's engine**; (b) bench models as format 2 area models:
their bindings and ops need KKS codes a bench part doesn't have; (c) app-side animation: no reference, nothing to test
bit for bit, and cause and effect could drift between channels.

Assembly steps: (i) **a section of the Workshop's data with procedure-like text and op-like needs**; (ii) the
procedure format (PLANT3D.md §8): its `at` names codes and its `do` names model ops, while assembly is the trainee's
handling (UI state) on a part with no code; it would need format 1 (frozen) or format 2 bent.

Cut faces: (A) **back faces drawn by an unshaded `cull_front` pass**, with closed shells; (B) the stencil buffer:
experimental in 4.7 and needs closed meshes as well; (C) generated cap polygons per plane position: geometry work every
frame on the phone.

## Choice

- **(1), (a), (i), (A)** as WORKSHOP.md specifies.
- **Data split:** the generator gives what depends on parameters (components, pivots, explode, fasteners, anchors,
  flow paths, symmetry); `data/plant3d/workshop/<part>.json` gives words, order, views and sources. A generator that
  declares nothing yields one component `body`, so every part can be shown.
- **Plant identical:** plant mode ignores the component tag and drops `"workshop"` pieces: every part's plant arrays
  byte for byte as before (proved in K1a on the whole kit). A merged stand-in the Workshop splits is a `"plant"` piece
  checked against its replacements' box (1 mm).
- **Scenes:** `built/workshop/<part>.scn`, pre-built, loaded on a worker thread; plant material names resolved at show
  time; the part's own frame.
- **Bench:** `walkdown-plant-bench` v1, format 1's node kinds, ops at components, trainer faults, one start state,
  bindings by component (§7.7's plus `flow`, `heat`, `pressure`); `ref/plant3d_bench.py`, `sim/bench_model.gd`,
  `ref/vectors/plant3d-bench-v1.json`; plant sequences taken by `tools/plant3d/workshop/make_bench.py` and checked.
  `mirror` (K6) maps plant bindings of the equipment onto bench values.
- **Shaders:** K1–K2 use the plant's materials (no new pipeline). From K3: `ws_lit` (the weathered include with
  discard by up to three planes and an instance-uniform heat/pressure ramp), `ws_cap`, `ws_xray`, `ws_flow` (unshaded).
  Their pipelines are queued in a hidden frame after the plant's first walkable frame, and the Workshop's load draws
  hidden once before the machine's first frame.
- **The plant meanwhile:** its own `World3D` is swapped out, not freed. Single play pauses the clock (held inputs
  released, speed restored on return; autosave unaffected). In a session the plant runs on and the person stands
  where it was left (the user, 2026-11-01); the bench runs locally, outside the session.
- **Rules (Note 9, `lean+vis`):** Workshop button to the machine's first frame ≤ 2.0 s with pipelines compiled, ≤ 5.0 s
  with an empty cache; back to the plant ≤ 1.0 s; after the first frame no frame over 100 ms and ≥ 95 % at ≥ 30 fps
  over the scripted Workshop walk; peak PSS ≤ 1.5 GB with the plant held; one kind ≤ 120,000 triangles and ≤ 300 draw
  calls in any view; a bench step ≤ 0.3 ms; the whole Workshop ≤ 20 MB of package. The budgets are measured with the
  transmitter in K1 and K3 and with the steam turbine in K4b, and written here as built.
- **Later (0073):** component ids are ≤ 16-character identifiers; fasteners are groups of addressable items with
  `tool`, `torque_nm` and `pattern` reserved; anchors name terminals and test points; the assembly needs carry a
  placing and a removing sentence, which the hand actions reuse.

## Capability matrix

CAPABILITIES.md §8 gains rows for see-through, cut and capped surfaces (render modes, discard, back faces, stencil
experimental), per-instance uniforms, and a second 3D world on the same viewport.

## Open for the user

None blocking K1a. Questions raised with K0 (MILESTONES.md, "Workshop"):
1. **Mirror in single play:** the paused plant's moment (default), or let the plant run while a mirror is open.
2. **A mark over a player who is in the Workshop** in a session (a flag in `pos`, a MULTIPLAYER.md change): not now
   (default), or with K1.

**When to revisit:** if `ws_lit` costs more than about 10 pipelines or its background compile costs the plant's frames
on the Note 9 (then compile at the Workshop's load only); if a kind can't stay within 120,000 triangles without losing
what the trainee learns from (the user's call, WORKSHOP.md §13); if stencil support leaves "experimental" in a Godot
the app moves to; if the APK nears 250 MB.

Sources: docs/plant3d/WORKSHOP.md, docs/PLANT3D.md, MULTIPLAYER.md, decisions 0041, 0054, 0057, 0060 ·
https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html ·
https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html ·
https://github.com/5wHN28Dg/kks-explorer/releases/tag/plant-v0.3.0
