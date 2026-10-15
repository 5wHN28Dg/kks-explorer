# Walkdown Plant content format, format 1

**Status: DRAFT 2026-10-15**, written before any app code (decision record 0054). It is frozen like the courses
(COURSES.md) once the first train's content (docs/plant3d/FIRST-TRAIN.md) loads and passes the vectors; after that a
change needs `"version": 2` and a new vector file. Requirements: https://github.com/5wHN28Dg/kks-explorer/wiki/3D-plant
(R1–R10). Engine: decision 0041.

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
- **Limits** (the build refuses the file above them): file size 16 MiB; per area 4,000 equipment items, 2,000 pipes,
  2,000 structures; per pipe 256 points; per model 4,000 values, 500 alarms, 64 machines; per procedure 200 steps.

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
  colour-blind eyes, and checked on every tier (the "look" rule).
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

- **The route** is `from`, then `points`, then `to`: a polyline through the centre of the pipe. `from` and `to` are
  nozzles or free points (`{"at": [x, y, z]}`, a pipe ending in the ground or in a header).
- **Bends** are made at every corner with a radius of 1.5 × the outside diameter (`bend` may say `3d` or `5d`).
  A corner that can't fit its bend between its neighbours is invalid (the content is wrong, not the drawing).
- **`dn`:** nominal size; the outside diameter comes from the DN table (EN 10220 / ASME B36.10 sizes in the kit), or
  from `od_mm`. **`insulation_mm`:** 0 for bare pipe; insulated pipe is drawn with metal cladding.
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
hall is `30UMA10`; a stair is just a stair), but every walkable one has an `id`.

```json
{"id": "st_floor_12", "part": "platform", "at": [10, -20, 12],
 "params": {"outline": [[0, 0], [70, 0], [70, 40], [0, 40]], "deck": "concrete", "edge": "handrail",
            "openings": [[[28, 14], [46, 26]]]}}
{"id": "st_stair_w", "part": "stair", "params": {"foot": [3, 12, 0], "top": [9.5, 16, 12], "layout": "switchback",
 "width": 1.2}}
{"id": "hrsg1_ladder_3", "part": "ladder", "params": {"foot": [96, 53, 30], "top": 34, "facing": 0}}
{"id": "st_door_w", "part": "door", "at": [0, 0, 0], "yaw": 270, "params": {"kind": "personnel", "width": 1.0}}
```

- **Walkable:** `platform`, `stair`, `ladder`, `floor` (inside a building), `road`, `grating`. The build makes the
  collision shapes from them; nothing else is walkable.
- **Stairs** go from `foot` to `top`; `layout` `straight` or `switchback` (flights folded inside the plan rectangle
  that foot and top span, as in a stair tower: the example rises 12 m in four flights within 6.5 × 4 m). Stairs keep
  the rise of every step between 0.15 and 0.20 m and the going at least 0.25 m; a flight that would
  rise more than 3.6 m gets a landing. **Ladders** above 3 m get a cage and, above 10 m, a rest platform. These are
  the common rules for fixed access to machinery (EN ISO 14122-3 and -4; the kit applies them, content doesn't
  repeat them). A stair or ladder whose ends don't meet a walkable surface, or whose flights don't fit, is an error. (The ladder
  example stands on the HRSG's +30 m platform and reaches the drum platform at +34 m, so it gets a cage.)
- **Doors** open when the trainee walks into them or presses them; `kind` is `personnel`, `double` or `roller`.
- **Buildings** (`building`) are a shell: outline, height, roof, wall cladding, and openings for doors, louvres and
  pipes. Inside a building the walls are drawn from inside too.

**Signs** are labels in the world: `{"text": "CW pump house", "at": [152, -16, 4], "yaw": 180, "size": 0.3}`.
Area and system signs help a trainee find the way (R9a): they are drawn on every tier.

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
| `walkdown://course/<course>` and `…/<course>/<page>` | Walkdown's course renderer at that course or page |

- **Codes in links** are read leniently, the plant's own codes strictly: a link's code (`[0-9A-Z]{4,24}`, as in
  courses) is cut to its longest beginning that matches the grammar, then matched; if that ends in an A3 letter and
  is not found, it is tried again without it (a component-level `30PAC10AP001KP01` becomes `30PAC10AP001K`, then
  `30PAC10AP001`). Anything else (another path, a malformed code, an unknown ID) opens the app at its start with a short
  message; links never carry anything but these paths.
- **A code the plant doesn't have** (for example a real plant's code from Walkdown's drawings) shows the plant's
  equipment of the same kind instead, labelled as such: same system letters and equipment letters (`LAC` + `AP`:
  "a feedwater pump in this plant: 10LAC10AP001"), else the same equipment letters, else the code's decoding only,
  with letters the plant's tables don't have shown as "not in this plant's key". The code is not stored or sent
  anywhere: Walkdown Plant has no network access (0054).
- **A link out with nothing to open it** (Walkdown not installed): the app says so instead of failing silently.

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

Names are unique across the plant (area models are joined in `plant.json` order; a value may read values of areas
listed before its own, and `ext` values named in `plant.json` cross the other way, §7.7). Each value may carry
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
| `{"ramp": ref, "rate": r, "rate_down": r2, "init": n}` | moves toward the input at most r units per second |
| `{"integrate": ref, "gain": g, "min": a, "max": b, "init": n}` | y ← clamp(y + g · input · dt, a, b): levels, inventories |
| `{"latch": set, "reset": reset, "init": 0}` | 1 from the first step `set` is true until `reset` is true (reset wins) |
| `{"delay": ref, "on": t, "off": t2}` | counts the consecutive steps in which it read its input true (the first counts 1); true when the count reaches t / 0.1 (on = 2 s: at the 20th such step); likewise false after t2 / 0.1 steps of reading false; `off` default 0 |
| `{"timer": ref}` | 0.1 × the number of consecutive steps in which it read its input true, this one included (0 when it reads false) |
| `{"wrap": ref, "period": p}` | x = y + input · dt, then y = x − p · floor(x / p) (so 0 ≤ y < p also for negative input): synchroscope phase angle, turning-gear rotor angle |

A *ref* is a number or a value name. A **stateless** node reads earlier values only, as this step computed them.
A **stateful** node (`lag`, `ramp`, `integrate`, `latch`, `delay`, `timer`, `wrap`) reads **every** reference as the
previous step left it, earlier or later in the list: that is how loops (level → pump trip → level) close without an
order problem, and it makes the two readings of "earlier" the same.

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
  from the trainee in `range`), `reset`, `acknowledge`, or a machine command (§7.4).
- **`set`:** the states it writes. A valve's `state` is its **command**; its position is a `ramp` of the command at
  the valve's travel rate (a 2 m butterfly valve takes a minute: the trainee sees and hears it move).
- **`needs`:** the **permissives**, each a value and the sentence shown when it is false. An operation whose
  permissives are not all true is refused, and the trainee sees which ones failed, in order: knowing *why* a pump
  won't start is the lesson.
- **`where`:** where the operation is offered: `local` (at the equipment), `screen` (the control room).

### 7.3 Interlocks

An interlock is an operation the plant does by itself: `{"id": id, "when": ref, "do": [Op, …]}`, done in the step
where `when` is true and was false in the previous step (a rising edge; on the first step "previous" is false) (a CW pump stops → its discharge valve closes; condenser pressure high → the turbine bypass is
blocked). They use the same op shape, without `needs` and `where`, and appear in the event list (§7.6) as
"automatic".

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
  A command in another state is refused like a failed permissive.
- **`set`:** states written on entering. **`next`:** `[condition, state]`, the first true one moves on (at most one
  move per step). **`watch`** (default true): fast-forward stops while the machine is in this state (§7.9).
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
latches (§7.1) until the op `{"do": "reset", "trip": id}` is made while its cause has cleared; `first_out` groups trips so that the panel
shows which of them came first, as real first-out annunciators do. Trips that fire in the same step are ordered as
they are listed in the model (plant.json's area order, then file order): the first one listed is "first out".

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
- States per alarm, as the common alarm-management model (ISA-18.2) describes them: normal → active unacknowledged
  (flashing, horn) → active acknowledged (steady) → cleared unacknowledged → normal; and **shelved**: set aside for
  a while by the operator (a nuisance alarm, an instrument under repair), shown in a list of its own, no horn, until
  un-shelved or its shelving time ends. The trainee acknowledges at the panel; the
  horn stops on acknowledge.
- **`priority`** 1 (high) – 3 (low) sets the colour and sound; **`clear`** gives a deadband so an alarm doesn't
  chatter; **`delay`** the seconds the condition must hold.
- **`where`:** the equipment the alarm leads to (one tap from the alarm list highlights and walks there: R10).
- **Events:** every operation, interlock, machine step, trip and alarm change goes into an event list with model
  time; procedures (§8) and the debrief read it.

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
- **`sound`:** a sound of the library (§11) on the part, its gain and pitch tables of values. **`lamp`:** a lamp
  or beacon lit when the value is true.
- **`shake`:** camera shake near the part from a vibration value (felt near a large machine; off when the platform
  asks for reduced motion).
- `ext` values (plant.json, §2) are values without a node: the scenario sets them, and any area may read them.

### 7.8 Scenarios

```json
{"format": "walkdown-plant-scenario", "version": 1, "id": "cold_iron", "title": "Cold start after a long outage",
 "init": {"ambient_t": 35, "ambient_wb": 25, "hrsg1_hp_drum_level": -150, …},
 "latched": ["gt1_trip_lube", "st_trip_lube", "st_trip_cond_p"],
 "faults": [{"id": "cw_b_fails", "when": {"cmp": ["cw_b_start_count", ">=", 1]},
             "set": {"cw_b_motor_fault": 1}, "text": "Pump B trips on overcurrent at its first start"}]}
```

`init` overrides any value's initial value and sets the `ext` values; `latched` names trips (by
their `id`) that start latched, as they stand in a stopped plant; `faults` are set by a condition, so a trainer can make "the standby pump fails"
happen at the moment that teaches most.

### 7.9 Time

Model time runs at 1× while anything is changing that the trainee should watch. A **fast-forward** (up to 60×) is
offered while no alarm is unacknowledged, no priority 1 alarm is active, and no machine is in a state with
`"watch": true`; it stops by itself when
one appears. Fast-forward runs more 0.1 s steps per frame (600 per second at 60×); the step never grows. Its cost on
the Note 9 is measured (0054) and the top speed is capped by what the phone keeps within the frame rule.

### 7.10 One step

Each 0.1 s step, in this order (the reference and the app must agree to the vectors):
1. The trainee's operations queued since the last step, in the order made: each is refused if a permissive in
   `needs` is false (read as the previous step left it), else its `set` is applied. Machine commands likewise.
2. `values` are evaluated in order (stateful nodes read the previous step's values where §7.1 allows).
3. Faults whose condition is true are applied (their `set`), once each.
4. Interlocks on a rising edge of `when`, in list order; their `set` is applied.
5. Machines: each moves at most once, by its first true `next`; the new state's `set` is applied.
6. Trips: a trip whose `when` has held for its `delay` latches; its `do` is applied; first-out as in §7.5.
7. Alarms change state (with their `delay` and `clear`).
8. Events of this step are written in the order above.

Every condition in steps 3–7 (`when`, `next`, permissive-like checks) reads the values as step 2 left them, not
as an earlier part of steps 3–6 changed them; states changed in steps 3–6 are read by `values` in the next step. A cold start that takes hours in a real plant takes about 40 minutes of play (FIRST-TRAIN.md §4).

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
- **`do`:** the operations expected (§7.2), in any order unless `"ordered": true`. **`done`:** the value that ends
  the step; without it the step ends when the trainee presses Next.
- **A tour** is the same file with `"kind": "tour"` and steps without `do` or `done`: a guided walk along a system's
  path (R7), each step a stop with text and `at`.
- **Procedure mode** checks the trainee: the event list (§7.6) shows an operation outside the expected step as a
  deviation (not refused: the plant reacts as it would). **Free mode** has no procedure.

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

| Group | Parts and their main parameters |
|---|---|
| Machines | `gas_turbine` (rating_mw, length, casing_d, intake: side/top, exhaust: axial); `generator` (rating_mva, length, d, cooling: air/hydrogen); `steam_turbine` (casings: list of {kind: hp/ip/ip_lp/lp, length, d}, exhaust: down/axial); `sfc` (static frequency converter cabinet row); `turning_gear` |
| HRSG | `hrsg` (length, width, height, modules, drums: list of {kks, d, length, elevation}, inlet_duct, outlet_duct); `drum` (d, length, saddles); `stack` (d, height, platforms, damper); `duct` (route, width, height, expansion joints) |
| Rotating | `pump_horizontal` (flow_m3h, head_m, motor_kw → frame size, baseplate, coupling guard); `pump_vertical` (flow_m3h, head_m, motor_kw, pit_depth: can or wet pit); `fan_axial` (d, blades, motor_kw, stack_height); `compressor_skid`; `vacuum_pump_skid` (kind: liquid_ring) |
| Heat exchange | `condenser` (shell length, width, height, waterboxes: 2 or 4, passes, hotwell); `shell_tube_hx` (d, length, horizontal/vertical); `plate_hx` (plates, frame); `cooling_tower` (cells_x, cells_y, cell_size, height, fan_d, basin_depth, fill: film/splash) |
| Vessels | `tank_vertical` (d, height, roof: cone/dome/open); `vessel_horizontal` (d, length, saddles) |
| Valves | `valve_gate`, `valve_globe`, `valve_butterfly`, `valve_ball`, `valve_check`, `valve_control`, `valve_safety` (dn, rating, actuator: manual/gear/electric/pneumatic/hydraulic, handwheel side); `damper` (width, height, blades) |
| Instruments | `pressure_gauge` (range, unit, dial_d), `pressure_transmitter`, `temperature_element`, `temperature_gauge`, `level_glass` (range), `level_transmitter`, `flow_element` (kind: orifice/venturi), `position_switch`, `vibration_probe`, `local_panel` (cabinet with displays), `push_button_station` (buttons: start/stop/emergency) |
| Electrical | `transformer` (mva, kind: gsu/aux, radiators, bushings), `switchgear_row` (panels, depth), `cabinet`, `junction_box`, `cable_tray` (route, width), `motor` (kw, frame; when a driver isn't part of its machine) |
| Pipes | `pipe` (§4), made of `elbow`, `tee`, `reducer`, `flange` pieces; `pipe_support` (kind: shoe/guide/anchor/hanger, from the span table); `pipe_rack` (bays, span, tiers, width) |
| Structures | `building`, `floor`, `platform`, `stair`, `ladder`, `handrail`, `door`, `column`, `beam`, `grating`, `road`, `trench`, `fence`, `slab`, `pit` |
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

- **`loop`** and **`once`** are recorded clips (Ogg Vorbis), each with its licence and source; the about list (0054)
  is generated from these entries.
- **`synth`** sounds are made from tones and filtered noise by the content tools at build time, as short seamless
  loops (one per layer: the tone, the broadband noise), and the app sets each layer's pitch and gain from values: a
  turbine's blade-pass tone rises with its speed, which no recording of one speed can do. Making the samples at run
  time (Godot's AudioStreamGenerator) is meant for C# or native code, not script (0054), and costs the phone CPU for
  nothing a pitched loop can't do.
- The sound library and what each machine sounds like: FIRST-TRAIN.md §6.

## 12. Validation and vectors

The build refuses the whole plant when any rule above is broken and names the file, the item (its code or ID) and the
rule. Error codes follow COURSES.md §10 (`bad_type`, `missing_key`, `unknown_key`, `bad_kind`, `bad_id`, `dup_id`,
`bad_ref`, `forward_ref`, `bad_table`, `limit`, …) plus `bad_kks` (grammar or not in the tables), `bad_route` (a bend
that doesn't fit, a pipe that doesn't reach its nozzle), `unsupported` (a pipe span with nothing below),
`not_walkable` (a stair or ladder whose end meets no walkable surface), `outside_area`.

Vectors (`ref/vectors/plant3d-v1.json`, made by the reference `ref/plant3d.py`, as for the courses):
- **`valid`** and **`reject`** descriptions, each reject breaking one rule;
- **`steps`:** a model, a list of events (operations, model steps of 0.1 s, fast-forward) and the expected values,
  alarms, trips and machine states after each, compared to 1e-6. They pin the lag, ramp, integrate, latch, delay
  and timer nodes, the permissive refusals, interlock edges, first-out and alarm states.

## 13. Not in format 1 (deliberately)

- No scripting or expressions in content (as in courses: content must not run code).
- No component level (level 3) KKS codes; no RDS-PP codes.
- No real process simulation: no flow network solving, no steam tables beyond sampled tables.
- No choice of condensing end (R3: air-cooled condenser, wet cooling tower, once-through). Format 1 describes the
  wet cooling tower only; version 2 adds alternative areas for one slot (`"slot": "cooling"`), one picked per
  scenario, when the second cooling end is built.
- No content loaded from outside the app (no downloads, no user content) while the engine's security response is a
  known weak point (0041).
