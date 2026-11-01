# Walkdown Plant: the realism programme

**Status: DRAFT 2026-11-01**, written before any code. Decision: 0073. Milestones: MILESTONES.md, "Realism".
Format: docs/PLANT3D.md format 2 (§14–§21), with the additions of §2 below. The Workshop (docs/plant3d/WORKSHOP.md,
decision 0072) is built first; this programme builds on its component trees and bench models. Everything here is
generic and invented (R1): no plant's procedures, data, drawings or organisation. Where a real practice is
followed, the public source is named (§14).

**The user's decision (2026-11-01).** The user asked how closely the roles the trainee plays resemble the real job,
and chose to add all of the following:
- **Hands-on work and tools** (§3): step-by-step jobs with the right tool, opening covers, disconnecting wires,
  connecting a HART communicator, reading a clamp meter or multimeter, valves, cutting and terminating wires,
  configuring a device, taking a sensor, transmitter or valve apart to find why it fails, doing heavy work yourself or
  ordering technicians to; troubleshooting where the cause is hidden; commissioning and decommissioning.
- **Ageing and breakdowns** (§4): wear over time, failures on their own, deterministic from a seed, with early signs
  for whoever looks.
- **Weather** (§5): rain, sandstorms, heat waves, rare cold, seen and heard, and acting on each part of the plant.
- **Documents and discussions** (§6): generic P&IDs and equipment manuals inside the app; two engineers who differ on
  how to do a job talk it through, and the trainee can take part.
- **Work management** (§7): work orders and job history, spare parts and the stores, shift handover and logbooks,
  planning a major outage.
- **HSE in depth** (§8): job safety analyses and toolbox talks, confined space entry, hot work, work at height,
  near-miss and incident reports, drills, heat stress.
- **Electrical and mechanical crafts and condition monitoring** (§9).
- **Engineering and compliance** (§10): root-cause analysis, management of change with drawing updates, alarm
  management, emissions reporting, the chemistry lab.

**The rule (R6, as the Workshop states it).** Fake the physics; never fake what the trainee learns from. Free to fake:
how a value is computed (tables, lags, sampled curves made by the content tools), particle rain, the look of dust.
Never faked: which tool fits, the order a job is done in, what a reading means and where it is taken, which way an
effect goes and roughly how much, what a mistake does, what a rule requires and why. Every procedure, failure mode and
limit comes from a public source (standards, manufacturers' published manuals, textbooks, regulators' guidance), cited
here or in the content's own `source` field. Nothing comes from a real plant: the repository is public.

**Reference photos.** The user's photos of a plant in service are private: never committed, cropped or turned into
textures. They were looked at only to judge what is typical (handheld field communicators, bench wiring with
ferrules, colour-coded wire and heat shrink, marshalling cabinets with terminal rows and power supplies, printed
drawings read at the cabinet, fine dust on every flat surface). Nothing of that plant is in this file.

## 1. The pieces, at a glance

| Area | What the trainee does | Built on | New in the engine (both engines, bit for bit) | New elsewhere |
|---|---|---|---|---|
| Hands-on (§3) | jobs step by step with tools and meters, in place at the equipment | the Workshop's component trees, assembly order and bench models (K1a–K3); works and permits (§15); tasks (§16.6) | carried tools, `hand` actions, meter readings, hidden causes | the work view at the equipment; tool catalogue |
| Ageing (§4) | finds early signs, plans the repair, or meets the failure | faults (§7.8), works, readings, bindings | `wear` and `draw` nodes; world streams | trends on the screens |
| Weather (§5) | works in it, sees its effects on the plant | `ext` values (§2 of PLANT3D), zones, reactions | the weather step, clock values | sky, fog, particles, wet and dusty surfaces, sounds |
| Documents (§6) | reads P&IDs and manuals; takes part in discussions | the content (areas, models), the Workshop's trees, `meet` | the `discuss` step | P&ID generator and viewer; manual and discussion formats |
| Work management (§7) | raises, plans and closes work orders; draws spares; hands over; plans an outage | works, staff, the clock | stock, deliveries, logbook entries, scheduled works | the work order panel |
| HSE (§8) | JSAs, toolbox talks, confined space, hot work, height, reports, drills, heat | permits, zones, PPE, unsafe acts, `muster` places | JSA input, entrants, standby and fire watch, heat rules | forms |
| Crafts (§9) | switching, racking, megger, relay tests, batteries; alignment, balancing, bearings, seals, lubrication, packing; vibration, thermography, oil | hands-on, wear, model content | `switch_effects` query | spectrum and thermal views |
| Engineering (§10) | root cause, management of change, alarm rationalisation, emissions, cycle chemistry | event log, first-out, S3's lab | change objects; alarm priority from a value | analysis tools in the debrief |

**What stays out of the engine.** Anything that changes the plant, a person or what another player sees is in the
engine (it has to be the same on every player of a session and in the reference, MULTIPLAYER.md §3). Pure views
(a spectrum drawn from model values, a drawing, the RCA board after the run) are the app's and are pinned by app
tests, not vectors.

## 2. Common engine pieces (format 2 additions)

Format 1 is frozen. These are additions to format 2, as LIFTS (§20) and S4 (§21) were: new optional keys. A plant
without them steps exactly as before; `plant3d-v1.json` and `plant3d-v2.json` keep every item byte for byte (a test
compares them with the committed files). The new behaviour gets its own vector file,
**`ref/vectors/plant3d-realism.json`**, made by `ref/make_plant3d_vectors.py` from `ref/plant3d.py` and
`ref/plant3d_staff.py`, and reproduced by `apps/plant3d/sim` bit for bit on Linux, Windows and the Note 9 (§13).

### 2.1 The world seed and its streams

- A version 2 scenario gains `"world": {"seed": n, "weather": W, "age": A}` (all optional; `seed` a whole number 0 to
  2³² − 1, default the staff seed, else 1).
- Draws use §17.5's generator (mix32, xorshift32, 24-bit `r`) with streams of their own, so nothing here changes a
  person's draws and a day without realism keys is unchanged. Stream of purpose tag P and index k: s =
  mix32(mix32(seed ^ P) ^ mul32(k + 1, 0x9e3779b9)), 1 if that is 0. Tags: weather `0x57454154`, draw nodes
  `0x44524157`, causes `0x43415553`, stores `0x53544f52`, lab `0x4c414253`. Indices are model order (the nth node of
  its kind, the nth fault), so an item added at the end of a file changes no other item's draws.
- **Engine-kept clock values** (with staff or a `world`): `world_hour` (time of day in hours, (C mod 864,000) / 36,000
  in doubles, C the clock in tenths, §16.1) and `world_day` (C div 864,000). Read by any node, as a machine's state is.
  They let content make diurnal tables, hourly averages and day counters without a clock in content.

### 2.2 Two new nodes

- **`{"draw": table, "init": n}`** (stateful constant): at step 0 takes table(u), u = r / 2²⁴ from its own draw
  stream, unless the scenario's `init` gives it. The table is an inverse distribution made by the content tools (a
  bearing's life spread, a transmitter's drift direction, a weak battery cell). It never changes during the run.
- **`{"wear": rate, "reset": ref, "max": b, "init": n}`** (stateful): y ← 0 when `reset` reads true, else min(b, y +
  max(0, rate) × 0.1), both read as the previous step left them. A work's `set` writes a `<item>_renew` state to 1; an
  interlock on its rising edge writes it back to 0 (the content tool makes both), so a renewal resets the wear for one
  step. A scenario's `init` overrides the start (§4.3: the plant's age).

### 2.3 Tools carried

- **`data/plant3d/tools.json`** (format `walkdown-plant-tools`): each tool's `id`, `title`, `kind` (`spanner`,
  `socket`, `screwdriver`, `hex_key`, `pliers`, `stripper`, `crimper`, `meter`, `communicator`, `test_set`, `lifting`,
  `ppe_gas` …), `size` where it has one (17 mm, PZ2, 5 mm), what it reads (`meter` and `communicator`: its modes) and
  where it is kept (places of kind `store`, or a new kind `toolbox` in workshops and vans). Limits: 200 tools.
- **Input** `[n, "tool", item, 0 | 1, person]` at a place that keeps it (taking and putting back), refused away from
  one (`where`), and a step kind `{"tool": [items] | "off"}` for NPCs, as `ppe` (§16.6). A person carries at most 12;
  the snapshot gains `carried`.

### 2.4 Hand actions

- A model gains **`hands`**: `{"kks", "action", "component", "tools": [ids], "wrong": {tool id: sentence},
  "needs": [[value, sentence], …], "set": {...}, "work": true | false, "minutes": m}`. `action` is an identifier
  (`open_cover`, `loosen_gland`, `lift_wire_1`, `connect_hart`, `crack_vent`, `fit_spare` …), `component` a name in
  the part kind's Workshop component tree (WORKSHOP.md), `tools` the tools that do it (any one), `wrong` the sentence
  for a tool a technician might try (a 13 mm spanner on a 17 mm nut, a flat screwdriver on a Pozidriv screw, an
  uninsulated screwdriver on a live terminal), `needs` the permissives in order (the assembly order: "the terminal
  cover is off first"; safety: "the loop is not proved dead"), `set` the component states it writes, `minutes` the
  clock minutes it takes (the person stays, as a `work` step), and `work: true` (the default) when it needs an
  accepted permit of a work on that code.
- **Input** `[n, "hand", kks, action, tool, person]`, handled in step 1. Event `[n, "hand", kks, action, tool,
  person, "done" | "refused" | "unknown", [reasons]]`; reasons in order: `authority` (the person is not the acceptor of
  an accepted permit for a work on that code, or another with `accept` and the discipline while the acceptor is off
  duty, as §15.5; or lacks `operate_local` for a `work: false` action), `tool` (the tool named isn't carried),
  `wrong_tool` (the tool doesn't do it: its sentence is shown), then the failed permissives. Done, its `set` is
  written at once (a locked code's writes follow §15.1: component states carry no `kks` of a lock point, commands
  are never in a hand action's `set`, validator `locked_write`).
- **Made by the content tool from the Workshop's data:** the component tree, fasteners and their sizes, the assembly
  order and its refusal sentences (WORKSHOP.md, K2) become hand actions for each piece of equipment a job names, with
  states named `<equipment prefix>_<component>_<state>`. The Workshop's sentences are the same sentences: one source.
  The validator refuses a hand action whose component the part kind's tree lacks (`bad_ref`).
- **What a hand action does to the plant** is ordinary model content: a lifted wire opens the loop, so the
  transmitter's current falls to 0, the control system marks the value bad and alarms (`bad_quality`). Cause and
  effect stay in the model, as the Workshop's rule says.
- **Limits:** the model limit of 4,000 values (§1) rises to 8,000 in a version 2 model with `hands`; at most 2,000
  hand actions. Component states exist only for equipment a job names (a transmitter about 15, a pump about 40).

### 2.5 Readings through a tool

- A model gains **`meters`**: `{"id", "kks", "point", "tool_kind", "mode", "value", "needs": [...], "else": value or
  number}`. `point` is where the probes or the clamp go (`terminals_sig`, `test_terminals`, `cable_l1`,
  `cable_both`, `junction_tb3_5`), `mode` the meter's mode (`mA_dc`, `V_dc`, `ohm`, `A_ac_clamp`, `hart`), `value` what
  it shows, `else` what it shows when a permissive fails (0 for a clamp round both conductors of a circuit, `OL` as
  `1e99` for an open ohm reading). Wrong uses are meters too, so their readings are right by construction.
- **Input** `[n, "read", code, value, meter]` (the S1 `read` with the meter named): `misread` beyond the step's
  `tol` against the meter's shown value as the previous step left it. Task step `{"read": code, "via": meter}`.
- **The HART communicator** is a meter of mode `hart` with several values (PV, loop current, range, damping, units,
  device status) and its own ops: a version 2 op gains `where` `hart`, offered only to a person carrying a
  communicator whose `connect_hart` hand state is true. Configuration ops (range, damping, units, loop test, trim)
  are `set` ops with `where: ["hart"]` and their permissives (write protect off; the loop in manual at the control
  room for a loop test).

### 2.6 Hidden causes

- A scenario fault gains **`causes`**: `[{"id", "weight", "set", "repair", "text"}]`. When the fault is applied
  (step 3) one cause is chosen with the causes stream (k = the fault's index), `weight`s as `choose`'s (§17.5), and its
  `set` written. Event `[n, "cause", fault, cause]` after the fault's, which the app hides until the debrief.
- A work's **`cures`** (with `repairs`): the causes it puts right. Its `done` repairs the fault only when the applied
  cause is among them; otherwise the work is done (a new transmitter fitted) and the fault stays, as on site. With
  `causes`, §15.2's "at most one work repairs a given fault" becomes "at most one work per fault and cause".
- The instructor's panel may pick the cause (`[n, "fault", id, cause]`, with its `instructor` event).

### 2.7 Step order and the digest

- Step 1 handles `tool` and `hand` inputs where they come, as ops. After step 1's inputs, a new **step 1w** runs the
  weather (§5.1). Steps 2–9 are unchanged; step 3 draws causes when a fault with `causes` is applied.
- The state digest (§17.14) gains, in this order after the staff: the weather (kind, hour of its last change, its
  stream, each `ext` lag's value), the draw nodes' values (they are values: already covered), `carried`, stock and
  deliveries (§7), logbook count, entrants (§8), change objects (§10), each applied fault's cause.

### 2.8 What stays as it is

Permits, isolations, locks, the staff step, lifts and multiplayer's lockstep are not changed. Everything here acts
through inputs and values the existing step reads, so a session needs no new message kind: the new inputs travel in
commits like any other (MULTIPLAYER.md §3.1).

## 3. Hands-on work and tools

### 3.1 What the trainee does

A job starts from a work order (§7) and a permit (§15) and is done at the equipment. Example, the condenser pressure
transmitter reads low against its two partners (an I&C technician's day):
1. Read the work order, the transmitter's manual (§6.2: its troubleshooting table) and the P&ID (§6.1: the
   transmitter, its manifold and its junction box). Do the JSA (§8.1).
2. Take the tools from the I&C workshop's toolbox: a screwdriver set, the HART communicator, a multimeter, a 17 mm
   spanner for the manifold; the permit is issued and accepted; the transmitter is isolated (its root valve and the
   manifold, kind `instrument`), and the control room has put the loop in manual.
3. At the transmitter: the **work view** (§3.3) shows it close up, the components of its Workshop tree. Unscrew the
   terminal-side cover (the housing's cover lock first), see the terminal block.
4. Connect the communicator across the loop (the signal terminals or the test terminals) and read PV, loop current and
   status. Connecting it with less than 250 Ω in the loop is refused by the device's silence, not by a sentence: the
   communicator says "no device found", and the manual's page says why (§14 [HART], [R3051]).
5. Measure the loop current with the multimeter at the test terminals (in series without lifting a wire), or with a mA
   clamp round one signal wire. Clamping both wires reads 0: a lesson, from `meters`' `else`.
6. Find the cause (hidden, §2.6): a blocked impulse line, a passing equalising valve on the manifold, drift of the
   sensor, water in the junction box, a loose terminal. Each test's result follows the hidden cause: venting the
   impulse line, closing the equalising valve, a two-point check with a hand pump against a reference gauge, the
   insulation of the cable, a pull on each terminal.
7. Put it right (a new seal on the junction box's gland, the manifold's valve, a trim through the communicator, or a
   new transmitter from the stores, §7.2, configured with the old one's range), close up in the reverse order, and do
   a loop check with the control room operator (on the radio: 4, 8, 12, 16, 20 mA seen on the screen).
8. Hand back the permit; the debrief shows the path: the tests made, the parts used, the time, and whether a part was
   changed that didn't need changing.

The same pattern covers: opening and closing valves (manual valves' handwheels, already local ops), cutting and
terminating wires (strip length, ferrule, crimp, torque: hand actions with their tools; a ferrule left off makes a
loose-terminal cause possible later, §4), taking a valve's actuator off, a positioner's calibration, and taking a
failed part apart at the workshop bench (the Workshop mode itself, opened on the removed part, shows why it failed:
§3.5).

**Heavy work, or ordering it.** A supervisor or engineer may do a job themselves or give it to technicians
(`call`, §16.6): the NPCs then do the same hand actions (their task steps name them), drawn with A1's work animations
at the equipment, and the trainee can watch, check quality points (the task's `say` at a hold point, the trainee's
`pick` to accept or send back) and sign off.

### 3.2 Troubleshooting

- A fault with `causes` (§2.6) is a symptom with hidden causes. The content lists, per symptom, the causes, the tests
  that tell them apart, and what each test shows under each cause (generated into `meters`, `hands` and values).
- Sources for the cause lists are manufacturers' troubleshooting tables and textbooks (§14: [R3051], [FCVH],
  [Liptak], [SKF], [API610]). Each symptom's table names its source in content.
- **The debrief's diagnosis tab**: the tests in order, which cause each ruled in or out, parts replaced, the time to
  find it.

### 3.3 The work view (the app)

- Opened by a job's step or the card's "Work on it" at the equipment, within reach and with the permit in place.
  The camera moves to a close view of the equipment; the plant stays drawn round it.
- The equipment's plant geometry is swapped for its Workshop component scene (pre-built per part kind, K1a), placed
  at the equipment's transform with its component states from the model (a cover off is off). So that one piece can
  be hidden, **equipment with jobs is built outside the merged cells** (its own instance per LOD, baked as any):
  the builder reads the list from the content. Budget §11.
- A tool tray shows what the person carries; an action is a tap on the component, then the tool (or drag the tool
  onto it). Touch, mouse, keyboard and gamepad alike. Meters and the communicator show their own screens, drawn from
  the meter's values. Refusals show their sentence beside the component.
- What changes between steps is drawn interpolated (a cover unscrewing over its `minutes`).

### 3.4 Commissioning and decommissioning

- **Commissioning** a piece of equipment (new, or after a major job): works of kind `commission` with their tasks:
  for an instrument, the loop check and the alarm and trip tests from the field (the control room confirms each); for
  a valve, the stroke test (open, close, times, limit switches); for a motor, the insulation test (§9.1), the bump
  test for rotation, the uncoupled run, then coupled. Each step reads values or makes ops that exist in the model.
  The equipment's `<code>_in_service` state is set at the end, and the screens show "not commissioned" until then.
- **Decommissioning:** isolate, drain, vent and purge (the model's drains and vents), disconnect (hand actions), tag
  "out of service", update the drawing through a change (§10.2).
- Sources: [IEC62382] for loop checks and the commissioning of electrical and instrument systems, manufacturers'
  start-up instructions ([API686] for machinery).

### 3.5 In the Workshop

- A part removed in a job can be opened in the Workshop mode (WORKSHOP.md K6's way in from the plant, but writable for
  the removed part only): its component states and the hidden cause show there (a torn diaphragm, a blocked
  impulse line's sludge, a worn seat). The Workshop's bench model runs the failed part (a transmitter with a drifted
  sensor reads 3 % high at the bench).
- The workshops' calibration bench (SITE.md) is a place for bench calibrations with a reference (the job's `read`
  steps against the reference's values).

### 3.6 Maps onto

Works and permits (§15), tasks and their steps (§16.6) with the new `tool`, `hand` and `read via`, reactions for
the NPC side, the Workshop's trees, sentences and bench models, the model's faults (§7.8) and hidden causes (§2.6).
Multiplayer: two players at one transmitter make inputs that the host orders; both see the same cover come off.

## 4. Ageing and breakdowns

### 4.1 What the trainee does

Walks a round and notices that pump B is louder and its bearing housing warmer than A's; looks at the trend on the
screen; measures the vibration (§9.3); raises a work order before it fails; or ignores it and meets the failure at
the worst time. Engineers decide when to stop the pump (a discussion, §6.3). A valve that sticks (stiction) makes
its loop hunt; a fouled filter raises its pressure drop; a transmitter drifts.

### 4.2 How it works

- **Wear items** per piece of equipment, made by the content tools: bearings, mechanical seals, packing, a valve's
  stiction, a transmitter's drift, a filter's or a heat exchanger's fouling, a cooling tower fan's gearbox, the GT
  compressor's fouling, the GT inlet filters (with dust, §5), a motor winding's insulation (with damp, §9.1), a
  battery's cells. Each: a `wear` node whose rate is a table of the duty (running, speed, load, temperature,
  lubrication state, dust), times the ext value `age_rate` (the scenario's compression, §4.3).
- **The P-F curve** ([Moubray], [ISO17359]): each item's early signs are tables of its wear, in the order they
  appear: vibration first (and its spectrum's bearing tones), then audible noise and heat, then smoke or leakage near
  the end. Signs bind as anything does: a `sound` binding's gain, a `show` on a local thermometer, a trend on the
  screen, a `shake`.
- **The failure** is an ordinary fault (§7.8) with `when` = wear ≥ its threshold, the threshold a `draw` node (§2.2):
  each item's life is drawn from the seed at step 0. The same seed fails the same pump at the same step on every
  player and in the reference. A failure may have hidden causes (§2.6: a seal leak from dry running, a bearing from
  over-greasing).
- **Repairs** by works whose `set` renews the item (`<item>_renew`, §2.2); a work that greases a bearing lowers its
  rate (a lubrication state), not its wear.
- **Spontaneous trips** of instruments and electrical parts (a power supply, a relay) with no wear sign are seeded
  hazards: a `draw` time per item (an exponential's inverse table) against the item's running hours.

### 4.3 Time

A run lasts hours of model time; real wear takes months. So:
- **The plant's age** (`world.age`): the scenario starts each item at a wear the content tool computes from "months
  since overhaul" by duty (so a trainer picks "6 months after the outage").
- **`age_rate`** (an `ext` value): 1 is real time on the plant clock; training scenarios use a rate at which an item
  near the end of its life shows its signs within a shift. The scenario says which. A trainee is never told a failure
  is coming; the signs are there for whoever looks.

### 4.4 Maps onto

Values, faults and works; findings (§17.12: a reading out of range given to the supervisor); trends (screens.json's
`trend`); the condition monitoring jobs of §9.3; work orders (§7). No new step kind.

## 5. Weather

### 5.1 The weather step

- **`data/plant3d/weather.json`** (format `walkdown-plant-weather`): weather **kinds** (`clear`, `hot`,
  `dust_haze`, `sandstorm`, `rain`, `thunderstorm`, `cold_clear`, `fog`), **seasons** with the clock days they cover
  (day of year from `world_day` and the start date), per season a transition table per clock hour (`[[from, to,
  weight], …]`, integer weights), and per kind and `ext` value a diurnal table over `world_hour` with a lag `tau` in
  model seconds.
- **Step 1w** (after step 1's inputs, before step 2), with weather on: at each step in which the clock passes a whole
  hour, one draw from the weather stream picks the next kind from the current kind's row (event `[n, "weather", from,
  to]` when it changes). Then each `ext` value it drives moves toward its target (its kind's table at `world_hour`) by
  a first-order lag (the factor computed once, as §7.1's), and `world_wx` holds the kind's index. A jump draws once per
  hour crossed, in order, and sets the ext values to their targets (the night passed, §17.6).
- **The ext values** the weather drives: `ambient_t`, `ambient_wb`, `ambient_rh`, `wind` (m/s), `rain` (mm/h),
  `dust` (mg/m³), `visibility` (m), `solar` (W/m²), `lightning` (0/1). Without weather the scenario sets them as
  format 1 says.
- `world.weather`: `{"season": id}` (seeded), `{"fixed": kind}`, or `{"script": [[day, "HH:MM", kind], …]}` for a
  trainer's day. The instructor's input `[n, "weather", kind]` (its `instructor` event).
- **Climate:** the generic site is a hot desert plain (SITE.md): long hot dry summers with dust and sandstorms on the
  north-westerly wind, short mild winters with a few rain days, thunderstorms in spring and autumn, rare frost on
  winter nights. Tables from public country-level climate data ([WBCCKP]) and WMO's definitions ([WMO]: a
  sandstorm brings visibility under 1 km). No real station's data.

### 5.2 What it does to the plant (model content)

| Effect | Content | Source |
|---|---|---|
| GT output and heat rate fall with ambient temperature | the GT's tables of `ambient_t` (about 0.5–0.9 % of output per °C above ISO conditions for heavy-duty machines) | [GER3567] |
| GT inlet filter loading | a `wear` item fed by `dust` × airflow; filter ΔP alarm, then the GT's runback on high ΔP; filter changes and pulse cleaning are works | [GER3620] |
| GT compressor fouling | wear fed by dust and humidity; output and compressor efficiency fall; offline and online water washes are procedures | [GER3620] |
| Cooling tower | cold water temperature from the wet bulb plus the approach; condenser pressure follows; fan icing on cold nights | [Perry], [CTI] |
| Wet or dusty instruments and panels | water ingress into enclosures with a poor gland (a hidden cause: a ground fault or a drifting signal) more likely with `rain`; dust in panels' filters raises cabinet temperature; outdoor transmitters' displays fade in `solar` heat | [IEC60529], [IEC62444] |
| Rare cold | impulse lines without heat tracing freeze (a held reading, §15.4's `hold` as a fault) | [Liptak] |
| Lightning | a lightning arrester's counter; a seeded nuisance trip of an exposed instrument loop | [NFPA850] |

### 5.3 What it does to people (staff content and two engine rules)

- **Outdoor work stops** when the weather says so: lifting with the crane or the roof hoist above the crane's wind
  limit, work at height in high wind or lightning, hot work in a sandstorm. The work's `needs` and the task's `wait
  until` read the weather values (no new engine rule); the permit form shows why.
- **Heat stress** (an engine rule, §8.4): WBGT from `ambient_t`, `ambient_wb` and `solar`, work and rest by the
  person's work rate ([ISO7243], [ACGIH]).
- **Slippery stairs and walkways** in rain: zones of wet stairs where running is an unsafe act (the app sends the
  trainee's pace as `[n, "pace", "walk" | "run"]` when it changes; NPCs never run). Way times don't change: the walking
  network's times stay fixed (§16.2).
- **Sandstorm PPE:** goggles and dust masks in outdoor zones while `dust` is above a level (zones' PPE as a value:
  `"ppe_when": [[value, [items]]]`, an engine addition read where §16.7 reads a zone's PPE).
- **Visibility:** the HSE officer suspends driving on site below a visibility (S4's vehicles wait).

### 5.4 What is seen and heard (the app; not in the vectors)

- **Sky and light:** the photographed sky blended toward an overcast or a dust-laden sky; the sun's energy and the
  ambient light follow `solar` and `dust`; Godot's depth fog (already on as the thin haze, 0057) thickens and takes a
  sand colour in dust, grey in rain; visibility matches the model's `visibility` value.
- **Rain and blown sand:** one particle emitter round the camera (GPUParticles3D, streaks for rain, small sprites for
  sand), cut off under roofs (the build's roof map); splashes as a texture on the ground near the camera.
- **Wet and dusty surfaces:** global shader parameters read by the one weathered shader (0057): wetness darkens and
  adds a sheen to top faces outdoors, and puddles in the yards' low spots; dust lays on top faces after a storm and is
  washed by rain. Uniforms only: no new shader variant (counted, §11).
- **Sound:** rain on roofs and on the ground, wind by `wind`, thunder after a flash (delay by distance), sand hiss.
  CC0 recordings or synth (§11 of PLANT3D), levelled as the library is.
- **Heat:** heat shimmer is left out (screen-space; 0057 left those out), the trainee's heat stress shows in the
  Crew panel.

## 6. Documents and discussions

### 6.1 Generic P&IDs

- **Made by the content tools** from the areas and models (`tools/plant3d/pid.py`): every pipe, valve, instrument and
  piece of equipment with its code is already in the content, so the P&IDs are generated and can't disagree with the
  plant. Symbols after ISA-5.1 and ISO 10628 ([ISA51], [ISO10628]); line numbers, sizes and media from the pipes;
  instrument bubbles with their codes; a title block with the generic plant's name and a revision table.
- **Format** `walkdown-plant-drawing` (version 1): sheets of polylines, arcs, filled shapes and text runs in sheet
  millimetres, with hot spots per code. Drawn by the app as one cached 2D mesh per sheet and level of detail, pan and
  pinch zoom, tap a code to open its card or "take me there". Layout is automatic (systems per sheet, flow left to
  right) and checked by the tool (no crossing text, no symbol overlap).
- **Revisions:** an implemented change (§10.2) adds a revision with a cloud round what changed.
- **In Walkdown too (a question for the user):** the same sheets could be exported as PDF and imported by
  `kks-import`, making a public demo plant for Walkdown.

### 6.2 Equipment manuals

- **Format** `walkdown-plant-manual`: COURSES.md's blocks (paragraphs, lists, tables, callouts, figures) per part
  kind, in our own words: description and specifications (from the kit's parameters), installation, commissioning,
  operation, maintenance intervals, **troubleshooting table** (symptom, cause, remedy: the same cause ids as §2.6),
  spare parts list (from the component tree, with part numbers of the generic catalogue, §7.2), safety notes.
  Figures: the Workshop's exploded and cut views rendered at build time.
- Each manual names the public manuals it follows ([R3051] for the transmitter, [FCVH] and [DVC] for control valves
  and positioners, [API610] and a pump maker's IOM for pumps, [SKF] for bearings, [IEEE43] for motors' insulation).
  No text is copied.
- Read in the app from the card, the work order and the job's steps (a link to a section).

### 6.3 Discussions

- **Format** `walkdown-plant-discussion`: a topic tied to a work or a decision, two or three participants by role
  (a maintenance supervisor and the maintenance manager, an I&C engineer and the shift supervisor), each **position**
  with its claims and **evidence** (a manual's section, a standard, a reading or trend of the run, an event), turns of
  lines, and **points where the trainee may speak**: options of their own (support one side with evidence, ask for
  a reading, propose a third way). An **agreement** is reached when its conditions hold (the evidence each side asks
  for has been put; the trainee's picks), and it names the outcome: which task, work or plan follows.
- **Engine:** a new task step `{"discuss": id}` that holds the participants at a `meet` and waits for the trainee's
  `pick`s at each point (the existing input), or takes each point's `default` when no player takes part, so a
  discussion between NPCs ends the same way every time. The outcome runs as `choose` does (its task in place of the
  rest). Lines are shown in the meeting and the radio log; no voice.
- **First discussions** (each with its public sources):
  - run a vibrating pump to the weekend's planned stop with extra monitoring, or stop it now ([ISO20816-3] zones,
    the P-F interval);
  - calibrate the transmitter in place or take it to the bench ([R3051]);
  - repack a leaking valve under pressure or isolate it ([FCVH]; the site's rule wins: isolate);
  - restart the steam turbine after a trip before the cause is known, or investigate first ([DOE-RCA]);
  - change an alarm's limit now or through a change ([ISA182], [MOC]).

## 7. Work management

### 7.1 Work orders and job history

- A **notification** (anyone: a finding on a round, an alarm, a trainee's report) becomes a **work order**: planned
  (tasks, crafts, hours, tools, spares, permit type, JSA), scheduled (a day and a crew), in progress (its works and
  permits), complete (findings, failure code after [ISO14224]: failure mode, cause, action), closed by the supervisor.
- **Engine:** works (§15.2) gain `wo` states as model values (`<work>_wo`: 1 notified … 6 closed) moved by inputs
  `[n, "wo", work, action, person, data]` with authorities as permits have; completion data are ids from lists (no
  free text in the engine but a short comment, as `remove_lock`'s reason).
- **History:** each piece of equipment has a generated generic history (past work orders made by the content tool from
  its wear items and the plant's age) and the run's own. Saved runs keep it; a new run starts from content.

### 7.2 Spare parts and the stores

- **Catalogue** (`walkdown-plant-stores`): parts with generic part numbers made from the component trees and manuals,
  stock per part, minimum and reorder levels, lead time in clock days, the store's places.
- **Engine:** stock counts as engine-kept values; inputs `[n, "issue", part, qty, work, person]` at the store's counter
  (the storekeeper's role or a self-service store), `[n, "order", part, qty, person]`; deliveries arrive at a clock
  time (event). A **wrong part** is a lesson, never a random trick: parts that look alike (two transmitters of
  different ranges, bearings of one bore and different clearance) are in the catalogue, the trainee picks the part
  number, and the fitting action's permissive checks it against the nameplate ("the range code on the new
  transmitter's plate is not the one on the data sheet"). The storekeeper NPC issues what is written on the
  request.
- Waiting days: a job held for a part sits in the backlog; the trainee may jump days (§17.6's jump, now also to a
  date) when the plant is quiet.

### 7.3 Shift handover and logbooks

- **Logbooks** per post (control room, field, electrical, WTP, maintenance): entries as inputs `[n, "log", book, kind,
  refs, text]` (kind: event, equipment status, instruction, permit, abnormal; refs: codes, works, alarms; text up to 500
  characters). NPCs write entries from their tasks' events.
- **Handover:** the incoming person reads the log and the outgoing person's handover sheet: open permits, isolated
  equipment, shelved and suppressed alarms, equipment out of service, abnormal values, jobs in progress, instructions.
  The engine knows each fact; a trainee who takes over ticks what they were told, a trainee who hands over picks what
  to pass on. The debrief lists what was missed ("PTW-0012 open with the pump locked out was not handed over").
  Source: [HSG48] on shift handover as a known factor in accidents, [CCPS] guidance.

### 7.4 Planning a major outage

- An **outage plan**: the works of a scheduled outage (from the plant's age and the wear items, an inspection list
  after [GER3620]: combustion and hot gas path inspections as work packages), each with duration, crafts and crew
  sizes, permits and isolations, spares and lead times, cranes, scaffolds. The trainee orders and schedules them on a
  Gantt; the tool shows the critical path and conflicts (two works on one isolation, the crane wanted twice, a
  confined space and hot work in one place).
- **Engine:** the plan is submitted as `[n, "plan", plan id, [[work, role, day, "HH:MM"], …], person]`, which adds
  slots to the people of those roles (as routines' slots, §16.5). The outage then runs with jumps between shifts;
  the debrief gives its length, the hours used, the permits, incidents and what was found late.
- Size: the largest single piece of the programme (§12, WM4).

## 8. HSE in depth

### 8.1 Job safety analysis and toolbox talks

- **JSA** (job safety analysis): before a permit is issued for a work with `"jsa": true`, the acceptor picks the job's
  steps' hazards and controls from a library (`walkdown-plant-hse`: hazards, controls, per job kind). Input `[n, "jsa",
  work, [hazards], [controls], person]`; `issue` is refused (`jsa`) without one. The debrief compares it with the
  work's own list (hazards missed, controls missing). Sources: [OSHA3071], [HSG250].
- **Toolbox talk:** a `meet` of the crew before the work, its topic from the JSA; attendance is recorded; the trainee
  as supervisor gives it by picking the points (checked against the job's hazards).

### 8.2 Confined space, hot work, height

- **Confined space** (works with `permit: "confined"`): the gas test exists (§15.2); now also continuous monitoring
  (the gas detector's values in the model: O₂ 19.5–23.5 %, flammables under 10 % LEL, H₂S and CO under their limits,
  [OSHA146], [L101]), ventilation (a blower's op), an **entry log** (inputs `[n, "enter", work, person]` and
  `"exit"`; the engine keeps the entrants), a **standby person** at the entry place for as long as anyone is inside (an
  unsafe act of kind `standby` otherwise), and a rescue plan picked in the JSA.
- **Hot work** (`permit: "hot"`): combustibles cleared and covered (hand actions), a fire extinguisher at the place
  (a tool), a **fire watch** present during the work and for the time after it that [NFPA51B] requires (an unsafe act
  `fire_watch` if they leave early).
- **Work at height:** the harness clipped (exists in S2's shortcuts), scaffolds with an inspection tag (green: safe;
  red: do not use) as a state of the scaffold, erected and inspected by the contractors' tasks; an unsafe act to use a
  red-tagged scaffold ([WAHR], [HSE-Height]).

### 8.3 Reports and drills

- **Near-miss and incident reports:** the trainee files a report of an unsafe act or event they saw (form: what, where,
  who, immediate cause, picked from lists; input `[n, "report", kind, refs, text]`). HSE NPCs act on reports (a safety
  walk to the place). An incident (an injury in the model: a seeded slip on a wet stair when running, a burn on hot
  work without gloves) is investigated (§10.1 for the method).
- **Fire and emergency drills:** an emergency (a fire alarm in a building, a gas release, a chlorine leak at the
  intake's dosing) by scenario or the instructor; the staff's reactions take everyone to their **muster** place (place
  kind `muster`, §16.2); the headcount compares the muster with who is on site (the engine knows); the emergency
  response team's tasks. Drills are timed and debriefed. Source: [NFPA850], [HSG65].

### 8.4 Heat stress (engine rule)

- **WBGT** outdoors = 0.7 × natural wet bulb + 0.2 × globe + 0.1 × dry bulb ([ISO7243]); the content tool's tables give
  the natural wet bulb and globe temperatures from `ambient_wb`, `ambient_t` and `solar`; indoors the halls' own
  values.
- **Work and rest:** a role's work rate (light, moderate, heavy) and the WBGT give the minutes of work per hour
  ([ACGIH] TLV table); a `work` step outdoors pauses for rest at a shaded rest place when its share is used (an engine
  rule in the staff step, both engines), and the trainee's own work past it is an unsafe act `heat`. Drinking water
  breaks and the buddy system are task steps.
- Heat illness in NPCs is not modelled as a random event; the rule prevents it, and a trainee's breach is debriefed.

## 9. Electrical and mechanical crafts, condition monitoring

### 9.1 Electrical

| Job | What the trainee does | Model and engine | Source |
|---|---|---|---|
| Switching programme | writes (orders from a list) and checks a switching programme for taking a motor feeder or a transformer out, then carries it out with a second person checking each step | switchgear ops with interlocks as permissives; the query `switch_effects(list)` runs the list in two copies of the run like §15.6's `lock_effects` and says what would trip or lose supply | [HSG253], [IEC61936] |
| Racking an MV breaker | open, rack from service to test to withdrawn, close the earthing switch, lock and tag; arc-flash PPE by the panel's label | breaker position states with the interlocks (racking only open; earthing only withdrawn), PPE zones per panel | [NFPA70E], [IEEE1584] |
| Prove dead | test the voltage detector on a known source, test the circuit, test the detector again | hand actions in order; skipping a step is an unsafe act | [HSG85] |
| Insulation test (megger) | at 500 V or 1 kV, 1-minute and 10-minute readings, the polarization index | a meter whose values come from the winding's insulation wear and the damp (`ambient_rh`, rain); PI under 2 fails | [IEEE43] |
| Protection relay test | secondary injection: current steps, the relay's operating time against its curve | a test set's current as a `set` op, the trip time from the relay's curve table (IEC standard inverse sampled by the tool) and a `timer` | [IEC60255-151] |
| Battery and UPS | float voltage, cell voltages and a weak cell (a `draw`), electrolyte level or impedance, the discharge test, the UPS transfer test | values and wear per string | [IEEE450], [IEEE1188] |

### 9.2 Mechanical

| Job | What the trainee does | Model and engine | Source |
|---|---|---|---|
| Laser alignment | soft foot check, readings of offset and angle, the shim and move values worked out, shims and moves made, readings again | the readings are linear functions of the feet's positions (sum and product nodes made by the tool); tolerances by speed; misalignment feeds the bearings' wear and the 2× vibration | [Piotrowski], [API686] |
| Balancing | single plane: initial reading, a trial weight, the correction worked out by vectors, the correction fitted | the 1× amplitude and phase from the unbalance's components (tables of sine and cosine made by the tool); the balance grade's limit | [ISO21940-11] |
| Bearing replacement | pull, heat the new bearing (induction heater, 110 °C limit), fit, set clearance, lubricate | the Workshop tree's hand actions; fitting cold or hammering is refused with why | [SKF] |
| Mechanical seal | change a cartridge seal: set the setting clips, remove after fitting | hand actions; a seal fitted dry wears fast (a cause later) | [API682] |
| Lubrication | grease quantity by the bearing's size (G = 0.005 × D × B), interval, the right grease; over-greasing heats the bearing | a lubrication state in the wear rate | [SKF] |
| Valve packing | tighten the gland evenly by the torque, or repack with the valve isolated | packing leak as wear; a stem stuck by overtight packing (stiction) | [FCVH] |

### 9.3 Condition monitoring

- **Vibration:** a data collector (a tool) at measurement points marked on the bearings: overall velocity (mm/s RMS)
  against [ISO20816-3]'s zones, and a spectrum the app draws from model values: 1× (unbalance), 2× (misalignment),
  bearing defect frequencies from the bearing's geometry (BPFO, BPFI, BSF, FTF, [SKF]), a noise floor. Routes and
  trends (readings kept per point in the run).
- **Thermography:** a thermal camera tool: the work view's false-colour picture of the component temperatures (model
  values per component of the Workshop tree), drawn with the Workshop's heat view (WORKSHOP.md K3/K4b), so no new
  shader; hot spots on terminals (a loose connection's cause), bearings, steam traps.
- **Oil analysis:** a sample taken (a hand action), sent to the lab, results after clock days: viscosity, water, ISO
  4406 cleanliness, wear metals, from the item's wear with a small lab spread (the lab stream). Source: [ASTM-D6224],
  [ISO4406].

## 10. Engineering and compliance

### 10.1 Root-cause analysis after a trip

- After a trip, the RCA tool (in the debrief and from the event list during the run) lays out the run's evidence: the
  first-out, the events around it, the trends, the hand actions' findings (a burnt terminal), the people's
  statements (discussions, §6.3, with the operators who were there). The trainee builds the causal chain (events and
  conditions linked, the "why" asked until a cause that can be acted on) and picks actions. It is checked against the
  scenario's hidden cause and contributing faults.
- View only (no engine): the evidence is what the run recorded. Method: [DOE-RCA].

### 10.2 Management of change and drawing updates

- **Change objects** in the model (`changes`): what it changes (a setpoint, an alarm limit or priority, a new or
  removed instrument, a logic change that content provides as alternative states), the reviews (engineering, operations,
  HSE), approval, implementation (a work), commissioning (§3.4), the drawing's revision (§6.1), training of the shifts
  (logbook instruction), closure. States as values `<change>_moc`, moved by inputs `[n, "moc", change, action,
  person]` with a new authority `approve_change`.
- A setpoint or limit that a change governs is a `state` whose `set` op has `needs` on `<change>_moc` being
  implemented; an **alarm's priority from a value** (`"priority_of": state`, an engine addition) lets
  rationalisation change it.
- Source: [MOC] (CCPS), [OSHA119] (l).

### 10.3 Alarm management

- From the run's events: alarms per operator per 10 minutes, floods (more than 10 in 10 minutes), standing alarms,
  chattering alarms, the top ten "bad actors", shelved alarms and for how long; against [EEMUA191] and [ISA182]'s
  benchmarks. Shown in the debrief and a control room screen.
- Rationalisation: the trainee proposes a change (§10.2: priority, deadband, delay, suppression by plant state) with
  its reason; implemented, the next run's alarm rates show the effect.

### 10.4 Emissions reporting

- The GT's model gains NOx, CO and O₂ at the stack as tables of load, ambient temperature and the combustion mode (lean
  premix above a load, diffusion below), and a CEMS (continuous emissions monitoring) with its analysers: drift, a
  daily zero and span check with calibration gases (an I&C job), a failed analyser's substitute data.
- Hourly and daily averages corrected to 15 % O₂ (content nodes with the clock values, §2.1), limits from a generic
  regulatory frame ([IFC-EHS] by default; [IED] as an alternative: a question for the user), an exceedance report
  and the operators' response (load change, combustion mode).

### 10.5 The chemistry lab and sampling

- The HRSG's cycle chemistry: the sample panel's analysers (specific and cation conductivity, pH, sodium, silica,
  dissolved oxygen, phosphate where dosed) and grab samples analysed in the lab with their methods' times, against
  normal and action levels after the IAPWS technical guidance ([IAPWS-TGD]); dosing (ammonia, phosphate) and
  blowdown as ops; a condenser tube leak as a fault with its signs (cation conductivity and sodium rising).
- Builds on S3's chemists and samples (§17.12) and the WTP.

## 11. Budgets on the Note 9

The frame rules and §18.4's shares don't change (MILESTONES.md: ≥ 95 % of frames at ≥ 30 fps, none over 100 ms that
the app causes, both in normal play; peak PSS ≤ 1.5 GB; first walkable frame ≤ 15 s; ≤ 13.5 s per first start).
The programme's share, measured in each milestone that draws or runs something new:

| | Note 9 (`lean+vis`) | Laptop (`full`) |
|---|---|---|
| Model step, all realism content together | ≤ 0.3 ms added; the whole step ≤ 2.1 ms (§18.4), so fast-forward keeps ≥ 12× | ≤ 0.1 ms |
| Staff step (heat rule, entrants, plans) | within §18.4's 0.3 ms at the shift change | |
| Weather step | ≤ 0.02 ms (one draw an hour, ten lags) | |
| Weather drawn (worst kind: sandstorm or rain) | GPU ≤ +2 ms median; one emitter, ≤ 2,000 particles within 25 m | ≤ +1 ms; ≤ 8,000 within 40 m |
| New pipelines | the particle shader only (≤ 4 pipelines), compiled in the hidden frame (0060); wetness and dust as global parameters of the weathered shader: no new variant (counted before and after) | same |
| Work view | the component scene within the Workshop's budget (0072), ≤ 8 more draw calls with the plant round it; loaded on a worker thread ≤ 300 ms; equipment with jobs built unmerged: ≤ 6 more draw calls in any view of the plant | |
| Document view | the 3D view stops drawing while a document fills the screen; a sheet opens in ≤ 300 ms; ≤ 40 MB for open sheets | |
| Sounds | ≤ 3 more players for weather | |
| Memory | ≤ 60 MB more peak PSS | |
| Package | ≤ 15 MB more for the whole programme (the APK limit is 250 MB, the user 2026-11-01) | |

A milestone that misses a budget is not done; cutting something the trainee learns from to meet it is the user's
call.

## 12. Order

The Workshop is built first (K0–K6, WORKSHOP.md). Realism's designs run now; its builds follow the Workshop (the
question of starting the non-Workshop tracks after K3 is the user's, MILESTONES.md). Within realism:
- **foundations first:** the engine pieces (§2) in three milestones that add no drawing (HW1, AG1, WX1), each with
  its vectors;
- **then the tracks**, each adding one kind of load measured alone: hands-on (HW2–HW6), ageing and monitoring
  (AG2–AG3), weather (WX2–WX4), documents (DC1–DC3), work management (WM1–WM4), HSE (HS1–HS3), crafts (EC1–EC2,
  MC1–MC2), engineering (EN1–EN4);
- **the outage (WM4) last**: it uses nearly everything.

The table with sizes, needs and what each ships is in MILESTONES.md.

## 13. Tests

- **Vectors** (`plant3d-realism.json`): `valid` and `reject` for every new key and error code; `steps` pinning the
  `draw` and `wear` nodes (step 0, reset, max, the scenario's `init`), the streams (an item added at the end changes no
  other's draw; a person's draws unchanged with a world), tools carried and their refusals, hand actions (each reason,
  the order, a locked code), meters and `read via` (misread, `else`), HART ops, hidden causes (a work that doesn't cure),
  the weather step (hour boundaries, a jump across hours, scripted and fixed weather, the instructor's input), stock and
  deliveries, logbook and report inputs, the JSA refusal, entrants and the standby and fire watch acts, the heat rule,
  change objects and `priority_of`, `discuss` with and without a trainee, `plan` slots, `switch_effects`; runs on the
  first train's content with forks per area; the digests of every 50th step.
- **The byte check:** `plant3d-v1.json` and `plant3d-v2.json` regenerated by the new reference equal the committed
  files.
- **Content checks** (Python): every hand action's component exists in its part kind's tree; every cause has a test that
  tells it from the others; every manual's troubleshooting causes exist; the P&ID generator's output is deterministic
  and every code of the model appears on a sheet; weather tables cover every hour and season.
- **App tests:** the work view's swap and restore of the equipment, the meter screens against model values, the
  document viewer's hot spots, weather's global parameters at each kind, a full job played (`tests/test_ui_hands.gd`).
- **The Note 9** per §11; the walk gains a `weather=` option and a `job=` option (the work view open).

## 14. Sources

Standards (bought, not copied: cited for what they require, in our words):
- [ISA51] ANSI/ISA-5.1, Instrumentation symbols and identification. · [ISO10628] ISO 10628-1/-2, Diagrams for the
  chemical and petrochemical industry. · [ISA182] ANSI/ISA-18.2, Management of alarm systems for the process
  industries. · [EEMUA191] EEMUA 191, Alarm systems: a guide to design, management and procurement. · [ISO14224]
  ISO 14224, Collection and exchange of reliability and maintenance data for equipment. · [ISO17359] ISO 17359,
  Condition monitoring and diagnostics of machines: general guidelines. · [ISO20816-3] ISO 20816-3, Mechanical
  vibration: evaluation of machine vibration, industrial machines. · [ISO21940-11] ISO 21940-11, Rotor balancing:
  rigid rotors. · [ISO4406] ISO 4406, Hydraulic fluid power: solid contamination code. · [ISO7243] ISO 7243,
  Ergonomics of the thermal environment: heat stress by the WBGT index. · [IEC60529] IEC 60529, Degrees of protection
  provided by enclosures (IP code). · [IEC62444] IEC 62444, Cable glands. · [IEC62382] IEC 62382, Control systems in
  the process industry: electrical and instrumentation loop check. · [IEC61936] IEC 61936-1, Power installations over
  1 kV AC. · [IEC60255-151] IEC 60255-151, Measuring relays and protection equipment: over/under current protection.
  · [IEEE43] IEEE 43, Recommended practice for testing insulation resistance of electric machinery. · [IEEE450] IEEE
  450, Maintenance, testing and replacement of vented lead-acid batteries. · [IEEE1188] IEEE 1188, the same for VRLA
  batteries. · [IEEE1584] IEEE 1584, Guide for performing arc-flash hazard calculations. · [NFPA70E] NFPA 70E,
  Electrical safety in the workplace. · [NFPA51B] NFPA 51B, Fire prevention during welding, cutting and other hot work.
  · [NFPA850] NFPA 850, Fire protection for electric generating plants. · [API610] API 610, Centrifugal pumps. ·
  [API682] API 682, Pumps: shaft sealing systems. · [API686] API RP 686, Machinery installation and design. ·
  [ASTM-D6224] ASTM D6224, In-service monitoring of lubricating oil for auxiliary power plant equipment.

Public guidance and regulations (free to read):
- [HSG250] UK HSE, Guidance on permit-to-work systems, https://www.hse.gov.uk/pubns/books/hsg250.htm · [HSG253] UK
  HSE, The safe isolation of plant and equipment, https://www.hse.gov.uk/pubns/books/hsg253.htm · [HSG85] UK HSE,
  Electricity at work: safe working practices, https://www.hse.gov.uk/pubns/books/hsg85.htm · [HSG48] UK HSE,
  Reducing error and influencing behaviour (shift handover), https://www.hse.gov.uk/pubns/books/hsg48.htm · [HSG65]
  UK HSE, Managing for health and safety, https://www.hse.gov.uk/pubns/books/hsg65.htm · [L101] UK HSE, Safe work in
  confined spaces (ACoP L101), https://www.hse.gov.uk/pubns/books/l101.htm · [WAHR] The Work at Height Regulations
  2005, https://www.legislation.gov.uk/uksi/2005/735 · [HSE-Height] UK HSE, Working at height,
  https://www.hse.gov.uk/work-at-height/ · [OSHA146] US OSHA 29 CFR 1910.146, Permit-required confined spaces,
  https://www.osha.gov/laws-regs/regulations/standardnumber/1910/1910.146 · [OSHA119] US OSHA 29 CFR 1910.119,
  Process safety management, https://www.osha.gov/laws-regs/regulations/standardnumber/1910/1910.119 · [OSHA3071] US
  OSHA 3071, Job hazard analysis, https://www.osha.gov/sites/default/files/publications/osha3071.pdf · [DOE-RCA] US
  DOE-NE-STD-1004-92, Root cause analysis guidance document · [IFC-EHS] IFC/World Bank, Environmental, Health and
  Safety Guidelines for Thermal Power Plants (2008), https://www.ifc.org/ehsguidelines · [IED] Directive 2010/75/EU
  (industrial emissions), Annex V, https://eur-lex.europa.eu/eli/dir/2010/75/oj · [IAPWS-TGD] IAPWS technical guidance
  documents on cycle chemistry (volatile treatments, phosphate and NaOH treatments, instrumentation),
  https://www.iapws.org/techguide.html · [WMO] WMO, Manual on codes / International Cloud Atlas (dust and sand storm
  definitions), https://cloudatlas.wmo.int · [WBCCKP] World Bank Climate Change Knowledge Portal (country climatology),
  https://climateknowledgeportal.worldbank.org · [ACGIH] ACGIH TLV for heat stress and strain, as summarised by US
  OSHA's Technical Manual section III chapter 4, https://www.osha.gov/otm/section-3-health-hazards/chapter-4 ·
  [HART] FieldComm Group, HART protocol, https://www.fieldcommgroup.org/technologies/hart · [MOC] CCPS, Guidelines
  for the management of change for process safety (Wiley, 2008) · [CCPS] CCPS, Guidelines for risk based process
  safety (Wiley, 2007).

Manufacturers' published manuals and handbooks:
- [R3051] Emerson, Rosemount 3051 pressure transmitter reference manual (loop resistance for HART, troubleshooting,
  trim). · [DVC] Emerson, Fisher FIELDVUE DVC6200 instruction manual (positioner calibration). · [FCVH] Emerson,
  Control Valve Handbook (packing, stiction, troubleshooting). · [SKF] SKF, Bearing maintenance handbook and rolling
  bearings catalogue (mounting, heating, relubrication quantity, defect frequencies). · [GER3567] GE Power, GER-3567,
  Gas turbine performance characteristics. · [GER3620] GE Power, GER-3620, Heavy-duty gas turbine operating and
  maintenance considerations (inspections, filters, washing, factors on intervals). · [Fluke] Fluke application
  notes on clamp meters and 4–20 mA loop calibrators.

Textbooks:
- [Moubray] J. Moubray, Reliability-centred Maintenance (the P-F curve). · [Liptak] B. Lipták, Instrument Engineers'
  Handbook. · [Piotrowski] J. Piotrowski, Shaft Alignment Handbook. · [Perry] Perry's Chemical Engineers' Handbook
  (cooling towers). · [CTI] Cooling Technology Institute, publications on cooling tower performance.

## 15. Not in this programme (deliberately)

- Real physics (fluids, heat, electrics, structures): tables and lags only (R6).
- Free text that the engine interprets: the engine records short texts (reasons, log entries, reports) but never
  reads them.
- Injuries shown on people, or anything graphic: incidents are reported and investigated, not shown.
- Speech for NPCs: discussions are text (the platforms' text-to-speech is noted in CAPABILITIES.md, not used).
- Real plant documents, procedures or data, and anything taken from the user's photos.
- Money: costs are hours, parts and megawatt-hours lost, not currency (a question for the user).
