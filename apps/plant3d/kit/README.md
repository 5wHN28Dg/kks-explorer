# The parts kit

Every piece of equipment in Walkdown Plant is made here, by code, from the parameters its content gives
(docs/PLANT3D.md §9, decision 0054 §1, §5). The content build (`builder/kit_place.gd`) places the parts; nothing here
runs when the app starts (the app loads the built scenes).

| File | What |
|---|---|
| `kit.gd` | the entry point: `Kit.make(part, params, ctx)`, the part list (`MAKERS`), the triangle budgets (`BUDGET`) |
| `mesh.gd` | the mesh builder: primitives in a part's frame, layers per material and visibility class, LODs |
| `parts_*.gd` | the generators, one file per group: machines, rotating, heat exchange, vessels and HRSG, valves, instruments and people cues, electrical, pipes |
| `parts_common.gd` | what many parts share: flanges and bolts, nozzles, baseplates, motors, couplings and guards, rails, ladders |
| `materials.gd` | the materials, the texture sets and the texture tiers |
| `fetch_textures.sh` | the CC0 textures, pinned by SHA-256 (never committed) |
| `gallery.gd` | pictures of every part, to look at (needs a display: `tools/plant3d/bench/offscreen.sh`) |

Every part of `data/plant3d/kit.json` outside the `structures` group has a generator (the structures are the
builder's own: walkable surfaces, stairs, ladders, buildings, pits, slabs, fences, the pipe rack). `tests/test_kit.gd`
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
- `group`: the node only holds others that move (a damper's blades): move its children.

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
nothing to stand on is reported by the build as a warning.

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

The first train (2026-10-16): 302,944 triangles at full detail in all, in 1,112 instanced or merged meshes (cells of
12 m, 6 m for detail; pipes and large parts cut by cell); 176 pipe
supports. The bench that decided the engine (0041) had 1.46 M triangles.

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

## Looking at it

```
tools/plant3d/bench/offscreen.sh godot --display-driver x11 --rendering-driver vulkan --path apps/plant3d \
  --script res://kit/gallery.gd -- --out=DIR [--parts=a,b] [--tier=full|lean+vis]
```
