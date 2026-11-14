# Walkdown Plant: the Workshop mode

**Status: DRAFT 2026-11-01**, written before any code (milestone K0). Decision: 0072. Milestones: MILESTONES.md,
"Workshop". It builds on docs/PLANT3D.md (the behaviour model §7, bindings §7.7, the kit §9, tiers §10, sounds §11,
vectors §12), the kit (`apps/plant3d/kit/README.md`), decisions 0041, 0054, 0055, 0057 and 0060, and
MULTIPLAYER.md. The realism programme (REALISM.md, decision 0073) builds its hands-on jobs on this file's component
trees, fasteners, assembly sentences and bench models; §14 says what this file keeps open for it.

**Name.** The site already has workshop buildings, among them an I&C workshop with a calibration bench (SITE.md). In
code and text this is "the Workshop mode" wherever the two could be confused; its code lives in
`apps/plant3d/workshop/`, its data in `data/plant3d/workshop/` (the bench models in its `bench/` folder). "Bench"
here is the Workshop's bench model; the performance bench of 0041 (`tools/plant3d/bench/`) is another thing.

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

**How it is drawn.** The Workshop is a full-screen `SubViewport` with a world of its own (`own_world_3d`: a neutral
floor, soft studio light, no sky, its own physics space), and the main viewport stops drawing 3D (`disable_3d`)
while it is open. The plant is neither moved nor freed: its nodes stay in their world, its physics goes on (the
player's body keeps standing on its floor), only its drawing stops. Swapping the main viewport's `world_3d` instead
would drag every node under it, the plant and the player's body included, into the Workshop's world. The plant's
sounds are muted on their bus and the app's non-positional ambience paused while away. Leaving hides the Workshop's
viewport and turns the main one's 3D back on: no reload. K1 checks this on the Note 9 (the plant's GPU time is gone
while the Workshop shows; nothing falls).

**Single play: the plant's clock pauses** (the default the spec set; nothing found that it breaks):
- any hold-to-run input (a hoist's or crane's pendant, `held_motion`) is released first, as when the pendant closes;
- `sim_clock` goes to PAUSED and the speed before (1×, fast-forward or already paused) is restored on leaving;
- staff, lifts mid-ride, procedures and permits wait with the clock. The autosave writes once more (the clock's speed
  is in the save's signature, `ui/autosave.gd`), then nothing while the model stands still, and still saves at once
  on going to the background;
- the Workshop's own state (exploded, handled, its bench run) is UI state and is not saved: if Android ends the app
  while it is open, the run continues in the plant where the trainee stood, paused as it was saved (the trainee
  presses play; the speed before the Workshop is not kept across the restart).

**Multiplayer: the plant does NOT pause** (the user, 2026-11-01). The session's clock runs on as everyone else plays:
- the player's person stands where they left it, and the other players see it standing (the walker makes no inputs;
  `pos` goes on at 5 Hz with the last position, MULTIPLAYER.md §6.3);
- held hold-to-run inputs are released (the release goes to the host as an input, as any pendant release);
- voice and radio go on; new alarms and radio calls for the player's role show in a strip at the top of the Workshop
  with **Back to the plant**;
- the Workshop's bench model runs locally, outside the session: it makes no session inputs and is not in the state
  digest;
- the other players see an "in the Workshop" mark over that player's person (the user, 2026-11-02): one flag in
  `pos` (bit 0 of its flags byte, MULTIPLAYER.md §6.3), set while the Workshop is open; built with K1;
- the plant's engine, the session layer and the others' avatars keep their CPU behind the Workshop (only the plant's
  drawing stops): the Workshop's rules are measured in a session as well (§8).

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
subassembly. **Reassemble all** animates everything home. Not while it runs: taking apart, handling and the
guided steps wait until the machine is stopped and at rest, apart from what the kind's data lets be opened live
(§4.7 `open_running`: a powered transmitter's terminal cover), with a technician's reason for the rest (the polish
after K4b).

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
  the realism programme names model states `<equipment prefix>_<component>_<state>` (REALISM.md §2.4) and value
  names are identifiers of at most 32 characters (PLANT3D.md §1): that leaves 16 characters for the prefix, the state
  and the two underscores. REALISM.md §2.4 fixes how they are shared, so no name is shortened case by case: an
  equipment alias of at most 8 characters and a state of at most 6 (8 + 1 + 16 + 1 + 6 = 32).
- **Tree:** each component has a `parent` (another component, or none for the machine's top level). Depth at most 6.
- **Root `body`:** a generator that declares no components puts everything in one component `body`. So every kit part
  can be shown in the Workshop (outside only, not taken apart) with no extra code; a kind gets its tree when its
  generator declares one.
- **Generator side** (per component): `pivot` (part frame, metres), the box it builds (measured), `explode` (a
  direction in the part frame and a distance in metres; default: from the parent's box centre to the component's,
  0.6 of the parent's size that way; where the two centres coincide, as a rotor's in its casing, straight up, the
  parent's height plus a tenth), `sym` (rotational symmetry for snapping: an axis and n, 0 = any angle),
  `anchors` (named points: terminals, test points, lifting eyes, a vent screw), `anim` (a moving piece: kind, axis
  and travel as kit/README.md "Moving parts" defines; each of the plant's anim channels is a component with `anim`, and
  the components inside a moving piece, such as a rotor's blade rows, are its children in the tree), `thin`
  (a sheet or a glass that is not a closed solid, §7.2).
- **Data side** (per component): `name` (1–60 characters), `does` (1–300), `material` (1–80, as words: "316L
  stainless steel"), `sealed` with `sealed_why` (its children never come apart: "The sensor module is sealed at the
  factory and replaced as a unit, never opened in the field"), `sources` (§11).

### 4.2 The component tag in the mesh builder

`kit/mesh.gd` keys its layers by material, visibility class and size bucket only. It gains two pieces of state, set
by the generator around its primitives:
- `comp`: the current component id (`g.comp(id, spec)` declares it, makes it current and selects the layer again for
  the current material, so a component can change between primitives without a new `use()`);
- `only`: `""` (shared: plant and Workshop), `"workshop"` (insides, split halves, closing faces: never in the plant)
  or `"plant"` (a merged stand-in the Workshop replaces, see below).

The builder makes a part in one of two modes, `Kit.make(part, params, ctx, seg_scale, workshop := false)` (the mode is
in the cache key):
- **plant mode** (as today): `comp` is ignored in the layer key and `"workshop"` pieces are not written, so the
  layers, triangles, LODs and lightmap are exactly today's. K1a proves this on the whole kit: every part's plant
  arrays before and after the change, compared byte for byte, and every built area's meshes the same;
- **Workshop mode:** the layer key is `comp|material|class|bucket`, `"plant"` pieces are not written, and the result
  gains `components`, `fasteners`, `flows` and `anchors`.

**One source of truth.** Shared pieces are written once and land in both. The rules that keep the Workshop's outside
the plant's (the tolerance the spec allows, stated here):
- a `"plant"` piece names the components that replace it (`replaced_by`); their joined box is the stand-in's within
  1 mm, their material the same, and their triangles per material between the stand-in's and 1.5 times it (split
  faces and joint flanges added); the gallery's side-by-side pictures (§10) show the shape;
- a `"workshop"` piece is either **hidden** in the assembled machine (inside the outer surface: insides, inner faces of
  a split, closing faces) or a **small outside piece** the plant doesn't draw: a fastener group, a cover's thread or a
  screw head, each no larger than 30 mm, marked `outside` in the generator and listed by the test with its size;
  anything larger seen from outside is shared;
- changing a shared piece changes the plant: then the lightmap is baked again and the plant's Note 9 walk is run
  again (§10).

So K1a keeps the plant byte for byte: the transmitter's covers are split from its housing as `"workshop"` halves of a
`"plant"` stand-in, its terminal block, electronics and sensor insides are hidden pieces, and its flange bolts, drain/
vent valves and housing rotation set screw are small outside pieces (the 3051's manual names no cover locking screw).

**As built (K1a, 2026-11-02).**
- `Gen.comp(id, spec)` and `Gen.only(kind, arg)` in `kit/kit.gd` (on the mesh builder `set_comp`, `set_only`): `only()`
  shared; `only("workshop")` hidden, `only("workshop", "outside")` a small outside piece, `only("workshop", "split")` a
  piece of a component that replaces a stand-in; `only("plant", [components])` the stand-in (an empty list: a mounting
  the plant draws and the Workshop leaves out, such as a free-standing transmitter's stand pipe). After a `"workshop"`
  block the generator calls `use()` again; a primitive drawn before it is reported in both modes (`Kit.problems`,
  which `tests/test_kit_frozen.gd` fails on; the Workshop result's `problems`, which the join refuses), and plant mode never
  makes a layer, not even an empty one, for a Workshop piece (the layers' order is the builder's cells' order).
- The Workshop mode's layer key is `comp|tag|material|class|bucket` (tag `shared`, `hidden`, `outside` or `split`), so
  the tests can tell the pieces apart; the scene merges a component's pieces per material.
- `Gen.fasteners(id, kind, items, draw)` (one item drawn by `draw` in its own frame, z the way it backs out; `kind`
  one of the list above, checked by the join) and `Gen.flow(id, points)`; fasteners are Workshop-only small outside
  pieces. A moving piece's builder (`g.move`) follows `comp()` and `only()` like the static one.
- An only() block that runs on into another component (`comp()` inside it) is recorded as a piece of each. A
  `"split"` piece must belong to a component that replaces a stand-in (the tests refuse any other).
- In the scene a fastener item backs out along its basis.y (Godot's axes; the generator's z), meta `back_axis`; the
  MultiMeshes get their instance transforms from the `items` meta at load. Moving pieces are drawn with their
  component's meshes at 0 and described in the root's `moving` meta, for K3 and K4b to animate.
- The join also refuses an assembly that places a part before its parent in the tree, and a fastener group drawn in
  a component its data's `joins` doesn't name; the validator refuses a group placed before the parts it joins.
- The check that the Workshop's code names no part kind is active since K1 (`apps/plant3d/workshop/`). The frozen plant check covers the context keys `pipe_od`, `out` and `floor_dz`; parts whose shape
  depends on other context (nozzles in use, shaft lines, heights above and below) are held only in the cases recorded.
- **The plant's proof:** `tests/test_kit_frozen.gd` compares a digest of everything plant mode gives (layers in order,
  arrays, LOD triangle counts, moving pieces, plates, solids) for 1,397 cases (every part of the kit with its defaults,
  the content's parameter sets, its limits, and instruments standing every way) with `tests/fixtures/kit_plant.json`,
  recorded from main's code before the change; a meant change to the plant records it again with
  `tests/kit_frozen.gd` and then bakes the lightmap and runs the plant's Note 9 walk. Every built scene of the plant
  (231 files: areas, ground, materials, navigation, people) was also compared by content with main's build: identical.
- **The data file** is made like the rest of `data/plant3d` by `tools/plant3d/make_content.py`, from a module per kind
  in `tools/plant3d/workshop/` (`test_plant3d` checks that the committed files are what it makes). `ref/plant3d.py`'s
  content check accepts `workshop/<part>.json` and runs `ref/plant3d_workshop.py` on it. Every component and fastener
  group cites a source (stricter than "per subassembly"); `assembly` and `views` are optional until K2 and K3.
- The transmitter in the Workshop: 14 components, 2 fastener groups, 1,396 triangles (the plant's 272).

**As built (K1, 2026-11-02).**
- `apps/plant3d/workshop/`: `workshop.gd` (the mode: its own `SubViewport` world, the plant's 3D off, the clock paused
  and its speed restored in single play, the plant running on in a session, the sounds muted, the walker's input and
  the plant's panels held; picking, the three-axis handle, hide, isolate, show all, Reset, Reassemble all),
  `explode.gd` (§4.3's pure function; sealed components' children never move; fastener items back out along the
  scene's `back_axis`, before their component moves), `orbit.gd` (mouse, touch, gamepad), `panels.gd` (the tree, the properties, the slider with
  "Selected subassembly only", the tools, Back to the plant, the session's strip). The handle and the floor are
  pre-built too (`built/workshop_ui/space.scn`, the plant's vertex format and materials: no new pipeline), and the
  selection is the lit material's own emission.
- Ways in: the card's **Workshop** button (a kind with a built scene) and a row of kinds in the settings panel. Esc,
  the gamepad's B (or Back to the plant) leaves; leaving a Workshop opened from the settings shows the settings again.
  On a gamepad the first press puts the focus on the tools (the D-pad moves between them, A presses). It doesn't
  open during a scripted flight ("Go there"), the tier probe or the map. The touch sticks hide while it shows (let
  go, as over the screens).
- A component turns about its pivot and a fastener group about its items' centre; the handle stands there.
- What is free to move (§4.5) reads the assembly's `needs` when the data has them (K2); until then everything is free
  but a sealed component's children, which say `sealed_why`.
- The session's strip counts new alarms since the Workshop opened (unacknowledged, not shelved or suppressed, as the
  horn counts them), and says so when the session ends while the Workshop shows. Radio calls for the player's role are not in the
  strip yet (left for K3, which builds the session's Workshop rules again).
- `pos` carries the Workshop flag (MULTIPLAYER.md §6.3) and the others mark the player.
- The Workshop walk (`walk=workshop`, `app/workshop_walk.gd`) enters, leaves and enters again, then runs the 3-minute
  orbit (assembled, 0 → 1 → 0, isolate, show all, a subassembly, the handle, Reset, Reassemble all) and leaves.
- **The Note 9** (lean+vis, a test-signed release build without the lightmap's bake, a fresh install: an empty
  pipeline cache; SAMPLE=1 for the reclaim rule), the transmitter, alone / in a LAN session with the laptop hosting:
  the first entry 1,813 / 1,682 ms (the rule: ≤ 5.0 s with an empty cache, ≤ 2.0 s compiled), the second 32 / 19 ms;
  back to the plant 17–67 ms (≤ 1.0 s); after the first frame no frame over 100 ms (the frame rule passes, 0 caused by
  the app), 99.91 / 99.94 % of the frames shown at ≥ 30 fps, mean frame 19.5 / 19.2 ms, median 16.8 ms (67 % of
  frames within 17.5 ms: the share at 60 fps), GPU median 2.9 / 2.7 ms (the plant's drawing is gone behind it); peak
  PSS 836 / 837 MB (≤ 1.5 GB); no pipeline compiled after the first 5 s. In the session the plant ran on (3 min 38 s of
  model time, 14 ms of model a second) and the session layer took 0.30 ms a frame on average, 3.8 ms at most (its own
  2 ms budget's known excess, MILESTONES.md MP2). The scene is 23 KB and the space 28 KB of the package.

**As built (K2, 2026-11-02).**
- `apps/plant3d/workshop/assembly.gd` (pure: the steps, placed and loose parts, the two sentences, snapping, the
  pile) and the steps in `workshop.gd`: **Assemble from exploded**, **Assemble from a pile**, **Take apart step by
  step**. A part is placed (at home relative to its parent, riding with it wherever that stands) or loose, with a
  transform in the machine's own frame, so a loose part stays where it lies when its parent is moved, and a part may
  be put into a parent that is still loose (the terminal block into a housing on the pile). The insides of a sealed
  component are never loose: their steps are done with it. The slider waits while the steps are on; Reset ends them
  with every part home, Reassemble all animates the loose parts home.
- The next step's words (its `text` and `why`) show above the tools; assembling, its ghost stands where the part goes
  (its own meshes, `ws_xray`, beside a loose parent too). A part let go within 2 % of the machine's box diagonal (at
  least 5 mm) and 10° of its place, modulo its `sym` (a group judged at its items' centre), snaps there unless a need
  is unmet: then the need's first sentence shows and the part stays loose. A placed part that a placed part needs
  can't be picked up (the need's second sentence). One step per fastener group, the group moved as one.
- The pile: every part (not a sealed one's insides) on the floor in front of the machine, in its home orientation, in
  rows by size, largest first (`Assembly.pile`, a fixed layout).
- `ws_xray` (`workshop/ws_xray.gdshader`: unshaded, `blend_mix`, `depth_draw_never`, a little more opaque at the
  outline). Queued twice: a hidden mesh of the space's (the plant's vertex format) with it in the plant 4 s after the
  first walkable frame (`warm_up`, as the chevron), drawn plain and instanced (a fastener group's ghost is a
  MultiMesh); and every part's own ghost, built as its step builds it and standing at home, drawn unseen (alpha 0) in
  the machine's first frame, hidden after it. One ghost per vertex format was not enough: the Note 9 still compiled a
  pipeline at the set screw's first ghost, and the laptop's Mobile renderer did too, at the same step.
- The transmitter's 16 steps (13 the trainee does: the sealed parts' insides come with them) follow the 3051 manual's reassembly (§6.5–§6.5.4; its take-apart, §6.4, is the
  reverse): the sensor module, the housing (needs the module), its set screw, the electronics board, the display, the
  electronics cover (needs the board and the display), the terminal block, the cable gland, the terminal cover (needs
  the terminal block), the process flange (needs the module), its bolts, the drain/vent valves, the manifold. The
  electronics cover is now sealed (the manual's spare parts list its window with it).
- The fixture kind is assembled from exploded in the tests (its lid's four-fold symmetry).
- The Workshop walk keeps its 3 minutes with the K1 phases shortened, then takes the machine apart step by step (each
  part drawn out and let go) and puts it back from a pile (each part drawn to its place and snapped).

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
- bolts back out first, then the part: a fastener group's items each back out along their own axis by the group's
  distance in the first half of its component's stage, and the components of that level move in the second half (a
  level with no fastener group uses its whole stage), as in a real take-apart the bolts come out before the flange
  comes off (the user, 2026-11-02);
- transform = home transform translated by the offset: computed from home every frame, never accumulated;
- **subassembly only:** the same function with the selected component as root (its own stages); the rest stays home,
  and so do the root's own fastener groups (they hold it to the rest). While it is on, a pick inside that subassembly
  keeps it taken apart; a pick outside it takes the picked one apart instead.

Handling (§4.5) is applied on top and cleared by Reset; the slider never reads it.

### 4.4 Fasteners

- **Generator side:** `g.fasteners(id, kind, items, draw)`: a group of identical fasteners, each item a transform
  (position and axis) in the part frame; drawn as one MultiMesh (one draw call per material), each item addressable by
  its index, so a later milestone can treat one bolt alone. `kind`: `bolt`, `stud_nut`, `screw`, `cap_screw`,
  `threaded_cover`, `clamp`, `gland`, `pin`, `circlip`, `key`.
- **Data side:** `name` ("8 casing bolts"), `joins` (the components it holds together, at least two), `sources`.
  `beyond` (K4a, at most 80 characters): what the group joins outside this kind's machine (a coupling's bolts: the
  next rotor on the shaft line, its own machine); with it `joins` may name one component.
- **Roles** (K4a): a group is a small outside piece (`outside`, each item at most 30 mm, the default), the
  replacement of a stand-in the plant draws (`split`: a casing's joint studs, a coupling's bolt ring; its items
  together held to the stand-in's box and triangles, in a moving piece too), or hidden inside the machine's outside
  (`hidden`: an inner casing's studs, every item held to the hidden pieces' rule). A stand-in the plant draws in
  several blocks is one stand-in: `only("plant", [...])` with the same components goes on with it.
- **Not here:** fasteners' sizes, the tools that fit them, torque values and tightening patterns, and components'
  damaged states belong to the realism programme's service file per kind (`data/plant3d/service/<part>.json`,
  REALISM.md §2.4), keyed by these group and component ids; the Workshop's properties panel shows a size once that
  file has one. The Workshop data file has no such keys (`unknown_key`).
- "What it's fastened to" in the properties panel comes from `joins`.

### 4.5 What is free to move

One relation serves assembly, disassembly and free handling: the assembly steps' `needs` (§4.6). A component is
**free** when no component that needs it is at home (in place and not exploded); a sealed component's children are
never free (trying says `sealed_why`). In the fully exploded view every component but a sealed one's children is free. Picking up a part that
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
  it, with that need's second sentence. Every named component exists. A need may name a fastener group too (K4a: the
  outer casing closes over the inner casing's studs, the lagging over the joint's).
- **Snapping:** within 2 % of the part kind's (the whole machine's) box diagonal (at least 5 mm) of home and within 10° of its home orientation,
  modulo the component's `sym` (its axis passes through the component's pivot).
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
- `open_running`: `{"allowed": [components that may be opened or taken off while it runs], "why": "…"}`: while the
  bench's machine is out of its resting state, taking apart and handling are refused with `why` for every other
  component, and the guided steps altogether (without it: none, with "Stop the machine and let it come to rest before opening it
  up"). The transmitter allows its terminal cover with the loop live (to measure the loop current or connect HART,
  outside a hazardous area); the electronics, the sensor module and the flange wait for the loop supply off. A
  rotating machine allows nothing: it is opened only at standstill on its turning gear (the user's decision,
  2026-11-07). The Workshop's code names no kind: the data says.

## 5. The pre-built Workshop scenes

- **Built ahead of time, like the areas.** `builder/` makes `built/workshop/<part>.scn` for every kind with a data
  file (the export already packs `built/*`), from `Kit.make(..., workshop = true)` with the data file's `params`
  (validated against kit.json's parameters; default: the plant's first instance of that kind, in the content's order,
  where it has one, so the Workshop shows the turbine the trainee walks past; the scene keeps them in its `params`
  meta, and the tests check that very shape). The data file's `context` (K4a) names keys of the context the plant
  builder works out for that same instance (`builder/kit_place.gd`: the shaft line's `axis_z`, `shaft_lo`,
  `shaft_hi`, and what a part stands under or over), which the scene is built with and keeps in its `ctx` meta: the
  steam turbine's coupling stands where it does in the plant. Only without `params`.
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
models are a format of their own, `walkdown-plant-bench`, version 1, one file per kind in `data/plant3d/workshop/bench/`, with
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
          {"flow": "impulse", "of": "flow_frac", "speed": 0.3, "colour": "pressure", "by": "p_line"},
          {"at": "sensor_body", "pressure": "p_sensed"},
          {"at": "bench", "sound": "steam_vent", "gain": {"of": "vent_flow", "table": [[0, 0], [1, 1]]}}],
 "legends": {"pressure": {"unit": "bar", "table": [[0, "#2c7bb6"], [10, "#d7191c"]]}},
 "readouts": ["p_applied", "p_sensed", "out_ma"],
 "mirror": [{"value": "p_applied", "from": {"bind": "show"}}]}
```

- **The model:** `values` with format 1's node kinds and format 2's `hold` (§7.1, §15.4: a blocked impulse line
  holds what was trapped; the steam turbine's model uses `hold` too); no staff, no isolations or works. Node kinds the
  plant's format gains later (REALISM.md's `draw` and `wear`) come to bench models as a version 2 of this format, with
  its vectors, when the realism milestones need them on the bench. `ops` (§7.2) whose `at` is a
  component or `bench` in place of `kks`, interlocks, machines, trips, alarms (§7.3–§7.6), `faults` as a scenario's
  trainer faults (no `when`; pressed from the bench panel, with their `repair`), and one starting state `start` (a
  scenario's `init`). The same 0.1 s step (§7.10), the same arithmetic and refusals.
- **Inputs** are `set` ops with a `range` (sliders) and machine commands (Start, Stop: the machine's own commands, so
  a turbine is rolled by its sequence). Pause and speed (0.1×–2×) are the bench clock's, as the plant's `sim_clock`.
- **Bindings** (by component, never by code): §7.7's `anim` (on a component the generator gave an `anim` kind: a
  rotor's `rotate` with `scale` in revolutions per second, a diaphragm's `translate` exaggerated by its travel, a stem),
  `show` (a gauge or display), `sound` (a sound of sounds.json, gain and pitch tables), `lamp`; and the Workshop's own:
  `flow` (a flow path: `of` the flow from −1 to 1 sets particle speed × `speed` m/s and density, its sign the
  direction; `colour` a legend's name and `by` the value it reads), `heat` and `pressure` (a component's surface
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
  steps it. The loaders turn each `at` into the engine's `kks` field (ops, faults, bindings), so the engine finds an
op by `(at, do, trip)` exactly as it finds a plant op by `(kks, do, trip)`, with no change. If the engine needs any change for
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
- As built (K4b): the source also names the plant **values** to take (their definitions are the plant's), the codes'
  places on the bench (`at`), the Run panel's words for taken ops (`titles`), and which of the bench's own values come
  before the taken ones (`before`); §6.6.

### 6.4 The transmitter's bench (K3)

Applied pressure (slider within its range and beyond it) → the isolating diaphragm moves (exaggerated so it is seen)
→ the sensed pressure, a lag of the damping time → the output 4–20 mA, shown on the display and at the terminals.
Faults: **over-range** (the output saturates at 20.5 mA and the display says so: NAMUR NE 43's signal levels),
**blocked impulse line** (the sensed pressure holds what was trapped while the applied pressure moves), **open loop**
(no current, the loop-powered display goes dark). Sources in §11.

**As built (K3, 2026-11-03).**
- **The format** as §6.1, with what writing the first file settled: `sources` (`{id, cite, url}`, at least one) is
  required at the top; an op may carry a `title` (the Run panel's words, ≤ 40 characters); a `show` binding may name
  a `lit` value (the value is shown on the component's face while `lit` is true: a loop-powered display); a `flow`
  binding's colour reads the value `by` names, and its `of` runs from −1 to 1, the sign the direction (into the
  transmitter while the pressure rises, out while it falls: §1's "which way things flow"); a value carries no `kks`
  and no node of the realism programme (`draw`, `wear`, `count`: `bad_kind`, kept for version 2). `ref/plant3d_bench.py`
  checks a file against its kind's component ids by joining it into `ref.plant3d.Model` with components for codes,
  so the plant's own checks and error codes apply; the content check (`ref/plant3d.py check_files`) reads
  `workshop/bench/<part>.json` beside its Workshop data file; the builder refuses an `anim` the generator didn't give
  that component and a `flow` on a path it doesn't make, and saves the bench file's text in the scene's `workshop`
  meta (`bench`).
- **Engines:** no change to either. `sim/bench_model.gd` reads the text into plant_model.gd's shape (version 2: the
  `hold` node and the trainer's events); `ref/vectors/plant3d-bench-v1.json` (`ref/make_plant3d_bench_vectors.py`)
  holds 2 valid files (the transmitter, and a synthetic kind with every node kind, a machine with a sequence, a trip,
  an interlock, alarms, faults and every binding kind), 53 rejects and both runs; `run_vectors.gd --only=bench` steps
  them through the app's engine and `tests/test_plant3d_sim.py GdscriptBench` compares every value's bits at every
  step and the state digests, with the straight-line program and the interpreter. `plant3d-v1.json`, `plant3d-v2.json`
  and `plant3d-realism.json` are byte for byte what they were.
- **The transmitter's model** (`tools/plant3d/workshop/pressure_transmitter.py bench()`, sources: the 3051 manual's
  §2.7.4 and §A.3.9 damping, §2.9.1 table 2-5 NAMUR levels; Lipták vol. 1 ch. 5): a 0–10 bar calibration; the slider
  from −1 to 12 bar; the loop supply a machine (Start, Stop); the impulse line a `hold` of the process pressure while
  blocked; the diaphragm and fill a 0.3 s lag, the sensing cell 0.1 s, the damping 0.4 s; 4–20 mA linear, held at
  3.8 and 20.5 mA (NAMUR NE 43 via the manual), alarms at both and for an open loop; no current and a dark display
  without the supply or with the loop open. Faults: over-range (the process pressure to 15 bar), a blocked impulse
  line, an open loop. Bindings: the diaphragm's `deflect` (6 mm of travel at 10 bar, its real few micrometres
  exaggerated), the display (reading and current, `lit`), the terminals' current, the impulse path's flow coloured
  by its pressure, the isolator's and sensing cell's colour by the pressure at the diaphragm.
- **The app:** `workshop/bench_clock.gd` (the engine stepped every 0.1 s of bench time, 0.1×–2×, Pause; values drawn
  between the last two steps), `bench_view.gd` (the bindings: anim, the display's face text and backlight, a tag
  over the terminals, flow, heat and pressure), `run_panel.gd` (Run, in the properties' place: machine commands, a
  slider per `set` op, Pause and speed, readouts, machine states, alarms with Acknowledge, the faults as toggles, the
  last refusal's sentence), `views.gd` (materials, X-ray, cutaway, section, flow particles). Start is refused with
  the data's `why` when the machine stands apart beyond `run_exploded`. The display cover's face is a ring round
  its window (the plant's drum end unchanged), and glass the generator marks `glass` is drawn see-through, so the
  LCD reads through it.
- **Reviews' fixes:** the flow's particles rest while the machine stands apart (its path is in the machine's frame);
  a display shows the words of an active alarm whose `where` it is ("Over range"); the face labels and the
  see-through glass go with what the cutaway or section removes (`ws_xray` knows no planes); a rotor whose `anim` has
  no travel turns at its value in revolutions a second, added up over bench time; a flow path is at most 8 points
  (the builder refuses more). `lamp` and `sound` bindings are checked but not yet drawn in the Workshop (the
  transmitter has none; K4b's turbine brings them).
- **From the adversarial review:** a fault with no `repair` stays shown as made (the engine ignores its repair);
  sliders follow the model when not dragged; the Run panel offers the bench's other ops (open, close, a trip's reset)
  and **Restart the bench**; the "stands apart" refusal covers every machine command that leaves the machine's first
  state; the validator reserves the clock values' names (as the app's loader does), refuses two `anim`s on one
  component and two `lit` values on one face; heat and pressure colours go to the shader in linear colour; a kept
  component's fastener groups ride with it through the cutaway; X-ray off leaves what Isolate hid hidden; the
  Workshop's material copies are made afresh at each entry. Left: a `rotate` anim turns about the component's pivot
  (a generator puts a moving piece's pivot there); the engine's input and event lists grow while a machine is open.
- **Shaders:** `ws_lit` is `weathered.gdshaderinc` with `#define WS_LIT` (the plant's shader compiles exactly as
  before: the hooks are preprocessor blocks): a discard by the cut planes (`ws_cut.gdshaderinc`, shared with
  `ws_cap`), no weather, the heat and pressure colour and the selection's glow as instance uniforms (`ws_ramp`,
  `ws_sel`; three with `ws_keep`). The selection no longer swaps materials. `ws_cap` (unshaded, `cull_front`, the
  same planes; flat, darker, hatched; its colour the material's tint, its texture's mean, its vertex colour) is the
  next pass of solid components' materials only while a cut or the section is on. The X-ray is `ws_xray` in yellow,
  on the kind's `xray_all` or on the selected part's subassembly. `ws_flow` draws 48 quads per path (a third on
  `lean+vis`), placed along the path in the vertex shader from uniforms (the path's points and lengths, the phase
  the app advances by bench time). Pre-warmed twice as K2's ghost: in the plant's world after its first walkable
  frame (ws_lit and ws_cap plain and instanced, discarding every fragment; ws_flow collapsed), and in the machine's
  first frame (the cap pass on with nothing cut, every flow at full density and no strength, the labels with text).
- **The walk** keeps its 3 minutes: the K1 and K2 phases shortened, the bench running all the while at 2× (the supply
  on, the pressure swept from −1 to 12 bar and back every 40 s), then the X-ray, the cutaway, a section swept across
  the machine, each fault made and repaired, Stop.
- **Measured** on the Note 9 (`lean+vis`, a test-signed release build of this branch, a cool start at 25.8 / 27.3 °C,
  installed fresh so the pipeline cache was empty; alone / in a LAN session with the laptop hosting): first entry
  4.77 / 4.47 s (≤ 5.0 s: K2's was 2.2 s; the machine's first frame compiles 14 surface and 10 specialization
  pipelines, the K3 variants with the machine's own), again 48 / 47 ms (≤ 2.0 s); back to the plant 16–44 / 12–44 ms;
  **no pipeline compiled after the machine's first frame**; no frame over 100 ms (the longest 42 ms); 99.93 % of
  frames at ≥ 30 fps, mean frame 19.41 / 18.96 ms, 91.3 / 93.8 % of frames shown at 60 fps (one refresh each); peak PSS
  859 / 876 MB; the bench step 0.123 / 0.105 ms mean (≤ 0.3 ms; the longest single step 0.5 / 2.0 ms). The laptop
  (Mobile renderer, an empty cache) likewise compiled nothing after the machine's first frame. Draw calls: 36–63 in
  the views K3 adds (the cut faces' pass included); the **pile assembly of K2 reaches about 510** on both the laptop
  and the phone, the same in K2's own build (measured on the laptop from main), over §8's 300: found here, not changed
  by K3. The APK (test-signed, with voice) is 121.1 MB; K3's own files (scripts, shaders, the bench file) are about 40 KB before compression.

**As built (K3 follow-ups, 2026-11-03).**
- **Draw calls:** the pile's ~510 were the 2D step sentence, not the 3D: an outlined, wrapped Label in the panels'
  canvas layer cost about two draw calls a letter (a long assembly step ~440; the 3D view drew 30 objects). It now
  draws on a canvas layer of its own just above the Workshop's (the same words, place and look), which follows the
  panels' visibility: the walk's most in any view is 58 on the laptop (from 515) and 59 on the Note 9 (from ~510).
- **The bench's logs:** the bench clock drops the engine's `inputs` log (nothing in the Workshop reads it) and the
  events both its readers have read, and past 512 the oldest; the engine itself is unchanged (it reads events only
  within a step, and the digest leaves the logs out). A test runs the transmitter's bench for 20 minutes of bench time
  beside an engine that keeps everything: the logs stay within 64 entries and every value and the digest agree bit for
  bit. The vectors are untouched.
- **First entry:** the plant's warm-up (§7.1) also loads each kind's machine on a worker thread, one at a time, and
  holds it hidden in the plant's world for 30 frames in the Workshop's own materials (ws_lit with the cap as its next
  pass, the glass) with its parts' ghosts, so their surface pipelines are made then rather than in the machine's first
  frame; not while the tier probe runs or a Workshop shows, nor on the Compatibility renderer (`kinds_warmed`; `warmed`
  stays the ghost's). The Workshop walk's first entry waits for it (`cold=1`: at once, as K3 measured). Laptop (Mobile
  renderer, an empty cache): first entry 1,641 ms at once, 696 ms after the warm-up. **The Note 9** (`lean+vis`, a
  test-signed release build of this branch without the lightmap's bake, fresh installs so the pipeline cache was
  empty, cool starts at 23.8 / 25.5 °C, SAMPLE=1; with the warm-up / `cold=1`): first entry 407 ms after the walk
  waited 7.9 s for the warm-up / 4,285 ms at once (≤ 5.0 s; K3's was 4.77 s); the warmed machine's first frame still
  compiled 1 surface and 10 specialization pipelines (the cold one 14 and 10); again 63 / 57 ms; back to the plant
  13–16 / 12–44 ms; no pipeline compiled after the machine's first frame; no frame over 100 ms (the longest 58 / 41
  ms; the frame rule passes, 0 caused by the app); 99.84 / 99.90 % of frames at ≥ 30 fps, mean frame 19.40 / 19.41
  ms, 89.9 / 91.2 % shown at 60 fps; peak PSS 851 / 834 MB; the bench step 0.119 ms mean in both (the longest 1.0 /
  0.5 ms).

**As built (K4a, 2026-11-03).**
- **The steam turbine** for the plant's first instance (the HP turbine): 54 components and 3 fastener groups (57 guided steps), 15,296
  triangles (§8's 120,000), its insides and simplifications in the kit README. The joint's 44 studs and the coupling's
  12 bolts replace the plant's stand-ins (`split`); the inner casing's studs are `hidden`.
- **Two calls (2026-11-03):** the coupling's bolts keep `beyond` (what they join is the next rotor, another machine),
  as §4.4 says. The joint flanges' stand-in is checked against its split pieces together (1.33 times its triangles,
  inside the 1 to 1.5 band), which is looser than a check per piece: one piece could be thin while another is thick
  and the set still pass.
- **The plant's warm-up waits while the Workshop shows** (§7.1): its hidden meshes' pipelines are made on the main
  thread as they enter the plant's world, so a trainee in the Workshop when it came due (4 s after the first walkable
  frame) got a hitch. The turbine's walk with `cold=1` found it: 1 surface pipeline after the machine's first frame and
  a 167 ms frame on the Note 9 (47 to 74 ms on the laptop). `tests/test_workshop_run.gd` opens the Workshop before the
  warm-up is due and checks it waits.
- **Draw calls:** at most 95 in any view of the walk, on the laptop and the Note 9 (the cut faces' pass included);
  before main's step words moved to their own layer (the K3 follow-ups) the pile's view reached 421.
- **The Note 9** (`lean+vis`, a test-signed release build of this branch with main merged, without the lightmap's
  bake, fresh installs so the pipeline cache was empty, cool starts at 26.4 / 28.3 °C, SAMPLE=1; with the warm-up /
  `cold=1`): first entry 163 ms after the walk waited 8.9 s for the warm-up / 4,023 ms at once (≤ 5.0 s); the warmed
  machine's first frame compiled 7 specialization pipelines and no surface one (at once: 12 and 7); again 67 / 81 ms;
  back to the plant 17–19 / 18–62 ms; no pipeline compiled after the machine's first frame; no frame over 100 ms (the
  longest 57 / 47 ms; the frame rule passes, 0 caused by the app); 99.79 / 99.89 % of frames at ≥ 30 fps, mean frame
  19.64 / 19.68 ms, 88.5 / 89.5 % shown at 60 fps; peak PSS 868 / 886 MB. The warm-up itself (every kind's machine
  held in the plant) made one frame of 0.71 s in the plant in the start's first seconds, as the transmitter's alone
  did (0.70 s, the K3 follow-ups).
- **Not covered by the walk:** its guided phases give each step 1.4 s (taking apart) and 1.6 s (from the pile), which
  leaves 14 of the turbine's parts loose when the 30 s are up, so the last steps' views are not walked.
- **Package:** the APK (test-signed, with voice) 121.4 MB, 0.3 MB over main's at f1f24bf7. Pictures: the wiki's Workshop page.

### 6.5 Plant values to bench inputs (K6, the mirror)

Opening the Workshop from the live plant can mirror that equipment's current state, read only. Each bench file's
`mirror` lists bench values and where each comes from in the plant, by the equipment's own bindings, so no plant value
name is written in bench data:
- `{"bind": "show"}`: the value the plant's `show` binding of that code displays (a transmitter's pressure);
- `{"bind": "anim", "channel": "shaft"}`: the value driving that anim channel (a turbine's speed, a valve's position);
- `{"bind": "lamp", "kind": "running"}`, `{"bind": "sound", "id": …}`: likewise;
- `{"machine": true}`: the equipment's machine's state (by its `kks`), mapped onto the bench machine's states by name.

In a mirror the bench steps as usual but each mirrored value is overwritten after step 2 by the plant's, its ops and
faults are not offered, and the panel says "Mirror of `<code>`, read only". In single play the mirror **freezes at the
moment the trainee left** (the user, 2026-11-02): the plant is paused, and the plant does not run while a mirror is
open; in a session it follows the plant live. The overwrite is an engine
addition (both engines, vectors) made in K6.

**As built (K6, the mirror, 2026-11-14).**
- **The entries** (`ref/plant3d_bench.py`, checked with the file): a machine is mirrored into its `<id>_state`
  (`{"machine": true}`, with an optional `else`: the state it stands in when no plant machine runs the code: a
  transmitter's loop supply, on); a value only if it is a `state` or a `lag`, `ramp`, `integrate`, `wrap`, `hold` or
  `latch` node (written after step 2, a stateless node would be made again from what it reads before anything read
  it; a timer's and a delay's counts are kept outside their value); each value once. The plant's machine is the one at
  the code, else the one at the code of a value the code's bindings read (the steam turbine's second casing shows the
  shaft's speed, whose code runs `st_start`). A plant value's unit is made the bench's: bar from kPa, MPa, mbar,
  kPa(a) and bar(a) (gauge: less 1.01325 bar) and metres of water (9.80665 kPa/m); any other pair is not mirrored, and
  the panel says so (`mirror_sources`; the app's `workshop/mirror.gd` gives the same answers, both tested).
- **The engines** (`ref/plant3d.py`, `sim/engine.gd` `set_mirror`, not an input: no log, no event, not in the
  digest): after step 2 each mirrored machine standing in another state enters the plant's (its `set` applied, the
  event's cause `mirror`), then the values are written. Two rules the spec left open, settled here: **a mirrored
  machine moves with the plant only** (its sequence's moves, commands, trips' and interlocks' actions on it are not
  taken), and **while a machine is mirrored the bench's trips are held** (not counted, not latched): the plant's
  protection trips the plant's machine and the mirror brings its state; a bench trip from a value the mirror can't
  reach (the gas turbine's flame, below) would otherwise trip a running mirror. `plant3d-v1.json`, `plant3d-v2.json`
  and `plant3d-realism.json` are byte for byte what they were; `plant3d-bench-v1.json` gains four mirrored runs (the
  transmitter, both turbines, the synthetic kind: followed live, a trip and a command that can't move the mirrored
  machine, the mirror ended) and eight rejects; both engines run them bit for bit.
- **The content:** the transmitter mirrors its display's pressure into `p_applied` and its supply `else` on (all 34
  of the plant's transmitters: 25 in bar, 6 filters' head loss in metres of water, 3 condenser vacuums in kPa(a)); the
  steam turbine its sequence's state, the shaft's speed and the steam's flow (from the inlet's sound; 30MAB10 has no
  steam sound: its flow is not mirrored); the gas turbine its sequence's state and speed.
- **Left open (the user's call):** the mirror reads only what the equipment's bindings show, so the bench's other
  values stay its own. The gas turbine's flame is on none of 10MBA10's bindings: a running gas turbine is mirrored at
  its speed and state with the bench's combustor unlit (cold in the heat view, its flame alarm raised). The steam
  turbine's load (MW) likewise stays the bench's 0. Ways on: a plant binding that carries the flame, or letting a
  made bench's source name plant values for its mirror (bench data would then hold plant names).
- **The app:** the card's Workshop opens the mirror (`ui.open_workshop(kind, code, true)`; the settings' list, a
  manual's link and a failed part open the free bench). The Run panel shows "Mirror of `<code>`, read only", what
  comes from the plant ("as you left it" or "as it runs") and what is not mirrored and why; no slider, command, fault
  or restart; one made anyway is refused. Pause, speed, readings, states and alarms (with Acknowledge) stay. **Leave the mirror** (an addition: the card is the main way in, and a powered transmitter or a running turbine can't be taken apart) gives the free bench from its start state, the plant still paused behind it. Single
  play reads the plant once (the plant is paused while the Workshop shows); a session reads it before every bench step
  (`bench_clock.mirror_live`). A mirrored machine that runs is not taken apart. `walk=workshop mirror=CODE`.
- **Tests:** `tests/test_plant3d_workshop_bench.py` `Mirror` (every transmitter, both turbines, the units, every plant
  state the bench's, the overwrite's rules), the bench vectors in both engines (`GdscriptBench`),
  `apps/plant3d/tests/test_workshop_mirror.gd` (from the card: the plant's values on the bench, read only, frozen in
  single play with the plant paused and not stepping, followed in a session with the plant running, the units, the
  turbines, the free bench from elsewhere; the app's resolution the reference's).

### 6.6 The steam turbine's bench (K4b)

**As built (K4b, 2026-11-03).**
- **Made, not written.** `tools/plant3d/workshop/make_bench.py` takes from the generated `model/st.json` (in memory, as
  `make_content.py` makes it) the start-up machine `st_start` (as `turbine`), five trips (lube oil pressure low-low two
  out of three, overspeed, axial displacement, bearing vibration, wet steam) and the generator breaker's opening by
  the turbine's protection (else the grid would hold a tripped rotor at full speed), four alarms, the excitation's and the
  breaker's ops with their synchronising permissives, the speed bias, each trip's reset, and 134 named values (the
  governor and the rotor's speed, the soak timer, the critical-speed band's vibration, the casing's warmth and the
  steam-to-casing match, the superheat, the synchronising check, the load), renamed by stripping `st_` (a machine's
  and a trip's own values follow their renamed ids) and with each code mapped onto a component or `bench` (`at`).
  The bench source (`steam_turbine.py bench_source()`) adds only what the plant's other areas give the turbine: the
  steam at the stop valves (two sliders, 40–130 bar and 400–565 °C), its saturation temperature (NISTIR 5078's table),
  the lube oil's pressure, the turning gear, the condenser's vacuum, the grid; and the steam path the plant's model
  doesn't have (its stages). The tool refuses a read value neither taken nor defined, a code with no place, a name
  taken twice or defined twice, an unknown piece, and orders the values so that every stateless node follows what it
  reads (the plant's order kept wherever it can be). `tests/test_plant3d_workshop_bench.py Turbine` checks the
  sequence, its sentences and five values are the plant's own, that a change to the plant's soak is a change to the
  bench, and the tool's refusals.
- **The steam path:** every stage's pressure proportional to the flow (the downstream is a turbine too; the first
  stage's pressure is the load's measure, NRC 7.3.2): 90 bar after the control valves and 25 bar at the exhaust at
  full flow (70 kg/s), an equal ratio across each of the eight stages, never below the condenser's; the temperature
  falling with the pressure, T2/T1 = (p2/p1)^0.2, from the inlet's (the plant's lag of the steam's); with no steam
  each stage is at the casing's temperature. The stop valves open in half a second and shut in a tenth (a trip); the
  control valves follow the flow.
- **The start:** a hot start (the casing at 420 °C, the steam at 500 °C: matched within the plant's 150 K), so Roll
  is taken at once; then the plant's sequence: 800 rpm, the 300 s soak, through the critical speeds (1,600–1,900 rpm),
  full speed no load, excitation at 95 %, the breaker inside ±10° and 0.1 Hz (the bias slips the phase), loaded.
  At the Run panel's 2× that is about 4½ minutes to full speed.
- **Drawn:** the rotor's `shaft` at 50 rev/s per unit speed (the plant's binding), turning right-handed about the
  axis against the steam's way, as the generator's blades are made for (`ST_TURN`), drawn at most 0.4 rev/s
  (`MAX_DRAWN_RPS`: faster, at 30 frames a second its rows of 34 blades seem to stand or turn back; the speed is on
  its tag, in the readouts and in the tone); the stop discs and control plugs
  are moving pieces of their own (`translate`, Workshop only: plant mode unchanged); seven flow paths (each chest's
  inlet past both seats, four lines along the blade path, the exhaust), coloured by pressure; every blade row, carrier
  and inner casing half and both chests coloured by temperature (**Heat**) or pressure (**Pressure**), two new
  toggles beside Flow, with the legend of the one shown in the Run panel (a component bound to both shows heat while
  both are on); the speed on a tag at the front pedestal.
- **Sound:** `blade_pass` (new, synthesised: 34 moving blades at 50 rev/s, 1,700 Hz and its harmonic, the steam's
  pink noise), its gain and pitch from the speed, and `steam_rush` at the chest by the flow; played by `bench_view.gd`
  from the plant's sound files while the Workshop shows (not paused, not when the plant's sounds were muted).
- **Faults:** the governor (its set point 15 % high: an overspeed trip at no load), thrust bearing wear (axial
  displacement; the bench's own wear, which goes back once the bearing is renewed: the plant's only grows), a rub (vibration), the lube oil pump lost, the steam's temperature falling 200 K (wet steam); each
  trips by the plant's own trip and is reset from the Run panel once its cause is gone; the breaker's trip too (Roll
  is refused while any is latched: left latched, it would not open the breaker at the next trip on load). The
  readouts carry the phase angle and the slip that synchronising reads (the steam's pressure and temperature are on
  their sliders).
- **Running taken apart:** as K4a's data says, only with the lagging off; Start is refused otherwise with its sentence.
- **Vectors:** `plant3d-bench-v1.json` gains two runs of the committed file's model: the committed one (rolled to its
  soak, the refusals on the way, a rub's trip, its reset, the lube oil lost; 900 steps) and the same with the soak cut
  to 10 s, the vector's only change (run up, synchronised, loaded, tripped on load by a rub and the breaker opened by protection; 2,599 steps); both
  engines bit for bit (`GdscriptBench`). The file is 14.2 MB (the transmitter's and the synthetic kind's 0.66 MB).
- **The walk:** each machine started with the first command its resting state takes (the turbine's Roll); every 0.2 s
  it switches on what it may (an op that sets something from 0 once its permissives hold: the excitation, the
  breaker); the sliders swept as before. The turbine's walk was measured with `bench_speed=6` (an option of the walk, past
  the trainee's 2×, logged; the default stays 2×), so that the plant's 300 s soak still lets it reach full speed
  within the 3 minutes (since the polish after K4b, which starts the bench only at 118 s, 20×; K5b's walk 30×).

- **The warm-up (K4b):** the ghost's and K3's warm pieces enter the plant's world one a frame, and a piece moved out of
  a kind's scene is no longer owned by its root (freeing the app mid warm-up crashed a full test run).
- **Measured** on the Note 9 (`lean+vis`, a test-signed release build, cool starts at 29.3 °C, installed fresh,
  `bench_speed=6`), with the warm-up: first entry 406 ms (≤ 5.0 s), again 169 ms (≤ 2.0 s), back to the plant
  14–21 ms; no pipeline compiled in the walk; no frame over 100 ms in it (the longest 40 ms); 99.88 % of frames at
  ≥ 30 fps, mean frame 19.85 ms, 88.5 % at 60 fps; peak PSS 1,116 MB (≤ 1.5 GB); at most 103 draw calls (≤ 300);
  the bench step 0.171 ms mean (≤ 0.3 ms; the longest 1.24 ms); every guided step walked (0 loose); loaded before
  the faults. The kernel reclaimed in 1.34 % of the samples (over the 1 % at which the reclaim rule judges no walk).
  With `cold=1` (the Workshop at once, 80 ms after the plant's first frame): first entry 4.17 s (≤ 5.0 s), again
  305 ms; 99.90 % at ≥ 30 fps, mean frame 19.94 ms, 89.1 % at 60 fps; peak PSS 1,123 MB; no reclaim. Its first way
  back to the plant took 1.52 s (§8: ≤ 1.0 s): the plant's own pipelines (one surface, seven specialization) compiled
  in its first frame back, the plant having drawn barely a frame before the Workshop opened; the second way back
  took 14 ms. The APK (test-signed) is 145.2 MB, of which K4b's own files are about 120 KB (the blade-pass sound 93 KB,
  the bench file 24 KB); K4a's was 121.4 MB, before main's other milestones.
- **Was not fixed in K4b (fixed after it, below): the plant's 0.7 s frame at the start.** 4.8 s after the first frame (the warm-up's time) one plant
  frame takes 705 ms (715 ms in the first run) and 8 surface pipelines finish in it. It is not the kinds' warm-up
  (#325 spread it; it stayed) nor the ghost's and K3's pieces entering together (one a frame now; it stayed): the
  Workshop's own shaders' first compilation holds the frame. The frame rules don't judge the first seconds; §8's
  Workshop rules hold. Left as a question for the user (moving that warm-up behind the start's loading, or baking
  those shaders).

**After K4b (the Workshop's polish, 2026-11-07).**
- **The 0.7 s frame: the Workshop's shaders baked at export.** The export's shader baker compiles only the shaders of
  the materials it finds in the exported resources (Godot's `shader_baker_export_plugin.cpp`: a shader file alone is
  not baked), and every Workshop material is made by script, so the four `ws_*` shaders were compiled on the phone,
  the first time in the plant's warm-up. The content build now saves one material per shader file the app ships
  (`builder/shader_mats.gd`, `built/shaders/`), the walking directions' and the weather's too, which were made by
  script as well; `tests/test_launch.gd` checks every shader file has one. The release APK carries 32 baked
  versions of the mobile scene shader instead of 20. **Measured on the Note 9 (2026-11-08): the frame stays.** The
  polish's own build (`walk=workshop`, the steam turbine, a cool start at 29.9 °C) had a 692 ms frame 4.82 s after
  the first frame with 8 surface pipelines in it; K5a's build with main merged 686 ms at 4.74 s (8); main before the
  polish (AG2's build) 730 ms at 4.82 s (8). Baking the shaders' source does not take away the driver's pipeline
  builds, which are what holds that frame (decision 0072, "Measured after K4b"). Still a question for the user:
  move that warm-up behind the start's loading screen, or leave it.
- **A running machine is not taken apart** (§3): while the bench's machine is out of its resting state the slider
  (towards apart), the selected subassembly, handling and both guided modes are refused with the kind's reason
  (§4.7 `open_running`); once it is stopped and at rest (the turbine's standstill, below 1 % speed on its turning
  gear; the transmitter's loop supply off) they are allowed again. The user's decision (2026-11-07): a powered
  transmitter's terminal cover may come off (to measure the loop current or connect HART, in a non-Ex area); its
  electronics, sensor module and flange need the loop supply off; a turning machine is opened only at standstill on its turning gear. Putting it back together, Reset, hiding
  and the views stay allowed. Starting a machine taken apart is still decided by `run_exploded` (§4.7). The walk
  (§8) therefore takes the machine apart first and starts it once it stands assembled again, at 118 s.

**As built (K5a, 2026-11-08).**
- **The gas turbine** for the plant's first instance, with its shaft line: 84 components and 2 fastener groups (86
  guided steps), 27,868 triangles in the built scene (§8's 120,000). The inlet plenum and bellmouth, the front bearing (journal halves,
  thrust bearing), the compressor casing halves with the plant's 40 studs (`split`), the inlet guide vanes and 8
  compressor stages, the discharge casing halves, 12 cans (end cover, six fuel nozzles, liner, transition piece each),
  the fuel gas manifold, the turbine shell halves with 3 stages of nozzles and buckets, the rear bearing, the exhaust
  frame and diffuser, the rotor with its 12 coupling bolts (`beyond`). The plant byte for byte unchanged
  (`test_kit_frozen`). Its data (`tools/plant3d/workshop/gas_turbine.py`) cites a public source per subassembly; the
  guided order is a major inspection's take-apart reversed. Simplifications (8 stages for an F class's 18, flat-plate
  blades, the rear bearing inside the shell, the thin exhaust, manifold and bleed pipes) in the kit README. No bench
  yet (K5b): the walk's run phases find no model.
- **The Note 9** (`lean+vis`, a test-signed release build of this branch with main merged (the polish's baked shaders
  in), fresh installs, SAMPLE=1, batteries at 27.9 / 29.2 °C; with the warm-up / `cold=1`): first entry 212 ms after
  the walk waited 13.1 s for the warm-up / 4,249 ms at once (≤ 5.0 s); again 101 / 436 ms; back to the plant 17–27 ms
  / 1.68 s the first time (as K4b's 1.52 s: the plant's own pipelines, one surface and seven specialization, in its
  first frame back, the plant having drawn barely a frame before the Workshop opened; §8's 1.0 s is met from the
  second time on); no pipeline compiled after the machine's first frame; no frame over 100 ms in the walk (the longest
  74 / 56 ms; the frame rule passes, 0 caused by the app); 99.85 / 99.81 % of frames at ≥ 30 fps, mean frame 19.90 /
  19.84 ms, 88.3 / 90.0 % shown at 60 fps; peak PSS 1,119 / 1,099 MB (≤ 1.5 GB); at most 135 draw calls in the
  Workshop (≤ 300); every guided step walked (0 loose). The kernel reclaimed in 0.59 / 1.07 % of the samples (the cold
  walk just over the 1 % at which the reclaim rule judges no walk, as K4b's warm one was). The plant's 0.7 s frame at
  the start is still there with the baked shaders: 686 ms at 4.74 s after the first frame, 8 surface pipelines in it.
  The APK (test-signed) 147.3 MB; the gas turbine's scene is 606 KB.

### 6.7 The gas turbine's bench (K5b)

**As built (K5b, 2026-11-08).**
- **Made, not written.** `make_bench.py` takes from the generated `model/gt1.json` the start-up machine `gt1_start`
  (as `turbine`): the SFC cranks it to 25 % speed, the HRSG purge (480 s), coasting to 15 %, fuel and igniters, the
  flame detected, the run-up with the SFC, the SFC off at 70 %, full speed no load, synchronised, loaded; eight trips
  (lube oil pressure low-low two out of three, flame failure, exhaust temperature high-high, exhaust spread
  high-high, overspeed, bearing vibration, compressor surge, lube oil temperature) and the generator breaker's
  opening by the turbine's protection, eight alarms, the DC emergency oil pump's interlock, the turning gear's,
  excitation's and breaker's ops with their permissives, the speed bias and the load set point, each trip's reset,
  and 182 named values (the speed and the governor, the purge's timer, the lube oil's pumps and switches, the fuel
  gas, ignition and the flame's latch, the load and its capacity by the ambient air, the fuel's demand and valves,
  the exhaust's twelve thermocouples and their spread, the air's flow, the compressor's discharge pressure and its
  surge detection, the vibration, the synchronising check), renamed by stripping `gt1_`. The plant's filter and
  compressor-fouling chains are `wear` nodes, which a version 1 bench may not hold (§6.1): the bench gives their
  results as a clean filter and clean blading (`dp_f`, `foul_f` at 1, no runbacks), and takes the plant's capacity
  formula over them. The source (`gas_turbine.py bench_source()`) adds what the plant's other areas give the GT: the
  ambient air (a slider, 0–50 °C), the closed cooling water, the grid, the HRSG's drum-level and feedwater
  permissives, no compressor wash running; and the gas path the plant's model doesn't have. `make_bench.py` needed no
  change. `tests/test_plant3d_workshop_bench.py GasTurbine` checks the sequence, its sentences and seven values are
  the plant's own, that a change to the plant's purge is a change to the bench, the tool's refusals, and the runs.
- **The gas path** (sources: NASA Glenn's compressor and power-turbine thermodynamics pages, GER-3434D): the
  compressor's eight drawn stages share the plant's discharge pressure (1 bar at the bellmouth, 11 bar at full speed
  no load, 15 at base load) in equal ratios, each stage's temperature from the ambient air's by NASA's relation with
  an efficiency of 0.87, T/T0 = 1 + (r^0.286 − 1)/0.87 (about 370 °C at the discharge at full speed, 30 °C ambient);
  the turbine's three stages share the expansion down to 1 bar at the exhaust, T/Tin = 1 − 0.89 (1 − (p/pin)^0.248)
  for the hot gas (γ 1.33). Every turbine temperature comes from **one chain**, so the stages stay in order through
  ignition, a trip and the coast-down: the hot gas's, worked back from the plant's exhaust temperature (and so with
  its thermocouples' lag, 20 s up and 60 s down: the colours are the gas path's as those thermocouples see it)
  through the expansion from each stage to the exhaust, the last stage the plant's exhaust temperature itself; or,
  where hotter, the compressor's discharge air expanded from the first nozzles (no flame). The **turbine inlet
  temperature** (`tit`, at the first nozzles, the combustor's outlet) is the larger of the hot gas's and the discharge
  air's: about 780 °C at full speed no load and 1,290 °C at base load with 600 °C at the exhaust. It is not a maker's
  "firing temperature" (GE's is at the first-stage buckets' inlet, after the first nozzles' cooling air has mixed in,
  some 100 K lower); 1,290 °C is what the plant's 600 °C exhaust and 15 bar give through this expansion, within the
  1,100–1,400 °C of heavy-duty E and F machines. A test steps the start and a flame-out and finds the inlet never
  colder than the first stage, each stage never colder than the next, the last stage the exhaust's. **The purge's
  heat:** the plant's discharge pressure rises linearly with the speed (1 + 10 × speed bar, plus 4 with load), so at
  the cranking speed (25 %) the compressor gives 3.5 bar and about 180 °C at its discharge through the purge; a real
  compressor's pressure ratio falls about as the square of the speed (nearer 1.6 bar there). The bench takes the
  plant's figure. Power laws are tables of the discharge pressure (the
  engines have no power node; 20 points from 0.5 to 20 bar: a surge at standstill takes the plant's discharge to
  0.5 bar, where the stages run the other way, each still between its neighbours, the last stage the discharge
  itself; the bench starts the plant's discharge-pressure lags at 1 bar, not the plant's 0). A test makes a surge at
  standstill, cranking, in the purge and coasting, and finds the pressures in order along the path. The fuel's flow is the plant's fuel valve times the base
  load's heat input (the plant's 9,750 kJ/kWh at 250 MW) over methane's lower heating value, 50.0 MJ/kg (NIST's
  enthalpy of combustion less the water's vaporisation): 13.5 kg/s at base load.
- **The start:** at standstill on its turning gear, the AC lube oil pump running (the oil pumps' own ops stay off
  the bench; the DC pump starts by the interlock). Start, and the plant's sequence runs: about 12¼ minutes of bench
  time to full speed no load, of which the purge is 8 (about 6 minutes at the Run panel's 2×). The **speed bias**
  (the plant's op, ±1 %, for synchronising) has no permissive in the plant's model: moved below zero while the SFC
  cranks, it holds the speed under the 24.5 % the sequence waits for, and the start waits until it is moved back;
  moved 1 % below zero in the run-up after the SFC is off, it holds the speed at 99 %, under the 99.5 % that full
  speed no load waits for (0.5 % below lands just on it). The plant's model behaves so; the bench takes it as it is
  (`make_bench.py` adds no permissive of its own), and `GasTurbine.test_a_speed_bias_below_zero_holds_the_sequence`
  pins both, so a change to the plant's model shows.
- **Drawn:** the rotor's `shaft` at 50 rev/s per unit speed (the plant's binding), right-handed about the air's way
  (`GT_TURN`, as the blades are made for), at most `MAX_DRAWN_RPS`; 16 flow paths (§6.1's limit; `_gt_flows`, Workshop
  only): the air down the plenum into the bellmouth, four lines along the compressor and four along the turbine (by
  pressure), the fuel from the gas ring down a pigtail to two cans' nozzles (by the gas's pressure), the flame along
  three liners and their transition pieces to the first nozzles (in the turbine inlet temperature's colour), two
  out of the diffuser; one of each set lies in the cutaway's quarter. Heat and Pressure colour the inlet guide vanes,
  the compressor's casings, stator rows and blades (the middle stage's air), the discharge casings, every liner and
  transition piece (the turbine inlet temperature), the nozzle rows (the gas entering each stage), the buckets (leaving it), the turbine
  shell and the exhaust (96 colour bindings of the bench's 115; the cans' casings, under the X-ray, are left their own
  colour). The speed on a tag at the front bearing housing, the exhaust temperature on the exhaust.
- **Sound:** `compressor_pass` (new, synthesised: the drawn rows' 40 blades at 50 rev/s, 2,000 Hz and its harmonic,
  the buckets' 3,000 Hz, 50 Hz, the air's pink noise), its gain and pitch from the speed; the plant's `combustion`
  roar by the flame, `exhaust_rumble` by the air's flow and `sfc_whine` while the SFC cranks.
- **Faults:** a flame-out (flame failure), the governor (its set point 15 % high: overspeed), exhaust thermocouple 7
  reading 80 K low (the spread), a compressor surge, a rub (vibration), a lube oil leak (lube oil pressure), each
  tripping by the plant's own trip and reset from the Run panel once its cause is gone; the AC lube oil pump lost
  (the DC pump takes over by the plant's interlock: no trip) and the fuel gas pressure low (a start is refused).
- **A turning machine is not opened, and runs only closed** (the user's decision of 2026-11-07 and the steam
  turbine's rule, §4.7): `open_running` allows nothing while it turns ("Not opened while the rotor turns: stop it,
  let the rotor come to standstill on its turning gear, then open it up"; the steam turbine's says the same since
  K5b's review), and `run_exploded` allows nothing either: the casings hold the air and the gas, the bearings the
  rotor, and a gas turbine has no lagging to leave off.
- **Vectors:** `plant3d-bench-v1.json` gains two runs: the committed file (cranked to its purge, the refusals on the
  way, the AC oil pump lost and the DC pump started by the interlock, a rub's trip in the purge, its reset refused
  and taken, a start refused while it coasts, the fuel gas low; 680 steps) and the same with the purge cut to 10 s,
  the vector's only change (fired, run up, synchronised, loaded for 10 s and tripped on load by a flame-out, the
  breaker opened by protection; 2,928 steps, most of them the plant's run-up, which no input shortens); both engines
  bit for bit (`GdscriptBench`). The file is 31.4 MB (14.7 MB before).
- **The walk:** the turbine's start is the first command its resting state takes, the excitation and the breaker
  switched on as they may (K4b). Two changes, both generic: a slider whose value a machine's states set (the sequence
  owns it: the speed bias, zeroed at standstill) is left alone until that machine waits for the trainee
  (`bench_clock.waits_for_trainee`: full speed no load; a slider's input counts as the trainee's), then held 1 % of
  its range above its middle (a slip of 0.01 Hz, which brings the phase slowly round into the synchronising window
  at any frame rate; a sine passed through it too quickly at 20 frames a second) and put back to 0 when that ends;
  swept from the start, the bias held the gas turbine's cranking short of the 24.5 % its sequence waits for. The walk
  switches on what it may every frame (at 30× a frame is 1.5 s of bench time). And with `bench_speed` past 2× (held
  to at most 60×) the walk lets the clock step as many steps a frame as that speed needs at 15 frames a second
  (`max_steps`; the clock's own 4 hold the trainee's 2× down to 20 frames a second), so a slower frame doesn't slow
  the run; loading or restarting a kind puts the clock back to its own 4 and the trainee's speeds. The gas turbine needs about 7,330 bench steps to full speed no
  load: the walk is measured with **`bench_speed=30`**, which gets it there at about 143 s, 12 s before the faults at
  155 s. `tests/test_workshop_run.gd` walks the running part at 30×, frames jittered from half to one and a half of
  their mean, on the gas turbine at 60 and 20 frames a second and on the steam turbine (each synchronised and loaded
  before the faults), and on the transmitter (its slider still swept, at the clock's own 4 steps a frame).
- **Pictures** (the gallery, `kit/gallery_workshop.gd`): a machine with a sequence is now run on until it waits for
  the trainee (`bench_clock.all_wait`, the walk's helper), at most 1,500 s of bench time, so both turbines are
  pictured at full speed; only the transmitter's applied pressure is moved for the pictures (the gas turbine shows
  its 30 °C ambient, the steam turbine its steam at the start's).
- **Flow particles sized to the machine** (`views.gd flow_size`): 0.2 % of the machine's longest side, from the
  transmitter's 4 mm to at most 5 cm, so that the gas turbine's (25 m) show from where it is seen whole; the steam
  turbine's grow from 4 mm to about 2 cm.
- **Measured on the laptop** (this branch, `--walk=workshop --kind=gas_turbine --bench_speed=30 --quality=lean+vis`
  on the private display, Forward+): first entry 126 ms after the plant's warm-up, again 118 ms, back to the plant
  15–19 ms; 0 guided steps loose; the turbine synchronised and loaded before the faults; no frame over 100 ms (the
  longest 50 ms, p95 17.3 ms); **the bench step 79 µs mean** (the longest 3.2 ms) over 53,998 steps.
- **The Note 9's first run (2026-11-09, at 4c1e5254): 93.77 % of frames at ≥ 30 fps** (rule ≥ 95 %; median frame
  23.7 ms; main's K5a gas turbine walk on the same phone minutes before, 99.75 %). The slow frames were in the
  phases with the whole machine shown and no guided step (assembled, exploded, subassembly, reset: medians of 33–50
  ms), before the bench was started, so not its steps. The cause: `bench_view.draw` asked `ws.assembled()` once
  for each of the 16 flows, and each ask works out every one of the 84 parts' offsets: 3.5 ms of a frame's 4.3 ms
  of drawing the bench on the laptop. Now asked once a frame (and at once when nothing is exploded), `set_ramp`
  writes an instance uniform only when its colour changed, and the ramps work out one colour a value a frame:
  drawing the bench takes 1.1–1.4 ms a frame on the laptop in every phase (from 4.1–4.5 ms), the flows 0.2–0.45 ms
  (from 3.3–3.7), the ramps about 0.4 ms. `test_workshop_run.gd` checks a frame asks once and rewrites no unchanged
  colour. The bench's own steps at the walk's 30× cost the Note 9 about 1.3 ms a frame (168 µs a step, about 7.5
  steps a frame at 40 frames a second; at the trainee's 2× about 0.08 ms).
- **The Note 9 (2026-11-09, at ab0cc104;** `lean+vis`, a test-signed release build, a fresh install, a cool start
  at 27.7 °C, SAMPLE=1, probe=1, `bench_speed=30`): first entry 407 ms after the walk waited 12.8 s for the warm-up
  (≤ 2.0 s; load 82 ms; its frame of 336 ms, the bench's six sound files and 8 specialization pipelines, is inside
  the entry); again 307 ms (load 137 ms); back to the plant 20–22 ms; every guided step walked (0 loose); the bench
  started at 118 s, synchronised and loaded before the faults; no frame over 100 ms in the walk (the longest 45.9 ms;
  the frame rule passes, 0 caused by the app, reclaim in 0.29 % of the samples); **99.80 % of frames at ≥ 30 fps**
  (from 93.77 % before the drawing fix), mean frame 20.10 ms, 87.7 % shown at 60 fps; peak PSS 1,145 MB (≤ 1.5 GB);
  at most 155 draw calls in the Workshop (≤ 300); **the bench step 172 µs mean** (≤ 0.3 ms; the longest 2.3 ms) over
  53,977 steps. The APK (test-signed) 147.8 MB, 0.5 MB over K5a's.
- **Package:** K5b's own files are about 130 KB (the bench file 37 KB, the compressor's tone 91 KB of Ogg Vorbis).

### 6.8 The horizontal pump and the motor (K6, first pull request)

**As built (K6, 2026-11-09).**
- **The motor** (`kit/parts_common.gd motor_h`, one tree for the motor kind and the pump's motor): the stator in its
  finned frame (the winding's end turns inside), the terminal box (anchors `u1`, `v1`, `w1`), the drive-end and
  non-drive-end shields with their bearing housings open to the rotor, the fan with straight radial blades, the fan
  cowl with its grille, the rotor and its two bearings; the drive-end shield's bolts and the cowl's screws. 11
  components, 2 fastener groups, 2,876 triangles (the plant's 724). **Its order is derived from how it is built, not
  from a manual** (the user, 2026-11-09): every step's reason says so.
- **The horizontal pump** (`kit/parts_rotating.gd`, the end-suction branch; the data file names an end-suction pump
  the plant has three of, 900 m³/h, 40 m, 160 kW): the baseplate, the volute hollow round the impeller's chamber, the
  back pull-out unit (the bearing frame, the casing cover with the seal's bore, the shaft, the mechanical seal, the
  inboard and outboard bearings, the end cover, the closed impeller with six backward-curved vanes), the spacer
  coupling, the guard, the plant's 12 casing bolts (`split`), and the motor's full tree from the same helper (the
  user's decision, 2026-11-09). 22 components, 3 fastener groups (25 guided steps), 6,444 triangles (the plant's
  2,482). The guided steps leave the motor standing (the spacer coupling); the explode lifts it first, so that its
  parts come apart above the pump.
- **The plant unchanged:** the pump's casing, scroll, nozzles and bearing frame are one stand-in, the motor's frame,
  end shields and cowl another. The plant's odd-segment caps list their circles' points mirrored: each split face lists
  them as its own cylinder does (`C._face`), and only the cowl's face to the frame keeps the plant's, closed with a seam
  of thin triangles (`C._zip`), so that the outline is the plant's within 1 mm.
- **New check:** `tests/test_workshop.gd _radial_lean`: an impeller's vanes curve back against the shaft's turn, a
  motor fan's blades lean neither way; the same vanes with the turn reversed must fail it.
- **Manuals:** the pump manual's parts list and figures now come from the pump's tree; `comes_with` in a manual of
  several kinds names one kind's parts (the grille with its cowl).
- **The Note 9** (`lean+vis`, a test-signed release build, a fresh install, a cool start at 30.0 °C, `walk=workshop
  kind=pump_horizontal probe=1`, SAMPLE=1): first entry 123 ms after the walk waited 14.8 s for the plant's warm-up
  (load 53 ms), again 38 ms; back to the plant 15–28 ms; every guided step walked (0 loose); after the machine's first
  frame no frame over 100 ms (the longest in the walk 48.1 ms), **99.83 % of frames at ≥ 30 fps**, median 16.8 ms, p95
  35.7 ms; peak PSS 1,168 MB; the pipelines compiled after the first 5 s were the plant start's (none in the
  Workshop). The APK 148.1 MB (K5b's 147.8 MB); the two scenes 130 KB of the package. **The motor kind's own walk**
  (2026-11-10, with the second pull request's build, `walk=workshop kind=motor probe=1`, a fresh install at 27.0 °C):
  first entry 116 ms after 4.5 s waiting for the plant's warm-up (load 43 ms), again 24 ms; back to the plant 16–18
  ms; every guided step walked (0 loose); no frame over 100 ms (the longest 53.3 ms), **99.78 % of frames at ≥ 30
  fps**, median 16.9 ms, p95 36.4 ms; peak PSS 1,159 MB; no pipeline compiled after the first 5 s. (A first walk the
  same morning had the kernel reclaiming memory in 54 % of its samples and was walked again, as the reclaim rule says.)

### 6.9 The vertical pump and the control valve (K6, second pull request)

**As built (K6, 2026-11-10).**
- **The vertical pump** (`kit/parts_rotating.gd pump_vertical`, its motor `kit/parts_common.gd motor_v`; the data file
  names a wet-pit pump the plant has three of, 550 m³/h, 30 m, 75 kW, a 6.5 m pit): the sole plate, the hollow
  discharge head with its branch, flange and motor stand, the packing box, the column in three sections (the
  lineshaft's bearings in their retainers, each joint's bolts a fastener group), the discharge case, two bowls and the
  suction bell, the shaft with two enclosed impellers on their taperlocks (vanes curved back against the turn), the
  spacer coupling, the head's hold-down bolts, and a vertical motor's own tree up to 500 kW (the stator in its frame,
  the drive-end bracket with the guide bearing, the top bracket with the thrust bearing, the fan, the drip cover, the
  rotor, the terminal box). 23 components, 3 fastener groups, 26 guided steps, 6,182 triangles (the plant's 2,018).
  The order is the Goulds VIT manual's (§6, p. 31; reassembly pp. 32–33) with Flowserve's VTP §6.8 as a second
  source; the motor's is derived from how it is built, as the motor kind's. The explode lifts the motor first and
  draws the string in the pit apart downwards (a real pump is lifted out whole: the steps say so).
- **The control valve** (`kit/parts_valves.gd`, the pneumatic actuator's branch; the data file names a DN 150 valve the
  plant has two of): a cage-guided globe valve (body, seat ring, cage, plug and stem, bonnet, packing, yoke, stem
  connector) with a spring-and-diaphragm actuator (the lower and upper casings, the diaphragm, the actuator stem, the
  spring) and its positioner and tubing; the bonnet studs and the casing cap screws. 15 components, 2 fastener groups,
  17 guided steps, 4,236 triangles (the plant's 1,768). The order is Fisher's: the easy-e ES manual (D100397X012) for
  the body and trim, the 667 manual (D100310X012) for the actuator; SAMSON's EB 8015 and EB 8310 second sources.
- **The plant unchanged** (`test_kit_frozen`); what is simplified and the trees' limits at other parameter sets are in
  the kit README.
- **New checks** (`tests/test_workshop.gd`):
  - `_explode_paths` had kept one small triangle per cell (a packed array appended as a copy). Keeping them all, it
    fails on #348's first coupling lift (0.25 m: the coupling rested in the bearing frame's path), the clearance #348
    fixed without a test.
  - `_turning`: everything in the `shaft` node turns on its line and rubs nothing that stands, nor runs through a
    closed face. It found #348's casing foot in the impeller's chamber, the frame's foot under its bore and the shafts'
    ends through closed faces, all fixed on the Workshop side (no exceptions).
  - `_seats`: the valve's plug lies on its seat at 0 travel, covers its bore, is on the stem's axis and lifts off as
    it opens.
  - `test_workshop` takes about 145 s on the laptop and runs in an app test shard of its own. `build.sh` now runs the
    shards one after another, each in its own Godot run; in a single run they had passed the 600 s limit.
- **The Note 9** (`lean+vis`, a test-signed release build, a fresh install for each kind, `probe=1`, SAMPLE=1, battery
  21.5–27.0 °C at the start):

  | | vertical pump | control valve |
  |---|---|---|
  | first entry (after the plant's warm-up) | 131 ms (load 48 ms) | 208 ms (load 49 ms) |
  | second entry | 27 ms | 26 ms |
  | back to the plant | 11–15 ms | 13–15 ms |
  | guided steps | all walked, 0 loose | all walked, 0 loose |
  | longest frame / over 100 ms | 42.1 ms / 0 | 42.6 ms / 0 |
  | frames at ≥ 30 fps | **99.93 %** | **99.92 %** |
  | median / p95 frame | 16.8 / 33.0 ms | 16.8 / 34.6 ms |
  | peak PSS | 1,144 MB | 1,162 MB |
  | pipelines after the first 5 s | 0 | 0 |

  The APK is 148.3 MB (the first pull request's was 148.1 MB). The two new scenes take 141 KB of the package.

### 6.10 The gate, globe and butterfly valves (K6, third pull request)

**As built (K6, 2026-11-10).**
- **The gate valve** (`kit/parts_valves.gd _rising`, `_gv_*`; the data file names a manual DN 300 gate valve the plant
  has several of): body, seat rings, wedge, stem, bonnet with its yoke, packing, stem nut, handwheel, the bonnet's 12
  studs. 8 components, 1 fastener group, 9 guided steps, 2,740 triangles. The order is Crane's (Pacific CSV IOM, the
  gate valve pp. 12-14).
- **The globe valve** (`_rising`, `_gv_stem`, `_gl_*`; a DN 50 PN 160 globe valve under a multi-turn electric
  actuator, the plant has four): body, seat ring, disc, stem, bonnet with its yoke, packing, the actuator (one part),
  its stem nut (output drive type A), display and handwheel, the bonnet studs and the actuator's bolts. 10
  components, 2 fastener groups, 12 guided steps, 2,134 triangles. Crane's order (p. 18, the operator first: §J p. 42)
  with AUMA SA's for the actuator.
- **The butterfly valve** (`_quarter`, `_bf_*`; a DN 250 butterfly valve under a part-turn electric actuator, the
  plant has six): body, liner, disc, shaft, packing, actuator, coupling, position indicator, handwheel, the actuator's
  bolts. 9 components, 1 fastener group, 10 guided steps, 1,528 triangles. Bray's Series 35/36 order (§13, pp. 28-29)
  with AUMA SQ's for the actuator.
- **The plant unchanged** (`test_kit_frozen`); what is simplified and the trees' limits are in the kit README.
- **New checks** (`tests/test_workshop.gd`): `_wedge` (the gate's wedge lies on both seat rings at 0 travel, covers
  their bore, clears it at full travel), `_discs` (the butterfly's disc's edge on the liner's bore, within its width,
  edge-on when turned by its travel); the globe's disc is held by `_seats`. Each made to fail once by a changed wedge or
  liner. `WS_ONLY=kind,…` runs `test_workshop` on those kinds alone (a quicker run while a tree is written).
- **The Note 9** (`lean+vis`, a test-signed release build, a fresh install for each kind, `probe=1`, SAMPLE=1, battery
  24.8–28.6 °C at the start, the kernel reclaiming in 0.98 / 0.16 / 0.16 % of the samples):

  | | gate valve | globe valve | butterfly valve |
  |---|---|---|---|
  | first entry (after the plant's warm-up) | 128 ms (load 43 ms) | 122 ms (load 45 ms) | 113 ms (load 44 ms) |
  | second entry | 27 ms | 29 ms | 26 ms |
  | back to the plant | 14–15 ms | 16–21 ms | 16–20 ms |
  | guided steps | all walked, 0 loose | all walked, 0 loose | all walked, 0 loose |
  | longest frame / over 100 ms | 41.6 ms / 0 | 41.4 ms / 0 | 56.5 ms / 0 |
  | frames at ≥ 30 fps | **99.94 %** | **99.91 %** | **99.94 %** |
  | median / p95 frame | 16.8 / 35.2 ms | 16.9 / 35.2 ms | 16.9 / 35.7 ms |
  | peak PSS | 1,158 MB | 1,159 MB | 1,166 MB |
  | pipelines after the first 5 s | 0 | 0 | 0 |

  The APK is 148.5 MB (the second pull request's was 148.3 MB).

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
| `ws_xray` | unshaded, `blend_mix`, `depth_draw_never`, `depth_test_disabled` (K2: the ghost shows through what stands in front of it) | from K2: the assembly's ghost; from K3 the X-ray too (an edge-weighted see-through, in another colour) | new, small |
| `ws_flow` | unshaded, `blend_add` | flow particles: one MultiMesh of quads per path, moved along the path in the vertex shader (the path in a small texture; speed and density as uniforms) | new, small |

One new lit shader and three unshaded ones: `ws_xray` arrives with K2 (counted and pre-warmed there), the other three
with K3. Each milestone counts its pipelines (`pipelines compiled`, and
`phone/launch.sh`'s log on the Note 9) before and after; 0057's numbers suggest about 7 for `ws_lit` and a few each
for the unshaded ones, to be measured in K3 and written into 0072.

**Compiled before they are needed:** after the plant's first walkable frame (never before: it would cost the 15 s
rule), a hidden node with one small mesh per Workshop variant queues their pipelines on Godot's worker threads, as the
walking directions' chevron does (0060); the pipeline cache (saved every 0.25 MB) keeps them for later starts. The
Workshop's own load draws its scene hidden for one frame first, so anything not yet compiled is compiled before the
first frame of the machine, never on the first X-ray click. K3 measures whether the background compile costs the
plant's frames on the Note 9; if it does, it moves into the Workshop's load alone (its entry rule, §8, allows it). The
shaders themselves are baked at export (decision 0060's shader baker), through a material of each saved by the
content build (`built/shaders/`): the baker bakes materials, not shader files (the polish after K4b).

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
| The Workshop walk (scripted, `app/workshop_walk.gd`) | 3 minutes on a fixed camera orbit: assembled, exploded 0 → 1 → 0, handled, the guided steps, then (the machine assembled again, at 118 s) Start, X-ray, cutaway, a section sweep, the faults, Stop (a running machine is not taken apart: the polish after K4b; the turbines' walks are measured with `bench_speed=30` since K5b, so that the steam turbine's 300 s soak and the gas turbine's 480 s purge still let them reach full speed in the 37 s before the faults; the walk then lets the clock step as many steps a frame as that needs) |
| Peak PSS | ≤ 1.5 GB with the plant held behind it |
| One kind's scene | ≤ 120,000 triangles (all components, insides included); ≤ 300 draw calls in any view of the walk, `ws_cap`'s second pass included (it is drawn only while a cut or section is on, on the components the cut reaches) (the plant's busiest measured 479 at p95 within the frame rules, 0041) |
| The bench step | ≤ 0.3 ms on the Note 9 (a bench model is a fraction of the plant's 1.4 ms) |
| Pipelines | counted per milestone, none compiled after the first frame of the machine |
| In a session | the same rules with the plant's engine, the session and a second player running behind the Workshop (a laptop host and the Note 9), measured in K1 and K3 |

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
| `data/plant3d/workshop/<part>.json`, `data/plant3d/workshop/bench/<part>.json` | the data |

A test reads every script in `apps/plant3d/workshop/` and fails on any part id of kit.json in it.

**Adding a new part kind with no Workshop code** (checked against this plan for K0): the kind's generator gains its
`g.comp()`, `g.only()`, `g.fasteners()` and flow paths; `data/plant3d/workshop/<part>.json` gives its words, order,
views and sources; `data/plant3d/workshop/bench/<part>.json` (or its bench source for the tool) gives its model and
bindings; a new sound goes into sounds.json (a synth sound made by the sound tools, a recording under 0055's rules). The card's button, the settings list, the builder, the gallery and the tests find
the kind from its data file. Nothing else changes. A test fixture proves it: a kind made for the tests only, its
generator in `tests/fixtures/` and its data files beside it. Today the kit's part list is fixed in code (`MAKERS` is
a constant and `_script()` a `match` over the generator scripts; `Kit.use_kit` replaces only kit.json), so K1a adds a
generic hook, `Kit.register(part, script, budget)`, which the tests use to add the fixture (the app's own kinds stay in
`MAKERS`). The fixture grows with the milestones: it builds and loads in K1a, explodes and is handled in K1, is
assembled in K2 and runs in K3.

## 10. Tests and pictures

In `apps/plant3d/tests/` and, for data, the Python suites:
- every component has a unique id, an existing parent and a pivot inside the part's box; the tree has no cycle;
- exploding to 1 and back to 0 restores every transform exactly; the same slider value gives the same transforms;
- the assembly is complete (every component and group placed once), every need names an existing component, and the
  guided order passes its own needs;
- the Workshop build's outside matches the plant's: `Kit.make()` in both modes for the same parameters, before the
  builder's 12 m cells: shared pieces identical, `"plant"` pieces matched by their `replaced_by` (box within 1 mm, same
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

**The Note 9** for every milestone that changes what is drawn or run (K1, K3, K4a, K4b, K5a, K5b at least: K4a and K5a are where the big scenes first show): the Workshop's
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
  manufacturers' published cutaways of heavy-duty frames. Its bench (K5b): NASA Glenn Research Center's Beginner's Guide to
  Propulsion (compressor and power-turbine thermodynamics), the NIST Chemistry WebBook (methane's heat of
  combustion), GE GER-3434D and GER-3620P; the sequence, trips and their values are the plant's own model.
- **Horizontal pump (K6):** ITT Goulds 3196 i-FRAME installation, operation and maintenance manual (2017: the
  maintenance chapter's take-apart, pp. 73–84, and its reassembly, pp. 102–132), Flowserve Durco Mark 3 ISO user
  instructions 85392719 (§6.8 dismantling, §6.10 assembly), a public summary of API 610's pump types (OH1), the US DOE
  Fundamentals Handbook's pumps chapter (the volute) and KSB's pump lexicon (backward-curved vanes, the direction of
  rotation named from the drive).
- **Motor (K6):** ABB's low voltage motors manual (3GZF500730-85), WEG's installation, operation and maintenance manual
  (50033244) and Innomotics' SIMOTICS 1LE1 operating instructions (A5E38483075A: IC 411, IM B3, the fan and the end
  shields). None of them gives a numbered dismantling order: the motor's order is **derived from how it is built, not
  from a manual** (the user, 2026-11-09), and its data says so in every step's reason.

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
  fastener groups and the assembly `needs` with their two sentences (§4.6): the Workshop's sentences are the jobs'
  sentences. Component ids are short identifiers (§4.1) so their states fit model value names.
- **The service file beside the Workshop's** (`data/plant3d/service/<part>.json`, REALISM.md §2.4) holds what the
  Workshop leaves out of its scope, keyed by its ids: fasteners' sizes and the tools that fit them, torque values and
  tightening patterns, components' damaged states. The Workshop's data file never holds these, so there is one home
  for each fact.
- **Fasteners are groups of addressable items** (§4.4): the service file's torque and pattern apply per group, and a
  torque state per item, without changing the geometry or the explode function.
- **Anchors** (§4.1) are the points where wires land and probes and clamps go (terminals, test terminals, a cable's
  core): the meters' `point` names them.
- **Faults are bench data at a component** (§6.1): internal faults (a torn diaphragm, a worn seat, a rubbing seal) and
  hidden causes are more faults and values in the bench model, and wear is a bench value read by bindings; the
  Workshop's code stays as it is, and the bench format gains the plant's new node kinds as its version 2 (§6.1).
- **Component states.** The Workshop's handling state (home, off, a cover open, a fastener group in or out) is UI
  state now; the hands-on milestones make the same states model values for equipment a job names, read by the
  component scene placed in the plant (§5: materials by name, the part's own frame, a scene per instance's
  parameters).
- **The heat view** (`ws_lit`'s ramp) is what the thermal camera draws (REALISM.md §9.3): no new shader.
- **A removed part on the bench.** The mirror (§6.5) is read only; REALISM.md §3.5 makes it writable for a part a job
  removed, with that part's component states and hidden cause.
- **Ageing and weather** live in the plant's model; the mirror maps their effects on the bench's inputs like any other
  plant value.
