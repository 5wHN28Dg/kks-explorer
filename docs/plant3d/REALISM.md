# Walkdown Plant: the realism programme

**Status: DRAFT 2026-11-01**, written before any code; the user's decisions of 2026-11-01 are in (below and decision
0073). Decision: 0073. Milestones: MILESTONES.md, "Realism".
Format: docs/PLANT3D.md format 2 (§14–§21), with the additions of §2 below. The Workshop (docs/plant3d/WORKSHOP.md,
decision 0072, being written in parallel from the user's Workshop spec: its names here follow that spec until K0
settles them) is built first; this programme builds on its component trees and bench models. Everything here is
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
- **The rest of the job** (J1–J8, added by the user the same day): operations, electrical, I&C, mechanical, HSE
  and environment, chemistry, stores and planning, people and administration, each as listed there.

**The user's answers (2026-11-01)** to the plan's questions:
1. The parts that don't need the Workshop are built **alongside it**: RE1, AG1, WX1 and DC1 (the generated P&IDs).
   Hands-on work waits for the Workshop's K3 (§12).
2. Ageing runs at a **training rate per scenario**, with real rates also available (§4.3).
3. Weather in free play is **on, seeded by season** for the hot dry climate (§5.1).
4. Emissions are judged against the **IFC / World Bank Group EHS guidelines for thermal power plants** (§10.4).
5. Costs are shown as **man-hours, parts and MWh lost**, with no currency (§15, J7).
6. The generated P&IDs appear **in the plant app only** (§6.1).
7. NPC speech is **text only** (§6.3, §15).

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
| The rest of the job (J1–J8) | operations, electrical, I&C, mechanical, HSE and environment, chemistry, stores and planning, people and administration | everything above; S4's staff | J0: grid events, the `count` node, forces and bypasses, permit conflicts, zone barriers, authorisations, duty hours, passes and languages, order approvals | panels and forms per item |

**What stays out of the engine.** Anything that changes the plant, a person or what another player sees is in the
engine (it has to be the same on every player of a session and in the reference, MULTIPLAYER.md §3). Pure views
(a spectrum drawn from model values, a drawing, the RCA board after the run) are the app's and are pinned by app
tests, not vectors.

## 2. Common engine pieces (format 2 additions)

Format 1 is frozen. These are additions to format 2, as LIFTS (§20) and S4 (§21) were: new optional keys, each
gated by its own key, so a plant or scenario without them steps exactly as before. The new behaviour gets its own
vector file, **`ref/vectors/plant3d-realism.json`**, made by `ref/make_plant3d_vectors.py` from `ref/plant3d.py` and
`ref/plant3d_staff.py`, and reproduced by `apps/plant3d/sim` bit for bit on Linux, Windows and the Note 9 (§13).

**What stays byte for byte, and what is regenerated.** The engine milestones (RE1, HW1, AG1, WX1) change no content:
`plant3d-v1.json` and `plant3d-v2.json` regenerated by the new reference equal the committed files (a test). The
content milestones (HW2, AG2, WX2 and later) add states, nodes and `ext` values to the first train, so the runs that
follow its content (v1's `train` and `hot`, v2's `day` and its forks) are regenerated as P1 and W2 did: the same
inputs and events, every earlier value the same at every snapshot, the new values added. Their synthetic items stay
byte for byte. The new digest parts (§2.8) are present only when their keys are, so a run without them keeps its
digests.

### 2.1 The world seed, its streams and the clock values

- A version 2 scenario gains `"world": {"seed": n, "year_day": d, "weather": W, "age": A, "changes": [ids]}` (all
  optional; `seed` a whole number 0 to 2³² − 1, default the staff seed, else 1; `year_day` 1–365, the day of the year
  of the clock's day 1, default 1, for the seasons of §5.1; `age` is read by the content tools only, §4.3;
  `changes`, §10.2).
- Draws use §17.5's generator (mix32, xorshift32, 24-bit `r`) on streams of their own, so a person's draws never
  change. A stream belongs to a purpose tag P and an item named by its id (a value name, a fault id, a person id): s =
  mix32(mix32(seed ^ P) ^ h), h the FNV-1a 32-bit hash of the id's UTF-8 bytes (offset 2166136261, prime 16777619,
  products by §17.5's mul32), 1 if s is 0. Adding or moving an item in any file changes no other item's draws. Tags:
  `draw` nodes `0x44524157`, causes `0x43415553` (per fault), weather `0x57454154` (one stream, id `"weather"`), stores
  `0x53544f52` (per part), lab `0x4c414253` (per sample point), NPC slips `0x534c4950` (per person, §3.1).
- **Clock values**, only in a scenario with `world`: `world_hour` (time of day in hours, (C mod 864,000) / 36,000 in
  doubles, C the clock in tenths, §16.1) and `world_day` (C div 864,000). Engine-kept values with slots after the
  isolations' and works' values, read by any node as a machine's state is.
- **Time bases.** The plant clock runs `day_scale` times faster than model time (§16.1). Anything people or the
  calendar measure (wear by running hours, weather's hours and days, averages per clock hour, lead times, heat
  limits) is in clock time; process dynamics (lags, ramps, trips) stay in model time. A clock rate r per clock second
  adds r × 0.1 × `day_scale` per step.

### 2.2 Two new nodes, and renewals

- **`{"draw": table, "init": n}`** (stateful constant): at step 0 takes table(u), u = r / 2²⁴ from its own stream, unless
  the scenario's `init` gives it. The table is an inverse distribution made by the content tools (a bearing's life
  spread, a transmitter's drift direction, a weak battery cell). It never changes during the run.
- **`{"wear": rate, "reset": ref, "max": b, "init": n}`** (stateful): y ← 0 when `reset` reads true, else min(b, y +
  max(0, rate) × 0.1 × `day_scale`), both read as the previous step left them: a clock-rate accumulator. It carries
  wear, and also any sum that resets (an hour's emissions, §10.4: `reset` on the hour's change).
- **Renewals:** a work gains `"renews": [wear values]`. Its `done` sets each to 0 in step 3, with its `repairs` and under
  the same rule (only while its isolation is complete after this step's locks). No state or interlock is involved, so
  locks can't leave a renewal half done.
- **Across a jump** (§17.6 and §7.2's day jump) a wear node adds rate × (the gap in clock tenths / 10) once, with the
  rate as the step before the jump left it, then min(b, …). The night's or the week's running ages the plant.

### 2.3 Tools carried

- **`data/plant3d/tools.json`** (format `walkdown-plant-tools`): each tool's `id`, `title`, `kind` (`spanner`,
  `socket`, `screwdriver`, `hex_key`, `pliers`, `stripper`, `crimper`, `torque`, `meter`, `communicator`,
  `test_set`, `lifting`, `gas_detector` …), `size` where it has one (17 mm, PZ2, 5 mm), its modes (meters), and where it
  is kept with how many (`"at": [[place, count], …]`, places of kind `store` or a new kind `toolbox`). Limits: 200
  tools.
- **Input** `[n, "tool", item, 0 | 1, person]`, handled in step 1: taking is refused away from a place that keeps it
  (`where`) or when none is left there (`none_left`: two people can't take the one HART communicator); putting back
  only at such a place. Counts per place and each person's `carried` (at most 12) are state. NPC step `{"tool":
  [items] | "off"}`, as `ppe` (§16.6), failing to its `else` when one is missing.

### 2.4 Hand actions

- A model gains **`hands`**: `{"kks", "action", "component", "tools": [ids], "wrong": {tool id: sentence}, "needs":
  [[value, sentence], …], "set": {...}, "input": state, "range": [lo, hi], "minutes": m, "work": true | false}`.
  `action` is an identifier (`open_cover`, `lift_wire_1`, `connect_hart`, `crack_vent`, `torque_flange`, `fit_spare`
  …); `component` a name in the part kind's component tree; `tools` the tools that do it (any one); `wrong` the
  sentence for a tool a technician might try (a 13 mm spanner on a 17 mm nut, a flat blade on a Pozidriv screw, an
  uninsulated screwdriver on a live terminal); `needs` the permissives in order (the assembly order, "the terminal
  cover is off first"; safety, "the loop is not proved dead"), read as the previous step left them, as ops' are;
  `set` the component states it writes; `input` and `range` a quantity the person gives (a strip length, a torque, a
  shim's thickness) written into that state, refused outside the range as a `set` op's is; `minutes` the clock minutes
  it takes; `work: true` (the default) when it needs an accepted permit of a work on that code.
- **Input** `[n, "hand", kks, action, tool, value or null, person]` in step 1. Event `[n, "hand", kks, action, tool,
  person, "start" | "done" | "refused" | "unknown", [reasons]]`; reasons in order: `authority` (not the acceptor of an
  accepted permit for a work on that code, or another with `accept` and the work's discipline while the acceptor is
  off duty, as §15.5; for `work: false`, lacking `operate_local`), `busy` (the person is in another hand action),
  `tool` (not carried), `wrong_tool` (with its sentence), the failed permissives, then a `value` outside `range`.
- **Time:** with `minutes`, an accepted action starts (event `start`) and the person is busy until the clock reaches
  its end, when its `set` and `input` are written (step 3, after the repairs) and `done` is made. A trainee who leaves
  the equipment's work place (`leave`) or an NPC pre-empted abandons it, with nothing written. Without `minutes` it is
  done at once in step 1. The busy state (action and end clock) is per person.
- **NPCs:** task step `{"hand": action, "kks": code, "tool": id, "value": n}`; a refusal goes to the step's `else`, or
  abandons the task, as an op's does.
- **Writes and locks:** component states carry no `kks` (validator `locked_write` if one names a code of the work's
  own isolation); a hand action never writes a command. Its writes are therefore never skipped by a lock.
- **From the Workshop's data:** the component tree and the assembly order with its refusal sentences (WORKSHOP.md,
  K2) are the source. The realism content tool adds what the Workshop leaves out of its own scope (fasteners' sizes
  and the tools that fit them, torque values, the damaged states of components: the Workshop spec §9 puts tools and
  wear out of its scope) in a file of its own per part kind, `data/plant3d/service/<kind>.json`, beside the Workshop's
  data, and generates the hand actions of each piece of equipment a job names, with states named `<equipment
  prefix>_<component>_<state>`. The validator refuses a hand action whose component the part kind's tree lacks.
- **Names that fit** (with WORKSHOP.md's ids, decision 0072): a value name is an identifier of at most 32 characters
  (PLANT3D.md §1) and a Workshop component id at most 16, so the prefix, the state and the two underscores share the
  other 16. The rule, fixed so that no name is shortened case by case: the equipment prefix is a short alias of at
  most 8 characters given per piece of equipment in the service file (`"alias": "cpt1"` for the first condenser
  pressure transmitter; unique in the plant), and a state name is at most 6 characters (`off`, `open`, `loose`,
  `torn`), so every generated name fits (8 + 1 + 16 + 1 + 6 = 32). The content tool refuses an alias or a state
  over its length, and the validator refuses any value name over 32 characters as it does today (`bad_id`).
- **What a hand action does to the plant** is ordinary model content: a lifted wire opens the loop, the current falls
  to 0, the control system marks the value bad and alarms. Cause and effect stay in the model.
- **Limits:** at most 2,000 hand actions. Values stay within §1's 4,000 a model; the cost per value (§11) is the real
  limit.

### 2.5 Readings through a tool

- A model gains **`meters`**: `{"id", "kks", "point", "tool_kind", "mode", "value", "needs": [...], "else": value or
  number}`. `point` is where the probes or the clamp go (`terminals_sig`, `test_terminals`, `cable_l1`, `cable_both`,
  `jb3_tb_5`), `mode` the meter's mode (`mA_dc`, `V_dc`, `ohm`, `A_ac_clamp`, `hart`), `value` what it shows, `else`
  what it shows when a permissive fails (0 for a clamp round both conductors, an open ohm reading as `1e99`, shown OL).
  Wrong uses are meters too, so their readings are right by construction.
- **Input** `[n, "read", code, value, meter]` (S1's `read` with the meter named): the person must carry a tool of the
  meter's kind (`tool`); `misread` beyond the step's `tol` against the meter's value as the previous step left it.
  Task step `{"read": code, "via": meter}`.
- **The HART communicator** is a meter of mode `hart` with several values (PV, loop current, range, damping, units,
  device status) and its own ops: a version 2 op's `where` may be `hart` (§16.6's `op` step and §17.1's checks gain
  it). The engine refuses a `hart` op with the reason `hart` unless the person carries a communicator and the
  equipment's `connect_hart` state is true. Configuration ops (range, damping, units, loop test, trim) are `set` ops
  with `where: ["hart"]` and their permissives (write protect off; the loop in manual for a loop test).

### 2.6 Hidden causes

- A scenario fault gains **`causes`**: `[{"id", "weight", "set", "repair", "text"}]`; `weight` a whole number or a
  value (read as step 2 left it, rounded down, below 0 as 0; all zero: the first cause), totals ≤ 2¹⁶ (§17.5). A value
  weight lets an earlier mistake make a cause likelier (a ferrule left off raises a loose terminal's weight).
- **When it is drawn:** in step 3, only when the fault is made (a fault not made because a write would be skipped,
  §15.1, draws nothing). One draw from the fault's cause stream, then the cause's `set` written after the fault's own.
  Event `[n, "cause", fault, cause]` after the fault's, which the app hides until the debrief. A trainer's fault applied
  again after a repair draws again. The instructor may name the cause (`[n, "fault", id, cause]`, with its
  `instructor` event): no draw is made then.
- **Repairs:** the fault's `repair` and the applied cause's `repair` are both written (the fault's first). A work's
  **`cures`** lists the causes it puts right: its `done`, and a repair under its permit (§15.5), repair the fault only
  when the applied cause is among them. Otherwise the repair input is answered exactly as one that cures (accepted,
  noted, no `unknown` or refusal), the work's own `set` and `renews` are written, and the fault stays: nothing tells
  the trainee the cause before the plant does. With `causes`, §15.2's "at most one work repairs a given fault" becomes
  "at most one work per fault and cause".

### 2.7 Where everything happens in a step

- **Step 1** (inputs, as §17.1, each where it comes, its event at once): `tool`, `hand` (started, or done at once),
  `read` with a meter, `hart` ops, and the inputs of the later sections: `wo` (§7.1), `issue` and `order` (§7.2),
  `log` and `handover_check` (§7.3), `plan` (§7.4), `jsa` (§8.1), `enter` and `exit` (§8.2), `report` (§8.3), `moc`
  (§10.2), `pace` (§5.3), `weather` (the instructor's), and J0's: `grid` (the instructor's), `force`, `pass`,
  `order_approve`. Their reasons are listed in the order each section gives; `jsa` comes after §15.3's `authority`,
  `state`, `iso_busy`, and `simops` after `jsa`; an authority naming an `auth` record is refused as `authority`.
- **Step 1w** (new, only with `world.weather` or `world.grid`): the clock values (§2.1, with `world`), then the
  weather (§5.1), then the grid events (J0). It writes the `ext` values it drives; every node reads an `ext` value as
  step 1w left it in this step (as a `state` is read as it stands after this step's ops).
- **Step 2:** unchanged, except with `forces` (J0): each forced value's node is computed as before into a slot of its
  own (`<value>_raw`, for the screens' "forced" mark), and the value's own slot then takes the force's `to` (or the
  value held when the force went on), so every later node, and steps 3–9, read the forced value.
- **Step 3:** after §15's locks and automatic moves and the repairs (format 1's, under a permit, then `done`'s, each
  with causes, §2.6): renewals (§2.2), hand actions whose minutes end, then deliveries whose clock time is reached
  (§7.2), in that order.
- **Steps 4–8:** unchanged (alarm priorities from values, §10.2, read as step 2 left them).
- **Step 9:** the staff step gains, each only when its key is present: the `discuss` step (§6.3, key: a discussions
  file), plan slots (§7.4), the standby and fire-watch acts (§8.2, works with `permit` `confined` or `hot` and the
  `standby`/`fire_watch` keys of their tasks), zones' `ppe_when` (§5.3), running on wet stairs (§5.3, zones with
  `"wet_when"`), the heat rule (§8.4, roles with `work_rate` and `world.weather`), NPC slips (§3.1, task steps with
  `slip`), vehicle runs' `needs` (§5.3), and J0's duty-hour limits (`fatigue`: the callout refused, the `fatigue`
  act), zone barriers (`barrier_when`), passes at the gate (`passes`) and who understood what (`languages`). It
  still writes no value: everything it does is an input or a person's
  state, as before.

### 2.8 The digest

The state digest (§17.14) gains, after its staff part and each present only when its key is: the clock values' slots
(they are values: already covered), the weather's kind, last change and stream, its scripted or instructor-set kind
and each driven lag's value; every stream's state (causes, stores, lab, slips); each applied fault's cause; tools'
counts per place and each person's `carried`; each person's busy hand action and end clock, `pace`, heat counters and
rest state (whole clock tenths); stock, orders and deliveries pending; work orders' states and data; logbook and
report counts; JSA records per work; toolbox-talk attendance; entrants per work; plan slots added; change objects'
states; and J0's: the grid event running and its start, each force's state and held value, each person's duty-hour
counters and days worked, the passes issued, the orders waiting for approval, and the `count` nodes' counters (with
the stateful nodes'). Everything the next steps read is in it, as §17.14 requires.

### 2.9 What stays as it is

Permits, isolations and locks, lifts and multiplayer's lockstep keep their rules. Everything here acts through
inputs and values, so a session needs no new message kind: the new inputs travel in commits like any other
(MULTIPLAYER.md §3.1). §17.6's sentence "a jump draws no random numbers" gains "except the weather's hourly draws
(§5.1)" in a scenario with weather.

### 2.10 As built for milestone RE1 (2026-11-01: the world, its streams, the clock values)

- **Where:** `ref/plant3d_world.py` (the reference) and `apps/plant3d/sim/world.gd` (the app's engine), with small
  hooks in `ref/plant3d.py` and `apps/plant3d/sim/engine.gd` (the slots, step 0, step 1w) and the loader's names
  (`plant_model.gd`). Vectors: `ref/vectors/plant3d-realism.json` (`streams`, and `staff`: the synthetic plant with
  staff whose model reads the clock values, its rejects and four runs, as plant3d-v2.json's `staff`), made by
  `ref/make_plant3d_vectors.py --only-realism --write`; `run_vectors.gd --only=realism` replays them (not in its
  default parts). Tests: `tests/test_plant3d_realism.py`, `tests/test_plant3d_sim.py` `GdscriptRealism` (every value's
  bits and the state digests, with the generated program and the interpreter).
- **`world` in RE1** holds `seed` and `year_day` only; `weather`, `age` and `changes` are unknown keys until WX1, AG2
  and EN2 define them. Refused: a `world` in a version 1 scenario (`unknown_key`), not an object (`bad_type`), a seed
  or year day out of range or not a whole number (`bad_number`), a plant without a clock (`bad_ref`).
- **The clock values' names** are readable in every version 2 plant (a value or `ext` value of either name is
  `dup_id`), and their two slots exist only in a scenario with `world`, after every other slot (after the lifts'
  loads too). So that no engine reads a slot that isn't there, a version 2 plant whose content names `world_hour` or
  `world_day` anywhere (the model files, staff.json, a procedure, screens.json, a scenario's faults) needs `world` in
  every scenario (`bad_ref`): `"world": {}` is enough. The app's loader (`plant_model.gd`, not the validator) keeps
  the same guard for what it reads (the model, scenario faults, staff reactions on a value) and refuses a value or
  `ext` value of either name, since the step bench's loads reach it unvalidated.
- **Saved runs and snapshots** don't carry the world's fields: the engine builds them from the scenario (their
  names begin with `_`, which `ui/run_save.gd` leaves out), so a save or a host's snapshot can't change the seed.
- **Step 1w** writes the two values after step 1's inputs and first-out records, so a jump's own step reads the new
  clock; step 0 writes them at C(0). A stateful node reads the previous step's, as for any value.
- **The digest:** RE1 adds no part to the digest tree: the clock values are values (in the digest's doubles), the
  world's seed is a constant, and no stream draws yet. Each later milestone adds its streams' states as §2.8 lists.
- **The byte check:** `plant3d-v1.json` and `plant3d-v2.json` made again by the new reference are byte for byte the
  committed files (`make_plant3d_vectors.py` without `--write`: "up to date").
- **A load of the planned size** (§11): `tools/plant3d/realism_synth.py N` makes N model values shaped like the
  realism content (wear items with their signs, component states and meters, diurnal tables with lags, emissions
  sums and holds, and above 600 the first train's own mix of node kinds) on the last area of the first train, with a
  `world` in every scenario; never shipped. `apps/plant3d/app/step_bench.gd` measures the step over the cold start and
  at base load with and without it: `apps/plant3d/sim/tests/bench_realism.gd` on a desktop, the app's `step=bench`
  option on a phone (the loads pushed as `realism-*.json` into its files folder, the result in `step.txt` there).

| Model step (base load, mean) | built (2,271 values) | + 600 | + 1,000 |
|---|---|---|---|
| Laptop (headless, `bench_realism.gd`) | 0.223 ms | 0.274 ms (+0.051) | 0.302 ms (+0.079) |
| Note 9 (release build, `step=bench`) | 0.418 ms | 0.505 ms (+0.087) | 0.554 ms (+0.136) |

The Note 9 (2026-11-01, a test-signed release build of this branch, battery 26.6 °C at the start; evidence in
`~/kks-work/build/re1/` on the maintainer's laptop): two runs. Each load measures the train as built first; in the
second run that first figure was 0.714 ms (the cold start's 0.708), against 0.418 in the first, while its 600 and
1,000 loads matched the first run's (0.504 and 0.563 ms at base load); the first run's three figures keep the
laptop's ratio (1.87×, 1.84×, 1.83×), so the second run's built figure is taken as the phone's scheduler (the bench
thread on a slow core), not the model. Added cost: about 0.15 µs a value at 600 and 0.14 at 1,000, well under §11's
"roughly 0.7 µs a value" (which was read from the app's walk with the water treatment plant, rendering and staff
alongside, not from the model alone). So the 1,000 values of J0's question cost +0.136 ms in the model alone, within
the 0.4 ms share; in the app the step has measured about 3× the bench's (1.36–1.45 ms in S2's walk against 0.42 here),
and if the added cost scaled the same way it would be about +0.26 ms at 600 and +0.41 ms at 1,000, at the share's
edge. A walk with the load in the app is not possible yet (the app runs only shipped content).

### 2.11 As built for milestone AG1 (2026-11-02: the wear engine)

- **Where:** `ref/plant3d.py` (nodes, works' `renews`, step 0's draws, step 3's renewals) and `apps/plant3d/sim/engine.gd`
  (the interpreter and the straight-line program both), the loader (`plant_model.gd`). Vectors: `plant3d-realism.json`'s
  `wear` (the realism base's plant with a pump that wears: its files, counts, 27 rejects and five runs, laid out as
  `staff`); tests `tests/test_plant3d_realism.py` `WearVectors` (each wear step against the formula, the draws against
  their streams, counts, renewals, the jump, `age_rate`), `GdscriptRealism` (every value's bits and the digests in
  the GDScript engine) and `check_world.gd` (the loader's guards).
- **The nodes** are format 2 node kinds: in a version 1 model file they are refused with format 1's codes (alone
  `bad_kind`, beside another kind that kind's `unknown_key`, as `hold`). A scenario fault's `when` stays stateless, so
  none of them can be one; no op, fault or work writes them (they are not states); a scenario's `init` may give any of
  them (a wear within 0 and `max`).
- **`draw`** (`{"draw": table, "init": n}`): the table is COURSES.md's (linear between rows); with neither its own
  `init` nor the scenario's, step 0 takes table(r / 2²⁴) of the first draw of the stream (world seed, purpose `draw`,
  the value's name), after the scenario's `init` and before the stateless nodes; then it never changes (no program
  entry). The seed is the world's (its own, else the staff's, else 1), so a scenario without `world` draws too.
- **`wear`** (`{"wear": rate, "max": b, "reset": ref, "init": n}`; `max` required, a number ≥ 0; `reset` optional): y ←
  0 when `reset` reads true, else min(b, y + r × k) with r = the rate if it is above 0 (else 0, NaN too), k = 0.1 ×
  `day_scale` computed once, everything as the previous step left it. A plant without a clock can't have one
  (`bad_ref`: it counts clock time). **Across a jump** (§17.6), in the jump's own step: y + r × (gap / 10) first (the
  gap in clock tenths, so the night's clock seconds), then + r × k (the step), then the max; the rate is the previous
  step's. The gap reaches the program through a slot after the constants (laid out with the main program's, so the
  generated script still depends on the model alone), written before step 2 and cleared after it; it is never in a
  snapshot or the digest.
- **`count`** (`{"count": ref, "by": ref, "reset": ref, "init": n}`; `by` default 1, `reset` optional): adds `by` on
  each step in which `ref` reads true and read false the step before, all three as the previous step left them; reset
  true gives 0 (its memory still follows `ref`). Its memory (one per node, in `mem`: so in saves, snapshots and the
  digest) starts as "not seen false", so a `ref` already true at step 0 (a machine running at the start) is not a start.
- **`renews`** on a work: 1 to 32 wear values (each a `wear` node, `bad_ref`; once each, `dup_id`), and the work must
  have an isolation (`missing_key`, as `repairs`: the user's rule that every job that repairs equipment isolates it).
  In step 3, after every `done`'s repairs and `set`, each work whose permit went to done in this step sets its wear
  values to 0 when its isolation is complete after this step's locks (a lock removed by authority in done's own step:
  no renewal); no event of its own (the permit's `done` is the record).
- **`age_rate`** is no engine rule: an ordinary `ext` value that the content multiplies into each wear's rate (the
  vectors' bearing: a duty table of the flow × `age_rate` × a constant), so each scenario gives its own (the user,
  2026-11-01: a training rate per scenario, 50 in the vectors' base; real time is 1, the vectors' second run).
- **The digest:** no new part: the draws, wears and counts are values, and the counts' memory is in `mem`.
- **The byte check:** `plant3d-v1.json` and `plant3d-v2.json` made by the new reference are the committed files.
- **The reference sets `day_scale` before compiling** (and the GDScript engine the clock), since a wear's factor reads
  it; no earlier value depended on the order.

### 2.12 As built for milestone WX1 (2026-11-02: the weather engine)

- **Where:** `ref/plant3d_world.py` (the file's check, the scenario's `world.weather`, the step) and
  `apps/plant3d/sim/world.gd` with `engine.gd`'s `_weather`. Vectors: `plant3d-realism.json`'s `weather` (the realism
  base's plant with weather.json: 44 rejects and six runs); tests `WeatherVectors` (the hourly chain recomputed from the
  stream and the file, each lag step, the season at midnight, the instructor, the jump's draws, the digest, the people's
  draws unchanged), `GdscriptRealism`, `check_world.gd`.
- **`weather.json`** (format `walkdown-plant-weather`, version 1; only in a version 2 plant): `values` (1–16 `{"id",
  "tau"}`: each an `ext` value of plant.json, its lag in clock minutes, above 0), `kinds` (1–16 `{"id", "targets"}`:
  a table over `world_hour` from 0 to 24 per driven value, every value given), `seasons` (1–12 `{"id", "days": [first,
  last], "start": kind, "hourly": [[from, to, weight], …]}`: first > last runs over the year's end; every day of the
  year in exactly one season; whole weights ≥ 0, a pair once, every kind with a total above 0 and at most 2¹⁶ from it,
  so the chain can always move on). `world_wx` (the kind's index in `kinds`) is the third engine-kept value, after the
  clock values, only in a scenario with `world.weather`; its name is reserved like theirs (`dup_id`), and content
  reading it needs `world.weather` in every scenario (`bad_ref`).
- **`world.weather`:** one of `{"season": id}` (seeded; the id must be the season of the scenario's start day, the
  day of the year from `year_day` and the start's day, so a scenario says which season it starts in and the chain
  starts at that season's `start` kind), `{"fixed": kind}`, or `{"script": [[day, "HH:MM", kind], …]}` (1–256 entries
  in time order, the first at or before the scenario's start: the kind at step 0 is the last entry at or before it).
- **Step 1w,** after the clock values: seeded, one draw from the weather stream for each whole hour h the clock passed
  since the step before (C(n − 1) div 36,000 < h ≤ C(n) div 36,000, so a jump's every hour, in order), the next kind
  picked from the current kind's row of the season of hour h's day by §17.5's `choose` ((r × T) >> 24 against the
  running sums; a draw is made at every hour, whether the kind changes or not); scripted, each entry passed in the step
  (C(n − 1) < its clock ≤ C(n)) sets the kind; fixed, nothing. Then each driven value moves toward its kind's table at
  this step's `world_hour`: y + (target − y) × f, f = 1 − e^(−0.1 × `day_scale` / (60 × tau)) computed once; in a
  step with a jump, the value is the target itself. `world_wx` takes the kind.
- **Who reads it:** a stateless node reads this step's driven values and `world_wx`; a stateful node the previous
  step's, as for the clock values and every value (§7.1), so §2.7's "every node reads an ext value as step 1w left it"
  holds for stateless nodes.
- **Events:** `[n, "weather", from, to]` once in a step whose kind at the end of step 1w differs from the kind before
  step 1 (a jump across several changes makes one event for the net change); the instructor's `[n, "weather", kind]`
  sets the kind in step 1 with `[n, "instructor", "weather", kind]` (the seeded chain goes on from it at the next hour, a
  script at its next entry); in a scenario without weather, or with a kind weather.json lacks, it does nothing and makes
  no event. A session carries it from the host's and the instructor seats' slots only (net/input_check.gd, as a
  fault), a save keeps one queued (ui/autosave.gd); the panel's button (ui/inputs.gd) comes with the instructor's
  panel (WX3).
- **The digest** gains, with weather only, the kind and the weather stream's state after the lifts' parts (the driven
  values and `world_wx` are values); a save keeps both (`wx_kind`, `wx_s`), the built tables are rebuilt from the
  scenario.
- **§17.6:** a jump still draws nothing for the people; the weather's hourly draws are made in the jump's step.

**The step's cost (AG1 and WX1 together).** `tools/plant3d/realism_synth.py N --engine` makes RE1's synthetic load with
the engine's own nodes (each wear item a `wear` node, a `draw`n life, the failure against it and a `count`) and the
weather at §11's size (weather.json with ten driven values: the train's `ambient_t` and `ambient_wb` and eight more
`ext` values, eight kinds, a draw an hour); the step bench prints a `WEATHER` line, the weather step alone over 20,000
calls (its lags, and with an hour crossed: a draw and the targets).

| Model step (base load, mean) | built (2,271 values) | + 600 (RE1's shapes) | + 600 `--engine` | + 1,000 `--engine` |
|---|---|---|---|---|
| Laptop (headless, `bench_realism.gd`) | 0.205 ms | 0.261 ms (+0.056) | 0.263 ms (+0.058) | 0.265 ms (+0.060) |
| Note 9, fast core (release build, `step=bench`) | 0.413 ms | 0.498 ms (+0.085) | 0.530 ms (+0.117) | 0.572–0.587 ms (+0.16–0.17) |
| Note 9, slow core (the same loads when the bench thread ran on a slow core) | 0.714 ms (RE1) | 0.790 ms | 0.826–0.837 ms | 0.905–0.916 ms |

| The weather step alone (10 lags, 20,000 calls) | each step (its lags) | a step with an hour crossed (a draw, the targets) |
|---|---|---|
| Laptop | 4.7 µs | 6.1 µs |
| Note 9, fast core | 10.4 µs | 15.6 µs |
| Note 9, slow core | 16.3–16.5 µs | 22.9–23.3 µs |

The Note 9 (2026-11-02, a test-signed release build of this branch, two runs of two loads each; evidence in
`~/kks-work/build/ag1wx1/` on the maintainer's laptop): as in RE1 the bench thread ran some loads on a slow core
(every figure of such a load about 1.6–2× its fast-core twin, the weather's timing with it), so the table keeps the two
apart. On the fast core, AG1's nodes and the weather at §11's size add 0.117 ms at 600 values and about 0.17 ms at
1,000, within the 0.4 ms share; RE1's shapes at 600 measured the same as in RE1 (0.498 ms). **The weather step meets
§11's ≤ 0.02 ms** in every step on both cores (10.4 and 16.4 µs); the step that crosses an hour (one in 6,000 at the
train's `day_scale`) takes 15.6 µs on the fast core and 23 µs on the slow one, so its mean over an hour stays under
0.02 ms. Its first version took 14.0 and 22 µs a step; hoisting the dictionary lookups out of the step and writing the
table lookup in place (the same comparisons and arithmetic; the vectors unchanged) gave these. The phone's battery was
at 29–35 °C over the runs.

### 2.13 HW1's details (settled 2026-11-03, before the code: the hands-on engine)

§2.3–§2.7 leave these open; settled here so both engines and the vectors follow one text.

- **The keys that gate it,** each alone: `tools.json`, a model's `hands` and `meters`, an op's `hart`, a scenario
  fault's `causes`, a work's `cures`, the task steps `tool` and `hand`, a `read` step's `via` and a `hand` step's
  `slip`. A plant without any of them steps, saves and digests as before.
- **`tools.json`** (format `walkdown-plant-tools`, version 1, only in a version 2 plant with staff.json: its places are
  the staff's): `tools`, 1–200 of `{"id", "title", "kind", "size", "modes", "at"}`; `kind` one of `spanner`, `socket`,
  `screwdriver`, `hex_key`, `pliers`, `stripper`, `crimper`, `torque`, `meter`, `communicator`, `calibrator`,
  `test_set`, `lifting`, `gas_detector` (the loop calibrator is a `calibrator`: a meter of its own kind); `title` 1–80 characters; `size` text
  of 1–16 characters; `modes` (1–16 identifiers of at most 16 characters) required on a `meter`, a `communicator` and
  a `calibrator`, and on no other kind; `at` 1–16 `[place, count]`, each place a `store` or the new place kind `toolbox`, once, the count a
  whole number 1–99. The counts per place (file order) and each person's `carried` (tool ids in the order taken, no
  tool twice, at most 12) are engine state, in saves and the digest.
- **Input** `[n, "tool", item, 0 | 1, person]` in step 1, at the person's place as the step before left it. Event
  `[n, "tool", item, 0 | 1, person, "done" | "refused" | "unknown", [reasons]]` (unknown: no such tool, or not 0 or
  1); reasons in order `authority` (no person, not a person, or not the input's player: §17.1), `where` (their place
  doesn't keep it), then taking `none_left`, `carried` (they have one), `full` (12 carried), putting back
  `not_carried`, then `busy` (the tool of their hand action under way: one tool does one job at a time). The NPC step `{"tool": [ids] | "off"}` acts in step 9, as `ppe` does, with the same events: each tool
  not yet carried taken in order, the first refusal fails the step to its `else`; `off` puts every carried tool back
  in order, and fails likewise. The trainee's step is done once they carry them all (`off`: none).
- **Hand actions** as §2.4, and: `tools` may be left out for a bare-hand action (the input's tool is then null);
  `wrong` names tools of tools.json that aren't in `tools`; `minutes` > 0 and ≤ 1440; `work` defaults to true;
  (kks, action) is unique; `component` must be in the part kind's tree (its Workshop data file's components, or
  `body` for a kind without one: WORKSHOP.md §4.1), refused `bad_ref`; a hand action's `set` and `input` are states
  that no op writes (a command, `locked_write`) and that carry no code of the isolation of a work on its code
  (`locked_write`). The engine writes them directly: no lock skips them. A hand action on a locked code is made (the
  job is done under its permit on isolated equipment).
- **Who:** a hand action names a person (null or no staff: `authority`), standing at the code's work place (`where`,
  §2.15). With `work: true` the person must be, for
  some work on that code whose permit is accepted (state 5), its acceptor, or another with `accept` and its
  discipline while the acceptor is off duty (§15.5); with `work: false`, `operate_local`.
- **The tool check:** the input's tool null when the action has `tools`, or a tool not carried: `tool`; a carried tool
  not in `tools` (or any tool for a bare-hand action): `wrong_tool` (the app shows `wrong`'s sentence for it, else a
  general one).
- **Minutes:** the action ends at the clock C + ⌈minutes × 600⌉ (clock tenths); the busy state is (code, action,
  tool, value, end, the person's place at the start). In step 3, after the renewals, each busy person in staff order:
  a step with a jump (§17.6) abandons it, so does the person no longer standing at that place (`leave`, `arrive`
  elsewhere, an NPC walking off); else, at C ≥ end, `set` and `input` are written and the event `done` made.
  Abandoning makes `[n, "hand", kks, action, tool, person, "abandoned", []]` and writes nothing. An NPC whose task is
  pre-empted (§17.3's pause), or whose task step is left any other way while the action is under way (a stop, a
  failure, the task ended), abandons it then, in step 9, with the same event; the action's end is handed only to the
  NPC step that waits on it. Who may is checked when the action starts (a permit suspended meanwhile doesn't stop it).
- **NPCs:** the `hand` step queues the input for the next step's step 1, as an op step does; `done` goes on, `start`
  waits for the end (the step is then not busy, so a higher priority task may pre-empt it), `abandoned`, `refused` or
  `unknown` fail to `else`. The trainee's `hand` step takes their `done` event; a `done` made before the step was
  current counts when the step comes if every state its `set` writes still has that value and its input the step's
  `value` (§17.8, the rule of 2026-10-23).
- **NPC slips:** only on a `hand` step: `"slip": {"per_mille": 1–1000, "set": {...}, "text"}`, the `set`'s states
  written by some hand action (component states). When an NPC's hand step is done, one draw r from the person's slip
  stream: a slip when (r × 1000) >> 24 < per_mille. The slip goes to the next step's step 1 as the NPC's input
  `("slip", person, task, step)`: its `set` written directly, event `[n, "slip", person, task, step]` (the app keeps it
  for the debrief). Players never slip.
- **Meters** as §2.5, with `needs` a list of 0–16 value names (a meter refuses nothing: it shows `else`), `value` a
  value name, `else` a value name or a number, `id` unique, `tool_kind` one of `meter`, `communicator`, `calibrator`,
  `mode` an identifier of at most 16 characters that some tool of that kind lists (lower case, as every identifier:
  `ma_dc`, `ma_clamp`, `hart` for §2.5's `mA_dc`, `A_ac_clamp`, `hart`). Shown: `value` when every need
  reads true as the step before left it, else `else`. A `read` step with `via` (a meter of its code; no show binding
  needed) takes the input `[n, "read", code, value, meter]`; a player without a carried tool of the meter's kind
  listing its mode makes `[n, "read", person, code, value, "tool"]` and the step waits; an NPC without one makes
  `[n, "read", person, code, null, "tool"]` and fails to `else`. Otherwise as S1's read against the meter's shown
  value. Like S1's, the read is matched in step 9.
- **HART:** `hart` joins `local` and `screen` in an op's `where` (version 2); such an op names `"hart": state`, the
  state that says a communicator is connected (made by a `connect_hart` hand action). Made with `where` `hart`, its
  authority is `operate_hart` (a new authority), and after `authority` comes the reason `hart`: the person carries no
  `communicator`, or the state reads false as the step before left it. Everything else is an op's, a locked code's
  refusal included (§15.1: a locked code refuses every op), except under the work's own accepted permit (§2.15).
- **Causes** as §2.6, with: 1–16 causes, ids unique in the fault, `weight` required (a whole number 0–65536 or a value
  name; the constants' total ≤ 65536), `set` required, `repair` optional, `text` 1–200 characters. A value weight is
  read as step 2 left it, rounded down, NaN or below 0 as 0, above 65536 as 65536. The draw: T the total, r the
  stream's next draw, y = (r × T) >> 24, the first cause whose running total exceeds y (T = 0: the first). The
  instructor's `[n, "fault", id, cause]` with a cause the fault lacks does nothing and makes no event. A repair writes
  the fault's `repair` and the cause's, and is not made if any of them would be skipped (§15.1).
- **Cures:** a work's `cures` (1–16 cause ids, unique) needs `repairs`; every scenario with that fault must give it
  those causes (`bad_ref`). Two works may repair one fault only when both have `cures` and no cause is in both
  (else `dup_id`). A work without `cures` cures every cause. A repair under its permit, or its `done`, whose work
  doesn't cure the applied cause writes neither repair and makes no `repair` event; everything else happens as for
  one that cures.
- **The digest** gains one part after the weather's, only in a run with any of the keys: the tools' counts (file
  order), each person's carried tools (as indexes in tools.json), each person's busy action or null, each cause
  stream's state and applied cause (faults with causes, in scenario order), and each person's slip stream state.
- **Snapshots** gain, with the same keys, `carried` (people with tools), `busy` and `causes` (applied faults' causes).

### 2.14 As built for milestone HW1 (2026-11-03: the hands-on engine)

- **Where:** `ref/plant3d_hands.py` (the reference: tools.json's check, the model's hands and meters, causes and
  cures, the step's pieces, the digest's part) with hooks in `ref/plant3d.py` and `ref/plant3d_staff.py`; the app's
  engine `apps/plant3d/sim/hands.gd` with hooks in `engine.gd`, `staff.gd` and the loader (`plant_model.gd`). Saves
  keep its state and check it (`ui/autosave.gd`), a session carries its inputs (`net/input_check.gd`).
- **Vectors:** `plant3d-realism.json`'s `hands`: the realism base's plant with tools.json (a toolbox and a store),
  the gauge's ten hand actions, five meters and a HART op, a fault with three hidden causes, two works curing
  different causes, an instrument technician's role and two people; 71 rejects and eight runs (tools carried, hand
  actions with every reason, meters and HART, a jump, an NPC's whole job with tools, permits, slips and readings, an
  NPC pre-empted, hidden causes with cures, a value weight). Tests: `tests/test_plant3d_realism.py` `HandsVectors`
  (each reason in order, the timed action's write in step 3, the draws against their streams, cures),
  `GdscriptRealism` (every value's bits and the digests in the GDScript engine, straight-line and interpreter),
  `apps/plant3d/tests/test_run_save.gd` (a save in the middle of an NPC's hand action goes on bit for bit; damaged
  hands-on state refused).
- **The byte check:** `plant3d-v1.json`, `plant3d-v2.json` and `plant3d-bench-v1.json` are what they were, and the
  realism file's `streams`, `staff`, `wear` and `weather` parts too.
- **The step's cost** (`realism_synth.py 600 --engine --hands`: RE1's 600 values, AG1's and WX1's engine nodes and
  weather, 150 hand actions writing the component states, 50 meters, tools.json at the store; `step_bench.gd`'s
  HANDS line times step 3's hands part alone with 12 actions under way in `shift_cold`, 20,000 calls): on the laptop
  (headless) the model step at base load 0.245 ms as built, 0.272 ms with `--engine`, 0.273 ms with `--hands` too:
  the hand actions and meters add nothing to a step with no action under way (they are entries, not nodes); the
  hands part with 12 actions under way is timed by the HANDS line (figures follow with the Note 9 run).
- **From the reviews:** an idle task has no hand step (it isn't paused when a player takes the person); a cause's
  `repair` needs the fault's own and writes no command its work's isolation locks; a save is refused when its tools
  don't add up to tools.json's or its NPC inputs name no person or slip. Not changed: the digest keeps no task
  step's own progress (a waiting `hw`, as an op step's `busy`), as §17.14 says.
- **Left open on purpose (a question for the user):** §15.1's "a locked code refuses every op" holds for HART ops,
  so a transmitter isolated by a lock on its own code can't be ranged or trimmed through the communicator until it
  is unlocked; hand actions are made on a locked code (the job's own work). Settled by the user on 2026-11-03: §2.15.

### 2.15 After HW1 (2026-11-03): HART under the work's own permit, hand actions at the equipment

- **A HART op on a locked code** (the user's decision, 2026-11-03) is made when it is made under the work's own
  accepted permit for that equipment: a work on that code whose permit is accepted (state 5), which holds every
  isolation with a locked point on the code, and under which the person acts (its acceptor, or another with `accept`
  and the work's discipline while the acceptor is off duty: the rule of a hand action's `work: true`, §2.13). Its
  writes are then made as that work's own `done` writes are (§15.1: not skipped by the locks its work holds). Any
  other op on a locked code, and a HART op otherwise (no permit, a permit issued but not yet accepted, another work's
  accepted permit, another person's, after the work's `done`), is refused `<isolation>_locked` as before. Under
  the permit the locks are not named, whatever else refuses it (`hart`, `authority`, a need). A trip's `reset` is not
  made this way (§15.1: it waits for the isolation's removal), and an op naming no person is never under a permit. A machine command made
  this way enters its new state as a command (the machine's own writes stay skipped on the locked code). Both
  engines: `ref/plant3d_hands.py` `hart_permit`, `apps/plant3d/sim/hands.gd` `hart_permit`, called from the op.
- **A hand action is made at the equipment** (found by HW1's blind review): the person must stand at a work place
  of the code (any `work` place in staff.json naming it), else the reason `where`, right after `authority`. This is
  stricter than an op or a lock, whose reach the app checks for the trainee (§17.1): the engine knows places, not
  distances, and a hand action's work place is what it can check. An NPC's `hand` step first walks to the code's
  work place (the first, as `go {"kks"}`), as a `lock` step walks to its point's; the validator refuses a `hand`
  step on a code without a work place (`bad_ref`).
- **Vectors:** `hands` gains a run (the HART op made with the code unlocked, refused with no permit, before the
  accept and under another work's accepted permit, made under the work's own, refused by another person, made
  locally and after the `done`), a run of the NPC's job that goes back to the toolbox after the permit (its first
  hand step walks to the gauge), a run with none of HW1's keys (no tools.json: a run's `files` entry null leaves
  a file of its part out; the HART op under the permit refused `hart` alone, as the app's engine now builds its
  works per code in every run) and a reject (a hand step on a code without a work place); a reference test checks
  the acceptor rule (another acceptor on duty: refused; off duty: made). Two runs changed with
  the place rule: the hand actions' run (the trainee walks from the toolbox to the gauge before acting, so a first
  action at the toolbox is refused `where`; its last HART op, under the trainee's accepted permit, is now made) and
  the jump's (the trainee stands at the gauge). Every other item of the file is what it was (a JSON comparison).

## 3. Hands-on work and tools

### 3.1 What the trainee does

A job starts from a work order (§7) and a permit (§15) and is done at the equipment. Example, the condenser pressure
transmitter reads low against its two partners (an I&C technician's day):
1. Read the work order, the transmitter's manual (§6.2: its troubleshooting table) and the P&ID (§6.1: the
   transmitter, its manifold and its junction box). Do the JSA (§8.1).
2. Take the tools from the I&C workshop's toolbox: a screwdriver set, the HART communicator, a multimeter, a 17 mm
   spanner for the manifold; the permit is issued and accepted; the transmitter is isolated at its root valve (kind `instrument`; the
   manifold's valves are the job's own hand states, so the tests of step 6 can work them), and the control room has
   put the loop in manual.
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
`pick` to accept or send back) and sign off. NPCs make the mistakes people make: a task step may carry `"slip":
{"per_mille": n, "set": {...}, "text"}`, drawn from the person's slip stream (§2.1) when the step is done (a wire on
the wrong terminal, a flange bolt left finger-tight), so a hold point has something to find. A slip's `set` writes
component states only.

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

- A part removed in a job can be opened in the Workshop mode, writable for the removed part only: a realism addition
  (HW3) beside the Workshop's read-only way in from the plant (its K6), using the damaged states of §2.4's service
  data: its component states and the hidden cause show there (a torn diaphragm, a blocked
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
- **Repairs** by works whose `renews` list the item (§2.2); a work that greases a bearing lowers its rate (a
  lubrication state), not its wear.
- **Spontaneous trips** of instruments and electrical parts (a power supply, a relay) with no wear sign are seeded
  hazards: a `draw` time per item (an exponential's inverse table) against the
  item's running clock hours (a `wear` node of running time).

### 4.3 Time

A run lasts hours of model time; real wear takes months. So:
- **The plant's age** (`world.age`, read by the content tools only): the scenario's `init` starts each item at a wear
  the content tool computes from "months
  since overhaul" by duty (so a trainer picks "6 months after the outage").
- **`age_rate`** (an `ext` value): 1 is real time on the plant clock; training scenarios use a rate at which an item
  near the end of its life shows its signs within a shift. The scenario says which (the user, 2026-11-01: a training
  rate per scenario by default, real rates available; the trainee doesn't pick it). A trainee is never told a failure
  is coming; the signs are there for whoever looks.

### 4.4 Maps onto

Values, faults and works; findings (§17.12: a reading out of range given to the supervisor); trends (screens.json's
`trend`); the condition monitoring jobs of §9.3; work orders (§7). No new step kind.

## 5. Weather

### 5.1 The weather step

- **`data/plant3d/weather.json`** (format `walkdown-plant-weather`): weather **kinds** (`clear`, `hot`,
  `dust_haze`, `sandstorm`, `rain`, `thunderstorm`, `cold_clear`, `fog`), **seasons** with the days of the year they
  cover (day of year = (`world.year_day` − 1 + `world_day` − 1) mod 365 + 1), per season a transition table per
  clock hour (`[[from, to, weight], …]`, whole weights, each row's total ≤ 2¹⁶), and per kind and `ext` value a
  diurnal table over `world_hour` with a lag `tau` in clock minutes (the factor 1 − e^(−0.1 × `day_scale` / (60 ×
  tau)) computed once).
- **Step 1w** (after step 1's inputs, before step 2), with weather on: at each step in which the clock passes a whole
  hour, one draw from the weather stream picks the next kind from the current kind's row (event `[n, "weather", from,
  to]` when it changes). Then each `ext` value it drives moves toward its target (its kind's table at `world_hour`) by
  a first-order lag (the factor computed once, as §7.1's), and `world_wx` holds the kind's index. A jump draws once per
  hour crossed, in order, and sets the ext values to their targets (the night passed, §17.6).
- **The ext values** the weather drives: `ambient_t`, `ambient_wb`, `ambient_rh`, `wind` (m/s), `rain` (mm/h),
  `dust` (mg/m³), `visibility` (m), `solar` (W/m²), `lightning` (0/1). They are declared in plant.json's `ext` (the
  content milestone WX2 adds them, and every scenario then sets them as §7.8 says; with weather on, the scenario's
  values are their step 0 values and the weather moves them).
- `world.weather`: `{"season": id}` (seeded), `{"fixed": kind}`, or `{"script": [[day, "HH:MM", kind], …]}` for a
  trainer's day. **Free play has weather on** (the user, 2026-11-01): its scenario carries `{"season": id}` for the
  season of its `year_day`, so the hot dry climate below plays out from the world seed; a scenario that needs clear
  skies says `{"fixed": "clear"}`. The instructor's input `[n, "weather", kind]` (its `instructor` event).
- **Climate:** the generic site is a hot desert plain (SITE.md): long hot dry summers with dust and sandstorms on the
  north-westerly wind, short mild winters with a few rain days, thunderstorms in spring and autumn, rare frost on
  winter nights. Tables from public regional climate data ([WBCCKP]) and WMO's definitions ([WMO]: a
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
| Heat on electrical plant | transformers' and the generator's cooling and loading limits fall with ambient temperature (derating tables); an electronic room whose air conditioning fails heats its cabinets, and electronics' faults follow their temperature | [IEC60076-7], [NFPA850] |
| Lightning | a lightning arrester's counter; a seeded nuisance trip of an exposed instrument loop | [NFPA850] |

### 5.3 What it does to people (staff content and two engine rules)

- **Outdoor work stops** when the weather says so: lifting with the crane or the roof hoist above the crane's wind
  limit, work at height in high wind or lightning, hot work in a sandstorm. The work's `needs` and the task's `wait
  until` read the weather values (no new engine rule); the permit form shows why.
- **Heat stress** (an engine rule, §8.4): WBGT from `ambient_t`, `ambient_wb` and `solar`, work and rest by the
  person's work rate ([ISO7243], [ACGIH]).
- **Slippery stairs and walkways** in rain: zones with `"wet_when": value` (wet stairs) where running is an unsafe act (the app sends the
  trainee's pace as `[n, "pace", "walk" | "run"]` when it changes; NPCs never run). Way times don't change: the walking
  network's times stay fixed (§16.2).
- **Sandstorm PPE:** goggles and dust masks in outdoor zones while `dust` is above a level (zones' PPE as a value:
  `"ppe_when": [[value, [items]]]`, an engine addition read where §16.7 reads a zone's PPE).
- **Visibility:** driving on site stops below a visibility: a vehicle's run gains `"needs": value` (an engine
  addition to §16.8: a run whose value is false at its departure waits, checked each step; riders at its stops keep
  their 30-minute walk rule). The lift's wind limit is its content's permissive (§20).
- **Gating:** `ppe_when` and `wet_when` on zones and the heat rule (roles' `work_rate`) are each off unless their key
  is in the content; the heat rule needs `world.weather` too.

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

### 5.5 As built for milestone WX3 (2026-11-02: the weather seen and heard)

- **The first train's weather** (`data/plant3d/weather.json`): the eight kinds of §5.1 and four seasons (winter days
  335–59, spring 60–151, summer 152–273, autumn 274–334) with hourly rows that keep a kind for hours (a sandstorm
  ends with odds of about one in five an hour; summer has no rain, winter its rain, fog and cold nights, spring and
  autumn the thunderstorms). It drives only what is drawn: `wind` (m/s), `rain` (mm/h), `dust` (mg/m³),
  `visibility` (m: under 1 km in a sandstorm, as [WMO]), `solar` (W/m²), `lightning` (0–1) and **`wet`** (0–1, added
  here: how wet surfaces under the sky are, a 25-minute lag, so they dry after the rain). They are new `ext` values of
  plant.json that every scenario sets (clear-weather values); `ambient_t`, `ambient_wb` and the plant's reactions stay
  WX2's, so the weather changes nothing the model computes. **Free play's weather:** the two version 2 scenarios
  (`shift_cold`, a summer day, year day 196; `shift_wtp`, a spring day, year day 100) carry `{"season": id}`; the
  version 1 scenarios can't carry `world` and stay clear (until 2026-11-03: §5.6). `plant3d-v1.json` and `-v2.json`
  were regenerated: the new values added, every earlier value the same.
- **Drawn** (`app/weather_view.gd`), every frame from the model's values eased over 2 s (the model's lags already take
  minutes), so every peer stepping the same run sees the same weather:
  - the depth fog's density 3 / `visibility` (5 % of the light through at the model's visibility), never thinner
    than the clear haze; its colour toward sand with `dust`, grey with `rain`, a pale mist when the view is short
    without either; its sky affect washes the photographed sky toward it below 8 km (no sky shader, nothing
    reprocessed);
  - the sun's energy by `solar` against the clear kind's at the hour (taken `solar`'s lag earlier, as the model's
    lagged value runs behind its table), blended toward a value from the view while the clear sky's sun is low (the
    app's sun stays where the photographed sky's is): no jump at dawn or dusk; its shadows softer under cloud; a
    lightning flash adds light for 0.15 s;
  - one GPUParticles3D round the camera (the phone 2,000 within 25 m, the full tier 8,000 within 40 m: §11), its
    share of them (`amount_ratio`) by how hard it rains (10 mm/h is all) or how much sand blows (dust 1–6 mg/m³),
    rain streaks falling with the wind's push or sand specks along the north-westerly wind; a particle that leaves
    the box re-enters at its other side, and one under a roof is not drawn;
  - **the roof map:** the build rasterises every building's and canopy's plan at half a metre into an R8 texture of
    the roof's height (quarter metres), `built/roof_map.res`, named in the build's manifest; the particles and the
    weathered shader read it as a global parameter;
  - **wet and dusty surfaces:** global parameters of the one weathered shader (`wx_wet`, `wx_dust`, `wx_rain`,
    `wx_roof`, `wx_roof_rect`): under the sky, wet darkens and glosses what faces up (a little the walls), with
    puddles in the ground's low patches and drops' rings on them (full tier only); laid dust (from `dust`, after a
    storm's dust while it settles, gone where wet) pales flat tops; the roof map is read 0.3 m along the surface's
    normal, so a wall's outer face is outdoors and its inner face indoors. The Workshop's bench (its own world, the
    same materials) gets none of it. Uniforms only: no new variant.
  - **Heat shimmer** is left out (screen-space, as 0057 left those).
- **Heard** (ui/sound_player.gd, three new sounds of the synth library, decision 0055): `rain` (loop, also heard on
  the roofs indoors at 0.35), `sand_hiss` (loop, in gusts), `thunder` (a one-shot rumble played after the flash,
  delayed by the strike's distance at 343 m/s and quieter with it, at most three on their way); the wind's existing
  loop follows `wind` (as loud as before at the clear kind's 2 m/s, about +5 dB in a sandstorm).
- **Lightning flashes** fall in 2-second slots of the model's steps: at a slot's first step (the clock's `stepped`,
  with the engine bound as soon as the clock takes it, so a session's catch-up steps count) the slot flashes when a
  32-bit mix of the world seed and the slot's number is under the model's `lightning` there × 0.08, at a step and a
  distance (0.4–6 km) taken from the same number: the same on every device, never this device's random numbers or
  eased values.
- **The instructor's panel** has a button per kind in a scenario with weather (the WX1 input `[n, "weather", kind]`).
- **Measured on the Note 9** (2026-11-02; test-signed release builds without the lightmap's bake, as S4's and DC1's
  walks; the frames walk among the crews, `crews=1`, 600 s, first starts, `SAMPLE=1`; evidence in
  `~/kks-work/build/wx3/` and the worktree's `results/` on the maintainer's laptop):

  | Run (battery at start) | Mean frame | At 60 fps | At ≥ 30 fps | GPU median / p95 | Over 100 ms (the app's) |
  |---|---|---|---|---|---|
  | main, 240 s, warm (31.5 °C; pipelines only, not judged) | 26.61 ms | 48.45 % | 99.11 % | 19.9 / 26.4 ms | 0 |
  | clear 2 (28.3 °C) | 25.70 ms | 49.25 % | 99.10 % | 19.7 / 26.0 ms | 0 |
  | clear 3 (29.3 °C) | 26.63 ms | 44.60 % | 98.36 % | 20.9 / 28.1 ms | 0 |
  | sandstorm 1 (25.1 °C) | 25.94 ms | 48.10 % | 98.87 % | 20.0 / 26.4 ms | 0 |
  | sandstorm 2 (29.6 °C) | 28.45 ms | 37.20 % | 95.14 % | 22.6 / 30.2 ms | 0 |

  The frame rule (no frame over 100 ms the app causes after the first 5 s) passes in every run. The sandstorm's GPU
  median against clear weather: +1.0 ms on the means of the two runs each (20.3 and 21.3 ms), +1.7 ms between the
  two warmest runs (29.3 and 29.6 °C), within §11's +2 ms; the phone's own spread between two runs of the same
  weather is as large (1.2 ms clear, 2.6 ms sandstorm). The first clear run did not start (the phone left adb as it
  began) and was walked again. The first frame's pipelines: main 12
  surface + 7 specialization, WX3 13 + 8 (the particles' draw pipeline; the process shader's compute pipeline is not
  in Godot's counts), compiled in the hidden frame; one pipeline compiled later in every walk, at the WTP (500 s in,
  a 15 ms frame), in clear weather too. First frame 10.2–11.5 s from launch, peak PSS 848–868 MB. Package: the APK
  121.0 MB of 250, +0.30 MB against main (the three sounds, the roof map, the scripts and shaders).
- **Measuring:** `weather=KIND` (app/main.gd, with `crews=1`) fixes the scenario's weather at that kind and its driven
  values at the kind's targets for the start hour, for the rest of that process (a restart into it too); ignored with
  `mp=`. Free play's seeded scenarios start from clear-weather values while their season's chain starts at its
  `start` kind (summer's `hot`): the values lag toward it from step 0.

### 5.6 Every scenario with its season's weather (2026-11-03)

The user (2026-11-03): the five scenarios that were format 1 (`cold_iron`, `hot_restart`, `wtp_cold`, `wtp_normal`,
`wtp_flood`) are made version 2 so that the weather, and the realism pieces after it, work in them; free play's
weather on, seeded by season.
- **The content** (`tools/plant3d/train_content.py`, `train_weather.FREE_PLAY`): each is `"version": 2` with
  `"world": {"year_day", "weather": {"season"}}` as its last key and nothing else new: no `start` (the clock starts at
  plant.json's, day 1 06:00, as before), no `staff` (no people, as before). Each takes the
  season of its crews' twin: `cold_iron` and `hot_restart` as `shift_cold` (summer, year day 196); the WTP's three as
  `shift_wtp` (spring, year day 100). **A world seed each** (the user, 2026-11-03, after #315 had left them all at the
  default 1, so the twins of one season drew the same weather): `"seed"` first in `world`, `cold_iron` 101,
  `hot_restart` 102, `wtp_cold` 103, `wtp_normal` 104, `wtp_flood` 105 (`train_weather.SEEDS`); `shift_cold` and
  `shift_wtp` keep their staff seeds (2 and 3) as the world's. Nothing in the first train's content draws from the
  world seed but the weather (no `draw` node, no seeded fault), so only the weather moved. Format 1
  itself, its validator rules and `plant3d-v1.json`'s synthetic parts are unchanged (its `about` still says "format 1
  vectors": its `train` and `hot` have run version 2 content since P1).
- **The vectors** (made again, then compared by JSON with main's): nothing moved between files. `plant3d-v1.json`'s
  `train` (cold_iron) and `hot` (hot_restart) stay where they are, as P1 left them following the first train's
  content (PLANT3D.md §19); `plant3d-v2.json`'s `wtp` (wtp_cold), `wtp_cip` and `wtp_regen` (wtp_normal) likewise.
  In those five runs every input, event and fork is the same and every value the same but the weather's: each
  snapshot gains `world_hour`, `world_day` and `world_wx`, and the driven values follow the season's kind instead of
  holding the clear values: in the summer runs `wind`, `solar`, `visibility` and `dust` (toward `hot`), in the spring
  runs `wind` and `solar` (spring starts at `clear`, whose other targets are the clear values); `rain`, `lightning` and
  `wet` stay 0. No run crosses a change
  of kind, so no `weather` event is added. Nothing the model computes reads the weather (§5.5), so no model value
  moved. **With the seeds of their own** (made again and compared by JSON with main's after #315, `weather` events
  set aside): every input, event, fork and model value the same; `train` (cold_iron, seed 101) and `hot`
  (hot_restart, 102) and `wtp` (wtp_cold, 103) the same values too (their seasons' first kind holds through each
  run), the summer chain changing to `dust_haze` at step 72,000 in nine of `train`'s forks that run past it (a
  `weather` event each; a fork's `end` holds no driven value); `wtp_cip` and `wtp_regen` (wtp_normal, 104) change to `dust_haze` at step
  12,000 (one `weather` event, `world_wx`, `wind`, `solar`, `visibility` and `dust` after it), as does
  `plant3d-v2.json`'s `train` fork that runs past it (fork 9; its forks carry no snapshot values). Since #315 too,
  `plant3d-v2.json`'s `staff`, `day` and every synthetic item, and `plant3d-realism.json`, are byte for byte main's.
- **What depends on it:** the app lists the same scenarios (by id; none gained `staff`, so none is offered as a crews'
  shift); a save or session snapshot of a run made before is refused as "content has changed" (the content's hash,
  `ui/run_save.gd`), as after any content change, and a session's players must share the content's hash; procedures,
  tours and links name the scenarios by id, unchanged. The app's test of a plant without weather (`test_weather.gd`)
  now makes such a scenario (cold_iron without `world`) instead of starting cold_iron. cold_iron is the app's default
  scenario, so a plain launch, the step bench's loads (`app/step_bench.gd`: the train as built and RE1's shapes
  without `--engine` now both carry the built weather's seven values, and print its `WEATHER` line) and a phone walk
  started in it would run summer's `hot` weather (a little dust and haze, a 12 km view) where earlier ones ran none.
  **So measured runs pin clear weather** (the user, 2026-11-03; MILESTONES' measurement rules): a walk or shot (`walk=…`, `shot=…`,
  `phone/frames.sh`, which writes `weather=clear` into walk.txt) and the step bench (`step=bench`,
  `sim/tests/bench_realism.gd`; its `STEP … weather=` field) run `weather=clear` unless they name another kind
  (`app/main.gd` `measured_weather`; not with `mp=`, where the host's weather rules); the step bench's `--engine`
  loads keep their own seeded weather (their hourly draws are what they measure: the built and plain loads' `WEATHER`
  lines time the fixed kind's step, so §11's 0.02 ms for a draw an hour is judged on the `--engine` load). The phone's
  view shots (`shot=`, `phone/shots.sh`, a GPU time per view) are measurements too and pin clear the same way.
  Free play keeps the season's weather.
  Figures measured before compare with these clear-weather runs (§5.5 measured the weather's own cost).

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
- **In Walkdown Plant only** (the user, 2026-11-01): the sheets are not exported for `kks-import` or Walkdown.

#### 6.1.1 DC1's details (settled 2026-11-02, before the code)

Nothing here comes from a real plant's drawings: the sheets are made from the content alone, with the symbols of the
public standards. No new dependency (decision 0073 already chose our own format drawn by the app).

- **The set.** A1 landscape sheets (841 × 594 mm) in an ISO 5457 frame (20 mm filing margin on the left, 10 mm on
  the other sides) with a title block in the bottom right corner after ISO 7200 (the plant's title, the sheet's
  title, its number `WDP-PID-NNN`, revision, sheet n of m, "generated from the content", "not to scale"). Sheet 001
  is the **legend**: every symbol used, the line types, the ISA letters and how a KKS code reads. Then a sheet per
  process area or group of systems, as the tool lists them: gas turbine 1; HRSG 1; the steam turbine and condenser;
  circulating water and the cooling tower; the auxiliaries; the raw water intake; the water treatment plant in three
  (pretreatment and filtered water; reverse osmosis and demineralisation; chemicals, sludge and waste water).
- **What is drawn.** Every equipment item, inline valve and instrument, equipment-mounted instrument and pipe of those
  areas, except what a P&ID does not show by ISO 10628 practice: electrical equipment (breakers, transformers,
  switchgear, excitation cabinets, the static frequency converter), control desks, and lifting gear (hoists, the
  crane, the lift and its gates and calls). Those keep their cards, without a drawing. The tool checks that every
  other code of the model has exactly one **home** hot spot (the place the card's Drawing button opens).
- **Symbols** after ISO 10628-2 (equipment, valves) and ISA-5.1 (instruments), drawn by functions of the tool, one per
  kit part kind (a test fails for a shown part kind without one). Instruments: a field-mounted bubble (no bar), with
  the first letter from the code's measurement letters (CP P, CT T, CL L, CF F, CS S, CY V, CG Z, CB B, CQ A, CW W)
  and the succeeding letters from the part (transmitter T, element E, gauge I, glass G, analyser IT, test point P),
  and the whole KKS code under the letters: a stadium (two half circles joined), since a KKS code is longer than
  ISA's loop number. Drawn uppercase in a single-stroke lettering of our own after ISO 3098 type B (monospace;
  2.5 mm for tags, 3.5 for equipment names, 5 and 7 for titles).
- **Lines.** Process 0.5 mm, DN 300 and over 0.7 mm, instrument process connections 0.25 mm solid; a flow arrow on
  each pipe; a pipe's label is its code, `DN` size and medium. Where two pipes cross, the later one is broken.
- **Layout** (automatic, checked). Flow left to right: equipment in columns by the longest path along the pipes
  (from → to; a cycle broken at its pipe whose source comes later in code order); families (codes differing only in
  their last digits, same part) stacked; equipment with no pipe in rows below. Instruments in a grid above their
  equipment. Pipes routed orthogonally on a 2.5 mm grid round symbols and text (A*, with costs for bends and
  crossings); inline items in their `at` order on the pipe's straight runs; pipe-to-pipe ends as tees; an open end
  ends in an arrow with its medium's name; an end on another sheet in an off-sheet connector (an arrow pentagon)
  naming that sheet and the code at the far end, which the viewer opens when tapped. The tool fails the content check
  if two symbols overlap, a text overlaps another text, a symbol or a line, a code has no home or two, or a character
  is outside the lettering; its output is the same on every run (tested).
- **Format** `walkdown-plant-drawing` version 1, a file per sheet, made by `tools/plant3d/pid.py` at every build of
  the app into `apps/plant3d/built/drawings/` (a view of the content, never committed: the reference validator's
  file list stays the plant format's), and an index `index.json` (`walkdown-plant-drawings`: the sheets in order, each code's home sheet, and the lettering's
  strokes). A sheet holds, in sheet millimetres with y down: `lines` (`[width, dash, [x, y, …]]`, dash 0 for a solid
  line), `circles` (`[width, x, y, r]`), `fills` (closed polygons), `texts` (`[x, y, height, angle, align,
  text]`), `spots` (`[code, x0, y0, x1, y1, home]`), `links` (`[sheet, code, x0, y0, x1, y1]`: the off-sheet
  connectors), `revisions` (`[rev, text]`, the table) and `clouds` (`[rev, x0, y0, x1, y1]`).
- **Revisions.** The shipped sheets are revision 0 ("first issue, generated from the content"). The tool's `revise`
  makes a later revision from changed content with the same generator, every equipment block kept where the
  revision before had it (only what changed moves; a sheet where that no longer fits is laid out afresh): a row in
  the table, and a cloud round every hot spot that is new, gone or moved. DC1 builds and tests that on a synthetic change; EN2's change objects (§10.2) use it.
- **The viewer** (`ui/drawing_view.gd`): full screen, as the control room's screens, with the 3D view off
  (`disable_3d`). A sheet list with Previous and Next above the sheet; drag, the arrows, the D-pad or the left stick
  pan, pinch, the wheel, the triggers and + and − zoom;
  a tap on a hot spot opens the card beside the sheet, a tap on a connector the other sheet at that code; the card's
  **Drawing** button opens the code's home sheet with the code centred and outlined. Opened from the bar
  ("Drawings") and from cards. Levels of detail: three canvas items per sheet, each recorded once when first needed
  (far: one-pixel lines, text of 5 mm and over; middle: one-pixel lines and all text; near: line widths in
  millimetres), the lettering expanded into their line lists; panning and zooming only change their transform.
  A walk option `walk=drawings` opens each sheet in turn and pans and zooms it, for the Note 9's measurement.
- **Budgets** (§11): a sheet opens in ≤ 300 ms on the Note 9, ≤ 40 MB more with the sheets open, the frame rules
  while panning and zooming; DC1's share of the programme's 15 MB of package measured.

#### 6.1.2 As built for milestone DC1 (2026-11-02)

- **The set:** ten sheets (the legend, GT 1, HRSG 1, the steam turbine, CW and the cooling tower, the auxiliaries, the
  intake, three for the WTP), every drawn code once at home; about 250 KB of JSON made in 2–5 s at every build. The
  tool's checks work on the exact geometry: symbols apart; texts clear of other texts and of other owners' lines,
  symbols, circles and filled shapes (and of their own pipe); no line through another owner's symbol (a pipe through
  its own inline items, and a line ending on a symbol, are joints); no two owners' lines along each other; a flow
  arrow on every pipe. A sheet that fails is laid out again with other spacings before the build fails.
- **Layout as built** adds to §6.1.1: an open end whose other end is on a symbol ends just beside it (arrow and
  medium's name) instead of at the margin; each pipe end keeps a straight approach as long as its inline items need,
  reserved before any pipe is routed; a label that fits nowhere on its pipe goes to the nearest free place with a
  leader; a symbol with several pipes on one side is drawn tall enough for them 5 mm apart (round ones keep their size).
- **The viewer as built:** the levels switch at 2.6 and 6 px/mm (below 2.6 the 2.5 mm text is under 6.5 px); at
  most three sheets kept drawn. Measured: the laptop (Iris Xe) median frame 4.1 ms, a level made in ≤ 6.1 ms; the
  Note 9 (`walk=drawings`, 200 s, every sheet panned and zoomed from the whole sheet to 10 px/mm): median 16.7 ms,
  p95 19.2 ms, longest 39.6 ms, none over 100 ms; the screen showed 98.8 % of frames at 60 fps and 99.97 % at
  ≥ 30 fps (the three long gaps it saw are the app's start, before the walk); a sheet's first level ready in ≤ 3.2 ms
  and any level made in ≤ 20.8 ms (budget 300 ms); peak PSS 1,036 MB. Package: +84 KB compressed for the sheets and
  about 19 KB for the viewer's scripts, of the programme's 15 MB (the APK 143.4 MB of 250).
- **Not in DC1:** revisions made by change objects (EN2 calls `revise`); manuals (DC2).

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
- **Engine:** a new task step `{"discuss": id}` that holds the participants at a `meet` (§16.6). When it starts, if
  no slot's person is a participant, every point takes its `default` and the discussion ends after its clock minutes:
  a discussion between NPCs ends the same way every time. Otherwise each point waits for a `pick` from a slot whose
  person is a participant (the first in the commit's order counts; others' are refused, `state`), at most the point's
  clock minutes, then takes its `default`. All of it is state, so every player agrees. The outcome runs as `choose` does (its task in place of the
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
- **Engine:** in a model with work orders the limit of 128 works rises to 512 (renewals, commissioning, outage
  packages and changes' implementations are works written in advance; a notification is matched to its work by the
  finding's code and kind). Works (§15.2) gain `wo` states as model values (`<work>_wo`: 1 notified … 6 closed) moved by inputs
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
- Waiting days: a job held for a part sits in the backlog; the trainee may jump days: `[n, "jump", "HH:MM", days]`
  goes to that clock time `days` days after its next occurrence (0 to 30), under §17.6's rules as amended in §7.4.
  Wear ages across it (§2.2).

### 7.3 Shift handover and logbooks

- **Logbooks** per post (control room, field, electrical, WTP, maintenance): entries as inputs `[n, "log", book, kind,
  refs, text]` (kind: event, equipment status, instruction, permit, abnormal; refs: codes, works, alarms; text up to 500
  characters). NPCs write entries from their tasks' events.
- **Handover:** the incoming person reads the log and the outgoing person's handover sheet: open permits, isolated
  equipment, shelved and suppressed alarms, equipment out of service, abnormal values, jobs in progress, instructions.
  The engine knows each fact; a trainee who takes over ticks what they were told, a trainee who hands over picks what
  to pass on: input `[n, "handover_check", "given" | "taken", [facts], person]`, facts named by kind and id (`permit`
  and a work, `alarm` and an alarm, `out` and a code). The debrief lists what was missed ("PTW-0012 open with the pump locked out was not handed over").
  Source: [HSG48] on shift handover as a known factor in accidents, [CCPS] guidance.

### 7.4 Planning a major outage

- An **outage plan**: the works of a scheduled outage (from the plant's age and the wear items, an inspection list
  after [GER3620]: combustion and hot gas path inspections as work packages), each with duration, crafts and crew
  sizes, permits and isolations, spares and lead times, cranes, scaffolds. The trainee orders and schedules them on a
  Gantt; the tool shows the critical path and conflicts (two works on one isolation, the crane wanted twice, a
  confined space and hot work in one place).
- **Engine:** the plan is submitted as `[n, "plan", plan id, [[work, role, day, "HH:MM"], …], person]`, which adds
  slots to the people of those roles (as routines' slots, §16.5). The outage then runs with jumps between shifts.
  **Jumps with permits open:** in a scenario with `world`, §17.6's rule becomes: a jump is refused while a permit is
  `issued` or `accepted` and its task is not held for the next duty (§17.10), or while anyone is in a hand action;
  permits requested, approved, isolated, done or returned, and held jobs, don't block, and held jobs' locks stay on
  through the gap (§17.10);
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
| Switching programme | writes (orders from a list) and checks a switching programme for taking a motor feeder or a transformer out, then carries it out with a second person checking each step | switchgear ops with interlocks as permissives; the query `switch_effects(list)` makes the list's ops one per step in a copy of the run, then 100 steps, against a copy without them (as §15.6's `lock_effects`), and says what would trip or lose supply | [HSG253], [IEC61936] |
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
  rationalisation change it: read as step 2 left it, rounded to the nearest whole number and clamped to 1–3; a change
  while the alarm is active changes its colour and counts, never its state (no new horn). Reactions, fast-forward and
  §15.6 read the priority in force.
- **Into the next run:** a run's implemented changes are listed in its save; a new run may start with them
  (`world.changes`), whose implemented states the engine sets at step 0, so the next run's alarms show the effect.
- **Drawings:** the P&ID generator makes, in advance, the revised sheets of each change object that alters what a
  drawing shows; the viewer shows the revision whose change is implemented.
- Source: [MOC] (CCPS), [OSHA119] (l).

### 10.3 Alarm management

- From the run's events: alarms per operator per 10 minutes, floods (more than 10 in 10 minutes), standing alarms,
  chattering alarms, the top ten "bad actors", shelved alarms and for how long; against [EEMUA191] and [ISA182]'s
  benchmarks. Shown in the debrief and a control room screen.
- Rationalisation: the trainee proposes a change (§10.2: priority, limit, deadband as the
  `clear` value of a limit state, suppression by plant state; an alarm's `delay` stays content) with
  its reason; implemented, the next run's alarm rates show the effect.

### 10.4 Emissions reporting

- The GT's model gains NOx, CO and O₂ at the stack as tables of load, ambient temperature and the combustion mode (lean
  premix above a load, diffusion below), and a CEMS (continuous emissions monitoring) with its analysers: drift, a
  daily zero and span check with calibration gases (an I&C job), a failed analyser's substitute data.
- Hourly and daily averages corrected to 15 % O₂ (`wear` nodes as clock accumulators reset on the hour's change,
  `hold` nodes keeping the last hour's result, §2.1–§2.2), limits from a generic
  regulatory frame: the IFC / World Bank Group EHS guidelines for thermal power plants ([IFC-EHS]; the user,
  2026-11-01: their limits for combustion turbines on natural gas and their fuel-oil alternative), an exceedance report
  and the operators' response (load change, combustion mode).

### 10.5 The chemistry lab and sampling

- The HRSG's cycle chemistry: the sample panel's analysers (specific and cation conductivity, pH, sodium, silica,
  dissolved oxygen, phosphate where dosed) and grab samples analysed in the lab with their methods' times, against
  normal and action levels after the IAPWS technical guidance ([IAPWS-TGD]); dosing (ammonia, phosphate) and
  blowdown as ops; a condenser tube leak as a fault with its signs (cation conductivity and sodium rising).
- Builds on S3's chemists and samples (§17.12) and the WTP.

## J. The rest of the job (the user, 2026-11-01)

The user added every other part of the plant's work they listed: operations, electrical, I&C, mechanical, HSE and
environment, chemistry, stores and planning, people and administration. They are numbered J1–J8 here so that they
can't be confused with PLANT3D.md's §15–§21, which this file cites by bare number. Each item names what the trainee
does, how it maps onto the engine and the content, its public source (§14) and its milestone (MILESTONES.md). The R6
rule holds for all of them. Like everything here, it is generic: a typical combined-cycle plant's equipment as the
sources describe it, never a real plant's.

### J0. What the engine gains, and what it costs

Most items are content (model values, ops, faults, works, tasks), staff content or views. Ten are small engine
additions, each gated by its own key so a plant or scenario without it steps exactly as before, each with its items
in `plant3d-realism.json` and in both engines bit for bit:
- **Grid events** (OP1, key `world.grid`): `grid.json` (format `walkdown-plant-grid`) gives events (a load request, a
  frequency dip, the grid lost, the grid back), each a table over clock seconds since it began of the `ext` values
  `grid_hz` and `grid_demand`; `world.grid` is `{"script": [[day, "HH:MM", event], …]}`, and the instructor's input
  `[n, "grid", event]` (its `instructor` event) starts one. Driven in step 1w after the weather; without weather, step
  1w runs for the grid alone. No draws.
- **A `count` node** (AG1, as a node kind it is refused where format 1 is read): `{"count": ref, "by": ref, "reset":
  ref, "init": n}` adds `by` (as the previous step left it) on each step where `ref` turns true; for starts, trips and
  operations counted by events (the gas turbine's starts and trips for its intervals, J7; a breaker's operations).
- **Forces and bypasses** (IC1, key `forces` in the model): `{"id", "value", "to": number | "hold", "kind": "force" |
  "bypass", "needs": [...]}`; input `[n, "force", id, "on" | "off", person, reason]` with a new authority
  `approve_force`, refused with its `needs`' sentences. While on, every reader of the named value reads `to` (or the
  value as it stood when the force went on) in place of the value step 2 computed; the value itself, for the screens'
  "forced" mark, is still computed. A bypass of a trip channel is the authorised override that STAFF.md §3 leaves out
  of format 2: it keeps a 2-out-of-3 trip at 2 out of 2. Forces are handover facts (kind `force`, §7.3) and listed in
  the digest.
- **Permit conflicts** (HS5, key `conflicts` in the works file): pairs of permit kinds that must not be live in one
  area at once (hot work beside a confined-space entry or a gas line opened, radiography beside any work, a lift over
  a live work); `issue` is refused with the reason `simops` (after `jsa`) while a conflicting permit is issued or
  accepted in a listed area.
- **Zone barriers** (HS6, key `barrier_when` on zones): `[[value, sentence]]`; while the value is true, entering the
  zone is an unsafe act of kind `barrier` (a radiography exposure, a hydrogen purge), read where §16.7 reads zones.
- **Authorisations** (PA1, key `auth` on people and on authorities): a person's records `{"auth": id, "until_day":
  d}`; an authority that names an `auth` is held only while `world_day` ≤ `until_day`, so an expired authorisation
  is refused as `authority` is today, with the sentence naming the record.
- **Duty hours** (PA2, key `fatigue` in staff.json): each person's clock tenths on duty in the last 24 clock hours and
  consecutive days worked; a callout or a held-over task that would pass the content's limits is refused for an NPC
  (the step's `else`), and the trainee's own work past them is an unsafe act of kind `fatigue`.
- **Passes** (PA4, key `passes` at a gate place) and **languages** (PA4, key `languages` on people): a person or
  vehicle without a valid pass is stopped at the gate (the guard's task issues one: input `[n, "pass", who, kind,
  person]`); a `say`, a toolbox talk's point or a handover fact reaches a hearer only if they share a language with
  the speaker or a person sharing one with each is at the `meet`; otherwise the debrief lists it as not understood.
- **Order approvals** (WM5, key `approvals` in the stores file): an `order` (§7.2) above the file's quantity or
  criticality level waits for `[n, "order_approve", order, person]` by a person with a new authority
  `approve_order` before its lead time starts.

**Budgets.** These additions together are within §11's staff step and weather step shares (they are per-person
counters, lookups at an input, and one more table in step 1w). The new plant systems are not: the fuel gas and
distillate systems, the emergency diesel, instrument air, fire water and CO₂, the switchyard and excitation add
model values to the first train (estimated 300–400, as built per milestone). §11's 600 values were sized before them,
and at about 0.7 µs a value on the Note 9 the two together would pass the 0.4 ms share. RE1 measured the step at
600 and at 1,000 added values (§2.10).

**Decided by the user (2026-11-02): the extra plant systems load per scenario.** The fuel gas and distillate systems,
the emergency diesel, instrument air, fire water and CO₂, the switchyard and excitation are optional content: each
scenario names the systems it loads, and a scenario without them steps without their values, so §11's 600 values
(and its 0.4 ms) stay the share of every scenario that loads none of them; one that loads some counts their values on
top, measured with the milestone that adds them. An "everything" day (every system loaded) is allowed on laptops and
is measured on the Note 9 (the user's words: allowed on laptops, measured on the phone). This unblocks OP4, OP5, OP6,
IC4, EC3 and EC6; how a scenario names its systems is settled with the first of them (OP4), in the content format
(PLANT3D.md format 2), with vectors of a scenario with and without a system.

### J1. Operations

| Item | What the trainee does | Model, engine | Source | Milestone |
|---|---|---|---|---|
| Grid dispatch: load changes | takes the grid operator's dispatch instruction on the radio (repeat back), ramps the block within its ramp rate, logs it | the dispatcher's instructions as grid events (J0); the block's load set op and ramp limits are model content | [NERC-COM002], [RfG] | OP1, OP2 |
| Frequency response | watches the governor answer a frequency dip by its droop (about 4–5 %), no operator action inside the deadband; reports the response | `grid_hz` from a grid event; the GT's droop and deadband as tables in the model | [RfG], [NERC-BAL003], [GER3567] | OP2 |
| Islanding | the grid is lost: the block runs back to house load or trips, the operator stabilises the island and resynchronises (EC3) | grid lost as an event; house-load and trip logic in the model | [RfG], [NFPA850] | OP3 |
| Black start | restores the block from dead: the black-start diesel, the essential boards, the GT started on its own power, energising the line to the grid on the operator's instruction | the black-start diesel and the boards as model content; the grid operator's steps as a scenario's grid events | [NERC-EOP005] | OP3 |
| Fuel gas supply | rounds of the fuel gas station (filters' ΔP, the knock-out drum's level, the heater keeping superheat above the dew point, pressure regulation); a low gas pressure trip | the station's values, faults and works; filters as wear items (§4) | [GEI41040], [GER3620] | OP4 |
| Dual-fuel changeover | changes over to distillate under load and back by procedure, with the purge and the limits on time on liquid fuel | the GT's fuel modes as a machine; the distillate system | [GEI41047], [GER3620] | OP4 |
| Emergency diesel test run | the monthly start and loaded run (or load bank), the readings, the auto start on loss of the essential board | the diesel, its batteries (wear, §9.1) and the transfer logic in the model | [NFPA110] | OP5 |
| Fire protection tests | the fire pumps' weekly run, a deluge valve's trip test, detectors and call points with the fire alarm panel | fire water and detection as model content; tests as tasks | [NFPA25], [NFPA72], [NFPA850] | OP6 |
| CO₂ lockout before entry | locks out the GT enclosure's CO₂ release (the lock-off valve and the panel's inhibit) and proves it before anyone enters; restores it after | an isolation of the CO₂ system (§15.1) as the entry work's `needs`; entering without it is an unsafe act | [NFPA12] | OP6 |
| Duty/standby changeovers | the rota's changeover of duty and standby pumps and fans, testing the standby's auto start | tasks on a routine (§16.5); auto-start logic exists | [Moubray] (hidden failures of standby units) | OP7 |
| Performance and heat-rate monitoring | reads heat rate and corrected output against expected, finds the loss (compressor fouling, condenser fouling, a passing drain), the weekly performance report | nodes computing heat rate and corrections to reference conditions from fuel flow, output and ambient (§5); the report is a view | [ASME-PTC46], [ASME-PTC22], [GER3567] | OP8 |

### J2. Electrical

| Item | What the trainee does | Model, engine | Source | Milestone |
|---|---|---|---|---|
| Excitation and synchronising | AVR in auto and manual, the capability curve's limits, synchronising with the synchroscope within the voltage, slip and phase limits, the check-synch relay's block | the generator's voltage, VArs and limits as tables; synchronising as an op with the limits as permissives | [IEEE-C50.13] | EC3 |
| Transformer oil DGA | takes an oil sample, reads the lab's dissolved gases, interprets them (key gases, ratios) and decides: resample sooner, or take the transformer out | the gases as tables of a hidden cause (overheating, partial discharge, arcing) and wear; results after clock days from the lab stream (§2.1) | [IEEE-C57.104], [IEC60599] | EC4 |
| Earthing tests | the earth grid's resistance by fall of potential, bonds checked | a meter whose value comes from the grid's state and a seeded corroded bond | [IEEE81], [IEEE80] | EC5 |
| Cathodic protection | pipe-to-soil potentials at test posts against the protection criterion, the transformer-rectifier's output | values per test post; a coating defect as a cause | [ISO15589-1] | EC5 |
| Cable fault location | after a failed insulation test: pre-location by time-domain reflectometry, pinpointing, the repair joint | the fault's distance a `draw` node; the meter's trace from it | [IEEE400] | EC5 |
| Switchyard operations | switching in the switchyard under the grid operator's control: instructions repeated back, isolators and earth switches in their interlocked order | switchyard positions and interlocks (as EC1's) | [NERC-COM002], [IEC61936], [HSG253] | EC6 |
| Emergency lighting tests | the monthly short test and the yearly full-duration test, a fitting that fails early | fittings' batteries as wear items; tests as tasks | [NFPA101] | EC7 |

### J3. I&C

| Item | What the trainee does | Model, engine | Source | Milestone |
|---|---|---|---|---|
| Forcing and bypass register | applies a force or bypass with its approval and reason, keeps the register, removes it after the job; finds a forgotten one at handover | forces (J0); the register is a view of them | [IEC61511] | IC1 |
| SIS proof tests | proof-tests a trip loop: bypass, inject at the sensor, see the logic and the final element act, restore, record | content over IC1's bypasses, hand actions and meters | [IEC61511], [ISA-TR84.00.03] | IC2 |
| PID loop tuning | a step test in manual, reading dead time and lag from the trend, tuning gains, seeing hunting from stiction (§4) rather than tuning | a loop's gains as states set by ops with authority; the process response is content | [Astrom], [Liptak] | IC3 |
| Instrument air | compressors, dryers (dew point), the receiver and header; low air pressure drives valves to their fail positions | the air system in the model; a dryer's failure brings moisture causes (§2.6) | [ISA7.0.01] | IC4 |
| Calibration traceability | uses only tools within their calibration date, whose certificates trace to a reference; a job done with an out-of-date tool is a finding and its readings are suspect | tools gain a calibration-due day (tool states, §2.3) | [ISO17025], [ISO10012] | IC5 |
| Fire and gas detector bump tests | bump-tests the portable gas detector before use and tests fixed detectors with test gas | tools' and detectors' states; a failed bump takes the tool out | [OSHA-SHIB-bump], [IEC60079-29-2] | IC5 |
| DCS backups, USB policy, patching | the engineering station's backups, the removable-media rule (scan kiosk), patches approved through a change (§10.2) | content and a hidden cause (an unscanned stick); views | [IEC62443], [NIST800-82] | IC6 |
| Vibration monitoring system setup | proximity probes' gap voltage and scale factor checked, alarm and trip settings and their time delays and voting | the monitor's values and meters | [API670] | IC7 |
| GT combustion tuning | combustion dynamics and emissions read per mode, the tuning's adjustments, a seasonal retune as ambient changes | tables of fuel split, dynamics and NOx/CO (§10.4) | [GER3568], [GER3620] | IC8 |
| Instrument tube compression fittings | cuts, deburrs, makes up a fitting (the turns from finger-tight, the gap gauge), leak-tests it | hand actions; a fitting under-tightened is a leak cause | [Swagelok] | IC9 |
| Ex hazardous-area inspections | visual, close and detailed inspections of equipment in a hazardous area (gland, enclosure, marking against the zone) | Ex equipment's states; defects as seeded findings | [IEC60079-17], [IEC60079-14] | IC9 |

### J4. Mechanical

| Item | What the trainee does | Model, engine | Source | Milestone |
|---|---|---|---|---|
| GT borescope inspection | borescopes the compressor and hot gas path through the ports, grades what is seen against limits | findings as tables of AG's wear (pictures generated per grade); a view through the tool | [GER3620] | MC3 |
| Combustion and hot-gas-path inspections | the inspection packages, their scope and their findings, due by J7's counts | works per package (the outage, WM4, uses them) | [GER3620] | MC3 |
| HRSG tube leaks and NDT | spots a tube leak's signs (makeup up, noise, a drum's level), locates it in the outage, chooses the NDT method (UT thickness, radiography, magnetic particle, dye penetrant) and reads the result | leak as a fault with a cause (flow-accelerated corrosion, corrosion fatigue) tied to chemistry (§10.5) | [Dooley], [ASME-V] | MC4 |
| In-place safety valve testing | tests a safety valve's set pressure in place with a lift-assist device, adjusts, seals | a meter of the lift force against the system pressure | [ASME-PTC25], [API576] | MC5 |
| Statutory pressure-vessel inspections | the written scheme of examination, inspection due dates, preparing a vessel for the inspector | due dates in clock days; works | [PSSR], [API510] | MC5 |
| Lifting gear certification and lift plans | slings and shackles with thorough examination dates and tags, a lift plan for the crane or a hoist (weight, radius, wind limit, exclusion zone) | lifting gear as tools with due days; the plan's limits as the lift work's `needs` (with §5.3's wind) | [LOLER], [L113], [ASME-B30], [BS7121] | MC6 |
| Steam trap surveys | a trap route with ultrasound and temperature, failed open or closed traps found, losses estimated | traps' states as seeded causes; thermography (§9.3) | [DOE-Steam] | MC7 |
| Corrosion under insulation | picks suspect locations (temperature range, damaged cladding), removes insulation, inspects | findings as `draw` nodes per location | [API583] | MC7 |
| Chemical cleaning | an HRSG or condenser chemical clean as an outage job: when it is due (deposit loading), the steps, the waste | works and their chemistry; waste to EV1 | [BW-Steam] | MC8 |
| Welding qualifications | checks a welder's qualification and continuity and the procedure for a repair before hot work starts | welders' records as authorisations (J0, PA1) | [ASME-IX], [ISO9606-1] | MC9 |

### J5. HSE and environment

| Item | What the trainee does | Model, engine | Source | Milestone |
|---|---|---|---|---|
| Site and contractor induction | inducts a visitor or contractor before they work; an uninducted person working is an unsafe act | an induction record as an authorisation (PA1) | [HSG159] | HS4 |
| First aid and CPR | the first response to an injured person (danger, response, call for help, CPR steps), the shift's first aiders | an incident scenario's tasks and picks (no injuries shown, §15) | [ERC], [OSHA151] | HS4 |
| The emergency response team | the ERT's call-out, roles and equipment in a drill | staff tasks on an emergency (§8.3) | [OSHA156], [NFPA850] | HS4 |
| Permit and lockout audits | samples live permits and lockouts against a checklist, records findings | a view over the permits and locks; findings as reports (§8.3) | [HSG250], [OSHA147] | HS5 |
| Simultaneous operations | sees conflicting permits in one area refused and plans around them | permit conflicts (J0) | [HSG250] | HS5 |
| Hydrogen hazards | a hydrogen-cooled generator's hydrogen: purity, purging with CO₂ before air, no ignition sources, the barrier during a purge | model values; a zone barrier (J0) | [NFPA55], [NFPA850] | HS6 |
| Chlorine hazards | the chlorine dosing area's detection, PPE and a leak drill | dosing area content; a drill (§8.3) | [NIOSH-NPG] | HS6 |
| Radioactive level gauges | the gauge's shutter locked before work near it, the controlled area | the shutter as an isolation point; a zone barrier | [IAEA-GSR3] | HS6 |
| Radiography barriers | the barrier and warning signs round an NDT exposure, nobody inside | a zone barrier during the exposure work | [IAEA-SSG11] | HS6 |
| Waste and spill response | waste segregation and records; a spill (transformer oil, diesel unloading) contained with the spill kit and reported | tasks, tools (spill kit) and a report | [IFC-EHS-Gen] | EV1 |
| Wastewater discharge monitoring | samples and analyses the discharge (pH, oil and grease, suspended solids, residual chlorine, temperature rise) against the limits, reports an exceedance | values from the WTP and cooling tower content; the lab stream | [IFC-EHS], [IFC-EHS-Gen] | EV2 |
| Noise surveys | a sound level meter round the plant, the hearing protection zones and the boundary's limits | a meter of model sound levels; zones' `ppe_when` (§5.3) from them | [IFC-EHS-Gen], [L108], [OSHA95] | EV2 |

### J6. Chemistry

| Item | What the trainee does | Model, engine | Source | Milestone |
|---|---|---|---|---|
| Cooling tower water treatment | cycles of concentration, blowdown, scale inhibitor and biocide dosing, the Legionella risk assessment and samples (results after days) | values; dosing as ops; fouling as wear (§4); the lab stream | [L8], [HSG274], [CTI] | CH1 |
| Fuel gas analysis | the gas chromatograph's composition, heating value and Wobbe index, sulphur and dew point against the turbine's fuel specification | values from the supply's content | [ISO6974], [ISO6976], [GEI41040] | CH2 |
| Lab instrument calibration | pH and conductivity meters calibrated with buffers and standards before use, the calibration log | lab tools' states (as IC5) | [ASTM-D1293], [ASTM-D1125], [ISO17025] | CH3 |
| Chemical inventory and safety data sheets | the inventory, GHS labels, the safety data sheet read before use, the risk assessment | content and views | [GHS], [OSHA1200], [COSHH] | CH3 |

### J7. Stores and planning

Costs are man-hours, parts and MWh lost, never money (the user, 2026-11-01): a budget is a number of crew hours, parts
drawn and generation lost.

| Item | What the trainee does | Model, engine | Source | Milestone |
|---|---|---|---|---|
| Purchase requisitions and approvals | raises a requisition for a part not in stock; approval levels by quantity and criticality | order approvals (J0) | [Palmer] | WM5 |
| OEM service engineers and long-term service agreements | what the agreement covers (the OEM's engineer leads inspections, the plant's staff support), booking the engineer, their arrival as a scheduled person | an OEM role in staff content with its scope as authorities; arrival as a plan slot (§7.4) | [GER3620] | WM5 |
| Budgets and KPIs | availability and forced outage rate, MTBF, PM compliance, backlog in crew weeks; the month's hours and parts against the budget | views from the run's events and works | [IEEE762], [EN15341] | WM6 |
| Critical spares policy | ranks parts by criticality and lead time, sets minimums for critical spares | catalogue content (§7.2) | [ISO55001], [Palmer] | WM7 |
| Spares preservation and shelf life | preservation rounds (stored motors' shafts turned), parts past their shelf life (elastomers, batteries, grease) refused at issue | parts' expiry days and preservation states | [ISO2230], [SKF] | WM7 |
| Stock audits | cycle counts; a discrepancy traced to an unrecorded issue | counts from the stores stream (§2.1) | [Palmer] | WM7 |
| GT maintenance intervals in equivalent operating hours and starts | sees the inspections fall due by the factored hours and starts (fuel, load, trips counting as several starts), plans the next outage from them | `wear` nodes for factored hours and `count` nodes (J0) for starts and trips, tied to AG's wear | [GER3620] | AG4 |

### J8. People and administration

| Item | What the trainee does | Model, engine | Source | Milestone |
|---|---|---|---|---|
| Training records and authorisations | the training matrix, who may issue, accept or isolate, an authorisation that expires mid-run | authorisations (J0) | [HSG250], [HSG65] | PA1 |
| Fatigue and overtime | callouts within the duty-hour limits; a tired person kept on is a risk the debrief names | duty hours (J0) | [HSG256], [API755] | PA2 |
| Daily and monthly reports | the shift's daily report (generation, events, faults, permits) and the month's (KPIs, J7) | views from the run's events | [IEEE762] | PA3 |
| ISO and insurance audits | prepares for and takes part in a management-system audit and an insurer's survey; findings and actions | an auditor's visit as staff content; findings as reports | [ISO9001], [ISO14001], [ISO45001], [FM-DS] | PA3 |
| Visitors and vehicle passes | the guard issues visitor and vehicle passes at the gate; escorts | passes (J0) at S4's gate | [HSG136], [HSG159] | PA4 |
| Multinational crews and language barriers | a crew without a shared language: an interpreter or a shared-language person at the toolbox talk, pictograms on signs | languages (J0) | [HSG48], [HSE-Migrant] | PA4 |

## 11. Budgets on the Note 9

The frame rules and §18.4's shares don't change (MILESTONES.md: ≥ 95 % of frames at ≥ 30 fps, none over 100 ms that
the app causes, both in normal play; peak PSS ≤ 1.5 GB; first walkable frame ≤ 15 s; ≤ 13.5 s per first start).
The programme's share, measured in each milestone that draws or runs something new:

| | Note 9 (`lean+vis`) | Laptop (`full`) |
|---|---|---|
| Model step, all realism content together | ≤ 0.4 ms added; the whole step ≤ 2.1 ms (§18.4), so fast-forward keeps ≥ 12× | ≤ 0.15 ms |
| Values added to the first train (the step's cost grows with them: the WTP's 600 values made the step about 1.4× as long, roughly 0.7 µs a value on the Note 9) | ≤ 600 in all: wear items and their signs ≤ 250 (about 40 items of ≤ 6 values: only items a scenario uses get sign tables), component states and meters ≤ 200 (equipment with jobs only; a state no node reads costs a slot, not an evaluation), weather, emissions and chemistry ≤ 150. RE1 measures the step on a synthetic model of this size before any content is written, and at 1,000 values for J0's question (the new plant systems of J1–J4) | |
| Staff step (heat rule, entrants, plans, discussions) | within §18.4's 0.3 ms at the shift change | |
| Weather step | ≤ 0.02 ms (one draw an hour, ten lags) | |
| Weather drawn (worst kind: sandstorm or rain; measured among A1's crowd with `crews=1`, where the S2 walks had the least headroom) | GPU ≤ +2 ms median; one emitter, ≤ 2,000 particles within 25 m | ≤ +1 ms; ≤ 8,000 within 40 m |
| New pipelines | the particle shader (≤ 4 pipelines) and the Workshop's heat-view variant when the thermal camera is first taken (as many as 0072 counts), both compiled in a hidden frame (0060: the particle shader at start, within the 13.5 s margin); wetness and dust as global parameters of the weathered shader: no new variant (counted before and after) | same |
| Work view | counted against the plant's budgets, not the Workshop's (the plant stays drawn): the component scene ≤ 30 draw calls and ≤ 30,000 triangles (the plant piece it replaces hidden), ≤ 40 MB more PSS, loaded on a worker thread ≤ 300 ms; any Workshop shader variant it uses (the heat view for thermography) counted as new pipelines below; equipment with jobs built unmerged: at most 2 pieces per 12 m cell and ≤ 12 more draw calls in any view of the plant; measured in HW2 | |
| Document view | the 3D view stops drawing while a document fills the screen; a sheet opens in ≤ 300 ms; ≤ 40 MB for open sheets | |
| Sounds | ≤ 3 more players for weather | |
| Memory | ≤ 60 MB more peak PSS | |
| Package | ≤ 15 MB more for the whole programme (the APK limit is 250 MB, the user 2026-11-01) | |

A milestone that misses a budget is not done; cutting something the trainee learns from to meet it is the user's
call.

## 12. Order

The Workshop is built first (K0–K6, WORKSHOP.md). The realism pieces that don't need it are built **alongside it**
(the user, 2026-11-01): RE1, AG1, WX1 and DC1 (the generated P&IDs). Hands-on work waits for the Workshop's K3 (HW1
needs it); everything else follows its dependencies in MILESTONES.md. Within realism:
- **foundations first:** the engine pieces (§2) in four milestones that add no drawing (RE1: world seed, streams,
  clock values and the step's cost at the planned size, with no Workshop dependency; then AG1 and WX1 alongside the
  Workshop, and HW1 after its K3), each with its vectors;
- **then the tracks**, each adding one kind of load measured alone: hands-on (HW2–HW6), ageing and monitoring
  (AG2–AG3), weather (WX2–WX4), documents (DC1–DC3), work management (WM1–WM4), HSE (HS1–HS3), crafts (EC1–EC2,
  MC1–MC2), engineering (EN1–EN4), and the rest of the job (J1–J8): operations (OP1–OP8), electrical (EC3–EC7), I&C
  (IC1–IC9), mechanical (MC3–MC9), HSE and environment (HS4–HS6, EV1–EV2), chemistry (CH1–CH3), stores and planning
  (WM5–WM7, AG4), people and administration (PA1–PA4). The engine additions of J0 come first in their tracks (OP1,
  AG1's `count`, IC1, HS5, HS6, WM5, PA1, PA2, PA4), each with its vectors;
- **the outage (WM4) last**: it uses nearly everything.

The table with sizes, needs and what each ships is in MILESTONES.md.

## 13. Tests

- **Vectors** (`plant3d-realism.json`): `valid` and `reject` for every new key and error code; `steps` pinning the
  `draw` and `wear` nodes (step 0, reset, max, the scenario's `init`), the streams (an item added or moved in any file changes no other's draw; a person's draws unchanged with a world), tools carried and their refusals, hand actions (each reason,
  the order, a locked code), meters and `read via` (misread, `else`), HART ops, hidden causes (a work that doesn't cure, answered as one that does;
  no draw for a fault not made; the instructor's cause; value weights), renewals under a lock, hand actions with
  minutes (busy, abandoned by leaving), tools' counts per place, jumps with permits open and wear across a jump,
  the weather step (hour boundaries, a jump across hours, scripted and fixed weather, the instructor's input), stock and
  deliveries, logbook and report inputs, the JSA refusal, entrants and the standby and fire watch acts, the heat rule,
  change objects and `priority_of`, `discuss` with and without a trainee, `plan` slots, `switch_effects`; J0's grid
  events (scripted, the instructor's, step 1w without weather), `count` nodes, forces and bypasses (a later node and a
  trip reading the forced value, the raw slot, `approve_force`), the `simops` refusal, zone barriers, expired
  authorisations, duty-hour limits, passes and languages, order approvals; runs on the
  first train's content with forks per area; the digests of every 50th step.
- **The byte check:** after the engine milestones, `plant3d-v1.json` and `plant3d-v2.json` regenerated by the new
  reference equal the committed files; after a content milestone, their synthetic items still do, and their content
  runs keep every input, event and earlier value (§2).
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
  rigid rotors. · [ISO4406] ISO 4406, Hydraulic fluid power: solid contamination code. · [IEC60076-7] IEC 60076-7, Power transformers: loading guide for mineral-oil-immersed
  transformers. · [ISO7243] ISO 7243,
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
  Safety Guidelines for Thermal Power Plants (2008), https://www.ifc.org/ehsguidelines · [IAPWS-TGD] IAPWS technical guidance
  documents on cycle chemistry (volatile treatments, phosphate and NaOH treatments, instrumentation),
  https://www.iapws.org/techguide.html · [WMO] WMO, Manual on codes / International Cloud Atlas (dust and sand storm
  definitions), https://cloudatlas.wmo.int · [WBCCKP] World Bank Climate Change Knowledge Portal (regional climatology),
  https://climateknowledgeportal.worldbank.org · [ACGIH] ACGIH TLV for heat stress and strain, as summarised by US
  OSHA's Technical Manual section III chapter 4, https://www.osha.gov/otm/section-3-health-hazards/chapter-4 ·
  [HART] FieldComm Group, HART protocol, https://www.fieldcommgroup.org/technologies/hart · [MOC] CCPS, Guidelines
  for the management of change for process safety (Wiley, 2008) · [CCPS] CCPS, Guidelines for risk based process
  safety (Wiley, 2007).

Manufacturers' published manuals and handbooks:
- [R3051] Emerson, Rosemount 3051 pressure transmitter reference manual (loop resistance for HART, troubleshooting,
  trim). · [DVC] Emerson, Fisher FIELDVUE DVC6200 instruction manual (positioner calibration). · [FCVH] Emerson,
  Control Valve Handbook (packing, stiction, troubleshooting). · [SKF] SKF, Bearing maintenance handbook and rolling
  bearings catalogue (mounting, heating, relubrication quantity, defect frequencies). · [GER3567] GE Power Systems,
  GER-3567H, GE gas turbine performance characteristics (F. J. Brooks, 2000). · [GER3620] GE Vernova, GER-3620P,
  Heavy-duty gas turbine operating and maintenance considerations (revision P, 2021; inspections, filters, washing,
  factors on intervals),
  https://www.gevernova.com/gas-power/resources/technical-downloads/ger-3620p-operation-maintenance-considerations. ·
  [Fluke] Fluke application notes on clamp meters and 4–20 mA loop calibrators.

Textbooks:
- [Moubray] J. Moubray, Reliability-centred Maintenance (the P-F curve). · [Liptak] B. Lipták, Instrument Engineers'
  Handbook. · [Piotrowski] J. Piotrowski, Shaft Alignment Handbook. · [Perry] Perry's Chemical Engineers' Handbook
  (cooling towers). · [CTI] Cooling Technology Institute, publications on cooling tower performance.

For the rest of the job (J1–J8):

Standards (bought, not copied; NFPA's codes are also free to read online after sign-in):
- [NFPA110] NFPA 110, Emergency and standby power
  systems · [NFPA12] NFPA 12, Carbon dioxide extinguishing systems (lockout before entry) · [NFPA25] NFPA 25,
  Inspection, testing and maintenance of water-based fire protection systems · [NFPA72] NFPA 72, National fire alarm
  and signaling code · [NFPA101] NFPA 101, Life safety code (emergency lighting tests) · [NFPA55] NFPA 55, Compressed
  gases and cryogenic fluids code (hydrogen) · [ASME-PTC46] ASME PTC 46, Performance test code on overall plant
  performance · [ASME-PTC22] ASME PTC 22, Performance test code on gas turbines · [ASME-PTC25] ASME PTC 25, Pressure
  relief devices · [ASME-V] ASME BPVC Section V, Nondestructive examination · [ASME-IX] ASME BPVC Section IX, Welding
  qualifications · [ASME-B30] ASME B30 series, Cranes, hoists and slings · [BS7121] BS 7121, Code of practice for
  safe use of cranes · [ISO9606-1] ISO 9606-1, Qualification testing of welders · [IEEE-C50.13] IEEE C50.13,
  Cylindrical-rotor synchronous generators (capability, synchronising limits) · [IEEE-C57.104] IEEE C57.104,
  Interpretation of gases generated in mineral oil-immersed transformers · [IEC60599] IEC 60599, Interpretation of
  dissolved and free gases analysis · [IEEE81] IEEE 81, Measuring earth resistivity, ground impedance and earth
  surface potentials · [IEEE80] IEEE 80, Safety in AC substation grounding · [ISO15589-1] ISO 15589-1, Cathodic
  protection of pipeline systems: on-land pipelines · [IEEE400] IEEE 400, Field testing and evaluation of the
  insulation of shielded power cable systems · [IEEE762] IEEE 762, Definitions for reporting electric generating unit
  reliability, availability and productivity · [EN15341] EN 15341, Maintenance key performance indicators · [IEC61511]
  IEC 61511, Functional safety: safety instrumented systems for the process industry (bypasses, proof tests) ·
  [ISA-TR84.00.03] ISA-TR84.00.03, Mechanical integrity of safety instrumented systems · [ISA7.0.01] ANSI/ISA-7.0.01,
  Quality standard for instrument air · [ISO17025] ISO/IEC 17025, Competence of testing and calibration laboratories
  · [ISO10012] ISO 10012, Measurement management systems · [IEC62443] IEC 62443, Security for industrial automation
  and control systems · [IEC60079-29-2] IEC 60079-29-2, Gas detectors: selection, installation, use and maintenance
  · [API670] API 670, Machinery protection systems · [IEC60079-17] IEC 60079-17, Explosive atmospheres: electrical
  installations inspection and maintenance · [IEC60079-14] IEC 60079-14, Explosive atmospheres: electrical
  installations design, selection and erection · [API510] API 510, Pressure vessel inspection code · [API576] API
  RP 576, Inspection of pressure-relieving devices · [API583] API RP 583, Corrosion under insulation and fireproofing
  · [API755] API RP 755, Fatigue risk management systems · [ISO6974] ISO 6974, Natural gas: composition by gas
  chromatography · [ISO6976] ISO 6976, Natural gas: calorific values, density and Wobbe index from composition ·
  [ASTM-D1293] ASTM D1293, pH of water · [ASTM-D1125] ASTM D1125, Electrical conductivity of water · [ISO55001] ISO
  55001, Asset management systems · [ISO2230] ISO 2230, Rubber products: guidelines for storage · [ISO9001] ISO 9001,
  [ISO14001] ISO 14001, [ISO45001] ISO 45001 (quality, environmental, occupational health and safety management
  systems: their audits).

Public guidance and regulations (free to read):
- [RfG] Commission Regulation (EU) 2016/631, requirements for grid connection of generators (frequency response,
  islanding), https://eur-lex.europa.eu/eli/reg/2016/631/oj · [NERC-BAL003] NERC BAL-003, Frequency response and
  frequency bias setting · [NERC-EOP005] NERC EOP-005, System restoration from blackstart resources · [NERC-COM002]
  NERC COM-002, Operating personnel communications protocols (all three free at
  https://www.nerc.com/pa/Stand/Pages/ReliabilityStandards.aspx)
- [IFC-EHS-Gen] IFC/World Bank, General EHS Guidelines (2007: wastewater, noise, hazardous materials, waste),
  https://www.ifc.org/ehsguidelines · [OSHA-SHIB-bump] US OSHA, Verification of calibration for direct-reading
  portable gas monitors (2013), https://www.osha.gov/publications/shib093013 · [NIST800-82] NIST SP 800-82r3, Guide
  to operational technology security, https://csrc.nist.gov/pubs/sp/800/82/r3/final · [PSSR] The Pressure Systems
  Safety Regulations 2000, https://www.legislation.gov.uk/uksi/2000/128, with HSE's ACoP L122 · [LOLER] The Lifting
  Operations and Lifting Equipment Regulations 1998, https://www.legislation.gov.uk/uksi/1998/2307 · [L113] UK HSE,
  Safe use of lifting equipment (ACoP L113), https://www.hse.gov.uk/pubns/books/l113.htm · [DOE-Steam] US DOE,
  steam system tip sheets (inspect and repair steam traps), https://www.energy.gov/eere/amo/steam-systems ·
  [HSG159] UK HSE, Managing contractors, https://www.hse.gov.uk/pubns/books/hsg159.htm · [ERC] European
  Resuscitation Council guidelines, https://cprguidelines.eu · [OSHA151] US OSHA 29 CFR 1910.151, Medical services
  and first aid · [OSHA156] US OSHA 29 CFR 1910.156, Fire brigades · [OSHA147] US OSHA 29 CFR 1910.147, Control of
  hazardous energy (periodic inspection of lockout procedures) · [OSHA95] US OSHA 29 CFR 1910.95, Occupational noise
  exposure · [OSHA1200] US OSHA 29 CFR 1910.1200, Hazard communication (all four at
  https://www.osha.gov/laws-regs/regulations/standardnumber/1910) · [L108] UK HSE, Controlling noise at work (L108),
  https://www.hse.gov.uk/pubns/books/l108.htm · [NIOSH-NPG] NIOSH pocket guide to chemical hazards (chlorine),
  https://www.cdc.gov/niosh/npg/ · [IAEA-GSR3] IAEA GSR Part 3, Radiation protection and safety of radiation sources ·
  [IAEA-SSG11] IAEA SSG-11, Radiation safety in industrial radiography (both at
  https://www.iaea.org/resources/safety-standards) · [L8] UK HSE, Legionnaires' disease (ACoP L8),
  https://www.hse.gov.uk/pubns/books/l8.htm · [HSG274] UK HSE, Legionnaires' disease technical guidance, part 1
  (evaporative cooling systems), https://www.hse.gov.uk/pubns/books/hsg274.htm · [GHS] UN Globally harmonized system
  of classification and labelling of chemicals, https://unece.org/about-ghs · [COSHH] UK HSE, COSHH,
  https://www.hse.gov.uk/coshh/ · [HSG256] UK HSE, Managing shift work, https://www.hse.gov.uk/pubns/books/hsg256.htm
  · [HSG136] UK HSE, A guide to workplace transport safety, https://www.hse.gov.uk/pubns/books/hsg136.htm ·
  [HSE-Migrant] UK HSE, Migrant workers (communication across languages), https://www.hse.gov.uk/migrant-workers/ ·
  [FM-DS] FM Global property loss prevention data sheets (free with registration),
  https://www.fmglobal.com/research-and-resources/fm-global-data-sheets.

Manufacturers' published documents:
- [GEI41040] GE, GEI-41040 (now GE Vernova's), Specification for fuel gases for combustion in heavy-duty gas turbines
  (revisions up to at least M, 2011; the current revision not confirmed: supplied with the turbine) · [GEI41047] GE,
  GEI-41047 (now GE Vernova's), Gas turbine liquid fuel specifications (revision H is the one contracts cite; the
  current revision not confirmed) · [GER3568] GE Power Systems, GER-3568G, Dry low NOx combustion systems for GE
  heavy-duty gas turbines (L. B. Davis, S. H. Black, 2000) · [Swagelok] Swagelok, Tube fitter's manual (MS-13-03) and
  the tube fitting installation instructions (MS-12-01, with the gap inspection gauge),
  https://www.swagelok.com/toolbox/tube-fitting-manual.

Checked 2026-11-02 (web search): every GE number above appears with that title in public sources; GEI-41040 and
GEI-41047 are not published for download (they come with a turbine) and were seen only in summaries and contracts, so
they are cited for what those say of them until a copy is in hand.

Textbooks:
- [Astrom] K. J. Åström, T. Hägglund, Advanced PID control (ISA, 2006) · [Dooley] **unverified**: cited from memory as
  R. B. Dooley, W. P. McNaughton, Boiler and HRSG tube failures: theory and practice (2016); no book of that title and
  year was found on 2026-11-02. It is probably EPRI's report Boiler and heat recovery steam generator tube failures:
  theory and practice (1012757, three volumes; its authors and year not confirmed), an EPRI product that is not free
  to read. MC4 needs a public source in its place (or the user's choice to cite EPRI's) before its content is written
  · [BW-Steam] Babcock & Wilcox, Steam: its generation and use (chemical cleaning) · [Palmer] R. D. Palmer,
  Maintenance planning and scheduling handbook (McGraw-Hill).

## 15. Not in this programme (deliberately)

- Real physics (fluids, heat, electrics, structures): tables and lags only (R6).
- Free text that the engine interprets: the engine records short texts (reasons, log entries, reports) but never
  reads them.
- Injuries shown on people, or anything graphic: incidents are reported and investigated, not shown.
- Speech for NPCs: discussions and the radio are text only (the user, 2026-11-01; the platforms' text-to-speech is
  noted in CAPABILITIES.md, not used).
- Real plant documents, procedures or data, and anything taken from the user's photos.
- Exporting the generated P&IDs to Walkdown or `kks-import` (the user, 2026-11-01: the plant app only).
- Money: costs are man-hours, parts and megawatt-hours lost, never currency (the user, 2026-11-01).
