# Walkdown Plant content format, format 1

**Status: DRAFT 2026-10-15**, written before any app code (decision record 0054). It is frozen like the courses
(COURSES.md) once the first train's content (docs/plant3d/FIRST-TRAIN.md) loads and passes the vectors; after that a
change needs `"version": 2` and a new vector file. Requirements: https://github.com/5wHN28Dg/kks-explorer/wiki/3D-plant
(R1–R10). Engine: decision 0041.

**Format 2 (DRAFT 2026-10-22, §14–§19)** adds staff who work the plant (roles, rosters, routines, tasks; the trainee
plays any role), permits to work and isolations that change the model, and the site beyond the train (water
treatment plant, camp). Its content plans: docs/plant3d/STAFF.md, WATER-TREATMENT.md, SITE.md; its milestones:
docs/plant3d/MILESTONES.md; decisions 0062–0066. Format 1 content stays valid under format 2 (§14).

**Multiplayer (DRAFT 2026-10-26):** docs/plant3d/MULTIPLAYER.md (deterministic lockstep of this engine, decisions
0067–0069). Milestone MP1 (as built, §17.13–§17.14): several trainees in one engine, one per player's slot, and the
state digest the players compare, with their vectors.

The plant you walk through in Walkdown Plant is **data**, like a course: a *description* (where every piece of
equipment, pipe and structure is), built from a **kit of parametric parts** (what each kind of thing looks like), made
alive by a **behaviour model** (how values change when someone operates the plant), and used by **procedures and
tours** (what a trainee does and sees). Nothing in the content runs code. The plant is invented (R1): every code
follows the public KKS key, none comes from a real plant.

| File | What it holds |
|---|---|
| `data/plant3d/plant.json` | the plant: its name, its KKS key tables, the colour scheme, the list of areas (§2) |
| `data/plant3d/areas/<area>.json` | one area's equipment, pipes and structures (§3–§5) |
| `data/plant3d/model/<area>.json` | that area's behaviour (§7) |
| `data/plant3d/procedures/<id>.json` | one procedure or tour (§8) |
| `data/plant3d/scenarios/<id>.json` | a starting state and its faults (§7.8) |
| `data/plant3d/sounds.json` | the sound library (§11), format `walkdown-plant-sounds` |
| `data/plant3d/sounds/<file>.ogg` | the recorded clips the library names (§11) |
| `data/plant3d/kit.json` | the parts kit's interface (§9), format `walkdown-plant-kit`: what the validator knows of each part |
| `data/plant3d/screens.json` | the control room screens (§7.11), format `walkdown-plant-screens`: which systems each screen shows and where (optional) |
| `data/plant3d/staff.json` | (format 2) the people who work the plant: places and ways, roles, people, rosters, routines, tasks, reactions, zones (§16), format `walkdown-plant-staff` (optional) |

The first train's files are made by `tools/plant3d/make_content.py` (repeated pieces such as twelve thermocouples or
ten fans stay consistent), and the tests check that the committed files are exactly what it makes.

The app never reads these files at run time. They are checked by the reference validator (`ref/plant3d.py`,
strict JSON as the repository's other readers: duplicate keys, trailing commas and the like are refused, which
Godot's own JSON parser does not do), then the build (0054) turns them into pre-built Godot scenes and a compiled
model; the app loads those. The build also refuses anything it can't draw, so a description that passes both is one
the app shows.

## 1. JSON rules

As COURSES.md §1, with these differences:
- **Identifiers** (area, part, value, procedure, step, scenario, sound names) match `[a-z_][a-z0-9_]{0,31}`.
- **KKS codes** match the grammar of §6 and are written without spaces.
- **Unknown keys are invalid**; every file names its format and version: `{"format": "walkdown-plant-<kind>",
  "version": 1, …}` (`walkdown-plant` for plant.json; `-area`, `-model`, `-scenario`, `-procedure`, `-sounds`).
- **Times** in content (`tau`, `delay`, `on`, `off`, …) are multiples of the model step, 0.1 s (§7.10).
- **Units:** metres, seconds, degrees, kilograms; process values in the unit named on the value (§7.1). Pipe sizes in
  millimetres (`dn`, `od_mm`, `insulation_mm`) because that is how they are written on drawings and data sheets.
- **Coordinates:** plant coordinates, **x east, y north, z up**, in metres from the plant's origin (the plot plan's
  reference point, FIRST-TRAIN.md). The build converts them to Godot's y-up axes. A heading (`yaw`) is in degrees
  clockwise from north, as on a plot plan.
- **Limits** (the build refuses the file above them, error `limit`): file size 16 MiB; per area 4,000 equipment items,
  2,000 pipes, 2,000 structures; per pipe 256 points (`from`, `points` and `to`); per model (all areas joined) 4,000
  values, 500 alarms, 64 machines; per procedure 200 steps.

## 2. The plant

```json
{"format": "walkdown-plant", "version": 1, "id": "ccpp", "title": "Generic 2-2-1 combined-cycle plant",
 "frequency_hz": 50,
 "kks": {"units": {"1": "Gas turbine train 1", "2": "Gas turbine train 2", "3": "Steam turbine unit", "0": "Common"},
         "systems": {"MBA": "Gas turbine: turbine and compressor", …},
         "equipment": {"AA": "Valve, damper (with actuator)", "AP": "Pump unit", …},
         "measurements": {"CP": "Pressure", …},
         "source": "Codes from the public KKS key (sources: docs/plant3d/FIRST-TRAIN.md §1); meanings in our own words"},
 "media": {"feedwater": {"group": "water", "band": "#2e7d32"}, "steam_hp": {"group": "steam", "band": "#c62828"}, …},
 "areas": ["control", "bop", "gt1", "trafo1", "hrsg1", "st", "cw", "ct"],
 "ext": ["ambient_t", "ambient_wb", "grid_frequency"],
 "start": {"at": [-20, 0, 0], "yaw": 90}}
```

- **`kks`** is the plant's own decoder table, written from the public key (FIRST-TRAIN.md §1). The app decodes a code
  with it (§6), so it never needs Walkdown's `data/kks.json`, whose tables come from a real plant's drawings (R1).
  It holds **only the codes this plant uses**, each with a short meaning in our own words: VGB sells and licenses the
  full key tables, also for use "in electronic systems" (FIRST-TRAIN.md §1), so they are not copied in.
- **`media`:** the fluids and gases the pipes carry. `group` picks the colour group (water, steam, air, gas, oil,
  chemicals, flue gas); `band` the colour of the identification band and flow arrow painted on the pipe. The groups
  follow the idea of DIN 2403 (identification of pipelines by the medium carried: water green, steam red, air grey,
  flammable gas yellow); the colours are ours, picked to stay distinguishable in daylight and dark scenes and to
  colour-blind eyes, and checked on every tier (the "look" rule). `name` (optional, up to 40 characters) is the service name
  stencilled in black on its pipes beside the flow arrows, as plants label their lines.
- **`areas`:** in this order the area files are read and their models joined (§7.1).
- **`ext`:** the values the plant's surroundings set (ambient temperature, the grid), given by the scenario (§7.8).
- **`start`:** where a trainee stands when the app opens (the control room).
- The keys above are all the keys plant.json has (`…` in the example stands for more table entries).

## 3. Areas and equipment

An area is a part of the plant that is built, loaded and (later, 0054) shipped as one piece: a gas turbine with its
building, an HRSG, the turbine hall, the cooling tower.

```json
{"format": "walkdown-plant-area", "version": 1, "id": "cw", "title": "Circulating water pumps",
 "bounds": [[140, -20], [165, 20]], "pack": "base",
 "equipment": [Equipment, …], "pipes": [Pipe, …], "structures": [Structure, …], "signs": [Sign, …]}
```

- **`bounds`:** the area's plan rectangle, `[[x0, y0], [x1, y1]]`. Areas don't overlap; everything in an area lies
  inside it, apart from pipes and cable trays, which belong to the area of their `from` end and may run through other
  areas and the ground between them to reach their end.
- **`pack`:** the content pack the area ships in (`base` for everything in the first train; 0054).

**Equipment** is one thing with a code:

```json
{"kks": "30PAC10AP001", "name": "Circulating water pump A", "part": "pump_vertical",
 "at": [150, -8, 0], "yaw": 0,
 "params": {"flow_m3h": 15000, "head_m": 22, "motor_kw": 1250, "pit_depth": 9},
 "plate": "motor_side",
 "parts": [{"kks": "30PAC10CP501", "name": "Discharge pressure gauge", "part": "pressure_gauge",
            "at": [1.1, 0, 2.6], "params": {"range": [0, 4], "unit": "bar"}}]}
```

- **`kks`:** unique in the plant. Equipment without a code of its own (a handrail, a lamp) is a structure (§5).
- **`name`:** what the trainee reads next to the code. Plain text, 1–80 characters.
- **`part`:** a kit part (§9); **`params`:** that part's parameters. Missing parameters take the part's defaults; an
  unknown parameter is invalid.
- **`at`, `yaw`:** the part's origin (§9 says where each part's origin is) and heading. `tilt` (`[pitch, roll]`,
  degrees) is optional for the rare part that isn't upright.
- **`parts`' positions** and every position of an area's content lie inside the area's `bounds` (in plan),
  `outside_area` otherwise; a part's position is its parent's plus its own `at` turned by the parent's `yaw`.
- **`plate`:** where the KKS tag plate is fixed (`none`, or a mounting point the part names). Tag plates are what a
  trainee looks for in the field, so they are drawn on every tier (§10).
- **`parts`:** smaller equipment fixed to this one (instruments, actuators, local push buttons). Their `at` is
  relative to the parent's origin and heading. One level only.
- **Nozzles:** every part names its connection points (`inlet`, `outlet`, `suction`, `discharge`, …; §9). Pipes end
  on them (§4), so a moved pump drags its pipe ends with it.

## 4. Pipes

```json
{"kks": "30PAB10BR010", "name": "Circulating water supply", "medium": "cooling_water",
 "dn": 2200, "insulation_mm": 0, "buried": [[1, 3]],
 "from": {"kks": "30PAC10AP001", "nozzle": "discharge"},
 "points": [[150, -14, 1.5], [150, -14, -6], [150, -30, -6], [40, -30, -6]],
 "to": {"kks": "30MAG10AC001", "nozzle": "cw_inlet_a"},
 "valves": [{"kks": "30PAC10AA101", "part": "valve_butterfly", "at": 0.02,
             "params": {"actuator": "electric"}}],
 "arrows": 25}
```

- **The route** is `from`, then `points`, then `to`: a polyline through the centre of the pipe. Each end is
  - a nozzle, `{"kks": …, "nozzle": …}`: the route leaves (or enters) it along the nozzle's direction, within 1°
    (`bad_route` otherwise); a pipe can't end on a tilted part (`unsupported`);
  - another pipe, `{"pipe": code, "at": [x, y, z]}` (a branch on a header): the point lies on that pipe's route,
    within 1 cm;
  - a free point, `{"at": [x, y, z]}`, only at or below ground (z ≤ 0: a pipe coming out of the ground or ending
    in a pit); above ground every pipe ends on a nozzle or another pipe.
- **The area:** a pipe belongs to the area whose file lists it, and its `from` end lies inside that area.
- **Bends** are made at every corner with a radius R of 1.5 × the outside diameter (`bend` may say `3d` or `5d`).
  A bend turning by θ takes R · tan(θ/2) of each segment beside it; a segment shorter than what its two bends take,
  points that coincide, or a corner turning by 179° or more, is invalid (`bad_route`: the content is wrong, not the
  drawing).
- **`dn`:** nominal size; the outside diameter comes from the DN table (EN 10220 / ASME B36.10 sizes in the kit), or
  from `od_mm` (0.9–1.5 × DN; required for a DN the table lacks). **`insulation_mm`:** 0 for bare pipe; insulated pipe is drawn with metal cladding.
- **`medium`:** a key of the plant's `media`: the band colour and the flow arrows painted on the pipe every `arrows`
  metres (0 = none), pointing from `from` to `to` (or the other way when the model says the flow reversed).
- **`buried`:** stretches that run below ground: not drawn, shown on the overview map. The route's points are
  numbered `from` = 0, then `points`, then `to`; segment i joins point i and point i + 1; `[a, b]` covers segments a
  to b, both included. (In the example the pipe leaves the pump in the pump house at +1.5 m, standing on its floor, goes
  down, runs buried along y = −30 at −6 m and enters the condenser pit at the same depth.)
- **`valves`, `parts`:** inline equipment at a fraction of the route's length (`at` 0–1), turned to the pipe.
  Instruments on a pipe (a thermowell, a pressure tapping) are `parts` with a `side` (top, bottom, left, right).
- **Supports** are made by the build (§9, `pipe_support`) at the spans of the kit's span table for that size,
  standing on the nearest structure below; a span with nothing below is an error the build reports with the pipe's
  code, so pipes never float.

## 5. Structures

Buildings, floors and the ways around them. Structures have no KKS code by default (`kks` is optional: the turbine
hall is `30UMA10`; a stair is just a stair), but every structure has an `id`, unique in the plant. A structure is
placed by `at` and `yaw` (an `outline` is relative to `at`, turned by `yaw`), except stairs and ladders, which are
placed by their `foot` and `top` alone.

```json
{"id": "st_floor_12", "part": "platform", "at": [10, -20, 12],
 "params": {"outline": [[0, 0], [70, 0], [70, 40], [0, 40]], "deck": "concrete", "edge": "handrail",
            "openings": [[[28, 14], [46, 26]]]}}
{"id": "st_stair_w", "part": "stair", "params": {"foot": [3, 12, 0], "top": [10, 16, 12], "layout": "switchback",
 "width": 1.2}}
{"id": "hrsg1_ladder_3", "part": "ladder", "params": {"foot": [96, 53, 30], "top": 34, "facing": 0}}
{"id": "st_door_w", "part": "door", "at": [0, 0, 0], "yaw": 270, "params": {"kind": "personnel", "width": 1.0}}
```

- **Walkable:** `platform`, `stair`, `ladder`, `floor` (inside a building), `road`, `grating`, and the ground
  (z = 0) outside the outline of a `pit` (whose own floor, at its depth, is walkable). The build makes the collision
  shapes from them; nothing else is walkable. A surface is its `outline` at the part's height, less its `openings`;
  a point meets it within 5 cm in height and in plan.
- **Stairs** go from `foot` to `top`; `layout` `straight` or `switchback` (flights folded inside the plan rectangle
  that foot and top span, as in a stair tower: the example rises 12 m in four flights within 7 × 4 m). Stairs keep
  the rise of every step between 0.15 and 0.20 m, the going at least 0.25 m and going + 2 × rise between 0.60 and
  0.66 m; a flight that would rise more than 3.6 m gets a landing as long as the stair is wide. The kit picks the
  number of steps; the stair is valid when some number of steps keeps these rules (`bad_stair` otherwise), with
  the flights f = ⌈rise / 3.6⌉ and, for n steps:
  - straight: going = (plan length − (f − 1) × width) / (n − f);
  - switchback: the short side of the rectangle at least 2 × width, and going = (long side − 2 × width) /
    (⌈n / f⌉ − 1). **Ladders** stand at `foot` and reach the height `top`; the climber faces `facing` (degrees clockwise from north)
  and steps off 0.4 m ahead, which must meet a walkable surface at `top`. Ladders above 3 m get a cage and, above
  10 m, a rest platform. These are
  the common rules for fixed access to machinery (EN ISO 14122-3 and -4; the kit applies them, content doesn't
  repeat them). A stair or ladder whose ends don't meet a walkable surface, or whose flights don't fit, is an error. (The ladder
  example stands on the HRSG's +30 m platform and reaches the drum platform at +34 m, so it gets a cage.)
- **Doors** open when the trainee walks into them or presses them; `kind` is `personnel`, `double` or `roller`.
- **Buildings** (`building`) are a shell: outline, height, roof, wall cladding, and openings for doors, louvres and
  pipes. Inside a building the walls are drawn from inside too.
  `floor` is its ground floor's finish: `epoxy` (painted, the default), `tile` (glazed ceramic tiles, as turbine
  halls' operating floors and walkways are laid) or `concrete` (bare, with its cracks and dust: a ground floor under a
  deck, a pump house). `crane`, when not 0, is the rail height of an overhead travelling crane spanning the hall: its
  runway on the columns along the long walls, the bridge, trolley and hook (drawn, not operated); only in a
  rectangular metal-clad hall, the rail 6 m up or more and at least 3 m under the roof (the build also refuses a
  trolley that would reach into the roof steel). A `floor` or a
  `platform` inside a building takes the same `finish` for a concrete deck.
- **Walls** (`wall`) stand along a `route`, `height` high and `thickness` thick, in concrete: a transformer yard's
  firewalls, a blast wall. They are solid.

**Signs** are labels in the world: `{"text": "CW pump house", "at": [152, -16, 4], "yaw": 180, "size": 0.3}`.
Area and system signs help a trainee find the way (R9a): they are drawn on every tier. A safety sign adds its
ISO 7010 `symbol` (`M003`, wear ear protection, is the one the app draws): the symbol above the text on a white
board fixed to the wall at `at` (on the wall's line), the text black under it.

## 6. KKS codes and links

**Grammar** (the public KKS breakdown levels, FIRST-TRAIN.md §1), written without spaces:

| Level | Characters | Example |
|---|---|---|
| 0 Plant (unit) | `G`: one digit | `3` (the steam turbine unit) |
| 1 System | `F0` digit, `F1F2F3` letters, `FN` two digits | `0PAC10` |
| 2 Equipment unit | `A1A2` letters, `AN` three digits, `A3` optional letter | `AP001` |

A code is level 0+1 (a whole system or machine: `1MBA10` would be read `1` + `MBA10` without F0, so codes always carry
F0: `10MBA10`), or level 0+1+2 (`30PAC10AP001`). Regular expression, with L = `[A-HJ-NP-Z]` (the key uses no I or O): `[0-9][0-9]L{3}[0-9]{2}(L{2}[0-9]{3}L?)?`.
Component level (level 3, e.g. a pump's motor) is not used in format 1: a pump and its motor are one piece of
equipment with one code. This is a subset of what courses accept (`[0-9A-Z]{4,24}`, COURSES.md §3), so any plant
code can be a course link.

**Decoding** reads the plant's `kks` tables (§2): unit name, system name, equipment or measurement name, and the
numbers, shown in the equipment card. A code in the plant's own content whose letters are not in
the tables is invalid (`bad_kks`).

**ISA tags.** Instruments carry, besides the KKS code, the ISA-5.1 function letters printed on the drawing bubble
(`"isa": "PIA"`): first letter the measured variable (P, T, L, F, S, V for vibration, Z for position…), then the
functions (I indicate, A alarm, T transmit, S switch, C control; H/L, HH/LL for alarm levels). The model's alarms
(§7.6) name both, as an operator sees them on the panel.

**Links** (0054):

| Link | Opens |
|---|---|
| `walkdown-plant://kks/<code>` | Walkdown Plant at that equipment: highlighted, with its card; the trainee chooses to walk or fly there |
| `walkdown-plant://procedure/<id>` and `…/<id>/<step>` | a procedure or tour (§8), at its first or that step |
| `walkdown://kks/<code>` | Walkdown at the tag with that code, on its drawing (as a course's code link) |
| `walkdown://course/<course>` and `…/<course>/<page>` | Walkdown's course renderer at that course or page |

- **Codes in links** are read leniently, the plant's own codes strictly: a link's code (`[0-9A-Z]{4,24}`, as in
  courses) is cut to its longest beginning that matches the grammar, then matched; if that ends in an A3 letter and
  is not found, it is tried again without it (a component-level `30PAC10AP001KP01` becomes `30PAC10AP001K`, then
  `30PAC10AP001`). Anything else (another path, a malformed code, an unknown ID) opens the app at its start with a short
  message; links never carry anything but these paths.
- **A code the plant doesn't have** (for example a real plant's code from Walkdown's drawings) shows the plant's
  equipment of the same kind instead, labelled as such: same system letters and equipment letters (`LAC` + `AP`:
  "a feedwater pump in this plant: 10LAC10AP001"; for a code without equipment letters, a system-level code of the
  same system), else the same equipment letters, else the code's decoding only, with letters the plant's tables
  don't have shown as "not in this plant's key". Of several codes of that kind the lowest in code order is shown.
  The reference is `read_link` in `ref/plant3d.py`, and the vectors' `links` (§12) pin it. The code is not stored or sent
  anywhere: Walkdown Plant has no network access (0054).
- **A link out with nothing to open it** (Walkdown not installed): the app says so instead of failing silently.

**Links into Walkdown** (0058). Walkdown's Android, GNOME and Windows apps register the `walkdown` scheme; the web client
takes no links. Walkdown reads a link more strictly than the plant does, because it holds a real plant's data and
acts for a signed-in person (`core/src/kks/applink.nim`, its tests in `core/tests/test_applink.nim`):

- The whole link is at most 128 characters, taken as given: no trimming, no percent-decoding. The scheme
  `walkdown://` is matched in any case (RFC 3986), everything after it exactly.
- `walkdown://kks/<code>` with `<code>` = `[0-9A-Z]{4,24}`: the first tag, in the drawings' order, whose code with
  its suffix is `<code>`, else the first whose code without the suffix is; its drawing opens with the tag selected
  and its panel, as when a course's code link is followed. A code on no drawing says so, nothing more.
- `walkdown://course/<course>` and `walkdown://course/<course>/<page>`, identifiers `[a-z_][a-z0-9_]{0,31}`
  (COURSES.md §1): that course, at that page, or where the learner left off; a course or page the device doesn't
  have opens as a course link to it does.
- Anything else opens nothing and says nothing: another kind, a query or fragment, an empty or extra path segment, a
  user or port, a malformed code or identifier. Walkdown only comes to the front (or starts) as when it is opened
  from the launcher. A device that has not joined a plant opens no link, now or after joining. No link reaches
  anything else in Walkdown: signing in, joining, sending, deleting, importing or fetching.
- A link waits while something unfinished is open over the main screen (the camera or a file picker, a photo being
  marked up, a form being typed): it opens once that is closed, and never takes it away.

## 7. The behaviour model

The plant reacts to the trainee through a declarative model, evaluated at a fixed step of **0.1 s** of model time,
whatever the frame rate. Like a course figure (COURSES.md §9.2), it is an ordered list of named values, each computed
from inputs and earlier values only, plus a small set of stateful nodes. Nothing is a formula: curves are tables made
by the content tools. The model is faked and reduced (R6): it has to show a trainee the right direction, order of
magnitude and time scale of every effect they can cause, not the plant's real physics.

```json
{"format": "walkdown-plant-model", "version": 1, "area": "cw",
 "values": [[name, Node], …], "ops": [Op, …], "interlocks": [Interlock, …], "machines": [Machine, …],
 "alarms": [Alarm, …], "trips": [Trip, …], "bind": [Binding, …]}
```

### 7.1 Values

Names are unique across the plant (area models are joined in `plant.json` order into one list: a stateless node
reads values earlier in that list, so of its own or earlier areas; a stateful node and every condition may read any
value, of a later area too; `ext` values named in `plant.json` are read by any area, §7.7). Each value may carry
`"unit"` (a display string such as `"kPa(a)"`, `"°C"`, `"%"`, `"rpm"`, `"m³/h"`) and `"kks"` (the measurement or
equipment it belongs to).

| node | result |
|---|---|
| `{"const": n}` | a constant (a design value) |
| `{"state": n, "kks": "<code>"}` | an operable state with initial value n: a valve's command 0–1, a pump or fan run command 0/1, a breaker 0/1, a setpoint. `kks` (optional) is the equipment it belongs to. Only ops (§7.2), interlocks, machines (§7.4), trips and faults change it |
| `{"of": ref, "table": [[x, y], …]}` | piecewise linear (COURSES.md §9.2 table rules); `"step": true` for steps |
| `{"sum": [ref, …]}`, `{"product": [ref, …]}`, `{"min": […]}`, `{"max": […]}` | |
| `{"diff": [a, b]}` | a − b |
| `{"select": ref, "cases": [ref, …]}` | as COURSES.md |
| `{"cmp": [a, ">=", b]}` | 1 or 0; also `>`, `<=`, `<` |
| `{"and": [ref, …]}`, `{"or": [ref, …]}`, `{"not": ref}` | logic on values ≥ 0.5 = true; result 1 or 0 |
| `{"lag": ref, "tau": t, "tau_down": t2, "init": n}` | first-order lag (below) |
| `{"ramp": ref, "rate": r, "rate_down": r2, "init": n}` | moves toward the input at most r units per second: y ← min(u, y + r · 0.1) when u ≥ y, else max(u, y − r2 · 0.1) (`rate_down` default `rate`; r · 0.1 computed once per node) |
| `{"integrate": ref, "gain": g, "min": a, "max": b, "init": n}` | y ← clamp(y + g · input · dt, a, b): levels, inventories |
| `{"latch": set, "reset": reset, "init": 0}` | 1 from the first step `set` is true until `reset` is true (reset wins) |
| `{"delay": ref, "on": t, "off": t2}` | counts the consecutive steps in which it read its input true (the first counts 1); true when the count reaches t / 0.1 (on = 2 s: at the 20th such step); likewise false after t2 / 0.1 steps of reading false; `off` default 0 |
| `{"timer": ref}` | 0.1 × the number of consecutive steps in which it read its input true, this one included (0 when it reads false), computed as count / 10 so every reader gets the same number |
| `{"wrap": ref, "period": p}` | x = y + input · dt, then y = x − p · floor(x / p) (so 0 ≤ y < p also for negative input): synchroscope phase angle, turning-gear rotor angle |

A *ref* is a number or a value name. A **stateless** node reads earlier values only, as this step computed them
(`forward_ref` otherwise; a `state` is read as it stands now, after this step's operations).
A **stateful** node (`lag`, `ramp`, `integrate`, `latch`, `delay`, `timer`, `wrap`) reads **every** reference as the
previous step left it, earlier or later in the list: that is how loops (level → pump trip → level) close without an
order problem, and it makes the two readings of "earlier" the same. "As the previous step left it" is the value at
the end of the previous step, after its steps 3–6 (§7.10), before this step's operations.

**Values the engine keeps:** each machine's state `<machine id>_state` (§7.4) and each trip's latch
`<trip id>_latched` (1 while latched, §7.5) are values too, read by any node anywhere in the list (they are not
computed in step 2) and by conditions; no other value may have those names (`dup_id`). Trip IDs are at most 24
characters, machine IDs at most 26.

**Times as steps.** A time t (a `delay`'s `on` and `off`, a trip's or alarm's `delay`, a shelving time) counts
round(t / 0.1) steps, rounded half up (⌊t / 0.1 + 0.5⌋; t is never negative here). A time in content is a multiple of 0.1 s (`bad_time` otherwise; a shelving time is the
trainee's and is only rounded), but t / 0.1 in double precision isn't always a whole number (0.3 / 0.1 =
2.9999…): round, never truncate.

**Arithmetic:** IEEE 754 double precision; `sum` and `product` in list order, left to right; a lag's factor
1 − e^(−0.1/τ) computed once per node. A value is true when ≥ 0.5; `cmp`, `and`, `or`, `not` give exactly 1 or 0.
`init` of `latch` and `delay` is 0 or 1; of `integrate` within `min`–`max`; of `wrap` within [0, period).

**Step 0** (when a scenario starts): every `state` and stateful node takes its initial value (`init`, or the
scenario's; defaults: `lag`, `ramp`, `integrate`, `wrap` 0; `latch`, `delay`, `timer` 0), every `ext` value the
scenario's, and the stateless nodes are evaluated once in order. Step 1 is the first 0.1 s step of §7.10.

**First-order lag:** y ← y + (u − y) · (1 − e^(−dt/τ)), with dt = 0.1 s, τ = `tau` when u ≥ y, else `tau_down`
(default `tau`). `tau` > 0. dt never changes: fast-forward runs more steps per frame (§7.9).

**Names.** Every key of a `set` (in ops, interlocks, machines, faults) is the name of a `state` value; a machine's
current state is the value `<machine id>_state` (§7.4); value names follow the identifier rule of §1.

### 7.2 Operations

What a trainee can do to a piece of equipment, at the equipment (local push button, handwheel) or from the control
room screens:

```json
{"kks": "30PAC10AP001", "do": "start", "set": {"cw_a_run_cmd": 1},
 "needs": [["cw_basin_level_ok", "Cooling tower basin level not above the minimum"],
           ["cw_a_valve_at_start", "Discharge valve 30PAC10AA101 not at its start position"]],
 "where": ["local", "screen"]}
```

- **`do`:** `open`, `close`, `stop_travel`, `start`, `stop`, `close_breaker`, `open_breaker`, `set` (with a value
  from the trainee in `range`), `reset`, `acknowledge`, or a machine command (§7.4). The shapes:
  - `set`: `"input": <state>, "range": [low, high]`; the trainee's number is written to the input state (a number
    outside the range is refused, naming the input);
  - `reset`: `"trip": <trip id>`; refused while the trip is not latched (naming `<trip>_latched`) or while its
    `when` was true in the previous step (naming that value): the cause must have cleared;
  - a machine command: `"machine": <machine id>`, `do` one of its commands; refused when the machine's current
    state doesn't take it (naming `<machine>_state`); an optional `set` is applied with it, before the machine
    enters its new state (so the new state's `set` wins where both write a state);
  - every other `do` has a `set`.
  An op is named by its equipment, its `do` and (for a reset) its trip: two ops with the same three are `dup_id`.
  An op that is done writes, in this order: a `set` op's number into its input; a reset's latch to 0 (restarting
  its trip's count); the op's `set`; a machine command's new state (§7.4).
  A refused op lists the values that failed, permissives first, in order.
- **`set`:** the states it writes. A valve's `state` is its **command**; its position is a `ramp` of the command at
  the valve's travel rate (a 2 m butterfly valve takes a minute: the trainee sees and hears it move).
- **`needs`:** the **permissives**, each a value and the sentence shown when it is false. An operation whose
  permissives are not all true is refused, and the trainee sees which ones failed, in order: knowing *why* a pump
  won't start is the lesson.
- **`where`:** where the operation is offered: `local` (at the equipment), `screen` (the control room).

### 7.3 Interlocks

An interlock is an operation the plant does by itself: `{"id": id, "when": value, "do": [Action, …]}` (optional
`kks`, the equipment it acts on, and `text`), done in the step where `when` is true and was false in the previous
step (a rising edge; on the first step "previous" is false) (a CW pump stops → its discharge valve closes; condenser
pressure high → the turbine bypass is blocked). Its `do` is a list of actions (§7.5), and it appears in the event
list (§7.6) as "automatic". A condition that is true in a stopped plant fires at step 1: write `when` so it is
false at the start (a pump that *stopped*, not one that is not running).

### 7.4 Machines (sequences)

A start sequence (gas turbine start, steam turbine roll) is a state machine:

```json
{"id": "gt1_start", "kks": "10MBA10", "init": "standstill",
 "commands": {"start": {"from": ["standstill"], "to": "crank"}, "stop": {"from": "*", "to": "coastdown"}},
 "states": [
   {"id": "standstill", "set": {"gt1_speed_sp": 0}, "watch": false},
   {"id": "crank", "set": {"gt1_sfc_on": 1, "gt1_speed_sp": 0.25}, "next": [["gt1_purge_speed", "purge"]]},
   {"id": "purge", "next": [["gt1_purge_done", "coast"]], "say": "HRSG purge: 5 volume changes"},
   …]}
```

- **`commands`:** the commands the machine takes: the states it is accepted in (`*` = any) and the state it moves to.
  A command in another state is refused like a failed permissive. Ops carry the commands (§7.2).
- **`set`:** states written on entering. **`next`:** `[condition, state]`, the first true one moves on (at most one
  move per step). **`watch`** (default true): fast-forward stops while the machine is in this state (§7.9).
- **Entering** a state (by a command, a `next`, or an action, even into the state it is in) writes its `set` and is
  an event. A machine moved by a command (step 1) or an action (steps 3–4) does not move again by `next` in step 5;
  a trip's action (step 6) moves it whatever happened before. At step 0 every machine enters its `init` state (its
  `set` applied, without an event) before the scenario's `init`.
- **`say`:** the step text shown on the control room screen and spoken in the event list.
- The machine's current state is itself a value (`gt1_start_state`, the index in `states`), so the model, the
  displays and procedures can read it. A machine ID is at most 26 characters, and a declared value named like a
  machine's state value is `dup_id`.

### 7.5 Trips

```json
{"id": "gt1_trip_lube", "kks": "10MBV10CP001", "isa": "PALL", "text": "GT lube oil pressure low-low",
 "when": "gt1_lube_p_ll", "delay": 2, "do": [{"machine": "gt1_start", "to": "trip"}],
 "first_out": "gt1"}
```

**Actions** (the `do` of interlocks, trips and faults, and what an op's `set` stands for) are `{"set": {name:
value, …}}` or `{"machine": id, "to": state}` (forces the machine into that state, entering it as in §7.4). A trip
latches (§7.1) when its `when` has been read true in max(1, `delay` / 0.1) consecutive steps (the count restarts
when it reads false and after a reset); its `do` is applied once, when it latches. It stays latched until the op
`{"do": "reset", "trip": id}` is made while its cause has cleared (§7.2); its latch is the value
`<trip id>_latched`, so permissives can read it ("a GT trip is latched: reset it first"). `first_out` groups trips
so that the panel shows which of them came first, as real first-out annunciators do: the first trip of a group to
latch while no trip of the group is latched is its first out; the record clears in the step the last latched trip
of the group is reset. Trips that fire in the same step are ordered as they are listed in the model (plant.json's
area order, then file order): the first one listed is "first out". Trips a scenario starts latched record no first
out, and while one of them is latched no other trip of its group is first out; their `do` is not applied at step 0
(the scenario's `init` describes the stopped plant as it stands).

### 7.6 Alarms and events

```json
{"id": "cond_p_high", "kks": "30MAG10CP001", "isa": "PAH", "text": "Condenser pressure high",
 "when": "cond_p_h", "clear": "cond_p_h_clear", "delay": 5,
 "priority": 2, "where": "30MAG10"}
```

- `when` and `clear` are value names (here `{"cmp": ["cond_p", ">", 15]}` and `{"cmp": ["cond_p", "<", 13]}` in
  `values`: FIRST-TRAIN.md §5).
- **`suppress`** (optional): a value; while it is true the alarm is suppressed by design, as alarm management
  does for alarms that are expected in a plant state (condenser pressure high while no vacuum pump runs and the turbine
  is at standstill). A suppressed alarm is listed as such, never sounds and never changes state.
- States per alarm (named in events and snapshots `normal`, `active_unack`, `active_ack`, `cleared_unack`), as the
  common alarm-management model (ISA-18.2) describes them: normal → active unacknowledged
  (flashing, horn) → active acknowledged (steady) → cleared unacknowledged → normal; and **shelved**: set aside for
  a while by the operator (a nuisance alarm, an instrument under repair), shown in a list of its own, no horn, until
  un-shelved or its shelving time ends. The trainee acknowledges at the panel; the
  horn stops on acknowledge.
- **`priority`** 1 (high), 2 or 3 (low) (a number: `2.0` is 2, as in any JSON reader) sets the colour and sound; **`clear`** gives a deadband so an alarm doesn't
  chatter; **`delay`** the seconds the condition must hold.
- **Exactly, in step 7:** an alarm is *on* when `when` has been read true in max(1, `delay` / 0.1) consecutive steps,
  and *clear* when `clear` is true (without `clear`: when `when` is false). Normal → active unacknowledged when on;
  active unacknowledged → cleared unacknowledged when clear; active acknowledged → normal when clear; cleared
  unacknowledged → active unacknowledged when on. While suppressed or shelved it keeps its state and its count
  restarts. The trainee's inputs (step 1): acknowledge (active unacknowledged → active acknowledged, cleared
  unacknowledged → normal; also on a suppressed alarm), shelve for a number of seconds (a number outside 0 < t < 10⁶:
  nothing happens, no event), un-shelve; a shelf made in
  step n for t seconds ends in step 7 of step n + round(t / 0.1), with an event (shelving a shelved alarm again
  sets a new end).
- **`where`:** the equipment the alarm leads to (one tap from the alarm list highlights and walks there: R10).
- **Events:** every operation, interlock, machine step, trip, fault, repair and alarm change goes into an event list
  with model time; procedures (§8) and the debrief read it.

### 7.7 Bindings: what is seen and heard

```json
{"kks": "30PAC10AP001", "anim": "shaft", "of": "cw_a_speed", "scale": 8.25}
{"kks": "30PAC10AA101", "anim": "disc", "of": "cw_a_valve_pos"}
{"kks": "30PAC10CP501", "show": "cw_a_disch_p"}
{"kks": "30PAC10AP001", "sound": "motor_large", "gain": {"of": "cw_a_speed", "table": [[0, 0], [1, 1]]},
 "pitch": {"of": "cw_a_speed", "table": [[0, 0.5], [1, 1]]}}
{"kks": "30PAC10AP001", "lamp": "running", "of": "cw_a_run"}
```

- **`anim`:** a named moving piece of the part (§9: a valve's `stem`, `disc` or `handwheel`; a pump's or fan's
  `shaft`; a damper's `blades`; a gauge's `needle`), driven by a value: positions take the value 0–1; a shaft turns at
  `of` × `scale` revolutions per second (`cw_a_speed` 0–1 × 8.25 = 495 rpm, a large vertical pump's speed).
- **`show`:** a gauge, level glass or local display shows the value in the part's range and unit.
- **`sound`:** a sound of the library (§11) on the part, its gain and pitch tables of values (the pitch moves every
  layer but a synth sound's electrical hum, §11). **`lamp`:** a lamp
  or beacon lit when the value is true.
- **`shake`:** camera shake near the part from a vibration value (felt near a large machine; off when the platform
  asks for reduced motion).
- `ext` values (plant.json, §2) are values without a node: the scenario sets them, and any area may read them.
- **`lamp`** kinds: `running`, `stopped`, `open`, `closed`, `fault`, `beacon`. `anim` and `shake` take an optional
  `scale`. Every binding's equipment, value and sound exist, and an `anim` channel is one the part names (§9).

### 7.8 Scenarios

```json
{"format": "walkdown-plant-scenario", "version": 1, "id": "cold_iron", "title": "Cold start after a long outage",
 "init": {"ambient_t": 35, "ambient_wb": 25, "hrsg1_hp_drum_level": -150, …},
 "latched": ["gt1_trip_lube", "st_trip_lube", "st_trip_cond_p"],
 "faults": [{"id": "cw_b_fails", "when": {"cmp": ["cw_b_start_count", ">=", 1]},
             "set": {"cw_b_motor_fault": 1}, "text": "Pump B trips on overcurrent at its first start",
             "kks": "30PAC10AP002", "repair": {"cw_b_motor_fault": 0}}]}
```

`init` overrides the initial value of a `state`, a stateful node other than a `timer` (a timer always starts at 0:
`bad_ref`) or an `ext` value (every `ext` value is set), under the same rules as a node's own `init` (§7.1:
`bad_value`);
`latched` names trips (by their `id`, each once) that start latched, as they stand in a stopped plant; `faults` are set by a
condition, so a trainer can make "the standby pump fails" happen at the moment that teaches most. A fault's `when`
is a value name or a stateless node over values (`{"cmp": …}` as in the example); a fault **without `when`** is a
trainer's fault, applied when the trainer presses it (a trainee input, taking effect in step 3 of the next step).
Each fault is applied once (a repaired trainer's fault can be applied again, below).

**Repairs.** A fault with `repair` (the states it writes, as a `set`) can be repaired once it has been applied: by the
trainer, or by the trainee at the equipment `kks` names (optional, a code of the plant: where the repair is offered,
within reach as a `local` op is, §7.2). A repair is a trainee input (`repair`, §7.10) and an event; it writes the
`repair` states and nothing else (a trip the fault caused stays latched until it is reset, a valve's command stays as
it was). A repaired trainer's fault can be pressed again, and is then applied again; a repaired fault with `when` is
not applied again in that run. A repair asked in the step its fault is pressed comes after it (step 3) and repairs it.
A repair writes its states whatever else set them: of two applied faults that set the same state, repairing one undoes
that state for both (the other stays applied, and can still be repaired). A repair of a fault that has no `repair`, has not been applied, is already repaired,
or isn't one of the scenario's does nothing and makes no event. (Format 2, §15.5: in a version 2 plant the trainee
repairs under a permit to work, and this input is the trainer's alone.)

### 7.9 Time

Model time runs at 1× while anything is changing that the trainee should watch. A **fast-forward** (up to 60×) is
offered while no alarm is unacknowledged, no priority 1 alarm is active, and no machine is in a state with
`"watch": true` (shelved alarms don't count; a suppressed alarm keeps the state it had); it stops by itself when
one appears. Fast-forward runs more 0.1 s steps per frame (600 per second at 60×); the step never grows. Its cost on
the Note 9 is measured (0054) and the top speed is capped by what the phone keeps within the frame rule.

### 7.10 One step

Each 0.1 s step, in this order (the reference and the app must agree to the vectors):
1. The trainee's inputs queued since the last step, in the order made: operations (each refused if a permissive in
   `needs` is false, read as the previous step left it, else applied, §7.2; machine commands likewise),
   acknowledgements, shelving, the trainer's faults and the repairs (noted here, applied in step 3). An acknowledgement or
   shelving of an alarm the model doesn't have, and a press of a fault the scenario doesn't have, one with a `when`
   or one applied and not repaired since, do nothing and make no event (an unknown operation is an `"unknown"` event, §12). Then
   the first-out records of groups with no latched trip are cleared.
2. `values` are evaluated in order (stateful nodes read the previous step's values where §7.1 allows).
3. Faults whose condition is true, and the trainer's faults pressed in step 1, are applied (their `set`), once
   each, in the scenario's list order (not the order they were pressed); then the repairs asked in step 1, in the
   scenario's list order, write their `repair` (§7.8).
4. Interlocks on a rising edge of `when`, in list order; their `set` is applied.
5. Machines: each moves at most once, by its first true `next`; the new state's `set` is applied.
6. Trips: a trip whose `when` has held for its `delay` latches; its `do` is applied; first-out as in §7.5.
7. Alarms change state (with their `delay` and `clear`).
8. Events of this step are written in the order above.

Every condition in steps 3–7 (`when`, `next`, permissive-like checks) reads the values as step 2 left them, not
as an earlier part of steps 3–6 changed them; states changed in steps 3–6 are read by `values` in the next step.
Step 0 is §7.1's. A cold start that takes hours in a real plant takes far less (FIRST-TRAIN.md §4, "As built": 110
minutes of model time, about 10 minutes of the trainee's time with fast-forward, walking and reading on top).

### 7.11 Control room screens

The control room has an overview screen per system, as a plant's control system does (operator mimics). They are made
from the model, not drawn value by value: `screens.json` says only which systems each screen shows, where each
system's group stands on the screen, the flow lines between the groups and the values trended, and every code of the
model lands on its screen by the beginning of its code. A model that gains a pump gains it on its screen.

```json
{"format": "walkdown-plant-screens", "version": 1,
 "overview": {"title": "Train 1 overview", "short": "Overview", "key": ["gt1_mw", "st_mw", "hp_p", "cond_p"]},
 "screens": [
   {"id": "cw", "short": "CW", "title": "Circulating water",
    "groups": [{"id": "pumps", "title": "Pumps and discharge valves", "at": [0, 0], "codes": ["30PAC10"]},
               {"id": "flow", "title": "Supply and return", "at": [1, 0], "codes": ["30PAB"]}],
    "lines": [{"from": "pumps", "to": "flow", "medium": "cooling_water"}],
    "trend": ["cw_flow", "cw_ret_t"]}],
 "left_out": [{"codes": ["30PAB10AA40"], "why": "Hand vents without position feedback: seen at the condenser"}]}
```

- **What a screen shows.** A code is *shown* when the model has anything for it: a value with a `unit` and that
  `kks`, a `show`, `lamp` or position binding (`anim` `stem`, `disc` or `blades`, §7.7), an op, a machine, an alarm
  (its `kks`, else its `where`) or a trip. Each shown code belongs to the group whose `codes` hold the **longest
  beginning** of it (`30PAD10AN` wins over `30PAD10` for `30PAD10AN001`), or is in `left_out` the same way. A shown
  code that no beginning matches is `unplaced`: every value, drive and valve of the model is on exactly one screen or
  deliberately left out, with the reason. Values without a `kks` are the model's workings and are not shown, except
  those a group names in `extra` (a generator's frequency and phase for synchronising): each value at most once,
  and never one with a code (it is shown by its code).
- **`codes`** and `left_out`'s `codes`: beginnings of codes, at least to the system letters (`30PAB`, `10MBV10`,
  `30MAG10CL`), each placed once in the file (`dup_id`). A group to which no shown code belongs and that has no
  `extra` shows nothing (`bad_ref`); so does a `left_out` entry that leaves nothing out, and one that leaves out a
  code with an alarm or an op worked from the screens (`where` holds `screen`): those need a screen.
- **`short`:** the screen's name on its tab, 1–16 characters; **`title`** its heading.
- **`at`:** the group's place, `[column, row]`, whole numbers 0–7; one group per place. The app sizes each column
  and row to its largest group. **`lines`:** flow lines between two groups of the screen, optionally naming the
  `medium` (plant.json) they carry, which is written on the line. **`trend`:** at most 6 values with a unit,
  drawn as sparklines on the screen. **`overview.key`:** 1–12 values with a unit, shown big on the overview with
  a tile per screen. **`left_out`:** each entry's `codes` (1–16) and `why`, its reason (1–200 characters). Limits:
  16 screens, 16 groups a screen, 16 codes a group, 16 `extra` values a group, 32 lines a screen, 64 `left_out`
  entries; a screen's `id` is never `overview`.
- **What the app draws** (high-performance HMI style, ISA-101): a grey background and grey
  equipment, colour only for what is abnormal. A drive (a code with a `running` lamp, or a `start` op that sets a
  state; a valve's position or a breaker's `closed` lamp make it a valve or a breaker first) is filled when it
  runs and hollow when stopped, by its `running` lamp's value or else the first state its `start` op sets; a valve
  shows its position and moves; a breaker is filled when closed (its `closed` lamp); a machine shows its state and
  `say`; a code whose trip is latched (a trip with its `kks`, or one whose actions stop it) is marked TRIP. Values
  are shown with their unit; an alarm not normal is marked at its code with its priority (1 red, 2 amber, 3 yellow;
  flashing while unacknowledged), and the screen's tab and the overview's tile carry the count of its alarms by
  priority. Under a drive or valve stands what its next operation needs: ready, or how many permissives are
  missing. The alarm banner at the top lists the newest unacknowledged alarms of the highest priority.
- **Operating from a screen** opens the code's card (§6), which offers the ops whose `where` holds `screen`, with
  their permissives: the same refusals as anywhere (§7.2). Nothing on a screen bypasses an op.
- The screens are reached in the control room, from its operator desks (`operator_desk` parts) and the app's
  Control room button; the values on them are refreshed a few times a second, not every frame.

## 8. Procedures and tours (one format, R10)

```json
{"format": "walkdown-plant-procedure", "version": 1, "id": "cold_start", "title": "Cold start of train 1",
 "kind": "procedure", "scenario": "cold_iron",
 "intro": [{"p": ["Bring the train from cold iron to base load. ", {"link": ["Course: start-up"],
            "to": {"course": "ppt", "page": "ccpp"}}]}],
 "steps": [
   {"id": "cw_a", "text": ["Start circulating water pump A (", {"link": ["30PAC10AP001"],
     "to": {"kks": "30PAC10AP001"}}, ") with its discharge valve at the start position."],
    "at": ["30PAC10AP001", "30PAC10AA101"], "go": "walk",
    "do": [{"kks": "30PAC10AP001", "do": "start"}],
    "done": "cw_a_run_stable", "why": ["With the valve at its start position (about 15 % open) the empty
     discharge pipe fills slowly, without a pressure surge."]}]}
```

- **`text`, `intro`, `why`:** runs and blocks of COURSES.md §3–§4 (paragraphs, lists, tables, callouts; `figure`,
  `image`, questions and `tool` are not allowed here). A `{"kks": …}` link inside a procedure highlights that
  equipment in the plant; a `{"course": …}` link opens Walkdown's course (`walkdown://course/…`).
- **`at`:** the equipment the step is about: highlighted, and the target of "take me there". **`go`:** `walk`
  (show the way on foot along walkable surfaces), `fly` or `none`.
- **`do`:** the operations expected (§7.2), in any order unless `"ordered": true`: each `{"kks", "do"}`, with
  `"value"` (within the op's `range`) for a `set` and `"trip"` for a `reset`, matching an op of the model.
  **`done`:** the value that ends the step; without it the step ends when the trainee presses Next.
- **A tour** is the same file with `"kind": "tour"` and steps without `do`, `done` or `ordered`: a guided walk along
  a system's path (R7), each step a stop with text and at least one code in `at`. A tour's `scenario` is optional.
- **In the model alone** (0054 §10), a procedure runs as a trainee who does exactly what each step says: its ops at
  once, then model steps until `done`; the tests require every first-train procedure to reach its last step this
  way with every op accepted.
- **Procedure mode** checks the trainee: the event list (§7.6) shows an operation outside the expected step as a
  deviation (not refused: the plant reacts as it would). **Free mode** has no procedure.
- **The debrief** (the app's, from the event list): the run's events in order with their model time (operations,
  alarm changes, shelving, trips with their first out, faults, interlocks, sequence steps, and the procedure's steps
  as they ended), each deviation with the step it was made in and the step it belongs to, and a summary (time
  taken, steps, operations, alarms, trips). Shown at the end of a procedure and from the alarm list during a run.

**Walkdown's procedures.** Walkdown's own `procedures.json` (from a plant's operation manual) holds steps of text with
linked codes. They map onto this format (`text` → `text`, linked codes → `at`), so one renderer can show both; the
plant's procedures stay plant data and never come into this repository.

**How a course points into the plant.** Course format 1 is frozen and its `kks` link target opens Walkdown's own
equipment page. A link into Walkdown Plant needs course format version 2 with one more target,
`{"plant": "kks/<code>"}` or `{"plant": "procedure/<id>[/<step>]"}`, opening the link of §6 (0054 lists this as
follow-up work, with its own vectors).

## 9. The parts kit

Every part is made by code from its parameters (R5); the kit is the only place geometry is defined. A part's
**origin** is on its base (the floor it stands on) at the centre of its footprint, or at its pipe connection for
inline parts; **`yaw` 0** points its main axis north (a pump's shaft, a valve's flow direction, a turbine's rotor).

Every part defines: its parameters with defaults and limits, its **nozzles** (named connection points with a
direction and DN), its **anim** channels, its **plate** mounting points, its **materials** (§10), and its pieces
in the four **visibility classes** of §10.

**The kit's interface** is `data/plant3d/kit.json` (format `walkdown-plant-kit`): what the validator and the
content tools know of each part, and what the Godot kit (`apps/plant3d/kit`, 0054) must implement; the build
refuses a part declared there that the kit lacks.

```json
{"format": "walkdown-plant-kit", "version": 1, "dn_od_mm": [[15, 21.3], …],
 "parts": {"pump_vertical": {"group": "rotating",
   "params": {"flow_m3h": {"type": "num", "min": 0.1, "max": 50000, "default": 1000}, …,
              "pit_depth": {"type": "num", "min": 0, "max": 20, "default": 6}},
   "nozzles": {"discharge": {"at": [0, 1.2, 1.5], "dir": "n"},
               "suction": {"at": [0, 0, ["pit_depth", -1, 0]], "dir": "down"}},
   "anim": ["shaft"], "plates": ["motor_side"]}, …}}
```

- **Parameter types:** `num` and `int` (`min`, `max`), `enum` (`values`), `bool`, `text` (`max` characters), `pair`
  ([low, high]), `xy`, `xyz`, `polygon` (3–256 points), `polygons`, `path` (2–256 points), `records` (a list of up
  to `max` objects with typed `fields`, one level deep). A parameter without `default` must be given.
- **Nozzles:** a position in the part's frame (x right, y forward along the main axis, z up, from its origin), each
  coordinate a number or `[parameter, factor, offset]` = parameter × factor + offset of a number parameter (a
  condenser's water boxes sit at half its length), and a direction `n`, `e`, `s`, `w` (in the part's frame, so `n` is
  forward), `up` or `down`.
- **`inline`:** the part may sit on a pipe (§4 `valves`, `parts`). **`walkable`:** exactly the walkable structure
  parts of §5. Groups: `machines`, `hrsg`, `rotating`, `heat_exchange`, `vessels`, `valves`, `instruments`,
  `electrical`, `pipes`, `structures`, `cues`; only `structures` parts are structures (§5), the others equipment.
- **DN table:** nominal size → outside diameter (EN 10220 / ASME B36.10), DN rising.

| Group | Parts and their main parameters |
|---|---|
| Machines | `gas_turbine` (rating_mw, length, casing_d, intake: side/top, exhaust: axial); `generator` (rating_mva, length, d, cooling: air/hydrogen); `steam_turbine` (length, d, casings: list of {kind: hp/ip/ip_lp/lp, length, d}, exhaust: down/axial); `sfc` (static frequency converter cabinet row); `turning_gear`; `filter_house` (air intake filter house: length, width, height) |
| HRSG | `hrsg` (length, width, height, modules, inlet_duct, outlet_duct); `hrsg_module` (a heating surface inside the casing: kind economiser/evaporator/superheater/reheater, width, depth, height); `drum` (d, length, saddles; a drum is equipment of its own with its code, standing on its platform); `stack` (d, height, platforms, damper); `duct` (route, width, height, joints); `silencer` (vent silencer: d, height) |
| Rotating | `pump_horizontal` (flow_m3h, head_m, motor_kw → frame size, baseplate, coupling guard); `pump_vertical` (flow_m3h, head_m, motor_kw, pit_depth: can or wet pit); `fan_axial` (d, blades, motor_kw, stack_height); `compressor_skid`; `vacuum_pump_skid` (kind: liquid_ring) |
| Heat exchange | `condenser` (shell length, width, height, waterboxes: 2 or 4, passes, hotwell); `shell_tube_hx` (d, length, horizontal/vertical); `plate_hx` (plates, frame); `cooling_tower` (cells_x, cells_y, cell_size, height, fan_d, basin_depth, fill: film/splash) |
| Vessels | `tank_vertical` (d, height, roof: cone/dome/open); `vessel_horizontal` (d, length, saddles); `package_boiler` (d, length, steam_tph); `basin` (an open concrete basin: length, width, depth) |
| Valves | `valve_gate`, `valve_globe`, `valve_butterfly`, `valve_ball`, `valve_check`, `valve_control`, `valve_safety` (dn, rating, actuator: manual/gear/electric/pneumatic/hydraulic, handwheel side); `damper` (width, height, blades) |
| Instruments | `pressure_gauge` (range, unit, dial_d), `pressure_transmitter`, `temperature_element`, `temperature_gauge`, `level_glass` (range), `level_transmitter`, `flow_element` (kind: orifice/venturi/magnetic), `position_switch`, `vibration_probe` (kind: velocity/proximity), `speed_probe`, `flame_detector`, `local_panel` (cabinet with displays), `push_button_station` (buttons: start/stop/emergency) |
| Electrical | `transformer` (mva, kind: gsu/aux, radiators, bushings), `breaker` (kind: gcb/mv, length), `switchgear_row` (panels, depth), `cabinet`, `junction_box`, `cable_tray` (route, width), `motor` (kw, frame; when a driver isn't part of its machine) |
| Pipes | `pipe` (§4), made of `elbow`, `tee`, `reducer`, `flange` pieces; `pipe_support` (kind: shoe/guide/anchor/hanger, from the span table); `pipe_rack` (bays, span, tiers, width) |
| Structures | `building`, `floor`, `platform`, `stair`, `ladder`, `handrail`, `door`, `column`, `beam`, `grating`, `road`, `trench`, `fence`, `wall`, `slab`, `pit` |
| People cues | `tag_plate` (KKS code text, size by plate kind), `sign`, `lamp`, `beacon`, `horn`, `emergency_stop`, `safety_shower` |

Parameters are physical quantities a data sheet gives (flow, head, power, diameter), and the part derives the rest
from tables in the kit (a 1,250 kW vertical motor has a frame of a certain size): content says what the equipment
*is*, the kit decides what it *looks like*. Each table in the kit names its source (manufacturers' published
catalogue ranges, standards' dimension tables) in the kit's own README.

## 10. Detail, LOD and tiers (R9, R9a)

One description and one asset set for every device; detail levels are generated. Each piece of a part belongs to
one **visibility class**:

| Class | What | Rule |
|---|---|---|
| `form` | the shape that tells what a thing is: casings, shells, pipes, buildings, platforms | drawn to the far plane on every tier; simplified meshes (fewer segments) with distance (automatic LOD), then merged per 12 m cell far away (Godot visibility ranges as HLOD) |
| `identify` | what tells which one and in which state: tag plates and signs, handwheels and stem positions, valve position indicators, gauge needles, lamps and beacons, rotating shaft guards, flow arrows and medium bands | **never removed for performance** on any tier. Drawn while legible (below); beyond that a floating label or symbol can stand in when the trainee asks for labels |
| `detail` | what makes it look real but tells nothing: bolts, flange studs, fins, weld seams, small brackets, grating texture | made only where it helps a trainee recognise the kind of thing (R9a: no detail for its own sake); a visibility range by size on every tier, shortest on the phone tier |
| `none` | decoration | not made at all (R9a) |

**Legibility distance.** A piece is drawn while it covers at least `min_px` pixels on the device's screen:
d_max = size × f / min_px, where f is the camera's focal length in pixels for the current resolution
(f = (h / 2) / tan(vfov / 2)). With the Note 9's lean preset (60 % of 1080 px, 70° field of view; 0041) f ≈ 460 px:
a 50 mm bolt head at 3 px ends at 7.7 m; a tag plate's 25 mm characters at 8 px per character end at 1.4 m, so the
plate is read up close, as in the field, and its code is also shown in the equipment card. The build computes each
piece's visibility range from its size; the tier sets f and `min_px` (`detail`: 3 px on the phone, 1.5 px on
laptops; `identify`: legible at 8 px, kept as a shape at any size).

**Instancing.** Static pieces are grouped by part, LOD, material, visibility class, size bucket (a factor of 2) and
12 m cell into instanced meshes (0041: grouping by cell cut the Note 9's draw calls by 93 %): Godot gives a
visibility range per mesh instance, so pieces of one group share one range, that of the bucket's smallest size. The
ranges are set when the plant loads, from the tier's resolution and field of view, and again when they change.
Moving pieces (`anim`) stay separate nodes.

**Tag plates** are `identify` in shape and colour (always drawn); only their text fades with legibility. A trainee
reads a code by walking up to the plate, as in the field, or in the equipment card on any tier; the look rule's
viewpoints for codes stand within 1.4 m of the plate, where every tier draws the text.

**Materials** are PBR sets from the kit's library (CC0, 0054) at three texture sizes (2048, 1024, 512 px); a tier
picks the size, never a different material. Paint colours (equipment colour, medium bands) are parameters, so one
texture set serves every colour.

**The look rule** (wiki: measurement rules): the same 10 viewpoints captured on each tier must show a trainee the
same equipment, codes, states and routes.

## 11. Sounds

A sound is bound to equipment (§7.7) and placed at the part, with distance attenuation, and occluded by building
walls (a wall between halves its loudness: a simple rule, not acoustics).

```json
{"id": "motor_large", "kind": "loop", "file": "motor_large.ogg", "licence": "CC0-1.0",
 "source": "<URL of the original>", "made": "trimmed, looped, normalised to −23 LUFS"}
{"id": "gt_whine", "kind": "synth", "tones": [{"of": "gt1_speed", "hz": {"table": [[0, 0], [1, 2850]]}}],
 "noise": {"colour": "pink", "band": [200, 4000]}}
```

- **`loop`** and **`once`** are recorded clips (Ogg Vorbis, `data/plant3d/sounds/<file>`), each with its licence
  (`CC0-1.0` only), its https `source`, how it was `made`, and optionally `uploader` and `date`; the about list
  (0054) is generated from these entries.
- **`synth`** sounds are made from tones and filtered noise by the content tools at build time, as short seamless
  loops (one per layer: the tones, the broadband noise, and the electrical hum at multiples of twice the grid frequency,
  which the app never pitches: `tools/plant3d/sounds/README.md`): `tones` (up to 8, each `hz` a number or `{"of", "table"}`,
  optional `gain` 0–1) and/or `noise` (`colour` white/pink/brown, `band` [low, high] Hz, optional `gain`), and the app sets each layer's gain, and each layer's pitch but the hum's, from values: a
  turbine's blade-pass tone rises with its speed, which no recording of one speed can do. Making the samples at run
  time (Godot's AudioStreamGenerator) is meant for C# or native code, not script (0054), and costs the phone CPU for
  nothing a pitched loop can't do.
- **Levels:** every sound, recorded or synthesised, is levelled by how loud its source is on site, not to one fixed
  loudness: its A-weighted level = −26 − 0.5 × (105 − its dB(A) at 1 m) dBFS (`tools/plant3d/sounds/README.md`).
  The −23 LUFS in the example above is a placeholder.
- **People cues and ambience** are the app's, not bound: footsteps by the floor underfoot (the content build marks
  each walkable slab's deck and each stair), doors as they run, and outdoors (no building's roof above) the wind and
  the distant plant, its level from how much of the plant runs. They are non-positional but for the doors. A hard
  limiter on the master bus caps the output level.
- The sound library and what each machine sounds like: FIRST-TRAIN.md §6.

## 12. Validation and vectors

The build refuses the whole plant when any rule above is broken and names the file, the item (its code or ID) and the
rule. Error codes follow COURSES.md §10 (`bad_type`, `missing_key`, `unknown_key`, `bad_kind`, `bad_id`, `dup_id`,
`bad_ref`, `forward_ref`, `bad_table`, `limit`, …) plus `bad_json` (not strict JSON), `bad_kks` (grammar or not in
the tables), `bad_route` (a bend that doesn't fit, a route that leaves its nozzle at an angle, a junction off the
other pipe, a free end above ground), `unsupported` (a pipe span with nothing below, a pipe on a tilted part),
`not_walkable` (a stair or ladder whose end meets no walkable surface), `bad_stair` (no step count keeps the stair
rules), `bad_time` (a time that isn't a multiple of 0.1 s), `outside_area`, `area_overlap`, `unplaced` (a code the
screens show that is on no screen and not left out, §7.11). The reference
(`ref/plant3d.py`) checks the rules above that need no geometry of the parts; the pipe supports and the part
geometry (a span with nothing below, a pipe through a part) are the Godot build's.

Vectors (`ref/vectors/plant3d-v1.json`, made by `ref/make_plant3d_vectors.py` from the reference `ref/plant3d.py`,
as for the courses):
- **`valid`** and **`reject`:** a small synthetic plant as `{relative path: file text}`, and changes to it
  (`change`: the files replaced, `null` for one removed) that each break one rule, with the error code;
- **`steps`:** small models (each replaces the synthetic plant's `model/a1.json` and `scenarios/s1.json`, and
  removes its `procedures/p1.json` and `screens.json`, which name ops and values of the synthetic model), their
  `inputs`, and the state
  after every step from step 0. They pin every node kind, the permissive refusals,
  interlock edges, machine moves, trips with first-out and reset (also against a trip the scenario starts latched),
  alarm states, suppression and shelving, faults and their repairs, and inputs naming no alarm or fault;
- **`links`:** links (§6) and what each opens in the synthetic plant: `{"open": "kks", "code", "match", "decode"}`
  (`match` one of `exact`, `without_a3`, `same_kind`, `same_equipment`, `decode`; `decode` the asked code's unit,
  system and equipment names, `null` where not in the key), `{"open": "procedure", "id", "step"}` (`step` `null`
  for the first) or `{"open": "start"}`;
- **`train`:** the first train's cold start run by its procedure: its `inputs`, every `event`, a full `snapshot`
  every `snapshot_every` steps and at the end, the step at which each procedure step ended; and `forks` from it
  (each from `base_step` of the cold start: its `inputs`, its `events`, the state at `until`, and the `expect`ation
  the tests check), one for every trip and interlock and for each wrong operator action the tests name.

**The trace format** (what the app's evaluator reproduces, bit for bit up to the 1e-6 of the numbers):
- an **input** is `[step, kind, …]` and takes effect in step 1 of that step, in file order:
  `[n, "op", kks, do, value or null, trip or null]`, `[n, "ack", alarm]`, `[n, "shelve", alarm, seconds]`,
  `[n, "unshelve", alarm]`, `[n, "fault", fault id]`, `[n, "repair", fault id]`;
- an **event** is `[step, kind, …]`, in the order §7.10 makes them: `[n, "op", kks, do, "done" | "refused" |
  "unknown", [failed values]]`, `[n, "machine", id, from, to, "command" | "next" | "action"]`,
  `[n, "fault", id]`, `[n, "repair", id]`, `[n, "interlock", id]`, `[n, "trip", id, first out]`, `[n, "alarm", id, new state]`,
  `[n, "shelve", alarm, seconds]`, `[n, "unshelve", alarm]`;
- a **snapshot** is `{"step", "machines": {id: state}, "tripped": [ids, sorted], "first_out": {group: trip},
  "alarms": {id: state} (those not normal), "shelved": [ids, sorted], "fast_forward", "values": {name: number}}`,
  the values being every declared value, every `ext`, every `<machine>_state` and every `<trip>_latched`.

## 13. Not in format 1 (deliberately)

- No scripting or expressions in content (as in courses: content must not run code).
- No component level (level 3) KKS codes; no RDS-PP codes.
- No real process simulation: no flow network solving, no steam tables beyond sampled tables.
- No choice of condensing end (R3: air-cooled condenser, wet cooling tower, once-through). Format 1 describes the
  wet cooling tower only; version 2 adds alternative areas for one slot (`"slot": "cooling"`), one picked per
  scenario, when the second cooling end is built.
- No content loaded from outside the app (no downloads, no user content) while the engine's security response is a
  known weak point (0041).

# Part 2: format 2 (DRAFT 2026-10-22)

Written before any code, from the user's decision of 2026-10-22 (staff with full roles to play, a water treatment
plant, a camp). Decisions: 0062 (the staff model), 0063 (characters and animations), 0064 (people on screen: budgets
per tier), 0065 (the water treatment process), 0066 (the site beyond the train). Content plans:
docs/plant3d/STAFF.md, docs/plant3d/WATER-TREATMENT.md, docs/plant3d/SITE.md. Milestones: docs/plant3d/MILESTONES.md.

## 14. What format 2 changes

- **Versions.** `plant.json` says `"version": 2` to use anything below. A version 2 plant may list area, model,
  scenario and procedure files of version 1 or 2; a key of this part in a version 1 file is `unknown_key`, as format 1
  says. Everything in §1–§12 holds unchanged: a plant with no `staff.json`, no `isolations`, no `works` and no `hold`
  node steps exactly as format 1, and the format 1 vectors (`plant3d-v1.json`) keep passing on both engines. Format 2's
  own vectors are `ref/vectors/plant3d-v2.json` (§19).
- **plant.json** gains `clock` (§16.1).
- **Models** gain the stateful node `hold` (§15.4), `isolations` (§15.1) and `works` (§15.2).
- **Scenarios** gain `staff`: `{"seed": n, "trainee": person id or null, "absent": [person ids]}` and `"start":
  {"day": d, "time": "HH:MM"}` (the clock at step 0; default plant.json's).
- **Areas** gain the kit parts of the water treatment plant and the camp (§18.6) and `"load": "inside"` (§18.5).
- **screens.json** gains `desks` per screen and on the overview: the codes of the `operator_desk` parts it is reached
  from (default: every desk); 1–16 codes, each an `operator_desk` of the plant (`bad_ref`), in a screens.json of
  `"version": 2` (`unknown_key` in version 1). An op whose `where` holds `screen` is offered only at a desk with a screen that shows its
  code: the water treatment plant's own panel works the WTP, the main control room's desks show its overview without
  operating it (WATER-TREATMENT.md §7).
- **staff.json** (new, optional): the people (§16).
- **One step** gains step 9, the staff (§17), and new trainee inputs (§17.6).
- **Limits** (`limit` above them): per model 64 isolations of at most 16 points, 128 works; per staff file 200
  people, 48 roles, 2,000 places of which 500 points, 6,000 ways, 16 vehicles, 400 tasks of at most 64 steps, 128
  reactions, 64 zones, 16 rosters, 64 routines.
- **New error codes:** `bad_clock` (a time that isn't `HH:MM`, a `day_scale` that doesn't divide 60),
  `unreachable` (a place no way reaches from the control room), `bad_way` (a way shorter than the straight line
  between its places; the build's check against the navigation mesh, §18.1), `authority` (a task step whose role
  can't do it, found by the validator: an `approve` step in a role without that authority), `bad_zone` (a place on a
  zone's edge, or whose zone list doesn't match the outlines, §16.2), `locked_write` (a work's `set`, an `op` step of
  its task, or a command its fault's `repair` writes, on a code of its own isolation, §15.2).

## 15. Permits to work and isolations (the model)

A permit to work is how a plant keeps people safe while they work on equipment: the work is asked for, approved,
the equipment is isolated (made safe and locked), the permit is issued to the person in charge of the work, the
work is done, the permit is handed back, the isolation is removed and the equipment is returned to service. In
Walkdown Plant this is part of the model, so a pump locked out by an electrician can't be started from the control
room, and an isolated transmitter shows as such on the operator's screen.

### 15.1 Isolations

```json
{"id": "iso_cw_b", "text": "CW pump B: motor supply and discharge valve",
 "points": [{"kks": "30PAC10AP002", "kind": "electrical", "safe": "cw_b_safe",
             "how": "Pump stopped; its breaker racked out, locked and tagged"},
            {"kks": "30PAC10AA102", "kind": "mechanical", "safe": "cw_b_valve_safe",
             "how": "Discharge valve closed; handwheel chained, locked and tagged"}]}
```

- **`points`** (1–16): the equipment made safe, each with its `kind` (`electrical`, `mechanical`, `process`,
  `instrument`: who may lock it, §16.3), the value `safe` that must be true to lock it (optional: an instrument's root
  valve needs none) and `how` (1–200 characters, shown on the permit and at the point). Each point's code is the `kks`
  of at least one `state` or alarm of the model (`bad_ref` otherwise: a lock must do something). `safe` should read the
  commands, not only what follows them: a pump commanded to run is not safe before it turns (`cw_b_safe` = run command
  0 and speed 0).
- **Holding.** An isolation is *held* by at most one work, its *holder*: the work whose `request` was done, from then
  until its permit is closed, or until it is cancelled and none of the isolation's points is locked (at the `cancel`,
  or at the unlock of its last locked point). A `request` for a work whose isolation has a holder (another work, or
  the same work cancelled with points still locked) is refused (`iso_busy`). Locks and unlocks name the holding work
  (another work: `state`).
- **Personal locks** (the user, 2026-10-23 and 2026-10-24): a point holds the locks of one or more people, each
  person's own, in the order placed; it is *locked* while it holds any. Several locks on one point are how a lock is
  handed over at a shift change (below): the point is never left unprotected.
- **Locking** (the input `lock`, §17.6) is noted in step 1 and made at the start of step 3 (§17.1), refused unless its
  work holds the isolation and either the permit is `approved` or `isolated`, or the point is already locked (an
  added lock, at any state: a handover's) (else `state`); unless the person may lock that kind (`authority`); unless
  the point holds no lock of this person (`locked`); and, for a point not yet locked, unless its `safe` is true as
  this step's step 2 computed it, after this step's ops (else the `safe` value's name; an added lock goes on equipment
  already made safe and locked). **Unlocking** removes the person's own lock, refused unless its work holds the
  isolation and either the permit is `approved` or `isolated` (a point locked in error), `returned` or `cancelled`, or
  it is `issued`, `accepted` or `done` and a lock of another person stays on the point (a handover's second half)
  (`state`); unless the point is locked (`unlocked`); unless one of its locks is this person's (`owner`: a lock is
  personal; the user, 2026-10-23). The reasons are listed in the order `authority`, `state`, then `locked`,
  `unlocked` or the `safe` value, then `owner`, every one that applies. Points may be locked and unlocked in any
  order. A lock or unlock naming no work, a work without an isolation, or a point that is not a whole number (a JSON
  integer) from 0 to the number of points − 1 is `unknown` (§17.7).
- **Lock removal by authority** (the input `remove_lock`, §17.6): a supervisor removes another person's lock, with
  the reason written down (the locker has gone home sick, say). The input may name whose lock (`owner`); without one,
  the point's earliest lock is removed. It is made in the same place and order as an unlock, with the authority
  `remove_lock` in place of `lock_<kind>`, refused unless its work holds the isolation and the permit is between
  `approved` and `returned` or `cancelled` (`state`), and unless the point holds a lock (of `owner`, when named:
  `unlocked`); no `owner` check. Its event names whose lock it was and the reason (§17.7); the debrief lists it. A
  reason that is not text of 1 to 200 characters makes it `unknown`, as are the cases that make an unlock `unknown`.
  A removal that leaves an `issued` or `accepted` permit's isolation incomplete suspends the work (§15.3's automatic
  move back to `approved`). An NPC's `unlock` of another person's lock is refused (`owner`) like anyone's.
- **Locks at a shift change** (the user, 2026-10-24): when the holder of a lock goes off shift with the work
  unfinished, the incoming person of their post places their own lock first, then the outgoing person removes theirs;
  both are events of the permit. NPCs do it in their handover tasks (the steps `{"handover": "take"}` and `{"handover":
  "give"}`, §16.6); a played role does the same from the permit form ("Take over the lock", §18.7). If nobody takes
  over, the outgoing person leaves with the lock on, and the shift supervisor removes it by authority with a reason
  (the reaction `lock_left` and the step `remove_locks`, §16.6–§16.7).
- **While a code is locked** (a point with that code is locked, in any isolation):
  - every op (§7.2) on that code is refused: the failed values are format 1's (the permissives that failed, then a
    machine's state, a trip's latch or cause, a `set` op's input), then `<isolation id>_locked` of each isolation
    locking it, in model order. A trip's `reset` on a locked code is refused too: a locked pump's trip is reset after
    the isolation is removed;
  - every write to a `state` whose `kks` is that code is skipped, whatever makes it: an op on another code (its `set`,
    a `set` op's number), an interlock, a machine, a trip, a fault or a repair, in steps 1 and 3–6 (the standby pump's
    auto-start can't start a pump that is locked out; nothing else changes). A work's own `repairs` and `set` (§15.2), and a repair under its permit (§15.5),
    are written to a locked code only if every isolation locking it is held by that work.
    A fault or a repair (§7.8, or a work's `repairs`) any of whose writes would be skipped is not made at all: not
    applied or repaired, no event (a trainer's fault pressed then is lost; one with a `when` is made once the lock is
    off; a repair asked then can be asked again, and the work's `done` still repairs its fault).
    A machine entering a state whose `set` is skipped still enters it: content gives such machines a permissive on
    `<isolation>_locked` so they can't be commanded into it;
  - every alarm whose `kks` is that code is suppressed (§7.6, as by design);
  - the screens mark the code isolated (a padlock and the permit's number), and the part carries the lock in the
    field (`identify` class, §10): a chain through the handwheel, a padlock and a danger tag on a valve; a padlock
    and tag on a breaker's racking hasp; a tag on an instrument's root valve.
- **Values the engine keeps:** `<isolation id>_locked` (the number of its points locked) and
  `<isolation id>_complete` (1 while all are). Read by any node and condition, as a machine's state is (§7.1);
  isolation and work IDs are at most 22 characters, and a declared value with one of these names (or `<work
  id>_permit`, §15.3) is `dup_id`. §7.1's list of what writes a `state` gains the works' `done` (§15.3).

### 15.2 Works

A work is a job on equipment that needs a permit: corrective (a fault to repair), preventive (a routine service) or a
calibration.

```json
{"id": "wo_cw_b_motor", "kks": "30PAC10AP002", "title": "CW pump B motor: bearing replacement",
 "discipline": "mech", "permit": "general", "isolation": "iso_cw_b",
 "repairs": "cw_b_fails", "set": {}, "task": "job_cw_b_motor"}
```

- **`discipline`:** `mech`, `elec`, `inst`, `chem` or `civil`: who may accept the permit (§16.3).
- **`permit`:** `general`, `electrical`, `hot` (hot work) or `confined` (confined space): shown on the form. The
  task of a `hot` or `confined` work has a gas test, a `read` step with `"test": "gas"` of a gas detector's value
  before its first `work` step (validator: `bad_ref` without one).
- **`isolation`** (optional): a work without one (an inspection) needs no locks.
- **`repairs`** (optional; the work then needs an `isolation`, `missing_key` otherwise: every job that repairs
  equipment is done with it isolated, the user, 2026-10-24): a fault of the scenario, repaired when the work is done (written as §7.8's repair, with its
  event), or before that by the trainee under the permit (§15.5); a work for a fault the scenario doesn't have does
  nothing more. At most one work repairs a given fault (validator: `dup_id`), so the card's repair always names
  the one permit it goes under. **`set`** (optional): states written when done (a service counter, or a state of another code).
- **No restarts under lock** (the user, 2026-10-23): a work's own steps never start or move its own locked-out
  equipment. A key of its `set` that is a `state` whose `kks` is a point of the work's own isolation is `locked_write`,
  and so is an `op` step of its task (§16.6) on such a code (checked with the tasks, milestone S1). What the work puts
  right on its own equipment is a fault it `repairs` (a calibration's drift is a fault whose repair puts it back to 0):
  a repair writes the fault's states, never a command. A scenario fault's `repair` key that is a command (a state an
  op's `set` writes, or a `set` op's `input`) of a code of the own isolation of a work that `repairs` that fault is `locked_write` too.
- **`task`** (optional until the plant has a `staff.json`, then required and a task of it, `bad_ref`): the staff task
  (§16.6) that does the work; the trainee does the same steps when they play its role. Without staff (milestone P1)
  the trainee runs a permit through its states from the permit form, in free mode (§17.1).

### 15.3 A permit's states

Each work has one permit at a time; its state is the value `<work id>_permit`:

| Value | State | Moved by | Who (§16.3 authority) |
|---|---|---|---|
| 0 | none | | |
| 1 | requested | `request` (from none, closed or cancelled) | `request` |
| 2 | approved | `approve` (from requested) | `approve` |
| 3 | isolated | by itself (below) | |
| 4 | issued | `issue` (from isolated) | `issue` |
| 5 | accepted: work may start | `accept` (from issued) | `accept` and the work's discipline |
| 6 | done | `done` (from accepted) | the acceptor (below) |
| 7 | returned | `return` (from done) | the acceptor |
| 8 | deisolated | by itself (below) | |
| 9 | closed | `close` (from deisolated) | `issue` |
| 10 | cancelled | `cancel` from requested, approved or isolated (points still locked stay locked until unlocked) | `approve` |

- Every other action from a state is refused (`state`), as is one by a person without the authority (`authority`);
  the reasons are listed in the order `authority`, `state`, `iso_busy`, every one that applies. An action naming no
  work of the model, or not one of the eight above, is `unknown` and changes nothing.
- **The acceptor** is the person who made `accept`. While they are off duty or absent, another person with `accept`
  and the work's discipline may make `done` and `return` (permits are handed back at a shift's end, as on site).
- `done` writes the work's `repairs` and `set` in step 3 (§17.1); its repair only while its isolation is complete
  after this step's locks (a lock removed by authority in the same step: not made, no event; 2026-10-24). The work itself is the task's `work` steps before
  it: the engine checks the permit and the person, not the task.
- **Automatic moves** are levels, checked in step 3 after the locks and unlocks, in work order (model order), each an
  event (§17.7): a permit at 2 whose isolation is complete (or that has none) goes to 3; at 3 with its isolation not
  complete, back to 2; at 4 or 5 with its isolation not complete (a lock removed by authority, §15.1), back to 2:
  the work is suspended until its isolation is complete again and the permit is issued and accepted again (2026-10-24);
  at 7 with no point of its isolation locked (or none), to 8. A permit at 6 (the work done) keeps its state: it is
  returned as usual.
- A **permit number** is given at `request`: `PTW-` and four digits, counted from 1 in the run, in the order requested
  (a work requested again after it was closed or cancelled gets a new number, and its acceptor is cleared).

### 15.5 Repairs under a permit

Decided by the user on 2026-10-23: in a version 2 plant the trainee repairs a faulted piece of equipment only under
an issued permit with its isolation in place; the trainer (the instructor's panel) still clears faults directly, to set
up training.

- **The trainee's repair** is the input `[n, "repair", fault, work, person]`: the fault repaired under that work's
  permit. In step 1, as it comes:
  - `unknown` (event `[n, "repair", fault, work, person, "unknown", []]`, nothing else) when the work is not a work of
    the model, the fault not one of the scenario's with a `repair`, or the work's `repairs` not that fault;
  - refused (`[n, "repair", fault, work, person, "refused", [reasons]]`) with the reasons, in this order, every one
    that applies: `authority` (as the permit's `done`, §15.3 and §17.1: a person in a plant without staff; with
    staff, anyone but the acceptor, or another with `accept` and the work's discipline while the acceptor is off duty
    or absent: played roles and NPCs alike, whose repairs are their work's `done`), `state` (the work's permit is not
    *accepted*, 5), `isolation` (the work has no isolation, or its isolation is not complete as step 1 finds it: a
    repair needs the isolation in place, the user's rule of 2026-10-23; added 2026-10-24, before which a work without
    an isolation repaired at *accepted*; since 2026-10-24 a work that repairs has an isolation, §15.2);
  - otherwise it is noted, without an event, and made in step 3 with format 1's repairs (one list, in the scenario's
    order) if the work's permit is still *accepted* after this step's locks and automatic moves (a lock removed by
    authority in the same step suspends it, §15.3: then nothing, no event), its writes being the work's own (§15.1: made on a code locked only by isolations the work holds), with
    format 1's `[n, "repair", fault]` event. As any repair (§7.8), one of a fault not applied, already repaired, or
    whose writes would be skipped does nothing and makes no event. A fault asked by the trainer and under a permit in
    one step is repaired once, as the work's. The work's `done` later finds it repaired and repairs nothing.
- **The trainer's repair** is format 1's input `[n, "repair", fault]`, unchanged (§7.8, also on a fault no work
  repairs). The app sends it from the instructor's panel only; in a version 2 plant the card offers the trainee the
  repair under a permit, at the equipment, while the work's permit is accepted (and says why not otherwise). A version 1
  plant has no works: its trainee repairs as format 1 says.
- **Instructor actions are visible** (the user, 2026-10-24): instructor mode stays open to anyone, but in a version 2
  plant every input of the trainer's (format 1's `fault` and `repair`, today the only ones; any bypass added later
  likewise) makes, as it comes in step 1 and before anything else it does, the event `[n, "instructor", kind, id]`
  (kind `fault` or `repair`, id the fault as given), whether it then acts or not. The debrief marks each, and a run
  with any says so at the top of the debrief and in the saved run's offer (§18.7). A version 1 plant makes none:
  format 1's synthetic vectors are unchanged, and only its `train` and `hot` runs, on the first train's version 2
  content, carry them.

### 15.6 What a lock would do

Decided by the user on 2026-10-23: before placing an isolation that would trip a machine (the second of the condenser
pressure transmitters, when 2-out-of-3 voting falls back and trips the steam turbine), the permit form warns ("this
isolation will trip the steam turbine") and asks for confirmation; the lock is then made as any other. Nothing is
special-cased: the engine answers from the model.

- **The query** `lock_effects(work, point, person)` (an engine call, not an input: it changes nothing and is not part
  of the run; `person` null in free mode, else the trainee's person, who makes the lock) runs two copies of the run as
  it stands, with the inputs already made and not yet stepped: one with the input `[lock, work, point, person]` made
  after them, one without. Each copy steps **100 steps** (10 s of model time) with no
  other input. The answer is `{"lock": the lock event's result in the first copy ("done", "refused" or "unknown"),
  "trips": [...], "alarms": [...]}`: the trips with a `trip` event in the first copy and none in the second, and the
  priority 1 alarms with an event to `active_unack` in the first copy and none in the second, each list in model order.
  A trip or alarm that would come anyway is not blamed on the lock; a runback is announced by its priority 1 alarm.
- 10 s holds a trip's delay in the first train (at most 5 s) and the vote that follows a lock at once; what a lock
  causes later (a level that falls over minutes) is the lesson of the run, not of the form.
- **The form:** a lock whose answer has trips or alarms is not sent at once. The form names what would trip (each
  trip's text, and the machines its `do` moves, by name) and the alarms, and offers "Lock it anyway" and "Don't
  lock", the focus on "Don't lock"; the lock is sent only on "Lock it anyway". Touch, keyboard and gamepad alike.
  The answer is computed off the main thread and the button says it is checking meanwhile. An answer with nothing to
  warn about that comes back after the run has moved on more than 1 s is asked again (three times at most, then the
  lock is sent); a check that fails sends nothing. The lock is sent only within reach of its equipment, as the Lock
  button itself.
- **Vectors:** a unit run's and a fork's `effects`, `[[step, work, point, answer], …]`: each asked when the run is at
  `step`, after the inputs of step + 1 are made and before that step is stepped.

### 15.4 The `hold` node

`{"hold": ref, "when": ref, "init": n}` (stateful; `init` and the scenario's `init` optional): y ← the input while
`when` is false, else y keeps its value. The input is read as this step computed it, so it is an earlier value
(`forward_ref` otherwise, as for a stateless node) and a hold whose `when` stays false is its input exactly; `when` is
read as the previous step left it, like any stateful node's input. At step 0 a hold takes its `init` (the scenario's
wins over its own) or, without one, its input's step 0 value, evaluated in order with the stateless nodes. A
transmitter whose root valve is shut holds its last reading; the content reads `<isolation>_complete` as `when`. A
`hold` key where format 1 is read (a version 1 model file, a version 1 plant's scenario) gets format 1's code: beside
another node kind `unknown_key`, alone `bad_kind`. **Voting:** an isolated channel of a 2-out-of-3 trip votes *tripped*, so the trip
runs 1-out-of-2 on the other two (the usual safe choice: a second fault trips the machine rather than hiding a
real one); a bypass that keeps 2-out-of-2 is an authorised override not in format 2 (STAFF.md §3).

## 16. Staff (staff.json)

```json
{"format": "walkdown-plant-staff", "version": 1, "origin": "cr_desk_a",
 "speeds": {"walk": 1.3, "stair": 0.5, "ladder": 0.3, "drive": 8},
 "places": [Place, …], "ways": [Way, …], "next": [[point index, …], …], "zones": [Zone, …],
 "roles": [Role, …], "rosters": [Roster, …], "people": [Person, …], "vehicles": [Vehicle, …],
 "routines": [Routine, …], "tasks": [Task, …], "reactions": [Reaction, …], "messages": {id: text, …}}
```

`origin` is the place every place must be reached from on foot (`unreachable` otherwise): a control room desk.
`put_right` names the tasks an HSE stop gives (§16.7): `{"ppe": task, "permit": task, "unsafe": task}`.

### 16.1 The clock

plant.json: `"clock": {"day_scale": 6, "start": {"day": 1, "time": "06:00"}, "week": ["mon", "tue", "wed", "thu",
"fri", "sat", "sun"]}`.

- **The plant clock** (the clocks on the walls, rosters, routines) runs `day_scale` times faster than model time: at
  6, a 12-hour shift is 2 hours of model time, a day 4 hours. Process dynamics stay in model time (a pump still
  starts in seconds, a person walks at 1.3 m/s); only what people plan by the clock is compressed. `day_scale` divides
  60 (1, 2, 3, 4, 5, 6, 10, 12, 15, 20, 30 or 60: `bad_clock` otherwise), so a whole clock minute is a whole number of
  steps: 600 / `day_scale`.
- **The clock is kept in whole tenths of a clock second**, never as a float, counted from 00:00 of day 0 (the day
  before the first), so it is never negative: at step n it is C(n) = S + n × `day_scale` + J, with S the start (day d
  at HH:MM is (d × 1440 + HH × 60 + MM) × 600 tenths; the start's day is at least 1) and J the sum of the jumps made
  (§17.6). Shown as day and HH:MM:SS (day = C div 864,000, the rest likewise, all on non-negative integers), the
  seconds truncated. **A clock time** T is reached in the first step n with C(n) ≥ T. `week` names day 1's weekday
  first: day d is `week[(d − 1) mod 7]`, mod the floor modulo (day 0 is the last of the week). Day 0 exists for
  rosters (a night shift on at the start).
- Durations in staff content (`work`, timeouts, routine offsets) are whole clock minutes. Content tools that need
  the clock (the WTP's clock-rate gains, WATER-TREATMENT.md §5) read `day_scale` from plant.json.

### 16.2 Places, ways and zones

```json
{"id": "cr_desk_a", "at": [-25, 2, 0], "yaw": 90, "kind": "desk", "room": "control_room", "pose": "sit"}
["cr_desk_a", "cr_door", 9.5, "walk"]
{"id": "gt1_hall", "outline": [[0, 50], [80, 50], [80, 80], [0, 80]], "z": [-1, 20], "ppe": ["helmet", "ear"]}
```

- **A place** is a spot a person stands, sits or lies at: `kind` is `desk`, `seat`, `bed`, `table`, `work` (where one
  works on equipment: `kks` names it), `door`, `stop` (a vehicle stop), `locker` (PPE), `store` (tools), `counter`,
  `point` (a way point) or `muster`; `room` groups places (`control_room`, `mess`, `camp_b1_r12`); a room's **door**
  is its first place of kind `door` in file order; `pose` (`stand`, `sit`, `lie`, `kneel`) and `yaw` say how a person
  is shown there; `depot` is where a vehicle stands; a person's **home** is the first `bed` of their home room.
- **Taking places.** A place of kind `point`, `door`, `stop`, `muster`, `counter`, `depot` or `work` holds anyone
  (several people can work at one machine). Every other place is *taken* from the step a person's route to it starts
  (reserved) until they leave it, or until the step that reserved it stops being current (done elsewhere,
  pre-empted, abandoned, skipped, a jump); it is *free* otherwise. A `go` to a named place taken by someone else ends
  at the place's room door (or, without a room, the last place before it on the route) and waits there; when it
  becomes free, the waiting people take it in index order; after 15 clock minutes of waiting the step fails (the
  task's `else`, or abandoned).
- **A way** joins two places: `[a, b, metres, mode]`, both directions, `mode` from `speeds`, metres > 0. Its time in
  steps is ⌈metres × 10 / speed − 1e-9⌉, computed once in IEEE doubles in that order, and at least 1. Ways of mode
  `drive` join `stop` and `depot` places and are used only by vehicles (§16.8). A way shorter than the straight line
  between its places is `bad_way`.
- **The walking network.** Places of kind `point` (at most 500) are the network: walking ways (`walk`, `stair`,
  `ladder`) join points to points; every other place has exactly one walking way, to a point (its stub). A route from
  place a to place b is a's stub, the points' route, b's stub (a and b on the same point: the two stubs). The points'
  route is the quickest by steps; of equal ones, the one whose list of point indices (from the start) is lowest,
  compared element by element, a shorter list being lower when one is the beginning of the other. **`next`** holds,
  for each point i and destination j, the point after i on the route from i to j (−1 for i = j): made by the content
  tool with that rule, checked by the validator against its own search (`bad_ref`), and only looked up by the engines.
  Vehicles' routes over `drive` ways (at most 64 stops and depots) follow the same rule, searched at load.
- **The content tools make places and ways from the layout** (a `work` place in front of every piece of equipment
  that has a local op, a reading or a work; points along walkways, at stair ends and doors), and the Godot build checks
  every walking way against the navigation mesh (§18.1).
- **Zones** are plan outlines with a height range and the PPE needed there. Each place lists its zones
  (`"zones": [ids]`), written by the content tool; the validator checks the list against the outlines and refuses a
  place within 1 cm of a zone's edge or height limits (`bad_zone`), so no engine ever tests geometry. A person on a
  way is in the zones listed by both its ends.

### 16.3 Roles

```json
{"id": "field_op", "title": "Field operator", "discipline": "ops", "look": "coverall_ops",
 "authority": ["operate_local", "request", "lock_mechanical", "lock_process"],
 "ppe": ["helmet", "boots", "glasses", "gloves", "ear"], "routine": "field_op_shift", "off": "off_duty", "play": true}
```

- **`discipline`:** `ops`, `inst`, `mech`, `elec`, `chem`, `civil` (contractors), `hse`, `mgmt`, `security`,
  `transport`, `camp`. Accepting a permit needs `accept` and the work's discipline (§15.2).
- **`authority`:** `operate_screen` (ops from the screens), `operate_local`, `request`, `approve`, `issue`, `accept`,
  `lock_<kind>` (§15.1), `remove_lock` (a lock removal by authority, §15.1), `stop_work` (HSE: halts a work, §16.7), `sample` (samples and lab readings), `drive`. The
  trainee in a role has exactly its authorities: an operator who is not authorised can't lock an electrical point.
- **`ppe`:** what the role wears at work (the items: `helmet`, `boots`, `glasses`, `gloves`, `ear`, `harness`,
  `face_shield`, `apron`, `vest`); it is put on with a `ppe` step at a locker.
- **`routine`**, **`off`:** the routines on and off duty (§16.5). **`play`:** whether a trainee may take the role.
- **`look`:** the avatar's outfit (§18.2).

### 16.4 People and rosters

```json
{"id": "a_fo1", "role": "field_op", "roster": "shift", "crew": "a", "call": "Field 1, crew A", "home": "camp_b1_r12"}
{"id": "shift", "kind": "rotation", "cycle": ["D", "D", "N", "N", "O", "O", "O", "O"],
 "crews": {"a": 0, "b": 2, "c": 4, "d": 6}, "hours": {"D": ["06:00", "18:00"], "N": ["18:00", "06:00"]}}
{"id": "day", "kind": "days", "days": ["mon", "tue", "wed", "thu", "fri", "sat"], "hours": ["07:00", "16:00"]}
```

- **A person** has a role, one roster (and a crew for a rotation), a `call` sign (1–32 characters; people have call
  signs, not names) and a `home` room in the camp. Their order in the file is their **index**, which orders
  everything they do in a step.
- **Duties.** A duty belongs to the day its start falls on. In a rotation, crew c on day d (d ≥ 0) works
  `cycle[(d − 1 + crews[c]) mod len]` with mod the floor modulo (Python's `%`; GDScript's `posmod`, not `%`); a duty
  whose end time is not after its start ends the next day. A `days` roster works on the listed weekdays, those hours.
- **On duty** from the step its start is reached to the step its end is reached (events `duty on` and `off`, §17.7);
  slots of the routine before the start or after the end (handover, the commute) are made all the same (§16.5).

### 16.5 Routines

```json
{"id": "field_op_shift", "slots": [
   {"at": "start-0:40", "task": "commute_in"},
   {"at": "start-0:15", "task": "handover_take"},
   {"at": "start+1:00", "every": "2:00", "until": "end-1:00", "task": "round_field"},
   {"at": "start+4:00", "task": "meal_break"},
   {"at": "end-0:15", "task": "handover_give"},
   {"at": "end+0:20", "task": "commute_out"}],
 "idle": "idle_field_office"}
```

- **`at`:** an offset from the duty's `start` or `end` (`start+1:00`, `end-0:30`, at most ±12:00), or a clock time
  `HH:MM`, which means its first occurrence at or after the duty's start. `every` repeats it while the time is at or
  before `until` (inclusive). Each slot makes a task instance for the person in the step its time is reached (§17.2);
  slots are worked out per duty, when the duty's day is known.
- **`idle`:** the task done when the queue is empty (it ends when anything else is queued).
- **Off duty** (`off`): a routine whose slots are offsets from the person's previous duty's end (`prev+1:00`) or next
  duty's start (`next-8:00`), or clock times `HH:MM` each day; a slot is made only while the person is off duty and
  not within its routine's slots of a duty (meals, sleep before the next duty, free time chosen by `choose` steps
  among the camp's places: gym, laundry, prayer room, recreation, own room). So a night crew sleeps by day with the
  same routine as a day crew.

### 16.6 Tasks

```json
{"id": "round_field", "title": "Field round: circulating water and cooling tower", "priority": 3,
 "steps": [{"go": "locker_field"}, {"ppe": "role"},
           {"go": {"kks": "30PAC10AP001"}}, {"read": "30PAC10CP501", "expect": [1.8, 3.2], "tol": 0.1},
           {"work": [2, 4], "anim": "inspect"},
           {"go": {"kks": "30PAD10BB001"}}, {"read": "30PAD10CL001", "tol": 0.05},
           {"say": "round_done", "to": "ccr_op"}]}
```

Steps, each done by an NPC as said and by the trainee through the input named (§17.6):

| Step | An NPC | The trainee |
|---|---|---|
| `go`: a place, `{"kks": code}` (its work place), `{"kind": k, "room": r}` (the first free one in place order) or `"home"` | walks the route; done on arrival | `arrive` at that place (the app sends it within 1.5 m) |
| `work`: clock minutes, or `[min, max]` (a whole number drawn, §17.5); `anim`, `tool` | stays for that time | stays at the place for that time (`arrive`/`leave`; time away doesn't count) |
| `read`: a code with a `show` binding; `expect` optional (inclusive); `tol` (in its unit); `"test": "gas"` for a gas test | records the shown value (as the previous step left it); outside `expect`: `out_of_range` | `read` with the value typed: `misread` if it differs from the shown value as the previous step left it by more than `tol`, else as an NPC |
| `op`: `{"kks", "do", "value", "trip", "where"}` (`where` `local` or `screen`, one of the op's own; a `screen` op comes after a `go` to a desk in the same task) | makes the op input | the same op, made as anywhere (§7.2) |
| `permit`: `{"work", "action"}` (`"work": "$"` = the task's work) | makes the permit input | the same, from the permit form |
| `lock` / `unlock`: `{"work", "point"}` or `{"work", "point": "all"}` (each point in order, walking to each) | goes to the point's work place, makes the input | the same, at the point |
| `ppe`: `"role"`, a list, or `"off"` | puts it on or off (at a locker for on) | `ppe` inputs at a locker |
| `say`: a message id, `to` a role, a person or `"channel"` | sends it (event; the radio log) | `say` from the radio panel |
| `wait`: `{"until": value, "minutes": timeout, "else": step}` or `{"permit": [work, state], …}` (done when the permit is at that state or past it in the order 1 → 9; cancelled ends it as a timeout) | waits | waits |
| `call`: `{"role", "task", "work"}` | queues the task for a person of that role (§17.3, "Who gets a task") | the same, from the radio panel |
| `meet`: `{"room", "with": [roles], "minutes"}` | goes to the room's first free `seat`, `desk` or `table` (else its door), waits for one on-duty person of each role (at most 15 clock minutes), then stays | the same |
| `choose`: `[[weight, task], …]` (weights ≥ 1) | picks one by its random numbers and runs it in place of the rest of this task | `pick` among them (no draw) |
| `ride`: `{"from": stop, "to": stop}` | boards a vehicle (§16.8) | the same, or walks instead (a `go`) |
| `sleep`: `{"until": "HH:MM"}` | lies at the home bed until then | may `jump` (§17.6) |
| `stop`: `{"stop": "act"}` (roles with `stop_work`; goes first to the place the acting person is at when the step starts) | stops the act the task was given for (§16.7) | the same |
| `handover`: `"take"` | takes over, one point at a time in model order, the locks of their post (§17.8) | locks those points from the permit form ("Take over the lock") |
| `handover`: `"give"` | at each of their locks in turn, waits for another lock on the point (60 clock minutes at most), then unlocks; a lock nobody took over stays | unlocks each lock another lock now shares |
| `remove_locks`: a message id (the reason) | removes by authority, one point at a time, the locks of the person the `lock_left` reaction named (§16.7), with the message's text as the reason | the same, from the permit form |

- A task has `priority` 1 (urgent) to 5 (default 3), `interruptible` (default true), `resume` (`"next_duty"`: a
  job left unfinished at the end of its person's duty is held and resumed at their next duty, §17.10), optionally `work` (the work it
  does, for `$`) and `else` targets inside it; `"unsafe": true` on a step marks a shortcut (§16.7). `anim` and
  `tool` are what the app shows (§18.3).
- **The validator** checks that each step's role can do it (`authority`) and that every `{"kks"}` has a work place;
  that every task has 1–64 steps, every `else` points forward, no task reaches itself through `choose` or `call`, and
  every `idle` and off-duty task has a step that takes time (`work` of at least 1 minute, `wait`, `meet`, `sleep`) (`bad_ref` otherwise),
  so no person loops within a step. A retry is written out as the steps again.
- A `work` step paused and resumed keeps the number it drew.

### 16.7 Reactions and unsafe acts

```json
{"on": {"alarm": 1}, "roles": ["ccr_op"], "task": "answer_alarm", "priority": 1}
{"on": {"trip": "*"}, "roles": ["shift_sup"], "task": "trip_call"}
{"on": {"fault": "cw_b_fails"}, "roles": ["shift_sup"], "task": "raise_work", "work": "wo_cw_b_motor"}
{"on": {"value": "wtp_mb_exhausted"}, "roles": ["wtp_op"], "task": "mb_regeneration"}
{"on": {"unsafe": "*"}, "roles": ["hse_officer", "shift_sup"], "task": "stop_unsafe", "seen": true}
```

- **`on`:** an alarm becoming `active_unack` whose priority number is at most n (`alarm`), a trip latching, a fault
  applied, a value turning true (a rising edge, as an interlock), a permit reaching a state (`{"permit":
  "requested"}`), or an unsafe act starting. The task goes to one person (§17.3). A reaction is skipped while a task
  it gave for the same source (the same alarm, trip, fault, value, permit or act) is still queued or current, so a
  chattering alarm doesn't flood anyone.
- **`{"lock_left": "*"}`** (2026-10-24): a person (not the trainee) who has left the site (off duty, no place, §17.8)
  while holding a lock not kept for a job of theirs held for their next duty (§17.10). The reaction is made once per departure, in phase 2 of the next step 9 (§17.2), with the
  person as its source; its task's `remove_locks` step removes their locks. A person who comes back on site with
  locks still on and leaves again makes it again.
- **Unsafe acts:** a person in a zone without one of the zone's PPE items; a person at the work place of a work's
  `kks` in a `work` step of a task for that work while its permit is not `accepted`; a step marked `"unsafe": true`
  while it runs. An act **starts** in the step its condition becomes true and **ends** when it is false (events
  `unsafe` and `safe`, once each).
- **Seen:** with `"seen": true` the reaction goes only to people of its roles who are in a zone of the act in the
  step it starts, or who come into one while it lasts (the safety walk finds it), the first in role order then
  index; it is made once per act. Without `seen` it goes by §17.3 in the step the act starts. Both in phase 5 of
  §17.2.
- **Stopping work.** When a person with `stop_work` reaches a `stop` step of a task a reaction gave them for an act
  (§16.6), the acting person's current task is abandoned (or goes to its `else`) and they
  are given the `put_right` task for the act's kind at priority 1 (put the PPE on at the nearest locker, report to the
  supervisor for a permit, or leave the shortcut); the act ends when its condition is false. A paused step is not
  running, so a paused `"unsafe"` step is no act.
- **The trainee's unsafe acts** are the same, from the trainee's `zone`, `ppe` and `arrive` inputs.

### 16.8 Vehicles

```json
{"id": "bus_1", "kind": "bus", "seats": 30, "driver": "driver", "home": "depot_1",
 "runs": [{"at": "05:40", "stops": ["camp_stop", "gate_stop", "cr_stop"], "dwell": 2}]}
```

- **`driver`** is a role. A run's `at` is its departure from its first stop; the vehicle leaves `home` that many
  clock minutes earlier as its drive there takes (rounded up), with the first on-duty person of the role, in index
  order, who is not on another run; with none, the run is skipped (event). The driver is taken from their task (it
  is paused, and they are not free, §17.3) and placed aboard; after the run the vehicle returns home and the driver
  resumes their queue at the depot.
- The vehicle drives the quickest route over `drive` ways (§16.2) between its stops, staying `dwell` clock minutes at
  each.
- **Boarding:** a person whose `ride` step waits at a stop boards a vehicle dwelling there whose later stops include
  `to`, in index order while seats are left; they leave it at `to`. A `ride` with no such vehicle within 30 clock
  minutes becomes a walk to `to`.

## 17. The staff step

### 17.1 Where things happen in a step

Format 2 extends §7.10 so:

1. **Inputs**, first the trainee's in the order made, then the NPCs' made in the previous step's step 9, in the order
   made. Each is handled as it comes and makes its event at once: ops (§7.2, with the authority and `where` rules
   below), alarm inputs, faults and repairs (noted, as format 1; a repair under a permit checked first, §15.5), `permit` (§15.3), `lock` and `unlock` (noted for
   step 3, no event yet), the trainee's `role`, `task_ack`, `arrive`, `leave`, `read`, `ppe`, `zone`, `say`, `pick`
   (recorded for step 9) and `jump` (§17.6). Then the first-out records (format 1).
2. As format 1.
3. First the locks and unlocks noted in step 1, in the order made, each checked against this step's values (§15.1)
   and an event; then the automatic permit moves (§15.3); then format 1's faults and repairs (with those under a permit, §15.5); then `done`'s
   `repairs` and `set`, in the order the `done` inputs were made.
4. – 8. As format 1 (with §15.1's skipped writes).
9. **Staff** (§17.2): reads the values and states as steps 2–8 left them and this step's events, and **writes no
   value**: everything an NPC does to the plant is an input queued for step 1 of the next step. An NPC is refused as
   the trainee would be, and a run is reproduced from its seed and the trainee's inputs alone.

**Ops and authority.** A version 2 op input names where it is made and by whom: `[n, "op", kks, do, value, trip,
where, person]`. An op whose `where` is not among the op's own `where` is refused (`where`); one by a person whose
role lacks `operate_screen` (where `screen`) or `operate_local` (`local`) is refused (`authority`). The engine doesn't
check that the person stands at the equipment or a desk: the app does for the trainee, the validator for NPC tasks
(§16.6). **Free mode** (no trainee person) and version 1 inputs (no `where`, no person) skip every authority and
`where` check: the trainee holds every authority, as in format 1, and may also make permit, lock and unlock inputs
with person `null`. A plant without `staff.json` is always in free mode: its op inputs keep format 1's form, and a
permit, lock or unlock input naming a person (not `null`) is refused (`authority`).

### 17.2 Order in step 9

**Placement** (at step 0, and after a jump, §17.6): with the clock C, every person's duties in force are known (a
level: no `duty` events for it); each person is put at the first place of the task of their slot whose time is the
latest at or before C and within its duty (or off-duty routine), and that slot's task is queued for them (it starts in
the next step 9); with no such slot, their idle task's place (on duty) or home (off duty). Slots before
C are not made. Vehicles stand at home. Step 0 makes no staff events.

1. **Duties and slots:** people whose duty starts or ends (event `duty`), in person order; then the slots whose time
   is reached, per person in slot order: a task instance each (§17.3). People in the scenario's `absent` take part in
   nothing.
2. **Reactions** to this step's events and edges (all but unsafe acts, phase 5), in reaction order: each gives its
   task to one person.
3. **Vehicles**, in file order: they move, dwell, set off (§16.8).
4. **People**, in index order: each advances its current task (§17.3), ending steps and starting the next until one
   waits, at most 64 task steps per person in a step. A `ride` boards in this phase.
5. **Unsafe acts** (§16.7) start and end, in person order; then the reactions to them, `seen` or not, in reaction
   order (§16.7).

### 17.3 Queues

- **Who gets a task** (a reaction or a `call`): among on-duty people of its roles, in the order the roles are listed
  then by index, the first *free* one: free = no current task, or only the idle task, or a current task whose
  priority number is greater than the new task's and which is interruptible. If none is free, the first on-duty one.
  If none is on duty, nobody: event `task` with person `null` and `unassigned`. A person on a vehicle run is not
  free. A queue holds at most 32 instances: one more is `unassigned`.
- **The queue** orders task instances by priority number, then the step made, then the order made. The current task
  is pre-empted between its steps by a queued task with a lower priority number when it is interruptible; a `work` in
  progress is paused (its time kept) and resumed when the task comes back, where it was being done: an NPC elsewhere
  (called away, or a job held overnight) first goes back to that place as a `go` would (`fail` as a `go`'s), and the
  time runs again from the step after their arrival (S2's review: a calibration was finished from the plant gate).
  A pre-empted `go` stops at the next place of its route.
- **Travel:** a `go` starting in step n takes its route's ways one after another; the person is at the end of way i
  after the sum of the steps of ways 1 to i (event `move` per way). A target place is reserved when the route starts
  (§16.2); a `{"kind", "room"}` target with no free place, or a named place another person holds, sends them to wait
  as §16.2 says.
- **Ends:** the task's last step done ends it (event `done`); a `wait` timed out without `else`, or a refused op,
  permit, lock or unlock without `else`, abandons it (`abandoned`). A `wait` on the trainee times out like any other.

### 17.4 The trainee's person

The trainee takes the scenario's `trainee` person, or one chosen at the start (the input `role` at step 1 only, a
`play` role not in `absent`; any other `role` input is refused, with its event; the trainee and the drivers can't be
`absent`: `bad_ref`).
Their person is in the queue as any other, but every step waits for its input (§16.6) and nothing else is done for
them; reactions and calls reach them by the rule of §17.3, like anyone. A `say` to the trainee arrives in the radio
panel.

### 17.5 Random numbers

Each person has their own stream:
- `mul32(a, b)` = a × b mod 2³² for a, b < 2³², computed exactly; GDScript, whose ints are signed 64-bit, uses
  `((a * (b & 0xFFFF)) + (((a * (b >> 16)) & 0xFFFF) << 16)) & 0xFFFFFFFF`, which never passes 2⁶³;
- `mix32(x)`: x ^= x >> 16; x = mul32(x, 0x7feb352d); x ^= x >> 15; x = mul32(x, 0x846ca68b); x ^= x >> 16;
- the scenario's `seed` is a whole number 0 to 2³² − 1; person i (from 0) starts at s = mix32(seed ^ mul32(i + 1,
  0x9e3779b9)), 1 if that is 0;
- a draw: s ^= (s << 13) mod 2³²; s ^= s >> 17; s ^= (s << 5) mod 2³²; r = s >> 8 (24 bits);
- a whole number in [lo, hi]: lo + ((r × (hi − lo + 1)) >> 24); `choose` with integer weights of total T (≤ 2¹⁶)
  picks the first whose running sum exceeds (r × T) >> 24.
- A draw is made when a `work` step with a range starts and when an NPC's `choose` starts, for the trainee too
  (their `work` ranges draw; their `choose` doesn't). A person added at the end of the file changes no one else's
  draws; their other effects (places taken, tasks given) may change others' days.

### 17.6 Inputs, jumps and fast-forward

| Input | Meaning |
|---|---|
| `[n, "role", person]` | the trainee takes that person (§17.4) |
| `[n, "permit", work, action, person]` | a permit action (§15.3) |
| `[n, "lock", work, point, person]`, `[n, "unlock", work, point, person]` | a point of the work's isolation (its index in `points`) |
| `[n, "remove_lock", work, point, person, reason]`, `[n, "remove_lock", work, point, person, reason, owner]` | a lock removal by authority (§15.1): `reason` is text of 1 to 200 characters; `owner` names whose lock (without it, the point's earliest) |
| `[n, "repair", fault, work, person]` | the trainee's repair under the work's permit (§15.5) |
| `[n, "arrive", place]`, `[n, "leave", place]` | the trainee reached or left a place |
| `[n, "read", code, value]` | a reading the trainee wrote down |
| `[n, "ppe", item, 0 or 1]` | the trainee took off or put on an item |
| `[n, "zone", zone, "in" or "out"]` | the trainee entered or left a zone |
| `[n, "stop", person]` | the trainee stops an unsafe act of that person's (§16.7, §17.11) |
| `[n, "say", message, to]` | a radio message from the trainee |
| `[n, "pick", index]` | the trainee's answer to a `choose` |
| `[n, "task_ack"]` | the trainee has seen the new tasks in their queue (§17.6, fast-forward) |
| `[n, "jump", "HH:MM"]` | sleep or skip to the next such clock time |

**A jump** is handled in step 1: accepted only when fast-forward is offered (below) and no permit of the run is
between `requested` and `returned`. J grows by the time from the clock to the next occurrence of HH:MM strictly after
it (§16.1); the gap is (old clock, new clock]. The plant's values are not stepped through the gap (the night passes
quietly); the rest of this step runs as usual. In step 9 of that step, before its phase 1: every queue is cleared
(event `skipped` for each instance, and for each slot whose time fell in the gap, except one exactly at the new
clock), each vehicle goes home, reservations are released, and the placement rule runs at the new clock (duties as
levels: no `duty` events for duties that began or ended in the gap); phase 1 then runs. A jump draws no random
numbers.

**Fast-forward** is a level, part of the snapshot's `fast_forward`: offered when format 1 offers it (§7.9) and the
trainee's person has no task instance given to them since their last `task_ack` (a new task, a call, a reaction, a
`say` to them). The app stops fast-forward when it stops being offered and shows the new tasks; the trainee's
`task_ack` makes it offered again, with steps of theirs still to do (a walk to the next gauge is their own pace).
In free mode, format 1's rule alone.

### 17.7 Events and snapshots

Events, at the place §17.1 makes them. Step 1: `[n, "permit", work, action, person, "done" | "refused" |
"unknown", [reasons]]` (`unknown` with an empty list),
`[n, "repair", fault, work, person, "refused" | "unknown", [reasons]]` (§15.5),
`[n, "role", person, "done" | "refused"]`, `[n, "task_ack"]`, `[n, "jump", from, to, "done" | "refused"]` (tenths of
clock seconds). Step 3, first: `[n, "lock", work, point, person, "done" | "refused" | "unknown", [reasons]]` and
`"unlock"` (§15.1's reasons), and `[n, "remove_lock", work, point, person, "done" | "refused" | "unknown", [reasons],
owner, reason]` (owner: the input's `owner` when it names one, else the person whose lock is the point's earliest as
the input is made, null when it holds none or the work and point name none), then
the automatic moves `[n, "permit", work, "auto", null, "done", [new state]]`. Step 9: `[n, "duty", person, "on" |
"off"]`, `[n, "task", person, task, "start" | "done" | "abandoned" | "skipped" | "unassigned"]`, `[n, "move", person,
from, to, arrive step]`, `[n, "vehicle", id, stop, "arrive" | "depart" | "skipped"]`, `[n, "read", person, code,
value, "ok" | "out_of_range" | "misread"]`, `[n, "say", person, message, to]`, `[n, "unsafe" | "safe", person, kind,
zone or work]`, `[n, "stop", person, acting person, kind, detail, "done" | "refused", [reasons]]` (§17.11),
`[n, "early", person, task, step index, kind, made]` (§17.8: an action of the trainee's made in step
`made` counts for that step). The op event of a version 2 op adds `where` and person; reasons and failed values are value names or
the words `state`, `authority`, `where`, `iso_busy`, `locked`, `unlocked`, `owner`, `isolation`. Step 1 also makes
`[n, "instructor", "fault" | "repair", id]` (§15.5) in a version 2 plant. The repairs a `done` makes in step 3 are
`[n, "repair", fault]` events, as §7.8's, after format 1's repairs.

A snapshot (§12) adds `"clock"` (tenths), `"people": {id: [where, task or null, step index]}` (where: a place,
`["way", from, to, depart, arrive]` or `["vehicle", id]`), `"vehicles": {id: [place or [from, to, depart, arrive],
`[people aboard]]}`, `"permits": {work: state}` (those not 0, in model order), `"ptw": {work: number}` (each work's
last permit number, in model order), `"locked": [[isolation, point], …]` (in model order, then point order),
`"unacked"` (the trainee's tasks given since their last `task_ack`) and the values `<isolation>_locked`,
`<isolation>_complete`, `<work>_permit` (in the value slots after the trips' latches: each isolation's two in model
order, then each work's). A version 2 plant's snapshot always has `permits`, `ptw` and `locked`, after
`fast_forward`, in that order; `clock`, `people`, `vehicles` and `unacked` come with staff (milestone S1).

### 17.8 As built for milestone S1 (2026-10-23)

The reference (`ref/plant3d_staff.py`, run by `ref/plant3d.py`'s Engine) and the app's engine (`apps/plant3d/sim/staff.gd`)
agree bit for bit on `plant3d-v2.json`'s `staff` part (§19). S1 builds the operators' side of §16–§17; what comes
later is **refused by the validator** (`unknown_key`, naming the milestone), so no content relies on behaviour the
engines don't have yet:
- **S2:** `zones`, `put_right`, the `ppe` and `stop` steps, `"unsafe": true`, reactions `on: {"unsafe"}` and `seen`
  (PPE, zones, unsafe acts and the safety walk): built, §17.11;
- **S4:** `vehicles`, `drive` ways, `ride` and `sleep`, a person's `home`, `"go": "home"`, a role's `off` routine
  (the camp, the buses, off duty).

What S1 settles that §16–§17 left open (the engines and the vectors follow these):
- **The gate.** staff.json has `"gate"`: a `door`, `point` or `muster` place where people come on site and leave it.
  Without homes (S4), a person **off site** has no place: the snapshot's `where` is null. An off-site person whose
  task starts (a slot before their duty, the idle task when the duty starts) appears at the gate (`[n, "move",
  person, null, gate, n]`); a person off duty with no current task and an empty queue leaves the site from where
  they stand (`[n, "move", person, place, null, n]`). Placement puts off-duty people off site.
- **A person's own routine:** a person may name a `routine` of their own, which replaces their role's (three field
  operators of one role, each with the round of their own area).
- **New step `ack`:** `{"ack": "$"}` acknowledges the alarm the task was given for (an NPC makes the `ack` input when
  it is unacknowledged; the trainee's step is done once it isn't).
- **`"$"` codes:** `{"go": {"kks": "$"}}` goes to the work place of the instance's code: an alarm reaction's alarm
  `where`, a fault reaction's fault `kks`, a permit reaction's work's `kks` (or the reaction's `work`'s); a `call`
  passes the caller's code, alarm and work on (its own `work`, when given, replaces the work). A task's `"$"` work is
  the reaction's `work`, the permit's work, the call's, or else the task's own `work`.
- **`else`** may stand on a `go`, `op`, `permit`, `lock` or `unlock` step (and inside a `wait`): the index of a later
  step. Without one, the failure abandons the task.
- **A jump** is also refused while NPCs' inputs of the step before are still to be made in step 1 (a supervisor's
  permit request then made after the jump's check would be left with no task). **Limits:** an idle task has a `work`
  of a minute or more (`bad_ref`: a `wait` already true or an empty meeting would end in its own step), and a routine
  makes at most 256 slots in a duty (`limit`).
- **The idle task** is given priority 6 (below every task), ends (`done`) when anything is queued or the duty ends,
  and starts again (a new `start`) when it ended with the queue still empty.
- **Pre-emption** is checked at a person's turn whenever they stand at a place: between steps, at each place a `go`
  reaches, during a `work`, `wait` or `meet`. Not while an NPC waits for the outcome of its input (an op, permit,
  lock or unlock: the outcome is read in the next step 9). A paused instance keeps its `work`'s time left and its
  `wait`'s start; its `go` or `meet` looks for its place again when it resumes. `choose` ends the task (`done`) and
  starts the chosen one in the same instance (`start`).
- **Who waits for a taken place** checks it at their own turn in phase 4 (so in index order); a `{"kind", "room"}`
  target takes any free place of its kind then. The 15 clock minutes count from their arrival where they wait.
- **A meeting's place** is the room's first seat, desk or table not held by another person, else its door (a room
  used by `meet` has a door: `bad_ref`); the people it waits for are on duty, other than the person, at a place of
  the room.
- **`lock` / `unlock` with `"all"`:** the NPC walks to each point's work place in turn and makes one input at a time;
  the trainee's step is done when each point has a `done` lock (or unlock) by them.
- **Slots** are made per person in the order (time, duty start, slot index, repetition); duties and their slots are
  worked out through the day after the clock's.
- **Placement:** a slot "within its duty" is one at or after the duty's start. A task's first place is its first
  `go`'s or `meet`'s place; without one, the idle task's; without that, the origin. The task queued by placement is
  not counted in `unacked`.
- **The jump's step:** its `skipped` events come first for every instance queued or current (people in order), then,
  per person, for the slots in the gap; phase 4 is not run in that step, so the placed tasks start in the next.
- **The trainee.** Their `arrive` and `leave` inputs are applied at the start of step 9 in the order made; a seat,
  desk or table they held is let go when they leave it or arrive elsewhere. A `read`
  is compared with the value as the previous step left it (`misread` beyond `tol`); otherwise the shown value is
  checked against `expect`, and the event carries the value typed. Their `op` (the same code, `do` and `where`),
  `permit`, `lock` and `unlock` steps are done when a matching input of theirs is `done` (a refusal leaves the step
  waiting: the debrief lists it); each `done` event counts for one step only.
- **Actions before their step** (the user, 2026-10-23). An op, permit action, lock or unlock of the trainee's that is
  `done` and that no step of theirs took in its step is *kept* (at most 32, the oldest dropped first). When an `op`,
  `permit`, `lock` or `unlock` step becomes current (it is first looked at, or again after its task was paused: not
  again while it waits), a kept
  action that matches it counts for it if what the step asks for is still true then: the earliest such one, taken
  out of the kept ones, with the event `[n, "early", person, task, step, kind, made]` (the debrief says it was done
  out of order). Still true:
  - an op: every state its `set` writes has that value, a `set` op's input has the step's `value` (when the step
    gives one), a reset's trip is not latched; a machine command is dropped from the kept ones in step 9 of any step
    where its machine entered a state other than by `next` (a command or an action) after it was made;
  - a permit action: the work's permit has the same number (§15.3) and is at the action's state or past it in the
    order 1 to 9 (`cancel`: still cancelled);
  - a lock: the point holds a lock of theirs and the work holds its isolation; an unlock: the point holds no lock
    of theirs (a kept unlock is dropped in step 9 of any step where they locked its point again).
  Values are read as steps 2–8 of this step left them. A `lock`/`unlock` step with `"all"` takes a kept action for
  each point still to do. Within a step, the current step's own matching inputs are taken first. A
  `say` step takes a `say` input of the same message and `to`; a `call` step a `call` input of the same role and
  task. Radio inputs that no step took are sent as they are: a message to its `to`, or a **call**, a new input
  `[n, "call", role, task, work]`, accepted when a `call` step names that role and task in a task the trainee's role
  lists in its new key `requests` (the radio panel's requests) and the work is null (the called task's own `work`
  then, if any), refused otherwise. A task called by a request may not use `"$"` (`bad_ref`): the radio gives it no
  work, code or alarm. So a role calls only what its own requests say (a control room operator can't send a field
  operator to close a valve for an isolation). Calls make the event `[n, "call", person, role, task, work, "done" |
  "refused"]`, the NPCs' too.
- **`unacked`** in the snapshot is a count. `[n, "say", …]` to the trainee's person or role counts.
- **Ops by a person** (§17.1): the reasons start with `where` (the op's own `where` lacks it; then no authority is
  checked) or `authority`, before format 1's failed values and the locks. While the trainee plays a person, an
  input of theirs naming no person, or another person, is refused (`authority`); a version 1 op too.
- **Reactions** take the reaction's `priority`, else the task's. A value reaction's edge is against its truth after the
  previous step 9 (at step 0: its value then).
- **The queue limit** of 32 counts the current task unless it is the idle task.

### 17.9 Locks at a shift change, as built (2026-10-24)

The user's decisions of 2026-10-24 (§15.1 "Locks at a shift change", §15.5 "Instructor actions are visible"), in
both engines and the vectors (§19):
- **A post** is a role and a routine (the person's own, else the role's): the three field operators of a crew hold
  three posts, one of each crew holds each. A person's *post-mates* are the other people of their post, but not of
  their own crew (crew-mates come and go together: two control room operators of a crew hand nothing over to each
  other).
- **`{"handover": "take"}`, an NPC:** at each of their turns while the step is current, the point to take is the
  first, in model order (isolations, then points), that holds a lock of a post-mate, none of theirs and none of a
  crew-mate of their post (one already took it over), whose work's permit is not `returned` or `cancelled` (its
  isolation is coming off: nothing to hand over), that no other person's take step has chosen and is still taking,
  and that this step has not tried. They walk to its work place
  (its code's, when it has one), make the `lock` input, read its outcome in the next step 9, and mark the point tried,
  whatever the outcome. The step is done when no point is left to take. A pause lets the chosen point go.
- **`{"handover": "give"}`, an NPC:** the point to give is the first, in model order, that holds a lock of theirs and
  that this step has not tried. They walk to its work place and wait there until the point holds another person's
  lock, at most 60 clock minutes from their arrival (no wait when its work's permit is `returned` or `cancelled`); then they make the `unlock` input and read its outcome. A wait
  that runs out leaves the lock on. Either way the point is tried; the step is done when no point is left.
- **`{"remove_locks": message}`, an NPC:** the instance's *owner* is the person its `lock_left` reaction named (no
  owner in any other instance: the validator allows the step only in the task of a `lock_left` reaction, `bad_ref`,
  and in a role with `remove_lock`, `authority`; the message is one of `messages`, `bad_ref`). The point is the first,
  in model order, that holds a lock of the owner and that this step has not tried; they walk to its work place and
  make `[remove_lock, work, point, person, the message's text, owner]`, the work being the isolation's holder, and
  read its outcome. The step is done when no point is left.
- **The trainee's steps:** `take` is done when no point holds a post-mate's lock without one of theirs; `give` when
  no point holds both a lock of theirs and another person's, and either they hold no lock or 60 clock minutes have
  passed since the step became current; `remove_locks` when the owner holds no lock. Their own inputs do the work, as
  the permit form makes them; nothing is taken from the kept actions.
- **Leaving the site with a lock:** at phase 2 of each step 9 the engine lists, in index order, the people other than
  the trainee and the absent who are off duty, off site (no place, not on a way) and hold a lock not kept for a held job (§17.10); each one not on the
  list of the previous phase 2 is a `lock_left` source for every reaction to it. In a step with a `duty` `on` event
  the previous list counts as empty, so a lock still left on is given again when someone comes on duty (a removal
  that found no supervisor on duty, `unassigned`, is not lost; one still queued is not given twice, §16.7).
- **The vectors** pin (§19): in `staff.runs`, a lock handed over by NPCs at the shift change while the permit is
  issued, with no step where a point is unlocked (the incoming electrician's and field operator's locks, then the
  outgoing ones' unlocks), and the deisolation later by the new holders; nobody of the post coming on (absent): the
  outgoing electrician's wait runs out, they leave with the lock on, and the supervisor removes it by authority (the
  permit suspended back to approved); the trainee taking over a lock, and giving one; in `steps`, a removal by
  authority while accepted (the work suspended, a repair noted in that step not made), an unlock while accepted
  refused with no other lock, removals naming their owner, the trainee's repair refused for `isolation` (a work
  without one), and the instructor events; and in `staff.reject`, the new steps' and reaction's rule breaks.

### 17.10 Day-shift jobs overnight and re-issued permits (the user, 2026-10-24)

- **An unfinished day-shift job keeps its lock overnight.** A task with `"resume": "next_duty"` (the content's jobs)
  that is current when its person (an NPC) is off duty, at their turn while they stand at a place and wait for no
  input's outcome, is *held*: paused as a pre-emption pauses it (§17.8, its `work` keeping its time left), taken off
  their queue, event `[n, "task", person, task, "held"]`; then any such task in their queue is held the same way, in
  queue order, without being started (no walk to it off duty); a person may hold several, in the order held. They then
  leave the site as anyone off duty with nothing to do. When their next duty starts (phase 1, after its `duty`
  event) the held instances go back into their queue (event `resumed` each, in the order held) and are picked by the
  queue's order. A jump skips them (event `skipped`) and placement clears them.
- **A lock kept for a job is not `lock_left`** (§16.7; the user, 2026-10-25): while anyone has a job for a work
  (an instance of a task with `resume`, given for that work: held, queued or current), every lock on that work's
  isolation stays on, whoever placed it: a person who leaves the site with such a lock keeps it (the technician who
  isolated for a colleague's job too, and when the job resumes on a day they are off), the equipment isolated and
  the permit held (not cancelled or suspended); each removes their own lock when the job ends (their own unlock, as
  any: the deisolation's task goes to the lock's owner on duty, §17.11). Once the job has ended, a lock whose owner
  is still off site is a lock left like any other (§17.9). The supervisor's removal by authority stays
  for a holder who can't return (from the permit form, logged as before), and for any other lock they left (§17.9:
  `lock_left` counts only locks not kept, and `remove_locks` removes only those). No removal by authority is made
  for a kept lock.
- **A permit re-issued after a suspension is offered again.** When a permit moves back to approved by itself (§15.3:
  a lock removed by authority), its jobs (instances of a task with `resume`, given for that work: current, queued or
  held) are abandoned at once in phase 2 (event `abandoned` each), so nobody works on equipment no longer isolated,
  and their reaction sources are free (§16.7): when the permit is issued again, its job is offered again.
- **An offer nobody could take is made again** (the user, 2026-10-24). An offer for a permit's work that found
  nobody of its roles on duty (`unassigned`) is kept: a reaction to a permit state, or a task's `call` step whose
  work is a work of the model (the supervisor's call to the trade that isolates; not the trainee's free radio calls).
  In phase 2 of any step where someone of its roles comes on duty (a `duty` `on` event) it is offered again (§17.3),
  and kept for the next such step while still unassigned, until someone takes it. It is dropped when the permit is no
  longer at the state it had when the offer was made, or the reaction's source is held by another task; one offer
  is kept once (a reaction by its source; a call by its roles, task and work), only while the permit is open
  (requested to deisolated), and a kept call is dropped once someone has that task for that work again (current or
  queued: the trainee's radio call, say). An offer that fails only because a queue is full is not kept; a re-offer
  that fails so waits for the next step where someone of its roles comes on duty. So a permit suspended and re-isolated or re-issued at night, when no technician of its trade is on duty, is
  offered at the start of that trade's next shift. Placement clears the kept offers.
- **Vectors** (§19): a staff run with an instrument technician on days whose job and lock run past 16:00, held
  overnight and resumed at 07:00 (no removal by authority); a day fork of the first train where CW pump B's lock is
  removed by authority while its job is in progress and the job is offered again when the permit is re-issued;
  `reject` has a repairing work without an isolation.

### 17.11 As built for milestone S2 (2026-10-25)

Zones, PPE, unsafe acts, the safety walk and stopping work (§16.2, §16.6, §16.7), in both engines and the vectors
(§19). What §16–§17 left open, settled so:
- **Zones** (`staff.json` `zones`, at most 64): `{"id", "title"?, "outline": [[x, y], …] (3–64 points, the even-odd
  rule), "z": [low, high] (high above low), "ppe": [items] (1 or more)}`. Each place's `zones` lists, in file order,
  exactly the zones whose outline holds it and whose heights it lies strictly between; a place within 1 cm of an
  edge or of a height limit is `bad_zone`, as a list that differs. The content tool widens an outline by 2 cm until
  no place is that near.
- **What a person wears** (`worn`, a set of PPE items): at placement (step 0, a jump) everyone on duty wears their
  role's `ppe` (at work already), everyone else nothing; a person coming on site at the gate wears nothing, and what
  they wore is left behind when they leave the site (in the locker). A `ppe` step puts on the role's items (`"role"`)
  or the listed ones, adding to what is worn, or with `"off"` takes everything off; an NPC's is done at once. A step
  that puts on comes after a `go` to a `locker` place (a named one or `{"kind": "locker", …}`) in the same task
  (`bad_ref`), as a screen op comes after a desk: the engine doesn't check where the trainee stands, the app does.
  The trainee's `ppe` inputs (§17.6: an item of the list and 0 or 1, a JSON integer; anything else is ignored) are
  applied at the start of step 9 with their `arrive`, `leave` and `zone` inputs, in the order made; their `ppe` step
  is done when they wear every item it asks for (`"off"`: nothing).
- **The zones a person is in:** their place's; on a way, the zones both its ends list; off site, none. The trainee's
  are those of their `zone` inputs (a zone of the file and `"in"` or `"out"`; anything else is ignored), whatever
  their place.
- **Unsafe acts**, three kinds checked in the order `ppe`, `permit`, `unsafe` for each person not absent, in phase 5
  of every step 9 (also a jump's, after its placement; never at step 0): `ppe`, the first zone (file order) of theirs
  needing an item they don't wear, its id the act's detail; `permit`, standing (not on a way) at a `work` place
  whose code is the `kks` of the current task instance's work, in a `work` step, while that work's permit is not
  `accepted`, the work's id the detail; `unsafe`, a current step marked `"unsafe": true` (an idle task never), the
  instance's work (or null) the detail. A kind's act starts when its condition becomes true (`[n, "unsafe", person,
  kind, detail]`) and ends when it is false (`[n, "safe", person, kind, detail at its start]`); the person's other
  kinds are acts of their own.
- **Reactions to acts** (`{"on": {"unsafe": kind or "*"}}`, no `work`): after the acts of phase 5, in reaction order.
  Without `seen`, each act started in this step (person order, then kind) is given by §17.3. With `seen: true`, every
  act going on (person order, then kind) not yet given by that reaction goes to the first person of its roles (role
  order, then index), on duty and not the acting person, who is in a zone the acting person is in now; once given,
  never again for that act (the source is the reaction, the person, the kind and the act's start step).
- **Stopping work.** The task an act's reaction gives carries the act. Its `stop` step (validator: only in the task
  of a reaction to an unsafe act, and in roles with `stop_work`, `authority`) walks an NPC to the place the acting
  person is at when the step starts (the end of the way they are on; a place someone holds: its room's door, else its
  point; the trainee at no place, between places: the step waits until they are at one or the act is over), and
  there, if the act still goes on and nobody has stopped it, stops it: `[n, "stop", person, acting person, kind,
  detail, "done", []]`; the acting person's current task goes to its current step's `else`, or is
  abandoned (an idle task ends `abandoned`), and they are given `put_right`'s task for the kind at priority 1. A
  stopped act still ends only when its condition is false (a `ppe` act when the PPE is on or they have left the
  zone). An act already over, or already stopped, or the stopper's own (a reaction without `seen` may give it to
  the acting person), ends the step with no event. An input the acting person had already made (a lock, an unlock,
  a permit action, an op) is not taken back: it is applied in the next step as any, its task gone (S2's review). The
  trainee stops an act with the
  input `[n, "stop", person]` (§17.6), handled at the start of step 9 with their other inputs there: refused
  (`[n, "stop", trainee, person, null, null, "refused", [reasons]]`) for `authority` (their role lacks `stop_work`;
  in free mode the person is null and the reason `authority`) and `no_act` (no act of that person goes on that
  nobody has stopped, or the person is the trainee: nobody stops their own act), else the person's first such act (kind order) is stopped as above. Their `stop` step is done
  when its act is over or stopped.
- **`put_right`** (`{"ppe": task, "permit": task, "unsafe": task}`, each optional, a task of the file): any role may
  be given one, so every step of these tasks must suit every role (`authority`).
- **Slots by weekday:** a slot may name `"days"` (weekdays, 1–7, no repeat): it is made only in a duty that starts on
  one of them (a week's list of preventive work and calibrations).
- **An unlocking task goes to a lock's owner** (implementing the user's rule that only a lock's owner removes it,
  §15.1): a task given by §17.3 whose steps `unlock` the instance's work (`"$"`) or the work given goes first to an
  on-duty person of its roles (role order, then index) who holds a lock on a point of that work's isolation; with
  none, by the usual rule.
- **Snapshots** add `"worn"` (`{person: items}` for those wearing any, the items in §16.3's order) and `"acts"`
  (`[[person, kind, detail, start step, stopped], …]`, person order then kind), after `people`.
- **The first train's staff** (`tools/plant3d/train_staff.py`): the maintenance disciplines at STAFF.md §1's numbers
  (six mechanical, four electrical and four I&C technicians), three maintenance supervisors (each with the week's
  list of their discipline, the mechanical one hosting the contractors), two HSE officers (the toolbox talk, safety
  walks at 10:00 and 14:00, stopping what they see), a contractors' supervisor and eight contractors on two works
  without isolation (scaffolding on HRSG 1's drum platform, painting in the CW pump house), each contractor taking
  the work's shortcut 1 time in 12; zones over the process areas; a locker room; the corrective works of the trainer's
  faults (CW pump discharge valves' limit switches added) and the week's preventive works and calibrations (cooling
  tower fan 4's bearings, CCW pump B's insulation test, the condenser pressure transmitters' calibration, which puts
  a drift right). Every role but the guards' plays.

### 17.12 As built for milestone S3 (2026-10-26)

The water treatment plant's people (docs/plant3d/STAFF.md, WATER-TREATMENT.md §7 "Staff"), in both engines and the
vectors (§19). What S3 adds to §16–§17:
- **Reactions by area.** A reaction on an alarm or a trip may name `"areas"` (1–64 area ids of the plant, no repeat;
  `bad_ref`, `dup_id`; on any other reaction `unknown_key`): it is then made only for the alarms and trips of the model
  files of those areas (a model file's `area`, §7). So the main control room answers the train's alarms and the WTP
  operator the WTP's and the intake's, and an RO train's trip is not the train's trip call (the WTP's trips are
  answered through their alarms, an RO train's trip also by its own reset and flush, and the mixed bed feed pumps'
  trips on the degassed water tank's low-low level, which have no alarm, by a reaction to the trip).
- **Findings.** A reaction may be `{"on": {"finding": code or "*"}}` (a code with a `show` binding, `bad_ref`): a
  `read` event of that code (any, for `"*"`) with the result `out_of_range`, the trainee's as an NPC's (a misreading is
  no finding). Made at the end of phase 5 (§17.2), after the reactions to unsafe acts, in reaction order, each reading
  in the order made; given by §17.3; the instance's `"$"` code is the code read, its work the reaction's `work`; its
  source is the reaction and the code (a second finding of the code while the task it gave is queued or current is
  skipped, §16.7). The laboratory's silica result that makes the WTP operator regenerate a mixed bed is one.
- **The gas test** of a `hot` or `confined` work's task (§15.2: a `read` with `"test": "gas"` before its first `work`
  step) is checked by the validator from S3 (`bad_ref`), when the first confined-space job (a mixed bed's internals)
  comes to the staff, and the read must give its safe range (`expect`, `missing_key`). The content reads a portable
  detector's oxygen at the vessel's manhole (`00GCF1nCQ003`, 19.5–23.5 %), then waits a minute for the air to be
  breathable: a failed test abandons the job before anyone goes in.
- **The first train's content** (`tools/plant3d/wtp_staff.py`, joined by `train_staff.py`): a WTP operator and a shift
  chemist in each crew, two chemists on days (STAFF.md §1), after S2's people in the file; the WTP's places measured on
  the navigation mesh like the train's (its control room with the WTP desk's two places and four lockers, the
  laboratory, the walk from the train and to the intake); zones over its yards, its hall (hearing protection), the
  intake's pump house, and the chemical areas (the chemical store, the regenerant tanks and CIP skid: face shield and
  apron, put on at the WTP's lockers by the tasks that go there); the WTP's handover at its desk and the laboratory;
  the WTP operator's round twice a shift, four hours apart (fourteen readings over the whole plant, about an hour and a
  half of the clock: the walks are not compressed); the chemists' samples (the sample panel's SDI, the laboratory's analyses,
  the mixed beds' silica at the laboratory's action limit of 15 µg/kg, under the analysers' alarm at 20) and the
  chemical stock and dosing check; a filter's backwash ordered by the shift supervisor when its head loss is due (a
  value reaction), a mixed bed's regeneration on the laboratory's finding, an RO train's cleaning in place when its
  normalised flow is down 10 % (a value reaction), an RO trip's reset and flush, a regenerant or coagulant tank refilled from
  the bulk delivery when a check finds it low (the tanker's unloading is not built, WATER-TREATMENT §9; vehicles are
  S4's); the train's control room calling the WTP when its demineralised water tank runs low (a value reaction, and
  a radio request of the control room operator's); the WTP's works under permits, asked for by the WTP operator when
  a fault makes one (cartridge changes, the RO analysers' calibrations, a mixed bed's internals, an RO train's
  membranes), its equipment taken out of service and its process points locked by the WTP operator (the other stream
  put in service first), the electrical points by the electrical authorised person and the instrument points by the
  I&C technician once they are safe; the I&C maintenance supervisor's week adds the standby RO train's analysers.
- **The model** (`wtp_model.py`) gains the cartridge changes (`wo_cart_a`, `wo_cart_b`, repairing the clogging under
  the RO train's isolation), the RO analysers' drifts (trainer's faults) and their calibrations under an isolation of
  the analyser and the train (its ORP trip and permeate dump read the analyser, whose shown value is held while it
  is isolated, §15.4: the train is locked out meanwhile), the gas test points, and `show`
  bindings for the readings the people take (the SDI, the filtered water turbidity, the dosing and regenerant tanks).
- **A value reaction's job abandoned is offered again** (S3's limit, fixed 2026-10-26, under §17.10's rule for an
  offer nobody could take). A job comes from a reaction on a value when its instance was given by it (its source) or
  given by a `call` step of a task that came from it (the instance remembers the reaction, as far down as calls go).
  When such a job ends `abandoned` (a backwash refused, a wait that timed out, a stop, a suspension) while the value
  is still true, the reaction's offer is kept (once per reaction), as §17.10's kept offers: in phase 2 of any step
  where someone of its roles comes on duty it is made again (the reaction's task to its roles, §17.3), unless someone
  has a job of that reaction then (current, queued or held: kept for the next such step); it is dropped once the
  value is false, and kept when the re-offer gives it to nobody (§17.3: nobody of its roles on duty, or the queue
  full). So a backwash abandoned in the day is ordered again by the next shift supervisor, at 18:00. Placement clears
  it with the others.
- **The WTP's handovers with both there** (S3's limit, fixed 2026-10-26, by the timing alone): the WTP's people are
  about 40 minutes of the clock from the gate (the control building's locker room on the way), so they come in at
  `start-0:45` and reach the WTP's desk or the laboratory between `start-0:15` and the start, while the outgoing one,
  there from `end-0:15`, is still on duty; they are still at the meeting when their own duty begins, so the outgoing
  one's meeting finds them too (a meeting counts people on duty). The outgoing one's handover has priority 2, so a
  round or samples still going at `end-0:15` (as placement starts them at a scenario's start) give way to it. The
  scenarios with staff start at 05:00, before the first of those slots (placement gives no slot before the start).
- **Left as it is:** the gas test point reads a constant (the air of a vessel opened and ventilated for the work).
- **The scenario `shift_wtp`:** shift_cold with filter 1 nearly due (its head loss reaches 2.2 m at about 06:05) and
  mixed bed A further used (its silica passes 15 µg/kg at about 06:50, the analyser's alarm at about 08:15).

### 17.13 Several trainees (multiplayer, milestone MP1)

A run is a **single-player run** (everything above, unchanged) or a **session run** (docs/plant3d/MULTIPLAYER.md §3,
decision 0067), chosen when the engine is made and kept for the run (saved with it). In a session run:
- **Slots and players.** There are 8 slots, 0 to 7; a slot plays one person or none. At step 0 the scenario's
  `trainee`, when it names one, is slot 0's (the host's); every other slot plays nobody. A single-player run is the
  case of slot 0 alone: its trainee is slot 0's person, and everything this section calls "the slot's person" is
  §17.4's trainee there.
- **Every input carries its slot** as its last element (`[n, kind, …, slot]`, the trace form of §12 and §17.6 with
  the slot appended; the vectors' and the commits' form). An input whose last element is not an integer 0 to 7 does
  nothing and makes no event. Step 1 handles the inputs in the order made (the commit's order, MULTIPLAYER.md §3.1),
  then the NPCs' as before; each input is handled as a single-player run handles its trainee's, **with its slot's
  person, as the slot stands at that moment, as the trainee**: the authority and `where` rules of §17.1 (an input
  naming no person, or another person, while the slot plays one: `authority`; a version 1 op too), the repair under a
  permit (§15.5). A lock, unlock or removal is checked in step 3 against its slot's person then. A slot that plays
  nobody is in **free mode**, as a single-player run without a trainee: format 1's inputs and the person-null permit,
  lock and unlock inputs pass the authority checks, an input naming a person is refused (`authority`), and its
  staff inputs do nothing (its `stop` is refused, `authority`, as in free mode).
- **`[n, "role", person, slot]`** at any step: done when the person is a `play` role, not `absent`, played by no slot,
  and the slot plays nobody; refused otherwise. Event `[n, "role", person, "done" | "refused", slot]`. When done, the
  person becomes the slot's: their current task, unless it is the idle task, is paused as a pre-emption pauses it
  (§17.3, §17.8: its step's place and reservation looked for again, its `work` keeping the time left, the input an NPC
  waits on forgotten: that input itself is still applied, in this step, as the NPC's) and taken up again at their
  turn; a person walking a way is between places from then on (the way given up; the place it started from kept as the
  place they left); their zones are, from then on, those their place or way gave them at that moment, changed by the
  slot's `zone` inputs; the slot's count of new tasks starts at 0 and its kept actions (§17.8) are none.
- **`[n, "release", slot]`** (made by the session's host only, MULTIPLAYER.md §3.3): done when the slot plays a person,
  who becomes an NPC at once (event `[n, "release", person, "done", slot]`); refused otherwise (`[n, "release", null,
  "refused", slot]`). Their current task, unless it is the idle task, is paused as above and taken up at their NPC turn
  (in this step's phase 4); one between places is put back at the place they last left (no event; one who was never at
  a place is off site, as an NPC); the slot's count of new tasks and its kept actions are cleared. A released person may
  be taken again by any slot (`role`). A single-player run ignores `release`.
- **`[n, "task_ack", slot]`** sets that slot's count to 0; event `[n, "task_ack", slot]`.
- **Counts of new tasks** (§17.6) are per slot: a task given to a slot's person counts for that slot; a `say` to a
  player's person or role counts for every slot whose person it reaches, other than the speaker's.
- **Fast-forward** (§17.6) is offered when format 1 offers it and no slot's person has new tasks; a jump likewise
  (any slot may make it: the host decides who, MULTIPLAYER.md §7.2).
- **Step 9:** the players' `arrive`, `leave`, `ppe`, `zone` and `stop` inputs are applied at its start in the order
  made, each to its slot's person at that moment (a slot playing nobody: `stop` refused, the others nothing). A
  `leave` keeps the place left for that slot. In phase 4 each player's person takes the turn of §17.4 (in person
  order, as anyone) with their own slot's inputs of the step; at a jump's step each player's actions are kept as
  §17.8 says. Every rule that §17.1–§17.12 give "the trainee" holds for each player's person, and every rule they
  give the NPCs for every person no slot plays (leaving the site with a lock, holding a job overnight, the gate).
- **Snapshots** of a session run add `"players": [[slot, person, count of new tasks], …]` (the slots that play a
  person, in slot order); `unacked` is the sum of those counts (in a single-player run, the trainee's as before).

### 17.14 The state digest

Every engine can give a **state digest** (MULTIPLAYER.md §4: what the players of a session compare): SHA-256 over
- the 13 bytes `wdp-digest-1\n`,
- every value slot's double (declared values, `ext`, machine states, trips' latches and the format 2 values, in slot
  order: §12's snapshot values), little-endian,
- the encoding of the **digest tree** in Godot 4.7's binary Variant form (`var_to_bytes`: every value a 4-byte
  little-endian header with its type, integers in 32 bits when they fit and 64 otherwise, floats in 32 bits when the
  single-precision value is the same double and 64 otherwise, text as its UTF-8 length and bytes padded to 4, arrays
  as a count and their elements; `ref/godot_variant.py` writes it for the reference).

The digest tree is an array (types: `b` a byte array, `i32` and `i64` packed arrays of 32- and 64-bit integers, `[…]`
an array, `int` an integer):
1. the step (`int`);
2. the stateful nodes' counters, the timers' and delays' step counts in program order (`i64`);
3. each machine's state as its index, model order (`i32`); each trip's latch (`b`) and its `delay` count (`i64`);
4. the first-out records, `[[group, trip], …]` sorted by group;
5. each alarm's state as its name (`[…]` of text), its `delay` count (`i64`) and the step its shelf ends, −1 when not
   shelved (`i64`); each interlock's `when` after the last step (`b`);
6. the faults applied and those repaired since, each a sorted array of ids;
7. each work's permit state (`i32`); the permits' numbers `[[work, number], …]` sorted by work; the count of permits
   requested (`int`); the acceptors `[[work, person or null], …]` sorted by work; each isolation's holding work as its
   index, −1 for none (`i32`); the locks `[[isolation index, point, [persons in the order placed]], …]` in model order;
8. the staff's part, or null without staff: the jumps' total J (`int`), the task instances made (`int`), whether the
   run is a session run (bool), the 8 slots' persons, −1 for none (`i32`), their counts of new tasks (`i32`), the places
   they last left, −1 (`i32`), their kept actions (8 arrays of §17.8's records), the reservations and holds
   `[[place, person], …]` sorted by place, the reaction sources given `[[source, count], …]` sorted by source, each
   reaction's value truth after the last step (null for a reaction not on a value), the offers kept (§17.10:
   `[source, source, roles, task, priority, work, code, permit's work, its state or the value's name]`), the people off
   site with a lock at the last phase 2 (sorted indexes, `i32`; kept only when a reaction is on `lock_left`), the `seen`
   reactions made `[[reaction, person, act kind, start], …]` sorted, the NPCs' inputs for the next step; then, one
   array per field over the people in file order: on duty (`b`), the duty (`[start, end]` or `[]`), the duties planned
   ahead, the last day planned (`i64`), how many slots are still to come (`i32`), the place (−1 for none, `i32`), the
   way (`[from, to, depart, arrive]` or `[]`), the current task instance or null, the queue, the jobs held, the place
   reserved and the place held (−1, `i32`), the outcome an NPC waits for (text or null), the random stream (`i64`), the
   PPE worn (a bit per item of §16.3's list, `i32`), the unsafe acts going on (per kind null or `[zone or work, start,
   stopped]`), the zones from zone inputs (a bit per zone, `i64`).

A task instance is `[task, priority, step made, order made, step index, work, code, alarm, source, idle, started,
interruptible, owner, act, source of the job's value reaction]`: an act as `[person, kind index, start]`, a reaction
source as its parts joined by `|` (`reaction|alarm|id`, `reaction|unsafe|person|kind|start`, …), a kept offer of a
call as `call|roles joined by /|task|work` (`<null>` for no work).

**What it leaves out, and why:** the event log and the input log (they only grow, and what they record is in the
state), the inputs still queued for the next step (in a session they arrive with commits and are not state yet), the
previous step's values (the next step makes them again), the model's constants, and what the specification leaves to
an implementation: a task step's own progress (a `work`'s or meeting's time left, a `go`'s place found, a lock round's
point; the app counts an NPC's work only when they wake, the reference every step, §0062), the staff step's wake-ups
and next phase 1, and what is derived from the rest (the locks per code, the locked points' bits). A difference that is
only in those shows in the digest by the step after the task step ends, when the instance's step index, events or
places differ.

## 18. People on screen (the app; not in the vectors)

### 18.1 Walking

- The logical position (§17.3) is the truth; the avatar shows it. **No path search for people at run time:** the build
  stores, for every way, the polyline the navigation mesh gives between its places (0059's mesh, stairs and ladders
  along their own paths), and an avatar on a way is placed along it by the fraction of its time gone. The build
  refuses a walking way whose mesh path is longer than its length + 10 % (`bad_way`), so people never visibly hurry.
- **No crowd simulation.** People keep to a lane: 0.35 m to the right of the polyline (by direction of travel), so
  two people meeting pass. Near the trainee (within 1 m ahead) an avatar steps aside up to 0.6 m, or stands and then
  catches up at up to 1.6 m/s; it never pushes the trainee and never leaves the walkable mesh. A late avatar is
  placed at its logical position the next time it is out of view.
- Doors open for people as for the trainee; vehicles drive on `drive` ways along their road polylines.

### 18.2 Avatars

- Bodies are CC0 exports of MakeHuman (MPFB) with CC0 clothes only, our own work clothes and PPE (coveralls,
  hi-vis vests, hard hats, glasses, ear defenders, harness, radio, tools) made as kit props on the hands, head and
  body (decision 0063). Animations: CC0 clips retargeted at import to Godot's humanoid skeleton profile; work poses
  the clips lack (a handwheel, a calibrator, typing) are made by our own poses and Godot's skeleton modifiers.
- **Looks** (`look` in a role): body (one of 8), outfit and colour, hard hat colour by function (white:
  supervisors, engineers and managers; yellow: operators and technicians; blue: contractors; green: HSE; these are
  ours, shown in a legend), each person's look fixed by index.
- **As built (A1, 2026-10-23):** KayKit's mannequin is a large-headed cartoon figure (hips at 0.41 m), so the bodies
  are ours, made by code at build time (`builder/people/body.gd`) on KayKit's skeleton at an adult's proportions,
  with KayKit's clips retargeted (rotations as they are, the hips' height scaled) and our own work poses
  (`builder/people/rig.gd`). Eight looks by role (`builder/people/looks.gd`): the plant's own staff in a blue
  coverall with reflective tape, a hi-vis vest and a **white** hard hat (confirmed by the user, 2026-10-23: white, blue for contractors, green for HSE, replacing the colours above), told apart by the
  vest's colour (orange: operators and supervisors; lime: maintenance, managers, HSE) and what they carry (radio,
  clipboard, tool belt, the calibrator's case); contractors grey with a blue hat, HSE officers a green one; safety
  glasses and ear defenders on every field role. Engineers, managers and office staff wear a dark shirt and trousers
  under a lime vest. Each look has a **road variant**: on roads and outside the process areas the hat is carried in the
  hand and a phone held in the other (its own walk, and an idle looking at the phone), the hat back on inside an area
  that requires it (the driver says which: `hat` in app/people.gd); the posed band, beyond the skinned one, shows the
  hat on. The person's height varies by ±6 % (the node's scale).

### 18.3 Animation

An `AnimationTree` per near avatar: idle, walk and run blended by speed, turning in place, and the actions of
`anim` (`inspect`, `talk`, `radio`, `type`, `sit`, `write`, `kneel_work`, `wrench`, `handwheel`, `calibrate`, `carry`,
`climb`, `eat`, `sleep`, `lift`). Advanced by the app (manual process mode) at 30 Hz within 10 m, 15 Hz to the end of
the skinned band, posed meshes beyond (§18.4).

### 18.4 Budgets per tier

The frame rules don't change (≥ 95 % of frames shown at ≥ 30 fps, none over 100 ms after the first 5 s, peak PSS
≤ 1.5 GB, first walkable frame ≤ 15 s on the Note 9; 0060's margin: every first start ≤ 13.5 s). People get a fixed
share, measured with the frames walk among a crowd (MILESTONES.md M3):

| | Note 9 (`lean+vis`) | Laptop (`full`) |
|---|---|---|
| Skinned avatars drawn | ≤ 12, within 25 m (A1's measurement, below) | ≤ 24, within 40 m |
| Their meshes | LOD0 ≤ 4,000 triangles (≤ 10 m), LOD1 ≤ 1,500; one material; ≤ 56 bones | the same assets |
| Posed band | to 80 m: unskinned meshes in 6 poses (≤ 500 triangles), one MultiMesh per pose and body (the outfit's colours per instance), pose changed 4 times a second; ≤ 50 draw calls | to 150 m; ≤ 50 draw calls |
| Beyond | not drawn | not drawn |
| People in the world (logical) | ≤ 200, every tier | |
| GPU time for people | ≤ 2.5 ms median added | ≤ 2 ms |
| CPU per frame for people | ≤ 2 ms (animation, placement) | ≤ 1 ms |
| Staff step | ≤ 0.3 ms per model step at the peak of a shift change, routes only looked up (`next`, §16.2); a jump's placement ≤ 50 ms | |
| Model step with the WTP and the staff | ≤ 2.1 ms, so fast-forward keeps at least 12× (0065); measured in W2 and S1 | |

| Memory | ≤ 100 MB PSS for bodies, clothes, animations and textures (1024 px on the phone) | |
| Load | the avatars' pipelines compiled in the hidden frame (0060): ≤ 1.5 s added to the first start | |

The nearest by distance get the skinned slots, people the trainee talks to or works with first. A tier that misses
its share after M3's measurement lowers its counts, never the frame rules (MILESTONES.md says what then needs the
user).

**Measured (milestone A1, 2026-10-25, decision 0064 as built):** the Note 9, release build, `lean+vis`, the 10-minute
`frames` walk with N skinned people round the walker (`crowd=N`), each run started at a battery temperature of at most
30 °C, the counts interleaved. Medians (range): 0 people (3 runs) 99.39 % (98.69–99.43) of frames at ≥ 30 fps, GPU
median 20.6 ms; 6 (2 runs) 99.39 % (99.35–99.42), +0.15 ms; 12 (2 runs) 99.40 % (99.35–99.45), +0.3 ms; 24 (2 runs)
98.85 % (98.59–99.10), +0.7 ms, one frame of 112 ms in one run. No other frame over 100 ms; first walkable frame
10.8–11.9 s; peak PSS 1,102–1,158 MB; the people's CPU 0.70 / 0.91 / 1.33 ms a frame (mean). The phone's count is
12. Third runs for 6 and 12 were not possible: the shared phone stayed above 30 °C for the next four hours.

### 18.5 Interiors and loading

An area with `"load": "inside"` (a camp block's rooms, the mess hall's kitchen) is a scene of its own, loaded when the
trainee comes within 15 m of its building's doors and freed 30 m away; its shell is in the area that holds it. Its
people are logical as anywhere and drawn only while it is loaded.

- **Content** (validator): only in a version 2 area of a version 2 plant; its bounds lie inside exactly one other
  area (the one holding its building) and overlap no other; it holds no equipment or pipes.
- **Built** (C1): the build leaves interiors out of the plant's scenes at the start and out of the lightmap's bake,
  lists them in the manifest's `interiors` with their buildings' doors, and bakes them into the walking directions'
  navigation mesh (a way into a room is a way like any other). The app (`app/interiors.gd`) checks the walker's
  distance four times a second, loads with `ResourceLoader.load_threaded_request`, and shows an interior only once it
  has loaded.

### 18.6 New kit parts

Water treatment (WATER-TREATMENT.md §5): `screen_band`, `bar_screen`, `clarifier` (circular, solids contact: d,
height, bridge), `thickener`, `filter_bank` (gravity cells: cells, cell size, gallery), `pressure_filter` (vertical
vessel: d, height, media), `cartridge_housing`, `ro_train` (vessels per stage, elements per vessel, frame),
`degasser` (tower, blower), `ion_exchanger` (mixed bed vessel: d, height, lateral nozzles), `dosing_skid` (day tank, the
metering pumps' plinths), `metering_pump`, `chemical_tank` (FRP, in a bund), `filter_press`, `sample_panel`, `lab_bench`, `agitator`
(on a tank or basin). Camp and site (SITE.md): `bed`, `locker`, `desk`, `chair`, `table`, `bench`, `counter`,
`shelf`, `washer`, `gym_rack`, `sofa`, `screen` (a TV or wall display), `carpet` (a floor finish), `vehicle` (bus,
pickup, SUV), `barrier` (a gate arm), `guard_booth`, `canopy` (shade over parking and walkways), `lamp_post`,
`planting` (by species: date palm, tamarisk, oleander, bougainvillea, a drought-tolerant shrub; SITE.md §4), `kerb` (painted), `court` (a fenced sports court), `porch`, `room` (an
interior partition with doors). Geometry is the kit's, as everything (§9).

As built (milestone C1; `data/plant3d/kit.json` has their parameters): these are structures (the `structures` group,
no code) that the parts kit draws (`apps/plant3d/kit/parts_site.gd`), placed by `at` and `yaw` and instanced per cell
like equipment, solid where a walker would meet them. Beyond the list above:

- **`planting`:** `species` (`date_palm`, `tamarisk`, `oleander`, `bougainvillea`, `saltbush`, `caper`), `height`
  and `spacing` (0: the species' usual), and `route` (relative to `at`): a row, one plant at its first point and
  then every `spacing` metres, each with a shape of its own; the default route, of no length, is one plant. Opaque
  geometry in the plant's one shader (no cut-out leaves, §10 and 0060): a palm's trunk, its leaf bases (`detail`) and
  its arching fronds (keeled blades, both faces), shrubs and crowns as clusters of lumps with their leaves' and
  flowers' colours in the vertices; a row's drip line (`detail`). The generated LODs thin them with distance.
- **`room`:** `walls` (records of `a`, `b`, plan points relative to `at`), `height`, `openings` (`door`, `window`,
  and `door_closed`: a shut door's leaf drawn in the wall, for a room nobody is shown).
- **`crossing`:** a marked pedestrian crossing (`width` across the road, `length` along it).
- **`sanitary`:** `wc`, `shower`, `basin` or an `ablution` row.
- **`counter`** kinds `serving`, `kitchen`, `range`, `sink`, `basin`, `reception`, `workbench`; **`shelf`** kinds
  `store`, `shoes`; **`gym_rack`** kinds `weights`, `treadmill`, `bike`, `bench`.
- §5's parts gain: a `building`'s `cladding` `panel` (prefabricated sandwich panels) and `floor` `vinyl` (matte vinyl
  tiles; also a `floor`'s or `platform`'s `finish`); a `door`'s `locked` (a shell's door that never opens: its leaf on
  the wall's outside, no opening needed); a `road`'s `surface` is drawn (asphalt, paved concrete, gravel) and a road
  at ground level is cut out of the ground and the yards (and opens the boundary wall where it crosses it).
- **Photo pass 3 (2026-10-25):** `planting` species `dracaena` (a pot plant, indoors only: SITE.md §4); `vehicle`
  kind `ambulance` (a high-roofed van); `canopy` `kind` `sail` (a car park's arched white shade sails on posts along
  one side, every bay of about 5.5 m: two stalls) besides `sheet`; `table` `kind` `wood` (a carved side table);
  `sofa` `cover` `leather`; a `road`'s `surface` `pavers` (block paving); and the new parts `hydrant` (a red pillar
  fire hydrant), `bollard` (`height`), `skip_bin`, `mast` (a lattice telecom mast, `height`) and `ac_unit` (a split
  air conditioner's outdoor unit on its wall brackets, `at` its foot on the wall's face, facing out).
- An interior (§18.5) holds only these parts and doors, and is drawn unbaked in the vertex format the instanced
  pieces already use, so showing one compiles no pipeline the start has not (0060).

### 18.7 The trainee's panels

- **Start:** scenario, day and time, and a role: the list of `play` roles with what their shift holds; or free mode
  (no role: the plant as in format 1, the people working around the trainee).
- **Tasks:** the role's day (from its routine), the current task's steps with the place and "take me there" (0059),
  the readings sheet of a round (each value with its expected range), what each NPC is waiting for from the trainee.
- **Permit form:** a work's permit, its state and history (who did what at which clock time), its isolation points
  with their `how`, which are locked (and by whom), and the buttons the trainee's authorities allow, each refused with
  its reasons as an op is.
- **Radio:** a log per channel (operations, maintenance, HSE) of the messages of §16.6 in text; the trainee sends
  from the messages their task offers and from requests (call a technician, ask for a permit). No voices and no free
  text: messages are content.
- **PPE:** what the trainee wears (at a locker), and the zone's needs when entering it.
- **Shift log and handover:** running equipment, open permits, alarms, findings of the rounds and work done, made from
  the events.
- **Map:** people as dots by role (a filter), the trainee's colleagues named.
- **Time:** the clock, fast-forward with "until my next task", and "sleep to the next shift" (a jump) when allowed.
- **Debrief:** §8's, with the role's tasks (done, late, abandoned, skipped), the permits and the unsafe acts.

Every panel works with keyboard, gamepad and touch, as the format 1 panels.

**As built for milestone S1** (the app, 2026-10-23): Start is the Crew panel at the start of a run with staff (the
roles, each with its people on duty or coming on, or free mode); Tasks, Radio and Time are in that panel too (the
current task's steps, the tasks waiting, "Seen", the readings sheet, the radio log with the role's requests, "Sleep
to" the next shift); the permit form is P1's, its actions made as the trainee's person; the map shows people as dots
by role (no filter yet), and the plant shows them as capsules. PPE, the shift log, the role's day ahead and the
debrief's role tab come with S2 and S4.

**Added 2026-10-24 (locks at a shift change, instructor actions):** the permit form lists every lock on a point (who,
in the order placed). At a point holding a lock of the trainee's post-mate and none of theirs it offers "Take over the
lock" (a `lock`, within reach as any lock); at a point holding a lock of theirs and another's, "Remove my lock (handed
over)"; their handover task's step says which points are left. "Remove by authority" names the lock it removes. The
debrief marks every instructor action ("by the instructor") and, when there is any, says at its top that the run
used instructor mode, with their number; the saved run's offer says so too. Both read the run's `instructor` events.
A point whose lock belongs to a day worker gone home says their lock stays on overnight and that they finish the job
on their next shift (§17.10).

**As built for milestone S2** (2026-10-25): every role of the first train's staff plays (the technicians, the
maintenance supervisors, the HSE officers, the contractors' supervisor and the contractors too). The Crew panel's
**PPE** part shows what the trainee wears and, for each zone they are in, what it needs and what is missing (entering a
zone says so on the screen); at a locker it puts on the role's PPE or takes an item off, and a task's `ppe` step is
"Put it on" there (else "Take me to a locker"). The app sends the zone inputs from the walker's position, four times
a second. The trainee's own unsafe acts are named in the panel and on the screen ("Unsafe act: you are …", and who
stopped their work). A role with `stop_work` sees the unsafe acts going on in its zones ("Unsafe acts in sight"); a
`stop` step, or any act there, offers "Take me to them" and, within 3 m of the person, "Stop the work". People wear the
hard hat on their head where their zone needs one and they wear it, in the hand elsewhere (A1's road variant, so a
person who has taken it off in a zone is seen without it). The debrief gains a Safety tab (every unsafe act, its end
and every stop; the trainee's own acts marked) and Your tasks (the trainee's task events), and its summary counts the
trainee's unsafe acts and the work they stopped.

## 19. Format 2 vectors

`ref/vectors/plant3d-v2.json`, made by `ref/make_plant3d_vectors.py` from `ref/plant3d.py` as format 1's:
- `valid` and `reject`: a small synthetic version 2 plant and its rule breaks (every new error code);
- `steps`: small models and staff files pinning the `hold` node, each permit transition and refusal (the automatic
  moves as levels, a shared isolation refused, the acceptor's hand-back), locks made in step 3 against this step's
  values (a start and a lock in one step), a code locked by two isolations, what a locked code refuses, skips and
  suppresses, every task step kind for an NPC and for the trainee, pre-emption and released reservations, waiting for
  a taken place, the `next` table and its ties, placement at step 0 and after a jump, rosters across midnight and day
  0, off-duty offsets, reactions (`seen` and not, duplicates skipped), unsafe acts and `stop`, `task_ack` and the
  fast-forward level, the random streams (a person added at the end changes no one else's draws), vehicles and
  boarding, jumps, and the authority and `where` refusals;
- `day`: the full content's first shift (12 clock hours from 06:00) with seed 1 and no trainee: every event, a
  snapshot every clock hour; and forks with a trainee (the operator granting a permit late, an electrician locking
  out the pump the operator then tries to start, a technician isolating a condenser pressure transmitter during a
  run, a contractor's unsafe act found by the safety walk).

The app's engine (`apps/plant3d/sim`) reproduces every vector bit for bit, format 1's and format 2's, on every
platform (CAPABILITIES.md §8).

**Added 2026-10-24 (locks at a shift change, §17.9):** `staff.runs` gains runs on the synthetic plant with the
handover steps, the `lock_left` reaction and a supervisor's `remove_locks` task (its own staff file); `steps` pins the
removal by authority while issued (the automatic move back to approved), an unlock while issued refused, and the
trainee's repair refused for `isolation`; the version 2 runs with a trainer's input carry its `instructor` event; the
first train's `day` follows its content, whose handover tasks now take over and give locks.

**Added 2026-10-23 (milestone P1b):** the unit runs pin the trainee's repair under a permit (refused before the
permit is accepted, with `authority`, and `unknown`; made with the permit accepted on a locked code; the work's `done`
then repairs nothing) beside the trainer's repair (made on a free code, not made on a locked one), and `effects`
(§15.6: a lock that trips a 2-out-of-3 vote, a refused lock, a trip that comes anyway); `reject` has `locked_write`;
the forks add the trainee's repair of CW pump B under its permit and the condenser pressure transmitters' warning (the
second transmitter's lock trips the steam turbine, the first's doesn't).

**Added for milestone S2** (2026-10-25, §17.11): `staff.runs` gains five runs on the synthetic plant's safety staff
(their own staff file and model, a run's `files`): PPE put on at lockers, the safety walks (slots by weekday), a
contractor without PPE starting before the permit seen and stopped twice, the contractors' hosted permit and a
shortcut stopped, the not-seen reaction, a stop from free mode; seed 3; the trainee as the HSE officer (PPE and zone
inputs, the stop input, refusals); the trainee's own unsafe act stopped and put right (refusals, inputs ignored);
a Tuesday. `staff.reject` gains the zones', PPE steps', stop steps', put_right's and weekday slots' rule breaks. The
first train's `day` follows its S2 content (seed 8: two contractors' shortcuts found by the HSE walks), with forks for
the calibration of a drift, a limit switch's corrective job, and the trainee as an I&C technician, an HSE officer and a
contractor taking the shortcut. Snapshots with staff carry `worn` and `acts`.

**As built for milestone P1** (2026-10-22: permits, isolations and the `hold` node, no staff): the file holds `valid`,
`reject` (the version rules, the `hold` node, isolations and works: every rule of §15 the validator checks), `steps`
(three unit runs in free mode: a permit's life with every action, refusal and automatic move, locks against this
step's values, what a locked code refuses, skips and suppresses; a code locked by two isolations, a cancel with
points still locked, a work without an isolation; an isolated transmitter's held reading, suppressed alarm and
tripped vote, and the `hold` node's step 0) and `train`: forks from the first train's cold start (its inputs, to rebuild
the base, and no snapshots) that lock out CW pump B, start a pump and lock it in one step, lock out the standby CCW
pump (its auto-start skipped), isolate condenser pressure transmitters 2 and 3, and service a cooling tower fan, each
with its expectations (`refused`, `lock_refused`, `permits`, `repaired`, alarms raised and not, values at the end).
Format 1's file keeps its synthetic parts byte for byte; its `train` and `hot` runs follow the first train's content,
now version 2: the same inputs and events, every format 1 value the same at every snapshot, with the new values and
the snapshot keys `permits`, `ptw` and `locked` added. S1 adds the staff's `steps` and `day`.

**Added for milestone MP1** (2026-10-26, §17.13, §17.14): `staff.runs` gains three session runs (`"session": true`,
inputs with their slot last): two players from step 1 with the claims refused in that step, inputs without a valid
slot, a player's inputs naming another slot's person and a version 1 op refused, a free slot's ops in the commit's
order (two in one step, either way round) and its stop refused, each slot's new tasks counted for it and fast-forward
held by one; three players with a release while walking between places (put back at the place left), a reclaim while
walking a way as an NPC, a release while working, a claim of a person asleep in a work step, a release of an empty
slot and a claim of another slot's person refused; the scenario's trainee as slot 0 with jumps refused by either
slot's new tasks and then accepted, a release and a reclaim. `day` gains a session fork (`session_cw_alarm`: the CW
field operator released while walking to the alarm and taken back by another slot). Every staff run, the day and every
fork carry `digests`: the state digest (§17.14) of step 0 and of every 50th step.

**Added for milestone S3** (2026-10-26, §17.12): `staff.runs` gains two runs on the synthetic plant with reactions by
area (an alarm reaction of area a1's given, one of area a2's never, the trip's call limited to a2 not made) and
findings (each reading of the stopped pump's gauge out of its range given to the supervisor, the code read their
`"$"`; a `"*"` finding given once while its task lasts; the trainee's reading typed right a finding, a misread one
not); `staff.reject` gains `areas` and `finding`'s rule breaks and the gas test's (a confined-space work's task
without one, a hot work's after its first work step). `day` follows the S3 content, and its forks may name their own
`scenario` (default the day's): on `shift_wtp`, the WTP's day without a trainee (the backwash ordered and run, the
chemist's finding, the regeneration), the trainee as the WTP operator (the backwash) and as the shift chemist (the
silica logged, the NPC operator regenerating); on `shift_cold`, the train's call for demineralised water (the tank's
drain left open), a cartridge change under a permit, an RO trip's reset and flush, RO A's cleaning in place, a mixed
bed's internals as a confined-space job (its gas test), RO B's ORP analyser calibrated after a drift.

**As built for milestone S1** (2026-10-23, §17.8): `staff` holds a synthetic version 2 plant with a clock at
`day_scale` 60 and staff (`files`, `counts`): two crews of operators on a rotation, a shift supervisor, an electrical
authorised person and two technicians on days, on a walking network with two equal routes (the tie rule) and a stair;
`reject`: its rule breaks (every staff error code of §14, the S2 and S4 keys refused); `runs`: seven runs, each with
its scenario (and staff file when it differs), its inputs, every event and a snapshot every `every` steps: a shift
change and a morning without a trainee (rounds, readings, a choice, an instruction over the radio, a trip, the alarm
answered and checked locally, a value reaction, two permits run between NPCs, locks by their roles, a technicians'
toolbox meeting, a taken seat waited for); the same with another seed; a person added at the end; the trainee as a
field operator (the role input, rounds walked and read, a misreading, calls answered); the trainee as control room
operator (the radio instruction, every refusal of §17.1, free radio calls); placement at 10:30 and jumps (refused
while a task waits for `task_ack` and while a permit is open; accepted; two in a step); an absent operator and a
call with nobody on duty. The first train's `day` comes with its staff content.
