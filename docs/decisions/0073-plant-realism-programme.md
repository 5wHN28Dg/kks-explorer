# 0073 Walkdown Plant's realism programme: everything that changes the plant in the deterministic engine, hands-on jobs from the Workshop's trees, seeded wear and weather, generated documents

Date 2026-11-01 · Scope: docs/plant3d/REALISM.md, docs/PLANT3D.md format 2 (additions), `ref/plant3d.py`,
`ref/plant3d_staff.py`, `apps/plant3d/sim`, the content tools, the app · Status: **accepted** (the user's answers of
2026-11-01, below), written before any code under the user's decision of 2026-11-01 (add every area of realism they
listed, and then every other part of the job: REALISM.md J1–J8) · Extends 0054, 0057, 0060, 0062,
0067, 0071, 0072 (the Workshop); no new dependency

**Question:** how do hands-on jobs with tools, ageing and spontaneous failures, weather, documents and discussions,
work management, deeper HSE, the crafts and engineering work fit the existing plant so that (a) every player of a
session and the Python reference see the same plant, the same failure and the same weather, bit for bit, (b) what the
trainee learns from is right and sourced while the physics is faked (R6), (c) the Workshop's component data is the one
source for what a job takes apart, and (d) the Note 9 keeps the frame rules?

## Findings

[V] verified here, [D] Godot 4.7 documentation, [S] source named, [—] not tried.

| | Finding | Source |
|---|---|---|
| The engine | a fixed 0.1 s step; ops with permissives and sentences, faults with repairs, works, permits and isolations, the staff step acting only through inputs, per-person xorshift32 streams seeded through mix32; bit for bit on Linux, Windows and the Note 9 | PLANT3D.md §7, §15–§17, CAPABILITIES.md §8 [V] |
| Its cost | 1.36–1.45 ms a model step on the Note 9 with the staff (budget 2.1 ms, keeping fast-forward ≥ 12×); staff step about 0.20–0.25 ms at the shift change (budget 0.3) | MILESTONES.md S2, S3 [V] |
| What already says most of it | an op refused with its sentences is a job step refused out of order; a fault with `when` is a failure at a threshold; a `read` with `tol` checks a reading; reactions on values give findings to supervisors; zones and PPE give unsafe acts; `meet` and `pick` give a discussion's turns | PLANT3D.md §7.2, §7.8, §16.6–§16.7 [V: worked through] |
| What it can't | which tool a person carries; a value that differs per run but is fixed within it (a bearing's life); a wear that resets on renewal; `ext` values that change during a run (they are the scenario's constants); a fault whose cause is chosen when it happens | the same |
| The Workshop | each part kind gets a component tree, assembly order with refusal sentences, fasteners, and a bench model in its own format (`walkdown-plant-bench`) | plant-workshop-spec.md, WORKSHOP.md (0072) |
| Plant geometry | static pieces are merged per material, class, size and 12 m cell; only anim channels are separate nodes: one piece of equipment can't be hidden alone | PLANT3D.md §10, `kit/mesh.gd` [S] |
| Weather in Godot | depth fog in every renderer (volumetric fog is Forward+ only, left out by 0057); GPUParticles3D in Forward+ and Mobile; global shader parameters set from script without a new shader variant | [D] environment_and_post_processing, particle_systems, shading_language (global uniforms) |
| Speech | `DisplayServer.tts_speak` uses the platform's text-to-speech on Windows, Linux (speech-dispatcher) and Android | [D] class_displayserver |
| Documents | Godot has no PDF renderer; 2D drawing (`draw_polyline`, meshes on a CanvasItem) on every renderer | [D] |
| Practice | permits, isolation, confined space, hot work, JSA, MOC, alarm management, condition monitoring, cycle chemistry: public standards and guidance exist for each | REALISM.md §14 |

## Alternatives

1. **Everything that changes the plant, a person, or what another player sees in the engine** (format 2
   additions, a vector file of their own), views outside it.
2. **Realism as app-side scripts** (wear, weather, tools in GDScript outside the engine): no Python reference, and
   multiplayer would have to send their state (lockstep sends only inputs, 0067): rejected.
3. **A format 3**: a new plant version for realism. Its keys are optional and a plant without them steps as before, as
   LIFTS' and S4's were; a new version would split content tools and vectors for nothing.

For hands-on jobs: (a) **hand actions in the model, generated from the Workshop's data**; (b) jobs only in the
Workshop mode: the plant would not see a lifted wire, and two players couldn't work together on it.

For the work view: (i) **equipment with jobs built outside the merged cells** and swapped for its Workshop scene;
(ii) masking one piece inside a merged mesh by a per-vertex ID: a change to the one weathered shader and its vertex
format (0060); (iii) a separate Workshop-like space for every job: loses the plant around the job.

## Choice

- **(1), (a) and (i).** The engine additions (REALISM.md §2): a world seed with streams per purpose and item id (FNV-1a of the id, so no item's draw depends on file order;
  persons' draws unchanged), clock values readable by nodes in a scenario with `world`, clear time bases (clock time
  for wear, weather and averages; model time for dynamics), the `draw` and `wear` nodes with works' `renews`,
  carried tools, hand actions and meters (made by the content tool from the Workshop's component trees and
  sentences: one source), hidden causes with `cures`, the weather step 1w driving `ext` values from a table file,
  and smaller pieces per area (stock and deliveries, logbook, report and JSA inputs, entrants with standby and fire
  watch acts, a heat rule, change objects, an alarm's priority from a value, the `discuss` and `plan` inputs, the
  `switch_effects` query), and for the rest of the job (REALISM.md J0) grid events, a `count` node, forces and
  bypasses, permit conflicts, zone barriers, authorisations, duty hours, passes and languages, and order approvals.
  Every addition is gated by its own key. Vectors in `ref/vectors/plant3d-realism.json`; the engine milestones leave
  `plant3d-v1.json` and `plant3d-v2.json` byte for byte, and content milestones regenerate their content runs with
  every input, event and earlier value kept (as P1 and W2 did).
- **Ageing:** the P-F curve's signs as tables of wear; lives drawn once per run from the seed; a scenario's age and an
  `age_rate` (an `ext` value) for training compression.
- **Weather:** a Markov chain over weather kinds per clock hour and season, one draw an hour; diurnal tables and lags
  per `ext` value; drawn with the existing depth fog, one particle emitter (the programme's only new shader, its
  pipelines compiled in the hidden frame) and global parameters of the weathered shader (no new variant).
- **Documents:** P&IDs generated by the content tools from the areas and models in a drawing format of our own,
  drawn by the app; manuals in COURSES.md's blocks; discussions as content with a `discuss` step whose outcome runs as
  `choose`; text only, no speech.
- **Thermography** reuses the Workshop's heat view; no new shader.
- **Budgets** (REALISM.md §11): ≤ 0.4 ms more per model step on the Note 9 (the step ≤ 2.1 ms) and ≤ 600 more values on the
  first train (about 0.7 µs a value there), weather ≤ +2 ms GPU
  median at its worst, ≤ 60 MB more PSS, ≤ 15 MB more package, the frame rules unchanged.
- **Sources:** every procedure, failure mode and limit cites a public source (REALISM.md §14); no plant data.

## Capability matrix

CAPABILITIES.md §8 gains rows for weather (depth fog, GPU particles, global shader parameters), documents (2D drawing;
no PDF renderer) and text-to-speech (available, not used), and the gaps paragraph names them.

## Decided by the user, 2026-11-01 (and 2026-11-02, item 9)

1. **When realism builds start:** the parts that don't need the Workshop (RE1, AG1, WX1 and DC1's generated P&IDs)
   are built alongside it; hands-on work waits for the Workshop's K3.
2. **Ageing speed:** a training rate per scenario, with real rates also available.
3. **Weather in free play:** on, seeded by season for the hot dry climate.
4. **Emissions limits:** the IFC / World Bank Group EHS guidelines for thermal power plants.
5. **Money:** costs as man-hours, parts and MWh lost, with no currency.
6. **Generated P&IDs:** in the plant app only (not exported for `kks-import`).
7. **NPC speech:** text only.
8. **The rest of the job:** the user added every other part of the work they listed (operations, electrical, I&C,
   mechanical, HSE and environment, chemistry, stores and planning, people and administration). REALISM.md J1–J8
   fits each into a track with milestones, dependencies and public sources; J0 lists the ten small engine
   additions they need, each gated by its own key with its vectors in `plant3d-realism.json` (grid events, a `count`
   node, forces and bypasses, permit conflicts, zone barriers, authorisations, duty hours, passes, languages, and order approvals).

9. **The new plant systems load per scenario** (2026-11-02; REALISM.md J0): the fuel gas and distillate systems,
   the emergency diesel, instrument air, fire water and CO₂, the switchyard and excitation (an estimated 300–400 model
   values) are optional content that each scenario loads or not, so §11's 600 values and 0.4 ms remain the share of a
   scenario without them; a scenario that loads some counts them on top, measured with its milestone. An "everything"
   day is allowed on laptops and measured on the Note 9. The other options were a wider share or coarser models. This
   unblocks OP4, OP5, OP6, IC4, EC3 and EC6. (RE1 had measured +0.087 ms at 600 values and +0.136 ms at 1,000 in the
   model alone on the Note 9, REALISM.md §2.10.)

## Open for the user

None at present.

**When to revisit:** if the model step with realism content passes its budget on the Note 9; if a trainer needs a
job the hand actions can't say (a bounded addition with vectors, never scripting); if Godot's particles or global
parameters cost more pipelines than counted; if the merged-cell exception for equipment with jobs costs more draw
calls than budgeted (then the per-vertex mask, measured).

Sources: docs/PLANT3D.md, docs/plant3d/REALISM.md §14, docs/plant3d/WORKSHOP.md ·
https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html ·
https://docs.godotengine.org/en/stable/tutorials/3d/particles/index.html ·
https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html ·
https://docs.godotengine.org/en/stable/classes/class_displayserver.html
