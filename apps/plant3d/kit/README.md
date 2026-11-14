# The parts kit

Every piece of equipment in Walkdown Plant is made here, by code, from the parameters its content gives
(docs/PLANT3D.md §9, decision 0054 §1, §5). The content build (`builder/kit_place.gd`) places the parts; nothing here
runs when the app starts (the app loads the built scenes).

| File | What |
|---|---|
| `kit.gd` | the entry point: `Kit.make(part, params, ctx)`, the part list (`MAKERS`), the triangle budgets (`BUDGET`) |
| `mesh.gd` | the mesh builder: primitives in a part's frame, layers per material and visibility class, LODs |
| `parts_*.gd` | the generators, one file per group: machines, rotating, heat exchange, vessels and HRSG, valves, instruments and people cues, electrical, pipes; `parts_site.gd` the site's and the camp's structures (planting by species, vehicles, gates, canopies, lamps, kerbs, the sports court, porches, partitions and furniture: docs/PLANT3D.md §18.6) |
| `parts_common.gd` | what many parts share: flanges and bolts, nozzles, baseplates, motors, couplings and guards, rails, ladders |
| `materials.gd` | the materials, the texture sets and the texture tiers |
| `fetch_textures.sh` | the CC0 textures, pinned by SHA-256 (never committed) |
| `gallery.gd` | pictures of every part, to look at (needs a display: `tools/plant3d/bench/offscreen.sh`) |

Every part of `data/plant3d/kit.json` outside the `structures` group has a generator (the structures are the
builder's own: walkable surfaces, stairs, ladders, buildings, pits, slabs, fences, the pipe rack), and so do the
site's and the camp's structures (`parts_site.gd`), which the builder places as it places equipment. `tests/test_kit.gd`
checks that, and everything below that a test can check.

## Frames

A part is built in its own frame: x right, y forward along its main axis (a shaft, the flow through a valve), z up,
metres, from its origin: the base at the footprint's centre, or the pipe's centre line for a part on a pipe (§9). The
builder turns it to its heading (a part on a pipe to the pipe's direction; on a vertical pipe its up lies across the
pipe, towards the north). Nozzles stand where `kit.json` says, and every nozzle a pipe ends on has its stub and flange
there, so pipes meet their equipment.

## What the builder makes of a part (the nodes)

Each area's scene (`built/areas/<area>.scn`) holds:

- `equipment/<KKS>`: one `StaticBody3D` per piece of equipment, named by its code, at the part's origin and
  heading, in the group `equipment`, with the metas `kks`, `part` and `aabb` (the part's box in the node's own axes,
  for highlighting it). Its children:
  - the moving pieces (below), each a `Node3D` named by its anim channel;
  - `plate`: the tag plate's code, a `Label3D` on the plate (the plate itself is instanced with the static pieces);
  - `label`: the floating label over the part (code and name, as before the kit);
  - its collision shapes (small parts on pipes and machines are not solid).
  Parts fixed to equipment (`parts` in the content) are nodes of their own, named by their codes, in the same
  `equipment` node; parts on pipes (valves, instruments) are such nodes in the `pipes` node.
- `pipes/<KKS>`: one `StaticBody3D` per pipe, in the group `pipes`, meta `medium`, with its collision; its meshes
  are with the static pieces.
- `kit`: the static pieces, instanced (`MultiMeshInstance3D`, group `kit_cells`, decision 0041): per 12 m cell (6 m
  for `detail` pieces), the meshes that stand in the cell more than once are instanced; those that stand there once
  are merged per material into one mesh. The transforms are in the meta `xforms` (12 floats each, MultiMesh's layout)
  and `app/plant.gd` gives them to the MultiMesh at load (Godot's headless renderer, which the build runs under, keeps
  no MultiMesh data).

## Moving parts

What the behaviour model animates (§7.7 `anim`) is a child node of the equipment's node, named by its channel, with
the metas `anim_axis` (a unit vector in the node's own axes: Godot's, y up), `anim_kind` and `anim_travel`. The
node's origin is the pivot; at value 0 the node is as built. Kinds:

- `rotate`: turn the node about `anim_axis` by `value × anim_travel` radians (right-hand rule); `anim_travel` 0
  means it turns freely: a shaft turns at `of × scale` revolutions per second (§7.7);
- `translate`: move it along `anim_axis` by `value × anim_travel` metres;
- `scale`: scale it along `anim_axis` by `value` (0 empty, 1 full);
- `lamp`: the node holds the unlit lens; its child `on` is the lit lens, hidden until the lamp is on;
- `group`: the node only holds others that move (a damper's blades): move its children;
- `slide` (lifting gear, PLANT3D.md §20.5): move it along `anim_axis` by `value × anim_travel` metres, not clamped
  (the value is a position in metres: `anim_travel` 1), drawn between the model's last two steps by the clock's
  fraction of a step (`ui/bindings.gd`), and nothing done while the value stands still. A slide nested in another
  (a crane's `bridge/trolley/hook`) moves with it; every slide's pivot is the part's origin, so a value is the
  piece's position in the part's frame;
- `stretch`: a piece drawn 1 m long from its pivot along `anim_axis` (a chain, a crane's ropes), scaled along that
  axis to `anim_travel − value` metres: it hangs down to the hook whose height the value is, interpolated likewise;
- `marker`: nothing moves it; it marks a point the app looks for by its name (a hoist's `pendant`, where its buttons
  are worked from: it rides on the bridge of a crane).

| Part | Node | Kind, axis (node axes) | 0 → 1 | Travel |
|---|---|---|---|---|
| gas_turbine, generator, steam_turbine, turning_gear, motor, pump_horizontal, vacuum_pump_skid | `shaft` | rotate about −z (the part's +y) | turns freely | 0 |
| pump_vertical, fan_axial, compressor_skid (its cooler's fan) | `shaft` | rotate about +y (up) | turns freely | 0 |
| valve_gate, valve_globe, valve_control | `stem` | translate along +y (up the bonnet) | closed → open: the stem rises out of the handwheel or yoke | the stroke: about the bore (gate), a quarter of it (globe, control) |
| valve_gate, valve_globe, valve_butterfly, valve_ball (and valve_control) | `handwheel` | rotate about its own axis: +y for a wheel on top, ±x for one on the side | turns freely | 0; empty where the actuator has no wheel (a lever, a cylinder) |
| valve_butterfly, valve_ball | `disc` | rotate about +y (the stem) | closed → open; the position indicator or lever on top turns with it (along the pipe = open) | π/2 |
| valve_check | `disc` | rotate about +x (the hinge, across the pipe) | shut → fully open; the lever and weight outside show it | 1.2 rad |
| valve_safety | `stem` | translate along +y | shut → lifted (spindle, cap, lever) | a quarter of the bore |
| damper | `blades` (a group) with `blade_0` … `blade_n` | each blade rotates about +x | closed → open | π/2 |
| pressure_gauge, temperature_gauge | `needle` | rotate about the dial's inward normal (clockwise as read) | the scale's start → its end | 3π/2 |
| level_glass | `level` | scale along +y from the glass's bottom | empty → full | 1 |
| breaker | `contacts` | rotate about −z for a GCB (the part's +y), −x for an MV breaker (the flag behind the mechanism's window) | open (green) → closed (red "I") | π/2 |
| lamp, beacon | `light`, `light/on` | lamp | off → on | 0 |
| monorail_hoist | `trolley`, `trolley/hook`, `trolley/chain`, `load_y`, `load_y/load_z`; `pendant` (marker) | slide along +y (the beam, from its tip), slide along +z (the hook's seat above the origin), stretch down, the load's slides along +y and +z (its base) | the value in metres | 1; the chain's: from under the hoist to the hook block's top |
| service_lift | `cab`, `cab/gate` | slide along +z (no binding: the app's lift, `app/lift.gd`, moves the cab to the model's `z` between steps, and raises the cab's gate with the landing gate where it stands) | the cab floor's height above the part's origin; the cab's gate risen | 1 |
| lift_gate | `leaf` | translate along +z | shut → open | 2.1 |
| overhead_crane | `bridge`, `bridge/trolley`, `bridge/trolley/hook`, `bridge/trolley/rope`, `load_y`, `load_y/load_x`, `load_y/load_x/load_z`; `bridge/pendant` (marker) | slide along +y (the runway), along −x (across), along +z; the ropes stretch down; the load's slides along +y, −x, +z | the value in metres | 1; the ropes': from the trolley to the hook block's top |

A `hoist_unit` (a hoist's drive, its hook's latch, its load cell: a code of its own, PLANT3D.md §20.5) draws nothing:
its hoist draws it, and the app carries its node with the piece it rides on (`kind` hoist and trolley: the trolley;
bridge: the bridge; latch and load_cell: the hook), so its label, its card's reach and "Show me" follow it.

A `lift_unit` (a service lift's drive, the cab's control panel, its load cell: codes of their own, PLANT3D.md §20.2)
draws nothing either: the lift draws them (the drive's cabinet with the main switch at the mast's foot), and the app
carries the panel's and the load cell's nodes with the cab (the panel gets a small body there, so a tap or the centre
of the screen picks it).

## Visibility classes and ranges (§10)

Every piece is `form`, `identify` or `detail`. Form and identify pieces are drawn to the far plane on every tier;
form pieces get LODs, identify pieces none (a simplifier measures shape, not colour); detail pieces (bolts, fins, stiffeners, seams, small brackets) are grouped by size
(a factor of 2) and drawn while they cover the tier's `detail_min_px` (`app/quality.gd`: 1.5 px on laptops, 3 px on
phones): `d = size × f / min_px` plus half the diagonal of their cell's box (Godot measures a range to the box's
centre), without a fade (a fading instance takes a transparent pipeline, compiled the first time anything fades). Tag plates and their codes are identify; the code's text is drawn while a character covers
8 px (`legible`), the plate always. Detail pieces cast no shadow.

## Materials and textures

One material per texture set and finish; a piece's colour is in its vertices (`materials.gd resolve`), so all paint
colours in a cell are one draw call:

| Material | Set (ambientCG, CC0) | Used for |
|---|---|---|
| `paint` | PaintedMetal004 (normal and roughness: its scratches and wear) | every painted part, the colour per piece (`PAINT`) |
| `metal` | Metal032 | bare, galvanised and dark steel: stems, flanges, frames, supports |
| `sheeting` | CorrugatedSteel005 | casings, wall cladding |
| `cladding` | Metal009 | insulation cladding (aluminium) |
| `concrete`, `grating`, `chequer`, `gravel`, `asphalt` | Concrete034, MetalWalkway010, DiamondPlate008C, Gravel023, Asphalt031 | foundations, decks, the ground, roads |
| `plain`, `plain_metal`, `lamp_*` | none | small pieces (dials, plates, rubber, glass, porcelain, the media's colour bands), lamps |

Every material with a texture set is the weathered shader (`weathered.gdshader`, `weathered.gdshaderinc`, decision
0057): the set's maps plus grime, run-off streaks, dust, rust and paint wear from world position and a build-made noise
(`builder/weather.gd`), each finish its own amounts (`materials.gd WEATHER`). A piece's vertex colour alpha says how
much it is touched (`EXPOSURE`: handrails, ladders and handwheels most), which is where paint wears to steel. The plain
materials use the same shader without textures or weathering; only the lamps stay Godot's standard material.

`fetch_textures.sh` downloads the 2K JPG sets (https://ambientcg.com, "all assets are CC0") into
`~/.cache/walkdown-plant/textures`, checks each against its SHA-256 before unpacking, and lays out the three tiers in
`kit/tex/2048`, `1024` and `512` (the same files, imported at three sizes, VRAM-compressed with mipmaps). The built
materials name the 1024 px textures; `app/quality.gd` switches them to the tier's size: 2048 px for `full`, 1024 px
for `lean+vis`. The 512 px set is imported but no tier uses it yet (kept for a heavier plant, 0054), so no export
carries it; the Android export leaves the 2048 px set out too (and carries only ETC2: checked in the release APK,
2026-10-16).

## Context (what the builder tells a part)

`ctx` carries what a part can't know from its own parameters:

- `axis_z`, `shaft_lo`, `shaft_hi`: machines on one shaft line (same area, height and heading line) share the
  highest shaft height any of them needs, and each shaft reaches half way to its neighbour, with a coupling there;
- `intake_top` (gas turbine): the height of the filter house standing over its top intake;
- `exhaust_to` (steam turbine): the top of the condenser under its exhaust;
- `inlet`, `stack_d` (HRSG): the duct that ends at its inlet, the stack it feeds;
- `decks`: the content's walkable surfaces over the part (an HRSG's roof, a stack's platform, a cooling tower's fan
  deck): the part leaves room for them and draws no access of its own there;
- `used`: the nozzles pipes end on, with their pipes' outside diameter;
- `out`, `floor_dz`, `pipe_od` (instruments and parts on pipes): which way is away from what it is fixed to, how far
  down the floor is, the pipe's outside diameter with its insulation.

## Pipes

`parts_pipes.gd pipe()`: the route with bends of 1.5 × OD (or 3d, 5d), cladding over insulation (bare pipe for
0.15 m either side of a valve or instrument in it, with the cladding's end rings), the medium's colour band every
`arrows` metres (12 m when `arrows` is 0) and a flow arrow on both sides and on top beside each band (when `arrows` >
0), the mating flange at each nozzle. Supports stand at the span table's spacing along every horizontal run: on the
highest deck, rack tier or the ground below (up to 40 m: a tall trestle gets a second leg and bracing), never in
walking space: over a narrow deck, a landing or a stair a pipe bridge spans it (legs where the walkway ends, within
8 m either side); on a deck at least 8 m wide both ways (a roof, a floor) posts stand as sleepers do. A pipe with
nothing to stand on is reported by the build as a warning. The medium's `name` (plant.json) is stencilled in black on both
sides of every horizontal run long enough for it, between the bands and clear of bends, valves and instruments
(`builder/kit_place.gd _stencils`: the safety signs' label settings, drawn within 30 m).

Valves' bodies, bonnets and yokes are black (`paint_valve`, cast iron and steel as delivered), electric actuators a
light silver grey (`paint_actuator`), bolts rusty steel (`steel_bolt`), handwheels red.

## Budgets

The most triangles one instance of a part may have at full detail (LOD 0), with any parameters the kit allows
(`BUDGET` in `kit.gd`; `tests/test_kit.gd` checks each part with its defaults, every parameter set the first train
uses, each number parameter at its minimum and maximum, every number parameter at its maximum at once with every
enum and flag value, and a 300 m route for the parts along a path). Not covered: what the builder's context adds
(couplings, nozzle stubs), and pipes, which have no budget of their own (a pipe's triangles grow with its route). LODs are made by Godot's own
simplifier (as for imported models, decision 0041), each no larger than the one before.

| Part | Budget | Most made (tests) |
|---|---|---|
| gas_turbine | 30,000 | 8,944 |
| generator | 12,000 | 1,028 |
| steam_turbine | 30,000 | 8,038 |
| sfc | 4,000 | 1,116 |
| turning_gear | 4,000 | 852 |
| hrsg | 20,000 | 4,064 |
| hrsg_module | 1,500 | 228 |
| drum | 9,000 | 8,316 |
| stack | 26,000 | 25,136 |
| duct | 4,000 | 1,296 |
| silencer | 3,000 | 1,044 |
| filter_house | 8,000 | 3,936 |
| pump_horizontal | 9,000 | 6,952 |
| pump_vertical | 11,000 | 10,036 |
| fan_axial | 6,000 | 1,472 |
| compressor_skid | 8,000 | 1,456 |
| vacuum_pump_skid | 8,000 | 3,114 |
| condenser | 12,000 | 4,656 |
| shell_tube_hx | 6,000 | 5,080 |
| plate_hx | 4,000 | 1,992 |
| cooling_tower | 40,000 | 31,232 |
| package_boiler | 8,000 | 3,096 |
| basin | 1,000 | 72 |
| tank_vertical | 9,000 | 8,680 |
| vessel_horizontal | 6,000 | 2,812 |
| clarifier | 9,000 | 3,160 |
| thickener | 7,000 | 3,288 |
| filter_bank | 9,000 | 2,730 |
| cartridge_housing | 3,000 | 2,304 |
| ro_train | 16,000 | 7,620 |
| degasser | 7,000 | 4,136 |
| ion_exchanger | 6,000 | 2,120 |
| dosing_skid | 3,000 | 756 |
| metering_pump | 2,500 | 476 |
| chemical_tank | 6,000 | 3,592 |
| filter_press | 6,000 | 2,892 |
| sample_panel | 4,000 | 1,692 |
| lab_bench | 2,000 | 320 |
| agitator | 3,500 | 692 |
| bar_screen | 5,000 | 1,772 |
| screen_band | 4,000 | 464 |
| valve_gate | 5,000 | 4,712 |
| valve_globe | 5,000 | 4,732 |
| valve_butterfly | 4,000 | 2,104 |
| valve_ball | 4,000 | 3,800 |
| valve_check | 4,700 | 4,092 |
| valve_control | 5,800 | 5,077 |
| valve_safety | 4,600 | 4,038 |
| damper | 4,000 | 1,504 |
| pressure_gauge | 800 | 508 |
| pressure_transmitter | 1,200 | 272 |
| temperature_element | 600 | 272 |
| temperature_gauge | 800 | 396 |
| level_glass | 1,500 | 172 |
| level_transmitter | 1,500 | 344 |
| flow_element | 2,500 | 912 |
| position_switch | 400 | 68 |
| vibration_probe | 400 | 128 |
| speed_probe | 400 | 92 |
| flame_detector | 500 | 120 |
| local_panel | 1,500 | 312 |
| push_button_station | 800 | 292 |
| transformer | 25,000 | 17,100 |
| breaker | 6,000 | 2,556 |
| switchgear_row | 8,000 | 5,556 |
| cabinet | 1,500 | 924 |
| junction_box | 400 | 120 |
| cable_tray | 6,000 | 3,900 |
| motor | 5,000 | 1,220 |
| elbow | 3,000 | 2,560 |
| tee | 2,000 | 384 |
| reducer | 1,000 | 192 |
| flange | 1,500 | 1,312 |
| pipe_support | 400 | 60 |
| tag_plate | 60 | 12 |
| sign | 60 | 44 |
| lamp | 300 | 188 |
| beacon | 400 | 192 |
| horn | 300 | 92 |
| emergency_stop | 400 | 172 |
| safety_shower | 1,500 | 296 |

With the water treatment plant (W1, 2026-10-22): 491,133 triangles at full detail in 1,832 instanced or merged
meshes, 330 pipe supports. The first train (2026-10-16): 302,944 triangles at full detail in all, in 1,112 instanced or merged meshes (cells of
12 m, 6 m for detail; pipes and large parts cut by cell); 176 pipe
supports. The bench that decided the engine (0041) had 1.46 M triangles.

## The Workshop mode (docs/plant3d/WORKSHOP.md §4)

`Kit.make(part, params, ctx, seg_scale, true)` runs the same generator with its component tags: `g.comp(id, spec)`
names the component the next primitives belong to, `g.only(...)` says whether they are shared with the plant, the
Workshop's alone (hidden insides, small outside pieces, split halves) or a merged stand-in the plant draws instead,
`g.fasteners()` and `g.flow()` add fastener groups and flow paths. Plant mode ignores all of it: its output is held to
what it was by `tests/test_kit_frozen.gd` (record again with `tests/kit_frozen.gd` only for a meant change to the
plant, then bake the lightmap and run the plant's Note 9 walk). A part whose generator declares no components is one
component, `body`. `Kit.register(part, script, budget)` adds a kind from outside the kit (the tests' fixture kind).

What each kind simplifies, and its sources (the data file `data/plant3d/workshop/<part>.json` cites them):
- **pressure_transmitter** (Rosemount 3051 reference manual, §6.4–§6.5): the valve manifold is one block with three
  handles; the process flange carries two drain/vent valves and four bolts into the sensor module; the sensor
  module is sealed (its isolating diaphragm and sensing cell are simple solids); the housing is the plant's drum split
  into the housing (two compartments) and its two screwed covers, with the electronics board and the LCD on the
  display side and the terminal block on the field side, held on the module's neck by the housing rotation set
  screw. The two alignment screws and the O-rings are not drawn; the two isolating diaphragms are one disk; the
  plant's one block is the process flange and the module's coplanar base together, so the flange bolts' shanks end
  in it.
  Running (K3, its bench model `data/plant3d/workshop/bench/pressure_transmitter.json`, made by
  `tools/plant3d/workshop/pressure_transmitter.py`): the isolating diaphragm is the moving piece `deflect` (6 mm of
  travel at the upper range: a real one moves a few micrometres), and the impulse path `impulse` runs up the axis
  from the impulse line through the manifold and the flange's port to the diaphragm (one line: the low side of a
  differential transmitter is not drawn). In the Workshop the display cover's face is a ring round the window's
  opening and the window closes it (the plant's drum end and window as drawn before), so the LCD reads through it.
- **steam_turbine** (K4a; the plant's first instance, the HP turbine: one casing, a combined stop and control valve
  on each side; GE GER-3646D and GER-3582E, the IMIA overhaul paper, the US Navy Fireman manual ch. 5, the NRC
  Westinghouse manual §7.3, the Siemens/KWU overhaul procedure for the order; the data file cites the pages): built
  with the instance's shaft line (the data file's `context`: `axis_z`, `shaft_lo`, `shaft_hi`), so its coupling
  stands where the plant's does. The plant's drum is the lagging, split into two half shells 0.2 m thick; under it
  the outer casing's halves (their joint flanges the plant's two boxes, each cut at the joint), the inner casing's
  halves with their own flanges and 12 hidden studs, the blade carriers' halves (a ring each, its bore a cone over
  the blade path) and 8 stages, each a stationary row (in the carrier's halves) then a moving row (on the rotor):
  flat plates, not aerofoils, the stationary rows' trailing edges leaning the way the rotor turns (right-handed
  about +y, steam to -y), the moving rows' leaning back, longer stage by stage. Real HP sections have more stages
  (GE: reaction designs about twice an impulse design's); the count drawn is a picture, not a design. The rotor is
  one forging: a drum with a balance piston ahead of the first stage (a reaction design's, GER-3646D), the thrust
  collar in the front pedestal (GER-3582E), the coupling flange at the end the shaft line gives it; its coupling bolts
  are the plant's bolt ring, and what they join beyond this machine is the next rotor (`beyond`). The pedestals are
  the plant's boxes: a body with a pit and a 10 mm cover plate on top, the journal bearings' halves in them and the
  thrust bearing's pad rings round the collar, in halves. The glands are two plain rings each end (no labyrinth teeth). In
  each valve chest a stop valve disc and a control valve plug on their stems, the plant's servomotor on top (a real
  combined valve has an actuator for each). **Simplified from text-only descriptions** (the user, 2026-11-03): the
  lagging (insulation under sheet cladding, as one shell) and the thrust collar and bearing (pads as two rings). The
  joint's 44 studs are the plant's (a fastener group replacing the plant's stand-in, held to its box and triangles).
  The order (the data file's `assembly`, reversed for taking apart) is the Siemens/KWU procedure's without its trial
  fits, the blade carrier inside the inner casing as GE's diaphragms are; the explode stages follow the tree (the
  rotor under the lower inner casing, so it lifts after the upper halves).
  Known shortcuts: the plant draws each valve's steam lead into the casing at the horizontal joint, so in the
  Workshop it is the lower half's (GER-3582E: the valves are piped to the lower half) and the upper halves lift past
  it; the joint flanges, pedestals and covers are one stand-in (the plant's paint pieces of the casing and the
  pedestals), held together to the plant's box and triangles, since each flange cut at the joint alone is 1.67 times
  its box's triangles.
- **gas_turbine** (K5a; the plant's first instance: a heavy-duty single-shaft machine, cold-end drive, axial exhaust,
  top intake; GE GER-3620P and GER-3434D, GEA-12985B, the Baker Hughes 9E overview, GE's patents on the inlet casing,
  the thrust bearing, the exhaust frame and the rotor's lift, the US Navy NAVEDTRA 14114; the data file cites the pages):
  built with the instance's shaft line (`context`), so its coupling to the generator stands where the plant's does. The
  plant's cone over the compressor is its casing, split at the joint into two halves 0.12 m thick, its joint flanges
  the plant's boxes each cut at the joint and its 40 studs the plant's (a fastener group replacing the stand-in); the
  combustion wrapper is the compressor discharge casing in two halves; the cladding drum over the turbine is the turbine
  shell with its insulation, 0.15 m thick, in halves with its two seams. Inside: a bellmouth in the inlet plenum (in halves), the
  variable inlet guide vanes and **8 compressor stages** (a moving row on the rotor, then a stator row in the casing's
  halves; GE's F class has 18, its E class 17: the count drawn is a picture, not a design), the rotor's drum of disks
  (one lathe: the tie bolts are not drawn), the distance piece through the combustion section, **3 turbine stages** (a
  nozzle row in the shell's halves, then a row of buckets on the wheels: GE's E and F classes have 3), all flat plates,
  not aerofoils, the moving rows turning right-handed about +y (air and gas flow to +y). **12 combustion cans**, as the
  plant draws them (a real 9E has 14, a 9F 18; GE's 12-can machine is the 60 Hz 7H): each the plant's casing (with its
  flow sleeve, one solid), its end cover with **six fuel nozzles** (GE's Dry Low NOx cans), a liner inside, and a
  transition piece from the can to the first stage's nozzles inside the wrapper; the crossfire tubes, spark plugs and
  the cans' own cover bolts are not drawn. The front bearing housing is the plant's drum on its pedestal: the drum lifts
  off as the housing's cover over the journal bearing's halves and the thrust bearing's two pad rings round the rotor's
  thrust collar (GE puts the thrust bearing at the inlet end). **Simplified:** the rear journal bearing is drawn just
  ahead of the exhaust frame's face, inside the shell, because the plant draws the shell's rear end closed (a disk the
  Workshop gives the exhaust frame) and the diffuser open behind it: a real one sits in the exhaust frame's inner barrel,
  and the gas path goes on through its struts. The exhaust frame and diffuser, the fuel gas manifold and the bleed pipes
  are `thin` (the plant draws them as open ducts and pipes). The rotor is sealed in this view (it comes out with its
  blades and buckets; changing a bucket, which GER-3620P does in the field, is not drawn). The order (the data file's
  `assembly`, reversed for taking apart) is a major inspection's: the combustion parts first, without lifting a casing,
  then the upper casings one at a time with their stator rows and nozzles, the bearings and the coupling, the rotor
  lifted out, then the lower halves; the inlet plenum comes off first, where a real inspection opens only the
  bellmouth's upper half. Also **simplified**: the upper inlet guide vanes and stator rows are parts of their own, put
  in over the rotor before the upper casing (a real unit's sit in the casing's upper half and lift with it), and the
  exhaust frame is one part that stays while the rotor is lifted (a real unit has its upper half off first). The
  nozzles lean with the rotor's turn and the buckets against it, as the compressor's stators and moving rows do, so
  the turbine drives the rotor the way the compressor is made to be driven (`tests/test_workshop.gd` checks every
  row's lean from its faces). **The explode:** a can above the joint rides up with the discharge casing's upper half
  and then comes out of it along its own axis, the only way out of the wrapper; one below comes out of the lower half
  along its axis only as far as its end cover stays above the foundation block, so the cans at the bottom stay in place
  (a real unit's lower cans come out into the pit under the machine, which is not drawn). The transition pieces above
  the joint lift once the upper half is off, farther than the rotor; those below stay. The liners stay in their cans
  (the plant draws each can closed at both ends; the steps take a liner out by hand). The bellmouth, the front
  bearing's drum (the plant's: its upper half is the housing's cover) and the thrust bearing's pad rings are split at
  the joint like the casings: the upper halves lift a little farther than the rotor, the lower halves stay. The bleed
  pipes ride up with the upper compressor casing; the exhaust frame lifts (it stands in the foundation block, so it
  can't slide back); the fuel gas ring stays (the plant draws it closed round the wrapper, among the end covers and
  into the block: it can go no way). `tests/test_workshop.gd` checks every kind's explode stays above the floor and that no two parts pass
  through each other (their triangles' boxes, cell by cell, in every stage), apart from the pairs listed there with their
  reasons: the plant's closed inlet plenum lifted over the shaft and the bellmouth, the plant's fuel gas ring, and the
  steam turbine's front pedestal round its rotor; two parts drawn into each other (a can through its wrapper's wall)
  are not judged. **The flow (K5b, `_gt_flows`):** 16 paths, Workshop only: the air down the plenum into the bellmouth,
  four straight lines along the compressor's annulus and four along the turbine's (mid-annulus, to +y), the fuel along
  the gas ring's upper arc and down a pigtail to two cans' nozzle tips, the flame from the nozzles' tips along three
  liners and through their transition pieces to the first nozzles, two lines out of the diffuser; one of each set in
  the cutaway's quarter. Straight lines, not the swirl the blades give the air.
- **motor** and the **motor of pump_horizontal** (one tree from `C.motor_h`, K6: kit/parts_common.gd): a totally
  enclosed fan-cooled induction motor (IC 411, foot mounted IM B3), as the ABB, WEG and Siemens/Innomotics manuals
  describe one. **The take-apart order is derived from how the motor is built, not from a manual** (the user,
  2026-11-09): none of those manuals gives a numbered dismantling sequence; the order is the one the parts allow (the
  fan cowl, the fan, the end shields, the rotor drawn out of the stator towards the drive end, the bearings off the
  shaft), and each part cites what the manuals do say about it. **Simplified:** the bearing caps are part of their end
  shields; the stator core is not drawn apart from the frame (its bore is the frame's), the winding is its two end
  turns (brass); the rotor is a plain core on its shaft (no cage bars drawn); the non-drive-end shield is the frame's
  end as the plant draws it, its spigot in the bore; the fan has eight straight radial blades (it cools whichever
  way the motor turns: `tests/test_workshop.gd` checks that no fan blade leans); the terminal box is one part with
  its terminals as anchors (`u1`, `v1`, `w1`). The plant draws the drive-end shield smaller than the frame, so its
  four bolts stand on its own face. In the pump's explode the motor is lifted off the baseplate whole first and its
  parts come apart above the pump (so that the back pull-out unit has room); the guided steps leave it standing, as
  the spacer coupling lets a real one stay. The bearings are fitted on the rotor's shaft before it goes in and come off
  it once it is out (in the guided steps they ride with it). The bench (later) will need the parts drawn in the
  `shaft` node (the pump's shaft, impeller, seal and bearings, the motor's rotor and fan) turned with it: today only the
  coupling (in the pump) or the rotor (in the motor) carries the `shaft` anim.
- **pump_horizontal** (the end-suction branch, K6): a back pull-out end-suction pump (the OH1 configuration in API 610's terms; the Goulds 3196 itself is an
  ASME B73.1 pump) as the Goulds
  3196 i-FRAME manual (maintenance pp. 73–84, reassembly pp. 102–132) and the Flowserve Mark 3 ISO instructions
  (§6.8, §6.10) take it apart: the coupling guard, the coupling and the motor off; the back pull-out unit (the bearing
  frame with the casing cover, the seal, the shaft and the impeller) drawn back out of the volute, which stays on its
  pipes; on the bench the impeller and the casing cover forwards, the shaft with its bearings and seal out of the
  frame at the coupling end; the seal and the bearings off the shaft. The guided steps fit each part in its place
  (a part's parent first), so the unit put together on the bench and the bearings fitted before the shaft goes in are
  said in the steps' reasons; the explode shows them coming out whole. **Simplified:** the spacer coupling is one part
  with its hubs (a real one's spacer drops out and the hubs stay on the shafts); the volute's passage is a plain
  chamber round the impeller (the plant's offset scroll shell outside it); the impeller is closed, six vanes in two
  straight pieces each, curved back against the shaft's turn (`tests/test_workshop.gd` checks the curve from the
  vanes' faces); the seal is one ring; the bearing frame's oil, the labyrinth seals and the gasket are not drawn; the
  discharge pipe starts in the scroll's wall (in the plant it reaches into the chamber); the casing's foot stops under
  the impeller's chamber and the bearing frame's foot is notched under its bore (the plant's reach in, where the
  impeller and the shaft turn); the shaft's end stands in a blind bore in the end cover, as the motor's shaft's ends do
  in its end shields (the plant draws their faces closed); the twelve casing bolts are
  the plant's bolt ring as a fastener group. The multi-stage barrel pump (`head_m` over 150) has no tree yet; the data
  file names an end-suction pump the plant has three of. **The stand-ins:** the pump's casing, scroll, nozzles and
  bearing frame are one stand-in, and the motor's frame, end shields and cowl another: the plant draws their caps with
  their circles' points listed the other way round (for an odd number of segments, other points of the same circle),
  so each split face lists its points as its own cylinder does (`C._face`), and only the cowl's face to the frame
  keeps the plant's points, with a seam of thin triangles (`C._zip`), so that the outline is the plant's within 1 mm.
- **valve_control** (the pneumatic actuator's branch, K6: kit/parts_valves.gd `_cv_*`): a cage-guided globe valve
  (as the Fisher easy-e ES) under a spring-and-diaphragm actuator (as the Fisher 667) with a digital positioner. The
  order (the data file's `assembly`, reversed for taking apart) follows the ES manual (the stem connector parted and
  the actuator off by its yoke locknut, the bonnet nuts and the bonnet, the packing; then the plug and stem, the cage
  and the seat ring) and the 667's (the casing cap screws, the upper casing, the diaphragm, its head and the stem, the
  lower casing), with SAMSON's 3241 and 3271 instructions as second sources; the positioner's feedback is a magnet on
  the stem connector (DVC6200). The guided steps put the actuator together on its yoke in place, where the shop does it
  on the bench and sets it on the valve whole (said in the yoke's step); the explode lifts it off whole first. **Simplified:**
  the body's flow passages are not drawn: its gallery is a round well from under the seat up to the bonnet, closed at
  the bottom, and the skin's top round the bonnet is a sloped lid from the gallery's rim to the skin (the plant draws
  the bonnet's flange sunk into the body's bulge); the cage is two rings and four posts (its windows' shapes, which give
  the characteristic, are not drawn); the gaskets, the packing's spacer and the plug's pin are not drawn; the packing
  is one ring and its flange the plant's gland; the yoke is the plant's two arms and head (the actuator stem passes
  through its solid head; the yoke locknut, the spring adjuster and the seal bushing are not drawn); **the spring sits
  inside the lower casing** under the diaphragm head (in a real 667 it sits in the yoke under the lower casing, put in
  from below), five turns drawn as rings; the diaphragm is a flat disc on its head and moves with the stem (a real
  one's edge is clamped between the casings' flanges and rolls); the diaphragm head, the diaphragm and the stems are
  drawn at the closed position (the plug on its seat: `tests/test_workshop.gd _seats` checks it sits there, covers the
  seat's bore and lies on the stem's axis); the positioner is the plant's box with its gauges, the tubing the plant's
  one straight tube (thin). The electric and hydraulic actuators have no tree yet. **The stand-ins:** the plant's body,
  neck, bonnet and diaphragm casing are one stand-in (the neck is not drawn in the Workshop: it lies under the lid), the
  stem another (split at the stem connector into the valve stem and the actuator stem); the bonnet's and the casing's
  bolt rings are fastener groups. **Known limits** (the tree is built and tested for the data file's DN 150 valve only, as the
  Workshop builds one scene per kind; WORKSHOP.md §5's scenes per equipment need these first): the plant's neck shows
  a few millimetres through the body's flats, where the Workshop's lid lies up to about 3 mm inside it; from DN 250 the
  Workshop's bonnet is drawn with the flange's segment count (9) round the plant's 8-sided bonnet, about 2 mm proud of
  its flats; at DN 32 and below the gallery is wider than the body's polygon and the generator refuses it (an assert).

- **pump_vertical** (the wet-pit pump, K6: kit/parts_rotating.gd, its motor from parts_common.gd `motor_v`): a
  wet-pit vertical turbine pump of two stages, as the Goulds VIT manual (bowl assembly p. 6, figs 1–4, disassembly §6
  p. 31, reassembly pp. 32–33) and the Flowserve VTP user instructions (§6.8) describe one; the data file names a pump
  the plant has three of (550 m³/h, 30 m, 75 kW, a 6.5 m pit). The sole plate and the discharge head (hollow round
  the shaft, its branch and flange, its motor stand) stay; the packing box in the head's top; the column in three
  sections, each joint's flanges on the upper section with the lineshaft's bearing in its retainer and the joint's
  eight bolts a fastener group; the discharge case, the two bowls and the suction bell (the plant's lathe split at its
  profile points and once more in its third segment); the pump shaft with two enclosed impellers on their taperlocks,
  five vanes each curved back against the turn (`tests/test_workshop.gd` checks the curve from the vanes' faces); the
  spacer coupling; the head's eight hold-down bolts; and a vertical motor up to 500 kW with its own tree (the stator
  in its frame, the drive-end bracket that is its mounting flange with the lower guide bearing, the top bracket with
  the thrust bearing that carries the pump's thrust, the fan, the drip cover, the rotor, the terminal box). **The
  motor's order is derived from how it is built, not from a manual**, as the motor kind's is: every step says so.
  The guided steps put the pump together as Goulds does, from the bell up (each impeller slid over the shaft and its
  taperlock driven, the next bowl bolted on), the column section by section, the head, the seal, the motor on the
  stand and the coupling last (its adjusting nut sets the impellers' lift); taken apart, the reverse. **Simplified:**
  the lineshaft and the bowl shaft are one shaft (a real one is in sections joined by threaded couplings); the
  impellers are drawn radial between flat shrouds; the bowls' diffuser vanes, the column's shaft enclosing tube
  and the taperlocks themselves are not drawn; the bell's mouth is closed by a flat plate (a real one is open,
  often behind a basket strainer: the Workshop's insides are hidden pieces, which no opening may show); the coupling
  is one part with its hubs and comes out sideways through the stand's window; the stand's two rings are the plant's
  discs with a bore round the shafts; the sole plate is the plant's solid box, the shaft drawn stopping at its faces (a real
  one has the column's opening); the packing box sits inside the head's top (the plant's stand ring is over it) and
  the explode draws it down inside the head. The motor's bearings, rotor and fan turn in the `shaft` node with the
  pump's shaft and impellers. **The explode:** the coupling out sideways and the motor lifted off first, its parts
  apart above (the drip cover ahead of the fan ahead of the top bracket ahead of the rotor); the string in the pit is
  drawn apart downwards, each part below moving farther, the impellers rising out of their bowls, while the shaft
  stays (a real pump is lifted out of the pit whole and laid down to be taken apart: the steps' reasons say so). A
  motor over 500 kW (the circulating water pumps') is one component. **The stand-in:** everything of the pump's
  casing the plant draws (the head, its branch and flange, the stand's rings, the column with its joints, the bowls)
  is one, and the motor's flange, frame and drip cover another. The plant draws the bowls after the joints' bolts, in
  their material, and so does the Workshop; its odd-segment discs list their circles' points mirrored, so the
  stand's lower ring is drawn about the downward axis and the upper about the upward one, and the motor's flange's
  face down keeps the plant's points with a seam (`C._zip`): the outline is the plant's within 1 mm. **Known limits** (built and tested
  for the data file's pump only, as the Workshop builds one scene per kind; WORKSHOP.md §5's scenes per equipment need
  these first): the column's sections and joints follow the pit (`int(pit / 3)` joints), so a 9 m pit has a fourth
  section and a 3 m one a second only, which the data file's names don't match; a motor over 500 kW has no tree; from
  a column of about DN 500 the shaft is wider than the stand rings' bore; under about 22 kW the fan stands through the
  drip cover's ceiling.

- **valve_gate** (a manual handwheel on top, K6: kit/parts_valves.gd `_rising`, `_gv_*`): a bolted-bonnet
  outside-screw-and-yoke gate valve, as the Crane Pacific cast steel valves' manual draws, lists and takes one apart
  (the gland's nuts, the bonnet's, the bonnet lifted with the stem and the wedge, the wedge off the stem, the stem
  drawn out, the packing; the handwheel and the stem nut last; the seat rings never). The yoke is the bonnet's own, as
  Crane's is. **Simplified:** the body's flow passages are not drawn (as the control valve's): the wedge and the two
  seat rings stand in a round well under the bonnet, as wide as the plant's bonnet flange lets its opening be, so the
  seat rings' bore is a little under half the pipe's (the well stands inside the bonnet studs' circle, and its
  opening is cut from the skin's bulge and cones) (a real gate valve's is the pipe's); the wedge is a round slab whose
  faces lean 5° (thicker at the top), the rings' faces lean with them (`tests/test_workshop.gd _wedge` checks that the
  wedge lies on both rings at 0 travel, covers their bore, and clears it at full travel); the stem's T-head and the
  wedge's slot are not drawn; the gasket and the backseat bushing are not drawn; the stem nut stays in the yoke's
  head, which the plant draws as one closed block (a real one comes out of it once its retainer is off), and the
  handwheel sits on top of the head without the nut showing. Drawn at the closed position: opened in the bench (later),
  the wedge would rise into the plant's bonnet, which is narrower than it. **The stand-ins:** the plant's body, neck,
  bonnet flange and bonnet are one (`body`, `bonnet`), its bonnet bolt ring a fastener group.
- **valve_globe** (a multi-turn electric actuator, K6: `_rising`, `_gv_stem`, `_gl_*`): a bolted-bonnet globe valve
  (Crane's: the operator off first, then the gland, the bonnet, the disc freed from the stem, the packing; the seat
  ring stays) under an electric actuator with an output drive type A (AUMA SA: the stem nut turns in the drive on its
  thrust bearing, and Crane takes the actuator off by unscrewing it off the stem with its handwheel, so the stem nut
  rides with it). **Simplified:** the actuator is one part (its motor, worm gear, switches and controls not drawn: its
  maker's service opens it), sealed with its stem nut, display (a thin part) and handwheel, which come off the valve
  with it; the body's passages are the control valve's well
  (`_cv_body`), the disc a plain plug on the seat ring (`_seats` checks it as the control valve's); the block and
  travel pointer in the yoke's window are the stem's (Crane names none: the plant draws it); the four actuator
  bolts stand under the actuator's flange beside the yoke's head, which the plant draws smaller than the flange.
- **valve_butterfly** (a part-turn electric actuator, K6: `_quarter`, `_bf_*`): a resilient-seated butterfly valve
  with a one-piece shaft, as Bray's Series 35/36 (its disc on taper pins; the actuator off, the gland, the pins, the
  shaft out through the top with its bushing and packing, the disc, the seat squeezed out) under an AUMA SQ part-turn
  actuator (the coupling on the shaft first, the actuator over it). **Simplified:** the body is the plant's closed
  drum (its faces meet the pipe's flanges), so the disc comes out through the face and the shaft through the neck's
  closed top flange in the explode; the taper pins and the bottom plate with its thrust bearing are not drawn (the
  steps say where they come out); the liner is a plain rubber ring round the bore (`tests/test_workshop.gd _discs`
  checks that the disc's edge lies on its bore, within its width, and lies edge-on when turned by its travel); the
  actuator is one part, sealed with its coupling, its position indicator (the plant's, turning with the disc) and its
  handwheel, and the shaft sealed with its bushing and packing (Bray drives them out together). **The stand-in:** the plant's drum lists its first face's points mirrored (an odd circle): the Workshop
  draws the plant's drum and closes it with a seam (`C._zip`); the disc's face the same, hidden.
- **Known limits** of the three (built and tested for the data files' sizes only, as the Workshop builds one scene per
  kind): the gate's well follows the bonnet flange (refused below DN 80, where its wedge has no room) and the
  globe's the control valve's (refused at DN 32 and below); the gate's lid drops below the bonnet's seat towards the
  cones, so a boss under the bonnet flange (the body's) closes the view under it;
  the other actuators of each kind have no tree.

- **fan_axial** (the cooling tower fan, K6: kit/parts_rotating.gd `_fan_*`; the data file names the plant's fan, 9.5 m,
  eight blades, 200 kW, a 3 m stack): an adjustable-pitch fan on a Hudson Tuf-Lite 6000 series hub, an Amarillo double
  reduction right-angle gear drive under it, an Amarillo composite drive shaft through the stack's wall to a motor on
  the deck. **The orders** (the user's decision, 2026-11-14): Hudson gives only the installation (the hub on the gear
  drive's shaft, the blades clamped between its plates, pitch and track, the seal disc), so **the fan comes apart in
  the reverse of Hudson's installation**, and its steps say so; the gear drive follows Amarillo's repair instructions
  (disassembly §1-4: the oil seal plate, the seal carrier and the intermediate bearing cover with their shims, the
  vertical cover, the output and intermediate shafts lifted out together, the horizontal carrier, the lower covers;
  then each shaft pressed apart); the drive shaft comes off in the reverse of Amarillo's installation steps (said in its
  step); the motor's order is derived from how it is built, as the motor kind's. **Simplified:** the plant's fan turns
  anticlockwise seen from above (its `shaft` node's axis is up) and its blades are pitched for that turn, so they push
  the air up (`tests/test_workshop.gd _blade_lean` checks it, and that the same blades turning the other way fail):
  Hudson's turn clockwise, so the plant's fan is their mirror image; the blades are flat plates (one part: a blade can
  be changed alone, the steps say so; one part turns on the shaft's line, as `_turning` asks); the hub is one part
  (its spool, two plates and the blade clamps; its bushing and the thrust retainer not drawn) and the blades' 32 clamp
  bolts are inside it (hidden), drawn backing out downwards, the way their nuts come off; the seal disc is the plant's
  dome, closed underneath, on six bolts; the gear case is the plant's closed box (0.9 x 0.7 x 0.6 m whatever the
  fan's size) with everything inside it hidden: the vertical cover is a plate inside its top and the input shaft's
  carrier sits inside its side, so they and the shafts come out through the box's faces in the explode (listed in
  `PASSES`); the plant draws the box's top 0.1 m up inside the hub, so the hub turns round it (listed in `RUBS`, the
  only such pair: everything inside the box stays clear of the hub); gears are plain discs with a gap where they mesh
  (no teeth); the bearing cups are part of the case and the cover; the inspection plates, the oil pump and the oil
  lines, the shim packs, spacers and keys are not drawn; the intermediate shaft and the input shaft are drawn standing
  (only the output shaft turns with the fan in the `shaft` node); the drive shaft is the plant's one tube (its two
  hubs, flex discs and spacer tube one part), the guard the plant's; the motor is the motor kind's tree, its rotor
  drawn standing (the fan's `shaft` node turns about another axis); the stack is thin (the plant draws it open). The
  gear drive is drawn taken apart in place, where Amarillo takes it off the tower to a shop. **The explode:** the guard,
  the drive shaft and the motor come off first and the hub lifts with its blades above the stack, then the blades and
  the seal disc leave it; the gear drive's parts come out upwards and the input shaft's carrier sideways, and each
  shaft's parts come off its nearer end. The gear drive's oil sample (REALISM.md §2.19) is now drawn from the gear case
  (`gb_case`). **Known limits** (built and tested for the data file's fan only): the gear drive's size does not follow
  the fan's; another blade count gives another `sym` but the same component.
- **generator** (the air-cooled turbo-generator, K6: kit/parts_machines.gd `_gen_*`; the plant's first generator, the
  gas turbine's, built with its shaft line: the coupling at the drive end): the stator in its frame (core, end
  windings), the end shields in halves at both ends, a fan shield round each of the rotor's fans, the bearing pedestals
  with their top halves, the rotor (body, retaining rings, two fans of straight blades), the coolers on top
  and their pipes, the terminal box, the brushless exciter (its stator and rotor) under its hood; the coupling's bolts.
  **The order** is BHEL's overhaul tender's (the user's decision, 2026-11-14: a contract scope for a hydrogen-cooled
  250 MW machine, **not a maker's manual**, which the data file and every step say), with WEG's S line manual (§8.1,
  §8.2) as the second source: the bushings, the bearings' top halves and the coupling, the exciter's hood and the
  exciter off its bed, the pipes and the coolers, the end shields' upper halves and the fan shields, the bottom end
  shields and the bearings, the rotor threaded out. The hydrogen seals and their seal oil are left out (this machine is
  air-cooled: the steps say so). **Simplified:** the plant's frame, bearing pedestals and exciter hood are one stand-in
  (all its identify-class paint), split into the frame's walls (closed by a wall inside and a ring at each end), the end
  shields' halves (slabs whose outer faces are the plant's ends), the pedestals and their caps (cut at the shaft line)
  and the hood; the plant draws the end shields' faces closed, so the rotor's shaft stops at their inner faces, and the
  pedestals are its boxes cut at the shaft line, so the journals are not drawn in them; the bearings' shells and oil catchers are their pedestals' and caps'
  (not drawn apart); the rotor's slots, wedges and winding are its body, its fans twelve straight blades (they lean
  neither way: `tests/test_workshop.gd` counts no leaning row) whose tips, like the retaining rings, pass through the
  stator's bore and the fan shields when it is threaded out; the bushings are inside the terminal box (one part), which
  the plant draws sunk in the plinth and which stays; the exciter's bed is not drawn (the plant's hood overhangs the
  plinth) and its coupling to the rotor is not drawn; the exciter's hood is the plant's closed drum, lifted over the
  exciter (listed in `PASSES`), and its end grille is the plant's disc 10 mm off the hood across the shaft's end (in
  `RUBS`); the coolers are two bundles in the plant's housing (its lifting lug on it), the pipes
  thin. **The explode:** the coolers, the hood and the exciter under it lift, the pipes move off, the end shields' upper
  halves lift and their lower halves and the pedestals move aside (the bearings' top halves then lift off them), then
  the fan shields slide out along the shaft and the rotor is threaded out through the drive end. **Known limits:** a
  hydrogen-cooled generator has no tree; built and tested for the plant's first generator only.

## Tables and their sources

The kit derives what a part looks like from what its content says it is (§9: content says what the equipment *is*).
The numbers are rounded typical values from these sources, good for the look, not for design:

- **Outside diameters by DN**: `kit.json dn_od_mm` (EN 10220 / ASME B36.10).
- **Flanges** (`parts_common.gd flange_dims`): outside diameter, thickness and bolt count of EN 1092-1 PN 16 flanges,
  fitted as functions of the pipe's outside diameter (DN 100: 212 mm, 8 bolts; DN 300: 472 mm, 12 bolts; DN 1400:
  1,680 mm, 36 bolts); higher ratings up to 60 % thicker.
- **Valve face-to-face lengths** (`parts_valves.gd ftf`): EN 558 basic series, fitted (gate DN 300: 456 mm, series
  15; globe DN 100: 340 mm, series 1; double-flanged butterfly short pattern).
- **Handwheels** (`wheel_r`): makers' tables, about 160 mm for DN 50 to 400–600 mm for DN 300.
- **Motor frames** (`motor_dims`): IEC 60072-1 shaft heights by power for 4-pole totally enclosed fan-cooled motors
  (makers' catalogue ranges); the body's diameter about 1.85 × the shaft height, its length 3.3 × plus 0.1 m.
- **Pipe support spans** (`parts_pipes.gd SPANS`): ASME B31.1 Table 121.5 (water service) to DN 600, extrapolated
  to 12 m above.
- **Pump sizes**: nozzles for 3 m/s (suction) and 4.5 m/s (discharge); a pump is multistage above 150 m of head.
- **Water treatment** (`parts_water.gd`, docs/plant3d/WATER-TREATMENT.md §1 for the sources): clarifier and
  thickener walls 0.3 m of concrete with 0.35 m freeboard, the solids-contact centre well about 0.28 × the radius;
  gravity filter cells with two wash troughs each and a pipe gallery between the rows (Ten States Standards §4.3);
  RO pressure vessels of 8-inch elements (1.016 m each) racked three high, permeate ports on the end caps (FilmTec
  manual); bar screens at 75 mm, inclined at 75°; mixed beds with dished heads (0.2 × the diameter) and a frontal
  valve nest; dosing skids sized from their day tank (height about 1.3 × its diameter); filter press plates of
  0.8–1.6 m.

## Looking at it

```
tools/plant3d/bench/offscreen.sh godot --display-driver x11 --rendering-driver vulkan --path apps/plant3d \
  --script res://kit/gallery.gd -- --out=DIR [--parts=a,b] [--tier=full|lean+vis]
```
