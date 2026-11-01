# Walkdown Plant: the Workshop mode

**Status: DRAFT 2026-11-01**, written before any code (milestone K0). Decision: 0072. Milestones: MILESTONES.md,
"Workshop". It builds on docs/PLANT3D.md (the behaviour model §7, bindings §7.7, the kit §9, tiers §10, sounds §11,
vectors §12), the kit (`apps/plant3d/kit/README.md`), decisions 0041, 0054, 0055, 0057 and 0060, and
MULTIPLAYER.md. The realism programme (REALISM.md, decision 0073) builds its hands-on jobs on this file's component
trees, fasteners, assembly sentences and bench models; §14 says what this file keeps open for it.

**Name.** The site already has workshop buildings, among them an I&C workshop with a calibration bench (SITE.md). In
code and text this is "the Workshop mode" wherever the two could be confused; its code lives in
`apps/plant3d/workshop/`, its data in `data/plant3d/workshop/` and `data/plant3d/bench/`.

## 1. What it is

The trainee picks one piece of equipment (a pressure transmitter, a steam turbine, a gas turbine, a pump, a valve…)
and it stands alone in an empty, neutral space, like a CAD viewer. They can take it apart with one slider, pick up and
turn any part, put it back freely or step by step in the right order, run it (Start, and the rotor turns and steam
flows), and look inside through an X-ray, a cutaway or a section plane they move. They see the flow, the heat and the
pressure, hear the machine and read its gauges. Changing a condition, such as closing the inlet valve, changes
everything they see and hear in the right direction.

**How real (the user's rule, R6 applied to the insides of machines).** It looks, behaves, sounds and runs like the
real thing; how is free. Faked freely: flow is particles along authored paths, heat and pressure colours come from
tables, sound is the existing synth and loop library, no CFD, FEA or solver. **Never faked:** which part is inside
which and where; which way things turn and flow; the order of stages (HP before IP before LP; compressor, combustor,
turbine); the order a machine comes apart and goes back; what changes when a condition changes, in which direction
and roughly how much; start-up and shutdown sequences, interlocks, permissives, trips and protections (reused from
the plant's model, §6.5); how one reading relates to another; what happens when something is done wrong. Every
channel (motion, particles, colours, sound, readings) follows the same model value: a valve that only moves its
picture is a bug. Shapes of internals, stage counts, blade orientation and assembly order come from public sources
(§11). No plant data: the repository is public.

## 2. Entering, leaving, and what the plant does meanwhile

**Ways in.** The equipment card's **Workshop** button, for equipment whose part kind has Workshop data
(`data/plant3d/workshop/<part>.json` exists); and a list of part kinds from the settings panel (Escape,
`hud.show_settings`; the app has no other main menu). The site's calibration bench is a natural later way in (§14).

**Leaving** returns the trainee to exactly where they were: same place, view, panels and speed.

**How it is drawn.** The Workshop is its own `World3D` (its own environment: a neutral floor, soft studio light, no
sky) swapped onto the main viewport; the plant's nodes stay in the tree, untouched, and are not drawn. The plant's 3D
sounds fall silent with it (the listener is in the other world); the app's non-positional ambience is paused while
away. Leaving swaps the plant's world back: no reload.

**Single play: the plant's clock pauses** (the default the spec set; nothing found that it breaks):
- any hold-to-run input (a hoist's or crane's pendant, `held_motion`) is released first, as when the pendant closes;
- `sim_clock` goes to PAUSED and the speed before (1×, fast-forward or already paused) is restored on leaving;
- staff, lifts mid-ride, procedures and permits wait with the clock; nothing in the model changes, so the autosave
  writes nothing new (it saves only while the run changes) and still saves at once on going to the background;
- the Workshop's own state (exploded, handled, its bench run) is UI state and is not saved: if Android ends the app
  while it is open, the run continues in the plant where the trainee stood.

**Multiplayer: the plant does NOT pause** (the user, 2026-11-01). The session's clock runs on as everyone else plays:
- the player's person stands where they left it, and the other players see it standing (the walker makes no inputs;
  `pos` goes on at 5 Hz with the last position, MULTIPLAYER.md §6.3);
- held hold-to-run inputs are released (the release goes to the host as an input, as any pendant release);
- voice and radio go on; new alarms and radio calls for the player's role show in a strip at the top of the Workshop
  with **Back to the plant**;
- the Workshop's bench model runs locally, outside the session: it makes no session inputs and is not in the state
  digest;
- a mark over the person ("in the Workshop") would need a flag in `pos`, a MULTIPLAYER.md change: not part of K0–K6.

**Entering never builds geometry.** The scene is pre-built (§5) and loaded with `ResourceLoader.load_threaded_request`;
the app calls `Kit.make()` only in the builder (0054 §4).

## 3. What the trainee can do

**The space.** Orbit, pan and zoom with the mouse; one finger orbits, two pan and pinch; double-click or double-tap
frames a part; Reset view. The gamepad orbits with the sticks, as the plant's look does.

**The component tree.** A collapsible panel: machine → subassemblies → components → small parts (fastener groups).
Selecting in the tree selects in 3D and the other way round; the selection is highlighted (the lit material's
emission, no new shader). The properties panel shows the name, what it does (one or two sentences), its material and
what it is fastened to (from the fastener groups, §4.4). Panels collapse so the 3D view fills the screen.

**Take apart.** One slider from assembled (0) to fully exploded (1), smooth, the same picture for the same value
(§4.3). Subassemblies come out first, their parts after. The slider works on the whole machine or on the selected
subassembly. **Reassemble all** animates everything home.

**Free handling.** Pick up any part that is free to move (§4.5) and drag it along an axis or turn it about one
(a three-axis handle; on touch, the handle's arrows and rings take one finger). Hide, show, isolate (the part and its
subassembly only), show all. **Reset** puts every part back to the transform it was built with (the home transform is
kept; nothing accumulates).

**Guided assembly and disassembly.** From exploded or from a pile (parts laid on the floor by size, a fixed layout
made by the generic code). The next step names the part and shows a ghost of it in place (the X-ray material); drag
it there and it snaps when near enough and turned right (§4.6). Out of order it is refused with the sentence a
technician would give, as an op's permissive is (§7.2 of PLANT3D.md). Fasteners go one step per group ("8 casing
bolts"). Disassembly is the same in reverse with its own sentences.

**Run it.** Start, Stop, Pause and a speed of 0.1× to 2×; sliders for the bench model's inputs; live readings on the
machine's own gauges and display and in a small readout panel; start-up follows the machine's real sequence (the
turbine is rolled up, not snapped to speed); the sound follows the model (a blade-pass tone rising with speed).
Everything moving is drawn interpolated between model steps, so 0.1× is smooth (as the hoists' `slide`).

**See inside.** Toggles that combine and work while running: **X-ray** (chosen outer parts, or all of them, become
see-through), **cutaway** (the kind's predefined cut, cut faces capped), **section plane** (moved and turned by the
trainee, capped), **flow** (particles along the authored paths in the right direction; speed and density follow the
flow value, colour the temperature or pressure, with a legend), **heat** and **pressure** (colour ramps on the
surfaces along the path). **Running while exploded** where the kind's data allows it (a rotor spinning lifted out of
its casing); otherwise the Run button says why (§4.7).

## 4. The component tree and its data

A part kind's Workshop data comes from two places, joined by the builder:
- **the generator** (`kit/parts_*.gd`, R5): everything that is geometry or depends on the parameters: the
  components, their pivots and boxes, explode directions and distances, fastener positions, anchors, flow-path
  points, symmetry for snapping;
- **the data file** `data/plant3d/workshop/<part>.json`: everything that is words, order or choice: names, what
  each does, materials as text, sealing, the assembly order and its sentences, the cutaway, which parts the X-ray
  takes, the bench model it runs, the sources.

The builder refuses a kind whose two halves disagree (a component in one and not the other, a step naming no
component, a binding at no component, a flow path the generator doesn't make).

### 4.1 Components

- **Ids** are identifiers of at most 16 characters (`[a-z_][a-z0-9_]{0,15}`), unique within the kind. Short, because
  the realism programme names model states `<equipment prefix>_<component>_<state>` within the 32-character value
  names (REALISM.md §2.4).
- **Tree:** each component has a `parent` (another component, or none for the machine's top level). Depth at most 6.
- **Root `body`:** a generator that declares no components puts everything in one component `body`. So every kit part
  can be shown in the Workshop (outside only, not taken apart) with no extra code; a kind gets its tree when its
  generator declares one.
- **Generator side** (per component): `pivot` (part frame, metres), the box it builds (measured), `explode` (a
  direction in the part frame and a distance in metres; default: from the parent's box centre to the component's,
  0.6 of the parent's size that way), `sym` (rotational symmetry for snapping: an axis and n, 0 = any angle),
  `anchors` (named points: terminals, test points, lifting eyes, a vent screw), `anim` (a moving piece: kind, axis
  and travel as kit/README.md "Moving parts" defines; the plant's anim channels are components of this kind), `thin`
  (a sheet or a glass that is not a closed solid, §7.2).
- **Data side** (per component): `name` (1–60 characters), `does` (1–300), `material` (1–80, as words: "316L
  stainless steel"), `sealed` with `sealed_why` (its children never come apart: "The sensor module is sealed at the
  factory and replaced as a unit, never opened in the field"), `sources` (§11).

### 4.2 The component tag in the mesh builder

`kit/mesh.gd` keys its layers by material, visibility class and size bucket only. It gains two pieces of state, set
by the generator around its primitives:
- `comp`: the current component id (`g.comp(id, spec)` declares it and makes it current);
- `only`: `""` (shared: plant and Workshop), `"workshop"` (insides, split halves, closing faces: never in the plant)
  or `"plant"` (a merged stand-in the Workshop replaces, see below).

The builder makes a part in one of two modes, `Kit.make(part, params, ctx, seg_scale, workshop := false)` (the mode is
in the cache key):
- **plant mode** (as today): `comp` is ignored in the layer key and `"workshop"` pieces are not written, so the
  layers, triangles, LODs and lightmap are exactly today's. K1a proves this on the whole kit: every part's plant
  arrays before and after the change, compared byte for byte, and every built area's meshes the same;
- **Workshop mode:** the layer key is `comp|material|class|bucket`, `"plant"` pieces are not written, and the result
  gains `components`, `fasteners`, `flows` and `anchors`.

**One source of truth.** Shared pieces are written once and land in both. A `"plant"` piece names the components that
replace it (`replaced_by`), and a test checks that their joined box is the stand-in's within 1 mm and of the same
material: that keeps the outside the trainee sees in the Workshop the one they walk past, without changing the plant
when a casing is split into halves. Changing a shared piece does change the plant: then the lightmap is baked again
and the plant's Note 9 walk is run again (§10).

**Retrofitting.** Each generator's `use()` calls stay; a generator gains `g.comp()` and `g.only()` calls around groups
of primitives. Moving pieces' mesh builders (`g.move`) carry `comp` too. Proved on the transmitter alone first (K1a),
then one kind per milestone.

### 4.3 The explode function

The slider value s ∈ [0, 1] gives every component's offset by a pure function, so the same s always gives the same
transforms and 1 → 0 restores them exactly:
- the tree's depth d (top level 0) gives each level a stage; with D levels below the chosen root, level d moves during
  s ∈ [d / D, (d + 1) / D], eased (smoothstep), and is at its full distance after it;
- a component's offset is the sum of its own and its ancestors' `explode` direction × distance × their stage's eased
  progress (children ride out with their subassembly, then leave it);
- a fastener group's items each back out along their own axis by the group's distance, in the group's stage;
- transform = home transform translated by the offset: computed from home every frame, never accumulated;
- **subassembly only:** the same function with the selected component as root (its own stages); the rest stays home.

Handling (§4.5) is applied on top and cleared by Reset; the slider never reads it.

### 4.4 Fasteners

- **Generator side:** `g.fasteners(id, items, kind, size)`: a group of identical fasteners, each item a transform
  (position and axis) in the part frame; drawn as one MultiMesh (one draw call per material), each item addressable by
  its index, so a later milestone can treat one bolt alone. `kind`: `bolt`, `stud_nut`, `screw`, `cap_screw`,
  `threaded_cover`, `clamp`, `gland`, `pin`, `circlip`, `key`.
- **Data side:** `name` ("8 casing bolts"), `joins` (the components it holds together, at least two), `size` (the
  thread or width across flats, as words: "M24", "7/16-20 UNF", "17 mm A/F"), `sources`. Reserved for the hands-on
  milestones and refused in Workshop data of version 1 (`unknown_key`): `tool`, `torque_nm`, `pattern` (§14).
- "What it's fastened to" in the properties panel comes from `joins`.

### 4.5 What is free to move

One relation serves assembly, disassembly and free handling: the assembly steps' `needs` (§4.6). A component is
**free** when no component that needs it is at home (in place and not exploded); a sealed component's children are
never free (trying says `sealed_why`). In the fully exploded view every component is free. Picking up a part that
isn't free shows the first holding step's removal sentence.

### 4.6 Assembly

The data file's `assembly` is the guided order, one step per component or fastener group:

```json
{"place": "flange_bolts",
 "text": ["Fit the four flange bolts and tighten them crosswise."],
 "needs": [["process_flange", "The flange bolts go in once the process flange sits on the sensor module.",
                              "Take the four flange bolts out before the process flange comes off."]],
 "sources": ["r3051_ch5"]}
```

- `place`: a component or fastener group; every component and group is placed exactly once (`dup_id`, `missing`).
- `text`, `why`: runs as procedures' (COURSES.md §3–§4, no figures or questions).
- `needs`: `[component, sentence when placing too early, sentence when removing too early]`, in order: placing is
  refused with the first unmet need's first sentence; removing a component is refused while a placed component needs
  it, with that need's second sentence. Every named component exists.
- **Snapping:** within 2 % of the part's box diagonal (at least 5 mm) of home and within 10° of its home orientation,
  modulo the component's `sym`.
- **Why not the procedure format (§8):** a procedure's `at` names KKS codes and its `do` names ops of the model; an
  assembly step names components of a part kind with no code, and the trainee's handling is UI state, not model state
  (§6). Bending format 1 (frozen) or format 2 to fit would be worse than a small section of the Workshop's own file
  that reuses the procedures' text runs and the ops' permissive idea. Decision 0072 records this.

### 4.7 Views per kind

- `xray_all`: the components the "all outer parts" X-ray takes (a single component's X-ray works on any).
- `cutaway`: up to two planes, each a normal in the part frame and an offset as a fraction of the part's box from its
  centre; with two, what lies on the positive side of both is cut away (a quarter); `keep` lists components the cut
  passes by (a rotor shown whole inside a cut casing).
- `run_exploded`: `true`, or `{"allowed": [components that may be out], "why": "…"}`: the Run button refuses with
  `why` when another component is out.

## 5. The pre-built Workshop scenes

- **Built ahead of time, like the areas.** `builder/` makes `built/workshop/<part>.scn` for every kind with a data
  file (the export already packs `built/*`), from `Kit.make(..., workshop = true)` with the data file's `params`
  (validated against kit.json's parameters; default: the first train's instance of that kind where it has one, so
  the Workshop shows the turbine the trainee walks past).
- **Nodes:** one `Node3D` per component at its pivot, named by its id, nested as the tree; under it one
  `MeshInstance3D` per material (the component's pieces merged per material: no 12 m cells, no instancing, no LODs: one
  machine seen close); fastener groups as `MultiMeshInstance3D` with their items' transforms in a meta (as the plant's
  cells, `app/plant.gd`); metas for the explode spec, symmetry, anchors, anim and flow paths (polylines in the part
  frame, by id). The data file's words and order are saved with it as a resource the app reads (no JSON parsed at run
  time, as for the plant).
- **Materials by name.** Meshes keep the plant's material names (`paint`, `metal`, `cladding`, …; colour in the
  vertices), resolved when the scene is shown: the Workshop's lit variant in the Workshop mode (§7), the plant's own
  where the realism programme's work view places a component scene in the plant (REALISM.md §3.3). The builder's
  `workshop_scene(part, params, ctx)` can also be called per equipment with its own parameters for that use.
- **Same frame as the plant.** The scene's origin and axes are the part's (kit/README.md "Frames"), so a component
  scene stands exactly where the plant part stands.

## 6. Running: the bench model

### 6.1 Its own format

Plant models are one file per area with bindings that name KKS codes; a part on the bench has no code. So bench
models are a format of their own, `walkdown-plant-bench`, version 1, one file per kind in `data/plant3d/bench/`, with
their own validator and vectors. Format 1 is not changed and format 2 is not bent.

```json
{"format": "walkdown-plant-bench", "version": 1, "part": "pressure_transmitter",
 "values": [["p_applied", {"state": 0, "unit": "bar"}], …],
 "ops": [{"at": "bench", "do": "set", "input": "p_applied", "range": [-1, 12], "title": "Applied pressure"}, …],
 "interlocks": […], "machines": […], "trips": […], "alarms": […],
 "faults": [{"id": "impulse_blocked", "text": "Impulse line blocked", "at": "process_flange",
             "set": {"blocked": 1}, "repair": {"blocked": 0}}, …],
 "start": {"p_applied": 0},
 "bind": [{"at": "diaphragm", "anim": "deflect", "of": "x_dia", "scale": 1},
          {"at": "display", "show": "out_ma"},
          {"flow": "impulse", "of": "flow_frac", "speed": 0.3, "colour": "pressure"},
          {"at": "sensor_body", "pressure": "p_sensed"},
          {"at": "bench", "sound": "steam_vent", "gain": {"of": "vent_flow", "table": [[0, 0], [1, 1]]}}],
 "legends": {"pressure": {"unit": "bar", "table": [[0, "#2c7bb6"], [10, "#d7191c"]]}},
 "readouts": ["p_applied", "p_sensed", "out_ma"],
 "mirror": [{"value": "p_applied", "from": {"bind": "show"}}]}
```

- **The model:** `values` with format 1's node kinds only (§7.1; no `hold`, no staff), `ops` (§7.2) whose `at` is a
  component or `bench` in place of `kks`, interlocks, machines, trips, alarms (§7.3–§7.6), `faults` as a scenario's
  trainer faults (no `when`; pressed from the bench panel, with their `repair`), and one starting state `start` (a
  scenario's `init`). The same 0.1 s step (§7.10), the same arithmetic and refusals.
- **Inputs** are `set` ops with a `range` (sliders) and machine commands (Start, Stop: the machine's own commands, so
  a turbine is rolled by its sequence). Pause and speed (0.1×–2×) are the bench clock's, as the plant's `sim_clock`.
- **Bindings** (by component, never by code): §7.7's `anim` (on a component the generator gave an `anim` kind: a
  rotor's `rotate` with `scale` in revolutions per second, a diaphragm's `translate` exaggerated by its travel, a stem),
  `show` (a gauge or display), `sound` (a sound of sounds.json, gain and pitch tables), `lamp`; and the Workshop's own:
  `flow` (a flow path: `of` the flow from 0 to 1 sets particle speed × `speed` m/s and density; `colour` a legend's
  name and the value it reads, default the path's temperature value), `heat` and `pressure` (a component's surface
  colour from a legend), each reading a value.
- **Readouts:** the values in the small panel (at most 12), with their units.
- **Limits** (`limit`): 600 values, 48 ops, 8 machines, 48 trips, 64 alarms, 24 faults, 128 bindings, 16 flow paths,
  12 readouts.
- **No free-running animation.** Everything the machine does while running reads a model value, drawn between the
  last two steps by the clock's fraction of a step.

### 6.2 Engines and vectors

- **Reference:** `ref/plant3d_bench.py` validates bench files (strict JSON, the rules above, every binding's
  component checked against the kind's data file's components) and turns one into the model the reference's `Engine`
  steps. **App:** `sim/bench_model.gd` loads it into the same shape `sim/plant_model.gd` gives, and `sim/engine.gd`
  steps it. An op's key is `(at, do, trip)` where the plant's is `(kks, do, trip)`. If the engine needs any change for
  this, it is made in both engines with vectors, and `plant3d-v1.json` and `plant3d-v2.json` stay byte for byte.
- **Vectors:** `ref/vectors/plant3d-bench-v1.json` (made by `ref/make_plant3d_bench_vectors.py`): `valid` and
  `reject` items, and `steps` for every committed bench file (its inputs: Start, slider moves, each fault and its
  repair, Stop) and for small synthetic ones; both engines bit for bit, as for the plant.

### 6.3 Sequences come from the plant's content

Where the plant already has a machine's start-up sequence, interlocks or trips (the steam turbine's `st_start` and its
trips, the gas turbine's `gt1_start` and its trips), the bench file is **made** by the content tool
`tools/plant3d/workshop/make_bench.py`, never copied by hand:
- a bench source per kind (`tools/plant3d/workshop/<part>.py`) names the plant machines, trips and interlocks to take
  (from the generated `data/plant3d/model/*.json`), a rename map from the plant's value names to the bench's, and the
  bench's own values for everything the taken pieces read (the tool refuses a reference left undefined);
- `tests/` checks that each committed bench file is exactly what the tool makes, as the plant's content is checked: a
  change to the plant's sequence that isn't made into the bench fails CI.

### 6.4 The transmitter's bench (K3)

Applied pressure (slider within its range and beyond it) → the isolating diaphragm moves (exaggerated so it is seen)
→ the sensed pressure, a lag of the damping time → the output 4–20 mA, shown on the display and at the terminals.
Faults: **over-range** (the output saturates at 20.5 mA and the display says so: NAMUR NE 43's signal levels),
**blocked impulse line** (the sensed pressure holds what was trapped while the applied pressure moves), **open loop**
(no current, the loop-powered display goes dark). Sources in §11.

### 6.5 Plant values to bench inputs (K6, the mirror)

Opening the Workshop from the live plant can mirror that equipment's current state, read only. Each bench file's
`mirror` lists bench values and where each comes from in the plant, by the equipment's own bindings, so no plant value
name is written in bench data:
- `{"bind": "show"}`: the value the plant's `show` binding of that code displays (a transmitter's pressure);
- `{"bind": "anim", "channel": "shaft"}`: the value driving that anim channel (a turbine's speed, a valve's position);
- `{"bind": "lamp", "kind": "running"}`, `{"bind": "sound", "id": …}`: likewise;
- `{"machine": true}`: the equipment's machine's state (by its `kks`), mapped onto the bench machine's states by name.

In a mirror the bench steps as usual but each mirrored value is overwritten after step 2 by the plant's, its ops and
faults are not offered, and the panel says "Mirror of `<code>`, read only". In single play the plant is paused, so
the mirror shows the moment the trainee left; in a session it follows the plant live. The overwrite is an engine
addition (both engines, vectors) made in K6.

## 7. Shaders and cut faces

Decision 0060: one lit shader and one vertex format; each lit ubershader is 0.6–0.9 s of serial compile on the Note
9; a new shader is counted before it is added. 0057 measured a two-sided variant at 20 more pipelines (with the
structures' own vertex format, since removed) and a discarding one at 7.

### 7.1 The variants (all in the plant's one vertex format)

| Variant | Pass | What for | From |
|---|---|---|---|
| plant materials | opaque, lit | K1–K2: the space, the tree, explode, handling (no new pipeline) | today's |
| `ws_lit` | opaque, lit, `discard` by up to three planes | K3 on: every component; heat and pressure ramps from an `instance uniform` (at most 16 per shader: Godot's limit) and the selection's emission | `weathered.gdshaderinc` |
| `ws_cap` | unshaded, `cull_front`, the same planes | the cut faces (below): `ws_lit`'s next pass on solid components | new, small |
| `ws_xray` | unshaded, `blend_mix`, `depth_draw_never` | X-ray (an edge-weighted see-through), and the assembly's ghost in another colour | new, small |
| `ws_flow` | unshaded, `blend_add` | flow particles: one MultiMesh of quads per path, moved along the path in the vertex shader (the path in a small texture; speed and density as uniforms) | new, small |

One new lit shader and three unshaded ones. Each milestone counts its pipelines (`pipelines compiled`, and
`phone/launch.sh`'s log on the Note 9) before and after; 0057's numbers suggest about 7 for `ws_lit` and a few each
for the unshaded ones, to be measured in K3 and written into 0072.

**Compiled before they are needed:** after the plant's first walkable frame (never before: it would cost the 15 s
rule), a hidden node with one small mesh per Workshop variant queues their pipelines on Godot's worker threads, as the
walking directions' chevron does (0060); the pipeline cache (saved every 0.25 MB) keeps them for later starts. The
Workshop's own load draws its scene hidden for one frame first, so anything not yet compiled is compiled before the
first frame of the machine, never on the first X-ray click. K3 measures whether the background compile costs the
plant's frames on the Note 9; if it does, it moves into the Workshop's load alone (its entry rule, §8, allows it).

### 7.2 Cut faces: the back-face cap

A cut opens a solid; where the eye looks through the cut into a solid it sees that solid's inner (back) faces. `ws_cap`
draws exactly those back faces, discarded by the same planes, in a flat cap colour (the material's, darker, with a
hatch), so the cut reads as a filled face. This needs **closed shells**: measured on 2026-11-01 (each layer's
triangles joined by shared positions, a shell closed when every edge is used an even number of times), the plant's
meshes are partly open today:

| Part (defaults) | Triangles | In closed shells | Open pieces |
|---|---|---|---|
| pressure_transmitter | 272 | 94 % | the display's glass disk |
| steam_turbine | 5,542 | 74 % | cladding drums without ends, some casing pieces |
| gas_turbine | 7,292 | 64 % | uncapped tubes, sheet pieces |
| pump_horizontal / valve_control / motor | 1,800 / 1,728 / 724 | 85 / 90 / 66 % | open cylinders, single faces |

So in Workshop mode every component is closed: generators close open pieces with `"workshop"` faces (end caps,
inner walls of cladding), and a component that is a sheet or a glass is marked `thin` and gets `ws_lit` without the
cap pass (same pipelines). A test checks every non-thin component's shells. Interpenetrating closed shells cap
correctly (looking through the cut you see either a part inside or a back face, which is the right answer either
way). The stencil buffer was the other way; Godot 4.7 marks stencil support experimental, and it needs closed meshes
too.

## 8. Frame, memory and size rules

The plant's frame rules (MILESTONES.md: ≥ 95 % of frames at ≥ 30 fps, none over 100 ms that the app causes, peak PSS
≤ 1.5 GB, first walkable frame ≤ 15 s with 0060's margin, the 1.2× rule) stay as they are and are not judged inside
the Workshop. The Workshop's own, on the Note 9 (`lean+vis`, release build, cool start, the reclaim rule as the plant's):

| | Rule |
|---|---|
| Workshop button to the first frame of the machine | ≤ 2.0 s with its pipelines compiled; ≤ 5.0 s with an empty pipeline cache (the first entry after an install) |
| Back to the plant's first frame | ≤ 1.0 s |
| After the first frame of the machine | no frame over 100 ms while orbiting, exploding, X-raying, cutting, sectioning and running; ≥ 95 % of frames at ≥ 30 fps over the Workshop walk |
| The Workshop walk (scripted, `app/workshop_walk.gd`) | 3 minutes on a fixed camera orbit: assembled, exploded 0 → 1 → 0, X-ray, cutaway, a section sweep, Start to full speed at 2×, a fault, Stop, exploded and running where allowed |
| Peak PSS | ≤ 1.5 GB with the plant held behind it |
| One kind's scene | ≤ 120,000 triangles (all components, insides included); ≤ 300 draw calls in any view of the walk (the plant's busiest measured 479 at p95 within the frame rules, 0041) |
| The bench step | ≤ 0.3 ms on the Note 9 (a bench model is a fraction of the plant's 1.4 ms) |
| Pipelines | counted per milestone, none compiled after the first frame of the machine |

**On the phone, cut what looks nice before what the trainee needs** (R9a), in this order: soft shadows, the X-ray's
edge weighting, the flow particles' density (down to a third, never their direction or speed), the floor's texture.
Never cut: components, motion, readings, the cut faces, the colours that carry heat and pressure.

**Package size.** The APK was 143.0 MB in plant-v0.3.0 (2026-10-30); the limit is **250 MB** since 2026-11-01 (the
user; 0054 §6), the desktop packages about 300 MB. The kit's meshes pack at 12–19 bytes a triangle (compressed
`.scn` with LODs, measured 2026-11-01): a 120,000-triangle scene is about 2 MB. The whole Workshop (every kind, its
data, bench files and sounds) is budgeted at **≤ 20 MB**; each milestone writes the APK's size before and after.
Past 250 MB: stop and ask (packs on demand are the user's call).

## 9. Code layout (generic: no part kind is named in it)

| Where | What |
|---|---|
| `apps/plant3d/workshop/` | the mode: the world swap and entry/exit (`workshop.gd`), the orbit camera, the tree and properties panels, explode, handling and its handle, guided assembly, the bench clock and panel, the views (X-ray, cut, section, flow, heat, pressure), the pile layout |
| `kit/mesh.gd`, `kit/kit.gd`, `kit/parts_*.gd` | `comp`, `only`, Workshop mode; each generator's tree |
| `builder/workshop_build.gd` | `built/workshop/<part>.scn`, the join of generator and data, its refusals |
| `sim/bench_model.gd` | the bench file into the engine's model shape |
| `ref/plant3d_bench.py`, `ref/plant3d_workshop.py` | the validators (bench; Workshop data: strict JSON, keys, identifiers, assembly integrity, sources) |
| `tools/plant3d/workshop/` | `make_bench.py` and the bench sources per kind |
| `data/plant3d/workshop/<part>.json`, `data/plant3d/bench/<part>.json` | the data |

A test reads every script in `apps/plant3d/workshop/` and fails on any part id of kit.json in it.

**Adding a new part kind with no Workshop code** (checked against this plan for K0): the kind's generator gains its
`g.comp()`, `g.only()`, `g.fasteners()` and flow paths; `data/plant3d/workshop/<part>.json` gives its words, order,
views and sources; `data/plant3d/bench/<part>.json` (or its bench source for the tool) gives its model and bindings;
any new sound goes into sounds.json. The card's button, the settings list, the builder, the gallery and the tests find
the kind from its data file. Nothing else changes. A test fixture proves it: a kind made for the tests only (a
generator in `tests/fixtures/` added to a test kit through `Kit.use_kit`, its data files beside it) builds, loads,
explodes, assembles and runs.

## 10. Tests and pictures

In `apps/plant3d/tests/` and, for data, the Python suites:
- every component has a unique id, an existing parent and a pivot inside the part's box; the tree has no cycle;
- exploding to 1 and back to 0 restores every transform exactly; the same slider value gives the same transforms;
- the assembly is complete (every component and group placed once), every need names an existing component, and the
  guided order passes its own needs;
- the Workshop build's outside matches the plant's: `Kit.make()` in both modes for the same parameters, before the
  builder's 12 m cells: shared pieces identical, `"plant"` pieces matched by their `replaced_by` boxes (1 mm, same
  material), `"workshop"` pieces only in the Workshop;
- plant mode is byte for byte what it was (K1a, every part); `BUDGET` and `tests/test_kit.gd` unchanged; the
  Workshop's own budget per kind (§8) checked;
- every non-thin component is closed (§7.2);
- each bench model passes its vectors in the reference and in GDScript bit for bit; each generated bench file is what
  the tool makes; every binding points at an existing component and value;
- the data-only fixture kind loads (§9); no part id in the Workshop's code.

**Pictures for the user:** `kit/gallery.gd` gains a Workshop mode capturing each kind assembled, half exploded, fully
exploded, cut away and running, on `full` and `lean+vis`. They go on the wiki and are linked from the PR, never
committed.

**The Note 9** for every milestone that changes what is drawn or run (K1, K3, K4b, K5b at least): the Workshop's
rules of §8, and the plant's walk again when a shared piece changed. Each milestone appends an "as built" paragraph
to MILESTONES.md.

## 11. Sources

Each kind's data file cites, per subassembly, at least one public cutaway, drawing or manual page, and a source for
the disassembly order (`sources`: `{"id", "cite", "url"}` at the file's top, referred to by id); the validator refuses
a subassembly or an assembly without one. The kit README's Workshop section lists, per kind, what is simplified and
points to these. Below that bar, internals are not invented and presented as real: the user is asked (§13).

Starting sources (to be checked page by page in each milestone):
- **Pressure transmitter:** Emerson Rosemount 3051 reference manual (public PDF: sensor module, electronics, housing
  covers, terminal block, process flange and bolts, drain/vent valves; disassembly and reassembly chapter); Yokogawa
  EJA/EJX and Endress+Hauser Cerabar user manuals (diaphragm seal, fill fluid); NAMUR NE 43 (signal levels for failure
  information); Liptak, *Instrument Engineers' Handbook*, vol. 1 (pressure measurement).
- **Steam turbine:** manufacturers' published cutaways (Siemens SST, GE, Mitsubishi brochures); Leyzerovich, *Wet-Steam
  Turbines* and *Steam Turbines for Modern Fossil-Fuel Power Plants*; Bloch and Singh, *Steam Turbines: Design,
  Applications and Rerating*; for the overhaul order, published inspection guides (EPRI's public summaries) and the
  same books' maintenance chapters.
- **Gas turbine:** Saravanamuttoo, Rogers and Cohen, *Gas Turbine Theory*; Boyce, *Gas Turbine Engineering Handbook*;
  manufacturers' published cutaways of heavy-duty frames.

## 12. Milestones

In MILESTONES.md's table, "Workshop": K0 (this plan), K1a (the component tag and the pre-built scene, proved on the
transmitter with the plant unchanged), K1 (the space, tree, take apart, handling, reset; entry from the card and the
settings), K2 (guided assembly), K3 (the bench format and its vectors, the transmitter's run, X-ray, cutaway, section,
its readings and faults), K4a/K4b (the steam turbine's insides and assembly; its running, flow, heat and pressure,
sound, the Note 9), K5a/K5b (the gas turbine, the same split), K6 (the other kinds, a few per pull request; then the
mirror from the live plant, §6.5).

## 13. When to stop and ask the user

- Geometry from anywhere but the kit's code (imported CAD, downloaded or bought models): licences, money, R5.
- A phone or tier dropped, or a Workshop rule (§8) the Note 9 can't meet without cutting something the trainee needs.
- Changing frozen format 1, or a change to format 2 that breaks content or vectors.
- No public source for how a machine is built inside or taken apart (§11's bar).
- The APK past 250 MB or a desktop package past about 300 MB.
- A real choice between alternatives that this file and the docs don't settle.

Out of scope for K0–K6: CFD, FEA, stress or deformation beyond an exaggerated visible motion, tools, torque, wear and
damage, several people in one Workshop, VR.

## 14. Later: hands-on work, ageing and weather (the realism programme)

The user has commissioned a later realism programme (REALISM.md, decision 0073): hands-on work with tools (HART
communicator, clamp meter, multimeter, opening covers, wiring, troubleshooting, commissioning), ageing and
breakdowns, and weather. The Workshop keeps tools and wear out of K0–K6, but its data is shaped so that those
milestones add to it without reworking it:
- **One source for jobs.** REALISM.md's hand actions are made by its content tool from this file's component trees,
  fastener groups and sizes, and the assembly `needs` with their two sentences (§4.6): the Workshop's sentences are
  the jobs' sentences. Component ids are short identifiers (§4.1) so their states fit model value names.
- **Fasteners are groups of addressable items** (§4.4): a later version adds `tool`, `torque_nm` and `pattern` (the
  tightening order) per group and a torque state per item, without changing the geometry or the explode function.
- **Anchors** (§4.1) are the points where wires land and probes and clamps go (terminals, test terminals, a cable's
  core): the meters' `point` names them.
- **Faults are bench data at a component** (§6.1): internal faults (a torn diaphragm, a worn seat, a rubbing seal) and
  hidden causes are more faults and values in the bench model, and wear is a bench value read by bindings; the engine
  and the Workshop's code stay as they are.
- **Component states.** The Workshop's handling state (home, off, a cover open, a fastener group in or out) is UI
  state now; the hands-on milestones make the same states model values for equipment a job names, read by the
  component scene placed in the plant (§5: materials by name, the part's own frame, a scene per instance's
  parameters).
- **The heat view** (`ws_lit`'s ramp) is what the thermal camera draws (REALISM.md §9.3): no new shader.
- **A removed part on the bench.** The mirror (§6.5) is read only; REALISM.md §3.5 makes it writable for a part a job
  removed, with that part's component states and hidden cause.
- **Ageing and weather** live in the plant's model; the mirror maps their effects on the bench's inputs like any other
  plant value.
